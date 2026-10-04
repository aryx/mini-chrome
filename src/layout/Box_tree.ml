(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Box_tree.mli *)
open Box_types

let rec fragments (b : box) : Html_layout.fragment list =
  List.concat_map (fun (l : Html_layout.line) -> l.fragments) b.lines @ List.concat_map fragments b.children

(* a box and all it holds moved by (dx, dy): a float or an inline-block
 * is laid out where it will not stay *)
let rec moved (dx : float) (dy : float) (b : box) : box =
  if dx = 0. && dy = 0. then b
  else
    {
      b with
      x = b.x +. dx;
      y = b.y +. dy;
      children = List.map (moved dx dy) b.children;
      backdrops = List.map (moved dx dy) b.backdrops;
      (* a fixed box is the window's: it stays *)
      lifted = List.map (fun ((l : box), bottom) -> ((if l.style.position = Fixed then l else moved dx dy l), bottom)) b.lifted;
      lines =
        List.map
          (fun (l : Html_layout.line) ->
            {
              l with
              top = l.top +. dy;
              baseline = l.baseline +. dy;
              fragments = List.map (fun (f : Html_layout.fragment) -> { f with x = f.x +. dx; baseline = f.baseline +. dy }) l.fragments;
            })
          b.lines;
    }

(* how far right a box's content reaches, for shrink-to-fit: its lines'
 * words, its children's content -- a block of width auto is as wide as
 * its container, which is not what it needs *)
let rec inner_right (b : box) : float =
  let lines =
    List.fold_left
      (fun m (l : Html_layout.line) -> List.fold_left (fun m (f : Html_layout.fragment) -> Float.max m (f.x +. f.width)) m l.fragments)
      b.x b.lines
  in
  List.fold_left (fun m c -> Float.max m (right_edge c)) lines b.children

and right_edge (b : box) : float =
  (* a float's margin is room it takes on its line: three floats that
   * fit by their boxes alone do not fit with it (GitHub's Notifications,
   * Fork and Star, the last one pushed under the others) *)
  let margin = match (b.style.float, b.style.margin) with Side_none, _ -> 0. | _, (_, Len mr, _, _) -> Css_values.resolve mr 0. | _ -> 0. in
  margin
  +.
  match b.element with
  | Some _ when b.style.width <> Auto || b.style.display = Table -> b.x +. b.width
  | Some _ ->
      let _, pr, _, _ = b.style.padding and _, br, _, _ = b.border in
      inner_right b +. Css_values.resolve pr 0. +. br
  | None -> inner_right b

let rec last_baseline (b : box) : float option =
  match List.rev b.lines with
  | l :: _ -> Some l.baseline
  | [] -> List.fold_left (fun found c -> match last_baseline c with Some _ as s -> s | None -> found) None b.children

let rec as_html_layout (b : box) : Html_layout.box =
  {
    kind = (match b.element with Some e -> Block e | None -> Anonymous);
    x = b.x;
    y = b.y;
    width = b.width;
    height = b.height;
    children = List.map as_html_layout b.children;
    lines = b.lines;
    floats = [];
    marker = b.marker;
    background = None;
  }

let picture_src (e : Dom.element) : string option =
  match Dom.attribute "src" e with
  | Some s when String.trim s <> "" -> Some s
  | _ -> (
      (* "a.png 1x, b.png 2x": its first address *)
      match Dom.attribute "srcset" e with
      | Some set -> (
          match String.split_on_char ' ' (String.trim (List.hd (String.split_on_char ',' set))) with
          | url :: _ when url <> "" -> Some url
          | _ -> None)
      | None -> None)
