(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Shadow_tree.mli *)
open Dom

let attr (name : string) (e : element) : string option = Dom.attribute ~extensions:true name e

(* the slot a light node asks for: "" is the one with no name *)
let wanted (n : node) : string = match n with Element e -> Option.value (attr "slot" e) ~default:"" | Text _ -> ""

let distribute ~(shadow : node list) ~(light : node list) : node list =
  let rec node (n : node) : node list =
    match n with
    | Element ({ name = "slot"; _ } as slot) -> (
        let name = Option.value (attr "name" slot) ~default:"" in
        match List.filter (fun l -> wanted l = name) light with
        (* given nothing but spaces between the tags: its own content *)
        | given when List.exists (fun l -> match l with Text t -> String.trim t <> "" | Element _ -> true) given -> given
        | _ -> List.concat_map node slot.children)
    | Element e -> [ Element { e with children = List.concat_map node e.children } ]
    | Text _ -> [ n ]
  in
  List.concat_map node shadow

let is_root (n : node) : bool = match n with Element ({ name = "template"; _ } as t) -> attr "shadowrootmode" t <> None | _ -> false

let rec composed (e : element) : element =
  (* its children first: a host can be in a host's shadow tree, or in its light one *)
  let children = List.map (fun n -> match n with Element c -> let c' = composed c in if c' == c then n else Element c' | Text _ -> n) e.children in
  match List.find_opt is_root children with
  | Some (Element root) -> { e with children = distribute ~shadow:root.children ~light:(List.filter (fun n -> not (is_root n)) children) }
  | _ -> if List.for_all2 ( == ) children e.children then e else { e with children }
