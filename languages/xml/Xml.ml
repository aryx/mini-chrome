(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Xml.mli *)

let is_space (c : char) : bool = c = ' ' || c = '\n' || c = '\t' || c = '\r'

(*****************************************************************************)
(* References *)
(*****************************************************************************)

let entities (s : string) : string =
  if not (String.contains s '&') then s
  else
    let b = Buffer.create (String.length s) in
    let n = String.length s in
    let rec go i =
      if i < n then
        if s.[i] = '&' then
          match String.index_from_opt s i ';' with
          | Some j when j - i <= 10 -> (
              let name = String.sub s (i + 1) (j - i - 1) in
              let code =
                match name with
                | "amp" -> Some 38 | "lt" -> Some 60 | "gt" -> Some 62 | "quot" -> Some 34 | "apos" -> Some 39
                | _ when String.length name > 1 && name.[0] = '#' ->
                    int_of_string_opt (if name.[1] = 'x' then "0" ^ String.sub name 1 (String.length name - 1) else String.sub name 1 (String.length name - 1))
                | _ -> None
              in
              match code with
              | Some c when c < 128 -> Buffer.add_char b (Char.chr c); go (j + 1)
              | Some c when Uchar.is_valid c -> Buffer.add_utf_8_uchar b (Uchar.of_int c); go (j + 1)
              | _ -> Buffer.add_char b '&'; go (i + 1))
          | _ -> Buffer.add_char b '&'; go (i + 1)
        else (Buffer.add_char b s.[i]; go (i + 1))
    in
    go 0;
    Buffer.contents b

(*****************************************************************************)
(* Reading *)
(*****************************************************************************)

let parse (s : string) : Dom.node list =
  let n = String.length s in
  let pos = ref 0 in
  let starts_with p = !pos + String.length p <= n && String.sub s !pos (String.length p) = p in
  (* the place after the next [p], and what was before it *)
  let skip_past p : string =
    let start = !pos in
    let rec go i = if i + String.length p > n then (n, n) else if String.sub s i (String.length p) = p then (i, i + String.length p) else go (i + 1) in
    let stop, after = go !pos in
    pos := after;
    String.sub s start (stop - start)
  in
  let skip_spaces () = while !pos < n && is_space s.[!pos] do incr pos done in
  let name () =
    let start = !pos in
    while !pos < n && not (is_space s.[!pos] || s.[!pos] = '>' || s.[!pos] = '/' || s.[!pos] = '=') do incr pos done;
    String.sub s start (!pos - start)
  in
  (* after "<name": the attributes, then ">" or "/>"; whether it is
   * an empty element *)
  let rec attributes acc =
    skip_spaces ();
    if !pos >= n then (List.rev acc, true)
    else if starts_with "/>" then (pos := !pos + 2; (List.rev acc, true))
    else if s.[!pos] = '>' then (incr pos; (List.rev acc, false))
    else
      let key = name () in
      skip_spaces ();
      if !pos < n && s.[!pos] = '=' then (
        incr pos;
        skip_spaces ();
        let value =
          if !pos < n && (s.[!pos] = '"' || s.[!pos] = '\'') then (
            let q = s.[!pos] in
            let start = !pos + 1 in
            let stop = match String.index_from_opt s start q with Some j -> j | None -> n in
            pos := min n (stop + 1);
            String.sub s start (stop - start))
          else name ()
        in
        attributes ((key, entities value) :: acc))
      else if key = "" then (incr pos; attributes acc)
      else attributes ((key, "") :: acc)
  in
  let text acc (raw : string) (decoded : string) : Dom.node list = if String.for_all is_space raw then acc else Text decoded :: acc in
  (* the nodes until "</" or the end *)
  let rec nodes (acc : Dom.node list) : Dom.node list =
    if !pos >= n then List.rev acc
    else if s.[!pos] <> '<' then (
      let start = !pos in
      (match String.index_from_opt s !pos '<' with Some j -> pos := j | None -> pos := n);
      let raw = String.sub s start (!pos - start) in
      nodes (text acc raw (entities raw)))
    else if starts_with "<!--" then (ignore (skip_past "-->"); nodes acc)
    else if starts_with "<![CDATA[" then (
      pos := !pos + 9;
      let raw = skip_past "]]>" in
      nodes (text acc raw raw))
    else if starts_with "<?" then (ignore (skip_past "?>"); nodes acc)
    else if starts_with "<!" then (
      (* <!DOCTYPE x [ its own declarations ]> *)
      let head = skip_past ">" in
      if String.contains head '[' && not (String.contains head ']') then ignore (skip_past "]>");
      nodes acc)
    else if starts_with "</" then (ignore (skip_past ">"); List.rev acc)
    else (
      incr pos;
      let name = name () in
      let attributes, empty = attributes [] in
      let children = if empty then [] else nodes [] in
      nodes (Element (Dom.element ~attributes name children) :: acc))
  in
  nodes []

(*****************************************************************************)
(* The tree read *)
(*****************************************************************************)

let local (name : string) : string = match String.index_opt name ':' with Some i -> String.sub name (i + 1) (String.length name - i - 1) | None -> name

let rec find (name : string) (nodes : Dom.node list) : Dom.element option =
  List.find_map (fun (nd : Dom.node) -> match nd with Element e when local e.name = name -> Some e | Element e -> find name e.children | Text _ -> None) nodes
