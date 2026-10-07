(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Browser_replay.mli *)

(* an address's name in a recording: the query left out, since it is
 * not the same twice (a request's number, a time) *)
let key (url : string) : string = Digest.to_hex (Digest.string (List.hd (String.split_on_char '?' url)))

(* how many answers were written for an address *)
let written : (string, int) Hashtbl.t = Hashtbl.create 16

let record (dir : string) (url : string) (body : string) : unit =
  let n = 1 + Option.value (Hashtbl.find_opt written (key url)) ~default:0 in
  Hashtbl.replace written (key url) n;
  try
    let seq = Filename.concat dir "_seq" in
    if not (Sys.file_exists seq) then Sys.mkdir seq 0o700;
    Out_channel.with_open_bin (Filename.concat seq (Printf.sprintf "%s-%d" (key url) n)) (fun oc -> Out_channel.output_string oc body)
  with Sys_error _ -> ()

let answers (dir : string) : string -> string option =
  (* how many were given, and whether the page was *)
  let given : (string, int) Hashtbl.t = Hashtbl.create 16 and first = ref true in
  fun url ->
    let read f = Some (In_channel.with_open_bin f In_channel.input_all) in
    let is_file f = try Sys.file_exists f && not (Sys.is_directory f) with Sys_error _ -> false in
    let n = 1 + Option.value (Hashtbl.find_opt given (key url)) ~default:0 in
    let seq = Filename.concat (Filename.concat dir "_seq") (Printf.sprintf "%s-%d" (key url) n) in
    let long = Filename.concat (Filename.concat dir "_long") (key url) in
    let path = match Str.bounded_split (Str.regexp "://[^/]*/") (List.hd (String.split_on_char '?' url)) 2 with [ _; p ] -> Filename.concat dir p | _ -> dir in
    let page = Filename.concat dir "page.html" in
    let was_first = !first in
    first := false;
    if was_first && is_file page then read page
    else if is_file seq then (
      Hashtbl.replace given (key url) n;
      read seq)
    else if is_file long then read long
    else if is_file path then read path
    else None
