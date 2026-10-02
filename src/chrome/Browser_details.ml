(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Browser_details.mli *)

let elements (e : Dom.element) : Dom.element list = List.filter_map (fun (n : Dom.node) -> match n with Element c -> Some c | Text _ -> None) e.children

let rec inside (e : Dom.element) (target : Dom.element) : bool = e == target || List.exists (fun c -> inside c target) (elements e)

let rec clicked (root : Dom.element) (target : Dom.element) : Dom.element option =
  (* the innermost first: a <details> in a <details> *)
  match List.find_map (fun c -> clicked c target) (elements root) with
  | Some d -> Some d
  | None ->
      (* its summary is its first <summary> child *)
      let summary = List.find_opt (fun (c : Dom.element) -> c.name = "summary") (elements root) in
      if root.name = "details" && (match summary with Some s -> inside s target | None -> false) then Some root else None

let is_open (details : Dom.element) : bool = Dom.attribute "open" details <> None

let rec toggled (root : Dom.element) (details : Dom.element) : Dom.element =
  if root == details then
    { root with attributes = (if is_open root then List.remove_assoc "open" root.attributes else root.attributes @ [ ("open", "") ]) }
  else if not (inside root details) then root
  else { root with children = List.map (fun (n : Dom.node) : Dom.node -> match n with Element c -> Element (toggled c details) | Text _ -> n) root.children }
