(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Script_dom.mli *)
open Js_value
open Script_types

(*****************************************************************************)
(* The copy: nodes with a parent *)
(*****************************************************************************)

let text_name = "#text"
let is_text (n : node) : bool = n.name = text_name

(* two more that are not elements: a comment (its text kept,
 * never shown), and a fragment, a parent for nodes on their way into
 * a tree (appended, its children go in its place) *)
let comment_name = "#comment"
let fragment_name = "#document-fragment"
let is_element (n : node) : bool = n.name = "" || n.name.[0] <> '#'
let make ?(text = "") ?(attributes = []) (name : string) : node =
  { name; text; attributes; children = []; parent = None; expando = []; wrapper = None; listeners = []; compiled = []; shadow = None }

let rec thaw (e : Dom.element) : node =
  let n = make e.name ~attributes:(e.attributes @ e.extensions) in
  let children =
    List.map
      (fun (c : Dom.node) ->
        let child = match c with Element e -> thaw e | Text s -> make text_name ~text:s in
        child.parent <- Some n;
        child)
      e.children
  in
  (* a <template shadowrootmode> written in the page is its parent's
   * shadow tree, not its child (Shadow_tree.mli: declarative) *)
  let declared (c : node) = c.name = "template" && List.mem_assoc "shadowrootmode" c.attributes in
  (match List.find_opt declared children with Some template -> attach_shadow n template.children | None -> ());
  n.children <- List.filter (fun c -> not (declared c)) children;
  n

(* a shadow tree's root for [host], holding [children]: a fragment,
 * whose parent is said to be the host -- so that what is put in it is
 * in the page, and an event in it goes up through the host *)
and attach_shadow (host : node) (children : node list) : unit =
  let root = make fragment_name in
  root.children <- children;
  List.iter (fun (c : node) -> c.parent <- Some root) children;
  root.parent <- Some host;
  host.shadow <- Some root

(* back into a Dom value: Netscape's attributes apart again (Dtd.origin),
 * as the lexer puts them *)
let rec freeze (n : node) : Dom.element =
  let origin = Dtd.element_origin n.name in
  let attributes, extensions =
    match origin with
    | Netscape -> (n.attributes, [])
    | Core -> List.partition (fun a -> Dtd.attribute_origin n.name a = Dtd.Core) n.attributes
  in
  let children = List.filter_map (fun c -> if is_text c then Some (Dom.Text c.text) else if is_element c then Some (Dom.Element (freeze c)) else None) n.children in
  { name = n.name; attributes; extensions; origin; children }

(* every element under [n] ([n] too), in document order *)
let rec elements (n : node) : node list = (if is_element n then [ n ] else []) @ List.concat_map elements n.children

let rec text_content (n : node) : string =
  if is_text n then n.text else String.concat "" (List.map text_content (List.filter (fun c -> c.name <> comment_name) n.children))

(* the top of the tree a node is in: the page's root, or that of a
 * tree a script made and has not put in the page *)
let rec top (n : node) : node = match n.parent with Some p -> top p | None -> n
let attribute (n : node) (k : string) : string option = List.assoc_opt k n.attributes

let set_attribute (n : node) (k : string) (v : string) : unit =
  n.attributes <- (if List.mem_assoc k n.attributes then List.map (fun (a, x) -> if a = k then (a, v) else (a, x)) n.attributes else n.attributes @ [ (k, v) ])

let detach (n : node) : unit =
  Option.iter (fun p -> p.children <- List.filter (fun c -> c != n) p.children) n.parent;
  n.parent <- None

let adopt (parent : node) (children : node list) : unit = List.iter (fun c -> c.parent <- Some parent) children

(*****************************************************************************)
(* HTML: innerHTML read and written *)
(*****************************************************************************)

let escape ?(quote = false) (s : string) : string =
  let b = Buffer.create (String.length s) in
  String.iter
    (fun c ->
      match c with
      | '&' -> Buffer.add_string b "&amp;"
      | '<' -> Buffer.add_string b "&lt;"
      | '>' -> Buffer.add_string b "&gt;"
      | '"' when quote -> Buffer.add_string b "&quot;"
      | c -> Buffer.add_char b c)
    s;
  Buffer.contents b

let rec html_of (n : node) : string =
  if is_text n then escape n.text
  else if n.name = comment_name then "<!--" ^ n.text ^ "-->"
  else if n.name = fragment_name then inner_html n
  else
    let attrs = String.concat "" (List.map (fun (k, v) -> Printf.sprintf " %s=\"%s\"" k (escape ~quote:true v)) n.attributes) in
    Printf.sprintf "<%s%s>%s%s" n.name attrs (inner_html n) (if Dtd.is_void n.name then "" else "</" ^ n.name ^ ">")

and inner_html (n : node) : string = String.concat "" (List.map html_of n.children)

(* a fragment's nodes: the parser makes a whole page of it, whose head
 * holds what belongs there (a <style>) and whose body the rest *)
let parse_fragment (s : string) : node list =
  let page = thaw (Html_tree.of_string s) in
  List.concat_map (fun (part : node) -> part.children) page.children

(*****************************************************************************)
(* Selectors *)
(*****************************************************************************)

(* the elements matching a selector, in document order, among those of
 * [n]'s tree that [keep]: matched on the frozen tree, with their
 * ancestors, as the page's style sheets are (Css.matches). The tree
 * is the one [n] is in: the page's, or one a script made and has not
 * put in the page (jQuery tries its selectors on such a one) *)
let matching (selector : string) (n : node) ~(keep : node -> bool) : node list =
  match Css.parse (selector ^ " {}") with
  | [] -> throw "SyntaxError" (Printf.sprintf "'%s' is not a valid selector" selector)
  | rules ->
      let found = ref [] in
      let rec go (ancestors : Dom.element list) (n : node) =
        if is_element n then (
          let e = freeze n in
          if keep n && List.exists (fun (r : Css.rule) -> Css.matches r.selector ancestors e) rules then found := n :: !found;
          List.iter (go (e :: ancestors)) n.children)
        else if n.name = fragment_name then List.iter (go ancestors) n.children
      in
      (* the tree [n] is in ends at a shadow root: what is in a shadow
       * tree is found from its root, not from the page (Shadow_tree.mli) *)
      let rec tree_of (n : node) : node = if n.name = fragment_name then n else match n.parent with Some p -> tree_of p | None -> n in
      go [] (tree_of n);
      List.rev !found

(* those under [within] *)
let select (_ : t) (selector : string) ~(within : node) : node list =
  let inside = elements within in
  matching selector within ~keep:(fun n -> n != within && List.memq n inside)

(* whether [n] itself matches *)
let matches (selector : string) (n : node) : bool = matching selector n ~keep:(fun c -> c == n) <> []
