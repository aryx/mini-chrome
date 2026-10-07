(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Frames.mli *)

type source = Inline of string | Address of string

let source (e : Dom.element) : source option =
  match (Dom.attribute "srcdoc" e, Dom.attribute "src" e) with
  | Some text, _ -> Some (Inline text)
  | None, Some src when String.trim src <> "" && not (String.starts_with ~prefix:"about:" src || String.starts_with ~prefix:"javascript:" src) -> Some (Address (String.trim src))
  | _ -> None

let addresses (tree : Dom.element) : string list =
  List.filter_map (fun e -> match source e with Some (Address a) -> Some a | _ -> None) (Dom.find_all "iframe" tree)

(* the documents read, by their text: a page is laid out again and
 * again, its frames' texts the same *)
let read_here = Per_domain.make (fun () : (int * int, string * Dom.element) Hashtbl.t -> Hashtbl.create 8)

let tree_of (text : string) : Dom.element =
  let key = (String.length text, Hashtbl.hash text) in
  match Hashtbl.find_opt (read_here ()) key with
  | Some (t, tree) when t == text || t = text -> tree
  | _ ->
      let tree = Html_tree.of_string text in
      if Hashtbl.length (read_here ()) > 16 then Hashtbl.reset (read_here ());
      Hashtbl.replace (read_here ()) key (text, tree);
      tree

let depth = 3

let rec graft (frame : Dom.element -> width:float -> height:float -> Box_types.box option) (b : Box_types.box) : Box_types.box =
  match b.element with
  | Some e when e.name = "iframe" -> (
      let bt, br, bb, bl = b.border in
      let pad l = Css_values.resolve l b.width in
      let pt, pr, pb, pl = b.style.padding in
      let x = b.x +. bl +. pad pl and y = b.y +. bt +. pad pt in
      let width = b.width -. bl -. br -. pad pl -. pad pr and height = b.height -. bt -. bb -. pad pt -. pad pb in
      if width < 1. || height < 1. then b else match frame e ~width ~height with Some inside -> { b with children = [ Box_tree.moved x y inside ] } | None -> b)
  | _ -> { b with children = List.map (graft frame) b.children }
