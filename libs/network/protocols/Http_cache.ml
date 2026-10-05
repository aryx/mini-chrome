(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Http_cache.mli *)

type entry = { url : string; stored : float; response : Http.response }
type store = { find : string -> entry option; keep : entry -> unit; entries : now:float -> (string * int * float * bool) list; place : string }

(* a header's values cut at the commas, in small letters: "max-age=60,
 * Public" -> [ ("max-age", "60"); ("public", "") ] *)
let directives (name : string) (headers : Http.header list) : (string * string) list =
  Http.values name headers
  |> List.concat_map (String.split_on_char ',')
  |> List.filter_map (fun d ->
         match String.split_on_char '=' (String.trim d) with
         | [ "" ] -> None
         | k :: v -> Some (String.lowercase_ascii k, String.concat "=" v)
         | [] -> None)

let seconds (name : string) (headers : Http.header list) : float option = Option.bind (Http.header name headers) (fun v -> float_of_string_opt (String.trim v))

let lifetime ~(stored : float) (headers : Http.header list) : float =
  let control = directives "Cache-Control" headers in
  if List.mem_assoc "no-cache" control then 0.
  else
    match Option.bind (List.assoc_opt "max-age" control) float_of_string_opt with
    | Some age -> age -. Option.value (seconds "Age" headers) ~default:0.
    | None -> (
        match Option.bind (Http.header "Expires" headers) Cookie.date with
        | Some expires -> expires -. Option.value (Option.bind (Http.header "Date" headers) Cookie.date) ~default:stored
        | None -> 0.)

let validators_of (headers : Http.header list) : Http.header list =
  (match Http.header "ETag" headers with Some tag -> [ ("If-None-Match", tag) ] | None -> [])
  @ match Http.header "Last-Modified" headers with Some date -> [ ("If-Modified-Since", date) ] | None -> []

let storable (r : Http.response) : bool =
  r.status = 200
  && (not (List.mem_assoc "no-store" (directives "Cache-Control" r.headers)))
  && List.for_all (fun (name, _) -> name = "accept-encoding") (directives "Vary" r.headers)
  && (lifetime ~stored:0. r.headers > 0. || validators_of r.headers <> [])

let fresh ~(now : float) (e : entry) : bool = now -. e.stored < lifetime ~stored:e.stored e.response.headers
let validators (e : entry) : Http.header list = validators_of e.response.headers

let revalidated ~(now : float) (e : entry) (r : Http.response) : entry =
  let said name = List.exists (fun (n, _) -> String.lowercase_ascii n = String.lowercase_ascii name) r.headers in
  (* the copy's Age was of its first coming *)
  let kept = List.filter (fun (name, _) -> not (said name || String.lowercase_ascii name = "age")) e.response.headers in
  { e with stored = now; response = { e.response with headers = r.headers @ kept } }

let magic = "mini-chrome cache 1"

let to_string (e : entry) : string =
  let b = Buffer.create (String.length e.response.body + 512) in
  List.iter (fun line -> Buffer.add_string b line; Buffer.add_char b '\n')
    ([ magic; e.url; Printf.sprintf "%.0f" e.stored; string_of_int e.response.status ] @ List.map (fun (k, v) -> k ^ ": " ^ v) e.response.headers @ [ "" ]);
  Buffer.add_string b e.response.body;
  Buffer.contents b

let of_string (s : string) : entry option =
  (* the lines up to the empty one, then the body as it is *)
  let rec lines (from : int) (acc : string list) : (string list * string) option =
    match String.index_from_opt s from '\n' with
    | None -> None
    | Some i when i = from -> Some (List.rev acc, String.sub s (i + 1) (String.length s - i - 1))
    | Some i -> lines (i + 1) (String.sub s from (i - from) :: acc)
  in
  match lines 0 [] with
  | Some (m :: url :: stored :: status :: headers, body) when m = magic -> (
      let header (line : string) = match String.index_opt line ':' with Some i -> Some (String.sub line 0 i, String.trim (String.sub line (i + 1) (String.length line - i - 1))) | None -> None in
      match (float_of_string_opt stored, int_of_string_opt status) with
      | Some stored, Some status -> Some { url; stored; response = { version = "HTTP/1.1"; status; reason = "OK"; headers = List.filter_map header headers; body } }
      | _ -> None)
  | _ -> None
