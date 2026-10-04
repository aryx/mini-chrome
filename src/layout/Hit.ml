(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Hit.mli *)

(* the link on a line at [x]: in a fragment, or in the space between
 * two fragments of the same link *)
let rec on_line (fragments : Html_layout.fragment list) (x : float) : string option =
  match fragments with
  | [] -> None
  | f :: rest ->
      if x >= f.x && x <= f.x +. f.width then f.look.link
      else (
        match rest with
        | next :: _ when x > f.x +. f.width && x < next.x && f.look.link <> None && f.look.link = next.look.link ->
            f.look.link
        | _ -> on_line rest x)

(* a box's children, the last drawn first: where two are at a point
 * (a positioned box over the flow, drawn after it), the one seen *)
let on_top (b : Html_layout.box) : Html_layout.box list = List.rev b.children

let rec link_at (b : Html_layout.box) ~(x : float) ~(y : float) : string option =
  if y < b.y || y > b.y +. b.height then None
  else
    let in_lines =
      List.find_map
        (fun (l : Html_layout.line) -> if y >= l.top && y <= l.top +. l.height then on_line l.fragments x else None)
        b.lines
    in
    match in_lines with Some _ -> in_lines | None -> List.find_map (fun c -> link_at c ~x ~y) (on_top b)

let rec fragment_at (b : Html_layout.box) ~(x : float) ~(y : float) : Html_layout.fragment option =
  if y < b.y || y > b.y +. b.height then None
  else
    let in_lines =
      List.find_map
        (fun (l : Html_layout.line) ->
          if y >= l.top && y <= l.top +. l.height then
            List.find_opt (fun (f : Html_layout.fragment) -> x >= f.x && x <= f.x +. f.width) l.fragments
          else None)
        b.lines
    in
    (* an inline-block is on its line as a fragment of no text,
     * its room, and what it holds is in a box under this one: a field
     * in an inline-block (Google's search box, in a <div
     * style="display: inline-block">) was hidden by the room it is in.
     * So such a fragment is the answer only if nothing inside is. *)
    let room (f : Html_layout.fragment) = f.text = "" && f.picture = None && f.control = None in
    match in_lines with
    | Some f when not (room f) -> in_lines
    | _ -> ( match List.find_map (fun c -> fragment_at c ~x ~y) (on_top b) with Some f -> Some f | None -> in_lines)

(* the element at a point: the fragment's there (a word, a picture, a
 * control, a float), else the innermost block around the point (a
 * table's cell, a list's item, the body) *)
let rec element_at (b : Html_layout.box) ~(x : float) ~(y : float) : Dom.element option =
  let inside (b : Html_layout.box) = x >= b.x && x <= b.x +. b.width && y >= b.y && y <= b.y +. b.height in
  let on (f : Html_layout.fragment) =
    let top = match f.picture with Some p -> f.baseline -. p.height | None -> f.baseline -. f.look.size in
    x >= f.x && x <= f.x +. f.width && y >= top && y <= f.baseline +. (0.3 *. f.look.size)
  in
  if not (inside b) && b.floats = [] then None
  else
    match List.find_opt on b.floats with
    | Some f -> Some f.element
    | None -> (
        match fragment_at b ~x ~y with
        | Some f when List.memq f (List.concat_map (fun (l : Html_layout.line) -> l.fragments) b.lines) -> Some f.element
        | _ -> (
            match List.find_map (fun c -> element_at c ~x ~y) (on_top b) with
            | Some e -> Some e
            | None -> ( match b.kind with Block e when inside b -> Some e | _ -> None)))

let rec anchor (b : Html_layout.box) (name : string) : float option =
  match b.kind with
  | Block e when Dom.attribute "id" e = Some name -> Some b.y
  | _ -> (
      match List.find_opt (fun (l : Html_layout.line) -> List.mem name l.anchors) b.lines with
      | Some l -> Some l.top
      | None -> List.find_map (fun c -> anchor c name) b.children)
