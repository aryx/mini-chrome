(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Browser_helpers.mli *)

type rule = { site : string option; kind : string option; run : string list }
type t = rule list

(*****************************************************************************)
(* The table *)
(*****************************************************************************)

let of_json (json : Json.t) : t =
  let text (name : string) (o : Json.t) = match Json.member name o with Some (String s) when s <> "" -> Some s | _ -> None in
  let rule (o : Json.t) : rule option =
    let run = match Json.member "run" o with Some (Array words) -> List.filter_map (function Json.String s -> Some s | _ -> None) words | _ -> [] in
    match (text "site" o, text "type" o, run) with
    | _, _, ([] | "" :: _) | None, None, _ -> None
    | site, kind, run -> Some { site; kind = Option.map String.lowercase_ascii kind; run }
  in
  match json with Array rules -> List.filter_map rule rules | _ -> []

let to_json (rules : t) : Json.t =
  let field name = function Some s -> [ (name, Json.String s) ] | None -> [] in
  Array (List.map (fun r -> Json.Object (field "site" r.site @ field "type" r.kind @ [ ("run", Array (List.map (fun s -> Json.String s) r.run)) ])) rules)

let starts (s : string) (prefix : string) : bool = String.length s >= String.length prefix && String.sub s 0 (String.length prefix) = prefix
let ends (s : string) (suffix : string) : bool =
  let n = String.length s and k = String.length suffix in
  n >= k && String.sub s (n - k) k = suffix

(* "https://www.youtube.com/watch?v=x": "www.youtube.com", "/watch?v=x" *)
let host_and_path (url : string) : (string * string) option =
  let after scheme = if starts url scheme then Some (String.sub url (String.length scheme) (String.length url - String.length scheme)) else None in
  match (after "https://", after "http://") with
  | (Some rest, _ | None, Some rest) -> (
      match String.index_opt rest '/' with
      | Some i -> Some (String.lowercase_ascii (String.sub rest 0 i), String.sub rest i (String.length rest - i))
      | None -> Some (String.lowercase_ascii rest, "/"))
  | None, None -> None

let for_url (rules : t) (url : string) : rule option =
  match host_and_path url with
  | None -> None
  | Some (host, path) ->
      List.find_opt
        (fun r ->
          match r.site with
          | None -> false
          | Some site ->
              let h, p = match String.index_opt site '/' with Some i -> (String.sub site 0 i, String.sub site i (String.length site - i)) | None -> (site, "/") in
              let h = String.lowercase_ascii h in
              (host = h || ends host ("." ^ h)) && starts path p)
        rules

let for_type (rules : t) (content_type : string) : rule option =
  let kind = String.lowercase_ascii (String.trim (List.hd (String.split_on_char ';' content_type))) in
  List.find_opt (fun r -> r.kind = Some kind) rules

let name (r : rule) : string = match r.run with program :: _ -> Filename.basename program | [] -> ""

let command (r : rule) ~(url : string) ~(file : string option) : string list =
  List.map (function "%u" -> url | "%f" -> Option.value file ~default:url | word -> word) r.run

(* the rules that need no writing: a film of YouTube's to mpv, asked
 * for by the menu (by a type, a program would run with no click: those
 * are the person's to write) *)
let defaults : t =
  List.map (fun site -> { site = Some site; kind = None; run = [ "mpv"; "%u" ] }) [ "youtube.com/watch"; "youtube.com/shorts/"; "youtu.be/" ]

(* is the program there: a path that is a file, or a name in one of PATH's directories *)
let found : (string, bool) Hashtbl.t = Hashtbl.create 8

let installed (caps : < Cap.env ; .. >) (program : string) : bool =
  match Hashtbl.find_opt found program with
  | Some b -> b
  | None ->
      let path = match CapSys.getenv caps "PATH" with p -> p | exception Not_found -> "" in
      let is_file f = Sys.file_exists f && not (Sys.is_directory f) in
      let b = if String.contains program '/' then is_file program else List.exists (fun dir -> dir <> "" && is_file (Filename.concat dir program)) (String.split_on_char ':' path) in
      Hashtbl.replace found program b;
      b

let table (caps : < Cap.env ; .. >) (own : t) : t =
  List.filter (fun r -> match r.run with program :: _ -> installed caps program | [] -> false) (own @ defaults)

(*****************************************************************************)
(* Running one *)
(*****************************************************************************)

(* those started and not yet seen ended *)
let running : int list ref = ref []

let launch (caps : < Cap.exec ; .. >) (argv : string list) : (unit, string) result =
  match argv with
  | [] -> Error "no program"
  | program :: _ -> (
      (* the authority to run it, asked for before it is *)
      let (_ : Cap.Exec.t) = caps#exec program in
      running := List.filter (fun pid -> match Unix.waitpid [ Unix.WNOHANG ] pid with 0, _ -> true | _ -> false | exception Unix.Unix_error _ -> false) !running;
      Logs.info (fun m -> m "running %s" (String.concat " " argv));
      try
        let nothing = Unix.openfile "/dev/null" [ Unix.O_RDONLY ] 0 in
        let pid = Fun.protect ~finally:(fun () -> Unix.close nothing) (fun () -> Unix.create_process program (Array.of_list argv) nothing Unix.stdout Unix.stderr) in
        running := pid :: !running;
        Ok ()
      with Unix.Unix_error (e, _, _) -> Error (program ^ ": " ^ Unix.error_message e))

let opened (caps : < Cap.exec ; Cap.open_out ; .. >) (r : rule) ~(url : string) (body : string) : string =
  let said =
    try
      let base = match host_and_path url with Some (_, path) -> Filename.basename (List.hd (String.split_on_char '?' path)) | None -> "" in
      let file = Filename.temp_file "mini-chrome-" (if base = "" || base = "/" then "" else "-" ^ base) in
      let (_ : Cap.FS_.open_out) = caps#open_out file in
      Logs.info (fun m -> m "writing %s" file);
      Out_channel.with_open_bin file (fun oc -> Out_channel.output_string oc body);
      match launch caps (command r ~url ~file:(Some file)) with
      | Ok () -> Printf.sprintf "Opened with <b>%s</b>, from the file <code>%s</code>." (name r) file
      | Error why -> "Could not be opened: " ^ why ^ "."
    with Sys_error why -> "Could not be written to a file: " ^ why ^ "."
  in
  Printf.sprintf "<title>%s</title><h1>%s</h1><p>%s<p>A helper program of the profile's Preferences (\"helpers\")." (name r) (name r) said
