(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Forms.mli *)

type kind = Text | Password | Checkbox | Radio | Submit | Reset | Button | Hidden | Select of (string * string) list | Textarea
type value = { text : string; checked : bool; selected : int }
type control = { element : Dom.element; kind : kind; name : string option; initial : value }
type form = { action : string; post : bool; controls : control list }

let lower (s : string option) : string option = Option.map String.lowercase_ascii s
let has (name : string) (e : Dom.element) : bool = Dom.attribute name e <> None

(* a <select>'s options: the label (the text), the value (value=, else
 * the text), and the first one selected (else the first) *)
let options (e : Dom.element) : (string * string) list * int =
  let opts = Dom.find_all "option" e in
  let labels =
    List.map
      (fun o ->
        let label = String.trim (Dom.text_content o) in
        (label, Option.value (Dom.attribute "value" o) ~default:label))
      opts
  in
  let rec first i = function [] -> 0 | o :: rest -> if has "selected" o then i else first (i + 1) rest in
  (labels, first 0 opts)

let control (e : Dom.element) : control option =
  let name = Dom.attribute "name" e in
  let text = Option.value (Dom.attribute "value" e) ~default:"" in
  let value ?(checked = false) ?(selected = 0) text = { text; checked; selected } in
  match e.name with
  | "input" -> (
      let kind =
        match lower (Dom.attribute "type" e) with
        | None | Some "text" -> Some Text
        | Some "password" -> Some Password
        | Some "checkbox" -> Some Checkbox
        | Some "radio" -> Some Radio
        | Some "submit" -> Some Submit
        | Some "reset" -> Some Reset
        | Some "button" -> Some Button
        | Some "hidden" -> Some Hidden
        | Some _ -> None
      in
      match kind with
      | Some kind -> Some { element = e; kind; name; initial = value ~checked:(has "checked" e) text }
      | None -> None)
  | "select" ->
      let opts, selected = options e in
      Some { element = e; kind = Select opts; name; initial = value ~selected "" }
  | "textarea" -> Some { element = e; kind = Textarea; name; initial = value (Dom.text_content e) }
  | _ -> None

let label (c : control) : string =
  match (Dom.attribute "value" c.element, c.kind) with
  | Some v, _ -> v
  | None, Reset -> "Reset"
  | None, Button -> ""
  | None, _ -> "Submit Query"

let rec controls_in (e : Dom.element) : control list =
  match control e with
  | Some c -> [ c ]
  | None -> List.concat_map (fun (n : Dom.node) -> match n with Element c -> controls_in c | Text _ -> []) e.children

let forms (root : Dom.element) : form list =
  Dom.find_all "form" root
  |> List.map (fun (f : Dom.element) ->
         {
           action = Option.value (Dom.attribute "action" f) ~default:"";
           post = lower (Dom.attribute "method" f) = Some "post";
           controls = controls_in f;
         })

let form_of (forms : form list) (e : Dom.element) : form option =
  List.find_opt (fun f -> List.exists (fun c -> c.element == e) f.controls) forms

(* a click on [e]: the <button> it is, or is in, if that button sends
 * its form (type=submit, or no type: HTML's default) -- the form and
 * the button. A <button> is not a control drawn by the browser as an
 * <input> is (its content is the page's, styled by the page), but a
 * click on it submits all the same *)
let submitting (root : Dom.element) (e : Dom.element) : (form * Dom.element) option =
  (* [e] and its ancestors, the nearest first *)
  let rec path (x : Dom.element) (above : Dom.element list) : Dom.element list option =
    if x == e then Some (x :: above)
    else List.find_map (fun (n : Dom.node) -> match n with Dom.Element c -> path c (x :: above) | Text _ -> None) x.children
  in
  let rec button (chain : Dom.element list) =
    match chain with
    | [] -> None
    | b :: up when b.name = "button" -> (
        match (lower (Dom.attribute "type" b), has "disabled" b, List.find_opt (fun (f : Dom.element) -> f.name = "form") up) with
        | (None | Some "submit"), false, Some f ->
            Some ({ action = Option.value (Dom.attribute "action" f) ~default:""; post = lower (Dom.attribute "method" f) = Some "post"; controls = controls_in f }, b)
        | _ -> None)
    | _ :: up -> button up
  in
  Option.bind (path root []) button

let submission (f : form) ~(value : Dom.element -> value) ~(submitter : Dom.element option) : (string * string) list =
  List.filter_map
    (fun c ->
         match c.name with
         | None -> None
         | Some name -> (
             let v = value c.element in
             match c.kind with
             | Text | Password | Hidden | Textarea -> Some (name, v.text)
             | Checkbox | Radio ->
                 if v.checked then Some (name, Option.value (Dom.attribute "value" c.element) ~default:"on") else None
             | Select opts -> (
                 match List.nth_opt opts v.selected with Some (_, value) -> Some (name, value) | None -> None)
             | Submit -> (
                 match submitter with Some s when s == c.element -> Some (name, v.text) | _ -> None)
             | Reset | Button -> None))
    f.controls
  (* a <button>'s own name and value, after the controls' *)
  @
  match submitter with
  | Some b when b.name = "button" -> ( match Dom.attribute "name" b with Some n -> [ (n, Option.value (Dom.attribute "value" b) ~default:"") ] | None -> [])
  | _ -> []
