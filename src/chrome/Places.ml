(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Places.mli *)

type entry = { url : string; title : string; visits : int; last : float }
type t = { mutable entries : entry list; mutable changes : int }

let create ?(entries = []) () : t = { entries; changes = 0 }
let entries (t : t) : entry list = t.entries
let changes (t : t) : int = t.changes
let kept = 2000

let score ~(now : float) (e : entry) : float =
  let days = (now -. e.last) /. 86400. in
  float_of_int e.visits *. if days <= 4. then 100. else if days <= 14. then 70. else if days <= 31. then 50. else if days <= 90. then 30. else 10.

let ranked ~(now : float) (es : entry list) : entry list = List.stable_sort (fun a b -> compare (score ~now b) (score ~now a)) es

let visit (t : t) ~(now : float) ~(url : string) ~(title : string) : unit =
  if not (String.starts_with ~prefix:"about:" url) then (
    let seen, others = List.partition (fun e -> e.url = url) t.entries in
    let visits = match seen with e :: _ -> e.visits + 1 | [] -> 1 in
    let title = match (String.trim title, seen) with "", e :: _ -> e.title | title, _ -> title in
    let all = { url; title; visits; last = now } :: others in
    (* the best alone, when there are too many *)
    t.entries <- (if List.length all > kept then List.filteri (fun i _ -> i < kept) (ranked ~now all) else all);
    t.changes <- t.changes + 1)

let bare (url : string) : string =
  let without prefix s = if String.starts_with ~prefix s then String.sub s (String.length prefix) (String.length s - String.length prefix) else s in
  without "www." (without "http://" (without "https://" url))

let site (url : string) : string = match String.index_opt (bare url) '/' with Some i -> String.sub (bare url) 0 i | None -> bare url

let has (text : string) (word : string) : bool =
  let n = String.length word in
  let rec at i = i + n <= String.length text && (String.sub text i n = word || at (i + 1)) in
  at 0

let matching (t : t) ~(now : float) (typed : string) : entry list =
  let words = List.filter (( <> ) "") (String.split_on_char ' ' (String.lowercase_ascii typed)) in
  if words = [] then []
  else
    let found = List.filter (fun e -> let text = String.lowercase_ascii (e.url ^ " " ^ e.title) in List.for_all (has text) words) t.entries in
    List.filteri (fun i _ -> i < 6) (ranked ~now found)

let completion (t : t) ~(now : float) (typed : string) : string option =
  let typed = String.lowercase_ascii typed in
  if typed = "" || String.contains typed ' ' then None
  else
    List.find_map
      (fun e ->
        let whole = String.lowercase_ascii (bare e.url) in
        if not (String.starts_with ~prefix:typed whole) then None
        else if String.length typed <= String.length (site e.url) then Some (site e.url)
        else Some (bare e.url))
      (ranked ~now t.entries)

let address (t : t) (text : string) : string option =
  let text = String.lowercase_ascii (String.trim text) in
  let is (e : entry) = String.lowercase_ascii (bare e.url) = text || String.lowercase_ascii (site e.url) ^ "/" = String.lowercase_ascii (bare e.url) && String.lowercase_ascii (site e.url) = text in
  Option.map (fun e -> e.url) (List.find_opt is t.entries)

(*****************************************************************************)
(* The History file *)
(*****************************************************************************)

let to_string (t : t) : string =
  let entry (e : entry) : Json.t = Object [ ("url", String e.url); ("title", String e.title); ("visits", Number (float_of_int e.visits)); ("last", Number e.last) ] in
  Json.to_string (Array (List.map entry t.entries)) ^ "\n"

let of_string (s : string) : (entry list, string) result =
  let entry (j : Json.t) : entry option =
    match (Json.member "url" j, Json.member "title" j, Json.member "visits" j, Json.member "last" j) with
    | Some (String url), Some (String title), Some (Number visits), Some (Number last) when url <> "" -> Some { url; title; visits = int_of_float visits; last }
    | _ -> None
  in
  Result.bind (Json.parse s) (fun json -> match json with Array es -> Ok (List.filter_map entry es) | _ -> Error "not a list of pages")

let file (dir : string) : string = Filename.concat dir "History"

let load (caps : < Cap.open_in ; .. >) ~(dir : string) : (entry list, string) result =
  let path = file dir in
  let (_ : Cap.FS_.open_in) = caps#open_in path in
  if not (Sys.file_exists path) then Ok []
  else (
    Logs.info (fun m -> m "history: reading %s" path);
    Result.map_error (fun why -> path ^ ": " ^ why) (match In_channel.with_open_bin path In_channel.input_all with s -> of_string s | exception Sys_error why -> Error why))

let save (caps : < Cap.open_out ; .. >) ~(dir : string) (t : t) : (unit, string) result =
  let path = file dir in
  let (_ : Cap.FS_.open_out) = caps#open_out path in
  let rec make (dir : string) = if not (Sys.file_exists dir) then (make (Filename.dirname dir); Sys.mkdir dir 0o700) in
  Logs.info (fun m -> m "history: writing %s" path);
  try
    make dir;
    (* its owner's alone: where one has been *)
    Out_channel.with_open_gen [ Open_wronly; Open_creat; Open_trunc; Open_binary ] 0o600 (path ^ ".tmp") (fun oc -> Out_channel.output_string oc (to_string t));
    Sys.rename (path ^ ".tmp") path;
    Ok ()
  with Sys_error why -> Error why
