(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Svg_shapes.mli *)
open Playground

(* something that is not a shape: the rasterizer's *)
exception Not_a_shape

let numbers (s : string) : float list =
  String.split_on_char ' ' (String.map (fun c -> if c = ',' || c = '\n' || c = '\t' then ' ' else c) s) |> List.filter_map float_of_string_opt

type op = Translate of float * float | Rotate of float | Scale of float

(* "translate(100, -50) rotate(30) scale(2)", left to right *)
let ops (s : string) : op list =
  String.split_on_char ')' s
  |> List.filter_map (fun part ->
         match String.split_on_char '(' (String.trim part) with
         | [ "" ] -> None
         | [ name; args ] -> (
             match (String.trim name, numbers args) with
             | "translate", [ x ] -> Some (Translate (x, 0.))
             | "translate", [ x; y ] -> Some (Translate (x, y))
             | "rotate", [ a ] -> Some (Rotate a)
             | "scale", [ k ] -> Some (Scale k)
             | "scale", [ k; k' ] when k = k' -> Some (Scale k)
             | _ -> raise Not_a_shape)
         | _ -> raise Not_a_shape)

(* the transforms applied, the last written first; a rotation and a
 * scale are about the origin, so of a group if the shape was moved *)
let transformed (ops : op list) (sh : shape) : shape =
  let at_origin (sh : shape) = if sh.x = 0. && sh.y = 0. then sh else group [ sh ] in
  List.fold_right
    (fun op sh -> match op with Translate (x, y) -> move x (-.y) sh | Rotate a -> rotate (-.a) (at_origin sh) | Scale k -> scale k (at_origin sh))
    ops sh

let elements (e : Dom.element) : Dom.element list = List.filter_map (fun (c : Dom.node) -> match c with Element e -> Some e | Text _ -> None) e.children

let rec of_element ~(picture_of : string -> Rgba_image.t option) (e : Dom.element) : shape list =
  let attr name = Dom.attribute ~extensions:true name e in
  let num name = match Option.bind (attr name) float_of_string_opt with Some f -> f | None -> 0. in
  let given name v = match attr name with Some v' -> v' = v | None -> false in
  (* no fill said is black; none is nothing drawn *)
  let filled (make : color -> shape) : shape list =
    match Svg.color (Option.value (attr "fill") ~default:"black") with Some (r, g, b) -> [ make (rgb r g b) ] | None -> []
  in
  (match (attr "stroke", attr "clip-path", attr "mask", attr "filter") with (None | Some "none"), None, None, None -> () | _ -> raise Not_a_shape);
  let made =
    match e.name with
    | "g" -> [ group (List.concat_map (of_element ~picture_of) (elements e)) ]
    | "rect" when attr "rx" = None && attr "ry" = None ->
        let w = num "width" and h = num "height" in
        filled (fun c -> rectangle c w h |> move (num "x" +. (w /. 2.)) (-.(num "y" +. (h /. 2.))))
    | "circle" -> filled (fun c -> circle c (num "r") |> move (num "cx") (-.num "cy"))
    | "ellipse" -> filled (fun c -> oval c (2. *. num "rx") (2. *. num "ry") |> move (num "cx") (-.num "cy"))
    | "polygon" ->
        let rec pairs l = match l with x :: y :: rest -> (x, -.y) :: pairs rest | _ -> [] in
        filled (fun c -> polygon c (pairs (numbers (Option.value (attr "points") ~default:""))))
    (* the Playground's words: centred on their place both ways *)
    | "text" when given "text-anchor" "middle" && given "dominant-baseline" "central" ->
        let size = match Option.bind (attr "font-size") float_of_string_opt with Some s -> s | None -> 16. in
        filled (fun c -> words c (Dom.text_content e) |> scale (size /. words_font_size) |> move (num "x") (-.num "y"))
    (* a picture not come yet: nothing; img: what an HTML parser makes of <image> *)
    | "image" | "img" -> (
        let w = num "width" and h = num "height" in
        match Option.bind (attr "href") picture_of with
        | Some img -> [ bitmap w h img |> move (num "x" +. (w /. 2.)) (-.(num "y" +. (h /. 2.))) ]
        | None -> [])
    | "title" | "desc" | "defs" | "metadata" -> []
    | _ -> raise Not_a_shape
  in
  let opacity = match Option.bind (attr "opacity") float_of_string_opt with Some a -> a | None -> 1. in
  let ops = match attr "transform" with Some t -> ops t | None -> [] in
  List.map (fun sh -> transformed ops (if opacity < 1. then fade opacity sh else sh)) made

let shapes ~(picture_of : string -> Rgba_image.t option) (svg : Dom.element) ~(width : float) ~(height : float) : shape list option =
  match List.concat_map (of_element ~picture_of) (elements svg) with
  | exception Not_a_shape -> None
  | inside ->
      (* the viewBox fitted in the box, its centre on the box's *)
      let x, y, vw, vh = match Option.map numbers (Dom.attribute ~extensions:true "viewbox" svg) with Some [ x; y; w; h ] when w > 0. && h > 0. -> (x, y, w, h) | _ -> (0., 0., width, height) in
      let k = Float.min (width /. vw) (height /. vh) in
      Some [ group [ group inside |> move (-.(x +. (vw /. 2.))) (y +. (vh /. 2.)) ] |> scale k ]
