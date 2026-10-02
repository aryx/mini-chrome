(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Glyph_picture.mli *)

let density = ref 1.

(* a letter's picture, and where it sits from the letter's left edge on
 * its baseline: its left and its top (y up), its size, in units *)
type picture = { img : Rgba_image.t; left : float; top : float; w : float; h : float }

let pictures : (string * Style.t * (int * int * int) * float, picture option) Hashtbl.t = Hashtbl.create 256
let kept () = Hashtbl.length pictures

(* the distance from p to the segment a b (a point, if a = b) *)
let distance (px, py) ((ax, ay), (bx, by)) : float =
  let dx = bx -. ax and dy = by -. ay in
  let len2 = (dx *. dx) +. (dy *. dy) in
  let t = if len2 = 0. then 0. else Float.max 0. (Float.min 1. ((((px -. ax) *. dx) +. ((py -. ay) *. dy)) /. len2)) in
  Float.hypot (px -. (ax +. (t *. dx))) (py -. (ay +. (t *. dy)))

(* a stroke's segments; a stroke of one point is a dot *)
let rec segments = function [ a ] -> [ (a, a) ] | a :: (b :: _ as rest) -> (a, b) :: (match rest with [ _ ] -> [] | _ -> segments rest) | [] -> []

let make ~(pen : float) ((r, g, b) : int * int * int) (strokes : (float * float) list list) : picture option =
  let d = !density in
  match List.concat strokes with
  | [] -> None
  | points ->
      let segs = List.concat_map segments strokes in
      (* the ink's box, the pen's half width and a pixel of soft edge round it *)
      let margin = (pen /. 2.) +. (1. /. d) in
      let fold f init pick = List.fold_left (fun m p -> f m (pick p)) init points in
      let left = fold Float.min infinity fst -. margin and right = fold Float.max neg_infinity fst +. margin in
      let bottom = fold Float.min infinity snd -. margin and top = fold Float.max neg_infinity snd +. margin in
      let width = max 1 (int_of_float (Float.ceil ((right -. left) *. d))) and height = max 1 (int_of_float (Float.ceil ((top -. bottom) *. d))) in
      let img = Rgba_image.create ~width ~height in
      for row = 0 to height - 1 do
        for col = 0 to width - 1 do
          (* the pixel's centre, in the letter's units *)
          let p = (left +. ((float_of_int col +. 0.5) /. d), top -. ((float_of_int row +. 0.5) /. d)) in
          let nearest = List.fold_left (fun m s -> Float.min m (distance p s)) infinity segs in
          let alpha = Float.max 0. (Float.min 1. ((((pen /. 2.) -. nearest) *. d) +. 0.5)) in
          if alpha > 0. then begin
            let o = ((row * width) + col) * 4 in
            img.rgba.{o} <- r;
            img.rgba.{o + 1} <- g;
            img.rgba.{o + 2} <- b;
            img.rgba.{o + 3} <- int_of_float (Float.round (alpha *. 255.))
          end
        done
      done;
      Some { img; left; top; w = float_of_int width /. d; h = float_of_int height /. d }

let shape ~key:((ch, look, color) : string * Style.t * (int * int * int)) ~(pen : float) ~(strokes : unit -> (float * float) list list) ~(x : float)
    ~(baseline : float) : Playground.shape option =
  let d = !density in
  let key = (ch, look, color, d) in
  let picture =
    match Hashtbl.find_opt pictures key with
    | Some p -> p
    | None ->
        (* a page of every size and colour: start again rather than grow *)
        if Hashtbl.length pictures > 4096 then Hashtbl.reset pictures;
        let p = make ~pen color (strokes ()) in
        Hashtbl.replace pictures key p;
        p
  in
  Option.map
    (fun (p : picture) ->
      (* its top left on a whole pixel: sharp, at the price of half a
       * pixel of the pen's place *)
      let snap v = Float.round (v *. d) /. d in
      let left = snap (x +. p.left) and top = snap (baseline +. p.top) in
      Playground.bitmap p.w p.h p.img |> Playground.move (left +. (p.w /. 2.)) (top -. (p.h /. 2.)))
    picture
