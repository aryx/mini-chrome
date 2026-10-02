(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Mosaic_draw.mli *)

open Playground

let ready = Browser_draw.ready
let later = Browser_draw.later
let glyphs = Browser_draw.glyphs
let decorations = Browser_draw.decorations
let metrics = Browser_text.metrics

(* a bevelled frame [t] thick: [light] above and on the left, [dark]
 * below and on the right -- raised; the other way round, sunken *)
let bevel ~(light : color) ~(dark : color) ~(t : float) (x : float) (y : float) (w : float) (h : float) : shape list =
  [ rectangle light w t |> move (x +. (w /. 2.)) (-.(y +. (t /. 2.)));
    rectangle light t h |> move (x +. (t /. 2.)) (-.(y +. (h /. 2.)));
    rectangle dark w t |> move (x +. (w /. 2.)) (-.(y +. h -. (t /. 2.)));
    rectangle dark t h |> move (x +. w -. (t /. 2.)) (-.(y +. (h /. 2.))) ]

(* a table's border (Netscape 1.1's <table border=n>): the table raised
 * by n, each cell sunken by 1 -- Motif's look, the one the first
 * tables had *)
let table_frame (table : Dom.element) (b : Html_layout.box) : Browser_draw.drawn =
  let t =
    match Dom.attribute "border" table with
    | Some "" -> 1.
    | Some s -> Option.value (float_of_string_opt s) ~default:1.
    | None -> 0.
  in
  if t <= 0. then []
  else ready @@
    let light = rgb 240 240 240 and dark = rgb 110 110 110 in
    (* below its caption *)
    let top = match b.children with { kind = Block c; y; height; _ } :: _ when c.name = "caption" -> y +. height | _ -> b.y in
    let cells =
      List.concat_map
        (fun (c : Html_layout.box) ->
          match c.kind with
          | Block e when e.name = "td" || e.name = "th" -> bevel ~light:dark ~dark:light ~t:1. c.x c.y c.width c.height
          | _ -> [])
        b.children
    in
    [ (top, b.y +. b.height, group (bevel ~light ~dark ~t b.x top b.width (b.y +. b.height -. top) @ cells)) ]

let rec draw ?(extensions = false) ~(visited : string -> bool) ~(picture_of : string -> Browser_picture.t option)
    (b : Html_layout.box) : Browser_draw.drawn =
  let lines =
    List.map
      (fun (l : Html_layout.line) ->
        (l.top, l.top +. l.height, later (fun () -> group (decorations ~visited l.fragments @ List.concat_map (glyphs ~visited ~picture_of ~decorated:false) l.fragments))))
      b.lines
  in
  (* a box's floats, each drawn over its own height, not its line's *)
  let floats =
    List.filter_map
      (fun (f : Html_layout.fragment) ->
        match f.picture with
        | Some pic -> Some (f.baseline -. pic.height, f.baseline, group (glyphs ~visited ~picture_of f))
        | None -> None)
      b.floats
  in
  let rule =
    match b.kind with
    | Rule e when extensions && Dom.attribute ~extensions "noshade" e <> None ->
        (* Netscape's noshade: a flat grey bar *)
        [ (b.y, b.y +. b.height, rectangle (rgb 110 110 110) b.width b.height |> move (b.x +. (b.width /. 2.)) (-.b.y -. (b.height /. 2.))) ]
    | Rule _ ->
        (* an inset line, as Mosaic's Motif drew it: dark above, light
         * below; its sides too when Netscape's size= makes it thick *)
        let h = b.height in
        [ ( b.y,
            b.y +. h,
            group
              ([ rectangle (rgb 130 130 130) b.width 1. |> move (b.x +. (b.width /. 2.)) (-.b.y -. 0.5);
                 rectangle (rgb 235 235 235) b.width 1. |> move (b.x +. (b.width /. 2.)) (-.b.y -. h +. 0.5) ]
              @
              if h > 2. then
                [ rectangle (rgb 130 130 130) 1. h |> move (b.x +. 0.5) (-.b.y -. (h /. 2.));
                  rectangle (rgb 235 235 235) 1. h |> move (b.x +. b.width -. 0.5) (-.b.y -. (h /. 2.)) ]
              else []) ) ]
    | _ -> []
  in
  (* a list item's marker, left of its first line, in its list's indent *)
  let marker =
    match (b.marker, Html_layout.first_baseline b) with
    | Some Bullet, Some baseline ->
        [ (baseline -. 12., baseline, circle (rgb 0 0 0) 3. |> move (b.x -. 12.) (-.(baseline -. 5.))) ]
    | Some (Number n), Some baseline ->
        let text = string_of_int n ^ "." in
        let look = Browser_text.root_look in
        let width = metrics look text in
        [ ( baseline -. 12.,
            baseline,
            group (glyphs { text; look; x = b.x -. 6. -. width; width; baseline; picture = None; control = None; element = Dom.element "li" [] }) ) ]
    | _ -> []
  in
  let frame = match b.kind with Block e when extensions && e.name = "table" -> table_frame e b | _ -> [] in
  (* a style sheet's background-color: under the box's content *)
  let background =
    match b.background with
    | Some (r, g, bl) ->
        [ (b.y, b.y +. b.height, rectangle (rgb r g bl) b.width b.height |> move (b.x +. (b.width /. 2.)) (-.(b.y +. (b.height /. 2.)))) ]
    | None -> []
  in
  ready background @ lines @ ready (floats @ rule @ marker) @ frame @ List.concat_map (draw ~extensions ~visited ~picture_of) b.children
