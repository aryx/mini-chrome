(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Lynx.mli *)

type page = { url : string; title : string; lines : string list; links : string list }
type t = page list
type step = Go of t | Stay of string | Quit

(* the text of the first <title> *)
let title_of (tree : Dom.element) : string =
  let rec text (n : Dom.node) = match n with Text s -> s | Element e -> String.concat "" (List.map text e.children) in
  let rec find (e : Dom.element) : string option =
    if e.name = "title" then Some (String.trim (text (Element e)))
    else List.find_map (fun (c : Dom.node) -> match c with Element c -> find c | Text _ -> None) e.children
  in
  Option.value (find tree) ~default:""

let is_web (address : string) : bool = String.starts_with ~prefix:"http://" address || String.starts_with ~prefix:"https://" address

let open_ (caps : < Cap.network ; Cap.open_in ; .. >) ?(width = 80) (address : string) : (page, string) result =
  let ( let* ) = Result.bind in
  let file = if String.starts_with ~prefix:"file://" address then String.sub address 7 (String.length address - 7) else address in
  let* url, content_type, bytes =
    if (not (is_web address)) && Sys.file_exists file && not (Sys.is_directory file) then (
      let (_ : Cap.FS_.open_in) = caps#open_in file in
      Ok ("file://" ^ file, None, In_channel.with_open_bin file In_channel.input_all))
    else
      let address = if is_web address then address else "http://" ^ address in
      let* url, (r : Http.response) = Http_client.fetch caps address in
      if r.status >= 400 then Error (Printf.sprintf "%s: %d %s" url r.status r.reason) else Ok (url, Http.header "Content-Type" r.headers, r.body)
  in
  let text = Charset.to_utf_8 (Charset.detect ?content_type bytes) bytes in
  let html = match content_type with Some ct -> String.starts_with ~prefix:"text/html" (String.lowercase_ascii ct) | None -> not (Filename.check_suffix url ".txt") in
  (* a text that is not HTML: its lines as they are *)
  if not html then Ok { url; title = ""; lines = String.split_on_char '\n' text; links = [] }
  else
    let tree = Html_tree.of_string text in
    let shown = Line_mode.render ~width tree in
    Ok { url; title = title_of tree; lines = shown.lines; links = List.map (Browser_url.resolve url) shown.links }

let show (p : page) : string =
  let head = if p.title = "" then p.url else Printf.sprintf "%s  (%s)" p.title p.url in
  let links = List.mapi (fun i l -> Printf.sprintf "[%d] %s" (i + 1) l) p.links in
  String.concat "\n" ((head :: "" :: p.lines) @ (if links = [] then [] else "" :: links)) ^ "\n"

let step (caps : < Cap.network ; Cap.open_in ; .. >) ?width (session : t) (typed : string) : step =
  let go address = match open_ caps ?width address with Ok p -> Go (p :: session) | Error why -> Stay why in
  match (String.trim typed, session) with
  | ("q" | "quit"), _ -> Quit
  | "", _ -> Go session
  | "b", _ :: (_ :: _ as before) -> Go before
  | "b", _ -> Stay "no page before this one"
  | typed, here :: _ when int_of_string_opt typed <> None -> (
      match if int_of_string typed >= 1 then List.nth_opt here.links (int_of_string typed - 1) else None with
      | Some link -> go link
      | None -> Stay (Printf.sprintf "no link %s: this page has %d" typed (List.length here.links)))
  | address, _ -> go address
