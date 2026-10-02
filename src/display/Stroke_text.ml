(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Stroke_text.mli *)

(* Hershey has glyphs for printable ASCII; anything else is its '?' *)
let char_of (s : string) = if String.length s = 1 then s.[0] else '?'

(* font units to the playground's, at a look's size *)
let scale_of (look : Style.t) = look.size /. Hershey.units_per_em

let metrics look s =
  let g = Hershey.glyph (char_of s) in
  float_of_int (g.right - g.left) *. scale_of look

(* claude: the line under text, and the one through it: [width] long
 * from [x], as thick as the look's pen nearly *)
let line color (look : Style.t) ~x ~width y =
  let pen = if look.bold then look.size /. 7. else look.size /. 16. in
  Playground.rectangle color width (pen *. 0.8) |> Playground.move (x +. (width /. 2.)) y

let underline color (look : Style.t) ~x ~width ~baseline = line color look ~x ~width (baseline -. (look.size *. 0.18))
let strike color (look : Style.t) ~x ~width ~baseline = line color look ~x ~width (baseline +. (look.size *. 0.25))

let glyph_segments color (look : Style.t) s ~x ~baseline =
  let g = Hershey.glyph (char_of s) in
  let k = scale_of look in
  (* a look is a pen: thicker for bold *)
  let pen = if look.bold then look.size /. 7. else look.size /. 16. in
  let slant = if look.italic then 0.2 else 0. in
  (* a point of the glyph, in the playground: Hershey's y goes down
   * with the baseline at 9, the playground's goes up from it *)
  let at (gx, gy) =
    let up = float_of_int (9 - gy) *. k in
    (x +. (float_of_int (gx - g.left) *. k) +. (up *. slant), baseline +. up)
  in
  let segment (x1, y1) (x2, y2) =
    let dx = x2 -. x1 and dy = y2 -. y1 in
    Playground.rectangle color (sqrt ((dx *. dx) +. (dy *. dy))) pen
    |> Playground.rotate (atan2 dy dx *. 180. /. Float.pi)
    |> Playground.move ((x1 +. x2) /. 2.) ((y1 +. y2) /. 2.)
  in
  (* claude: a round pen: a dot at each point of the stroke fills the
   * joint between two segments and rounds the stroke's ends.
   *
   * old: half the shapes (a stroke of n points was n-1 rectangles, now
   * 2n-1 with its dots), so faster, but the square corners of the
   * segments stuck out of each joint: spikes, once the page is zoomed.
   * The segments were one pen-width longer, so that joints overlapped
   * rather than leaving notches, and there was no dot:
   *
   *   let segment (x1, y1) (x2, y2) =
   *     let dx = x2 -. x1 and dy = y2 -. y1 in
   *     Playground.rectangle color (sqrt ((dx *. dx) +. (dy *. dy)) +. pen) pen
   *     |> Playground.rotate (atan2 dy dx *. 180. /. Float.pi)
   *     |> Playground.move ((x1 +. x2) /. 2.) ((y1 +. y2) /. 2.)
   *   in
   *   let strokes = List.concat_map (fun stroke -> pairs (List.map at stroke)) g.strokes in
   *)
  let dot (x, y) = Playground.circle color (pen /. 2.) |> Playground.move x y in
  let rec pairs = function a :: (b :: _ as rest) -> segment a b :: pairs rest | _ -> [] in
  let strokes =
    List.concat_map (fun stroke -> let points = List.map at stroke in pairs points @ List.map dot points) g.strokes
  in
  let advance = float_of_int (g.right - g.left) *. k in
  let rule y =
    Playground.rectangle color advance (pen *. 0.8) |> Playground.move (x +. (advance /. 2.)) y
  in
  strokes
  @ (if look.underline then [ rule (baseline -. (look.size *. 0.18)) ] else [])
  @ if look.strike then [ rule (baseline +. (look.size *. 0.25)) ] else []

(* claude: opti: the letter as one picture made once (Glyph_picture.mli
 * says why and what it costs), its underline and its strike still
 * rectangles: a frame of about:chrome drawn in 8 ms instead of 74. The
 * simple way, the pen's, is glyph_segments above (letters=segments,
 * opti=off). *)
let glyph_picture color (look : Style.t) s ~x ~baseline =
  match color with
  | Color.Rgb (r, g, b) ->
      let g' = Hershey.glyph (char_of s) in
      let k = scale_of look in
      let pen = if look.bold then look.size /. 7. else look.size /. 16. in
      let slant = if look.italic then 0.2 else 0. in
      (* glyph_segments' [at], from the letter's left edge on its baseline *)
      let at (gx, gy) =
        let up = float_of_int (9 - gy) *. k in
        ((float_of_int (gx - g'.left) *. k) +. (up *. slant), up)
      in
      (* the picture is the letter's alone: its lines are the fragment's *)
      let key = (s, { look with underline = false; strike = false }, (r, g, b)) in
      let letter = Glyph_picture.shape ~key ~pen ~strokes:(fun () -> List.map (List.map at) g'.strokes) ~x ~baseline in
      let advance = float_of_int (g'.right - g'.left) *. k in
      let rule y = Playground.rectangle color advance (pen *. 0.8) |> Playground.move (x +. (advance /. 2.)) y in
      Option.to_list letter
      @ (if look.underline then [ rule (baseline -. (look.size *. 0.18)) ] else [])
      @ if look.strike then [ rule (baseline +. (look.size *. 0.25)) ] else []
  | _ -> glyph_segments color look s ~x ~baseline

let glyph color (look : Style.t) s ~x ~baseline =
  match !Mini_opti.letters with
  | Pictures when !Mini_opti.enabled -> glyph_picture color look s ~x ~baseline
  | _ -> glyph_segments color look s ~x ~baseline
