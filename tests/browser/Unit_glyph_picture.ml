(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_glyph_picture.mli *)

let look : Style.t = { Style.plain with size = 16. }
let black = Playground.rgb 0 0 0

(* the picture of a shape that is a bitmap *)
let image (s : Playground.shape) : Rgba_image.t = match s.form with Bitmap (_, _, img) -> img | _ -> Alcotest.fail "a bitmap"

let with_letters (l : Mini_opti.letters) (f : unit -> 'a) : 'a =
  Mini_opti.letters := l;
  Fun.protect ~finally:(fun () -> Mini_opti.letters := Pictures; Glyph_picture.density := 1.) f

(* an horizontal stroke 8 long, a pen of 2: Glyph_picture.mli's formula *)
let bar ~x = Glyph_picture.shape ~key:("-", look, (0, 0, 0)) ~pen:2. ~strokes:(fun () -> [ [ (0., 4.); (8., 4.) ] ]) ~x ~baseline:0.

let tests =
  Testo.categorize "Glyph_picture"
    [
      Testo.create "a stroke's picture: opaque on the pen's path, clear away from it" (fun () ->
          Glyph_picture.density := 1.;
          let img = image (Option.get (bar ~x:0.)) in
          (* the ink's box, 8 by 0, and round it the pen's half (1) and a pixel *)
          Alcotest.(check (pair int int)) "12 by 4" (12, 4) (img.width, img.height);
          let alpha col row = img.rgba.{(((row * img.width) + col) * 4) + 3} in
          Alcotest.(check int) "on the stroke" 255 (alpha 6 1);
          Alcotest.(check int) "its other half" 255 (alpha 6 2);
          Alcotest.(check int) "above it, the soft edge: no ink" 0 (alpha 6 0);
          Alcotest.(check bool) "its round end: fainter than the middle" true (alpha 1 1 > 0 && alpha 1 1 < 255);
          Alcotest.(check int) "past its end" 0 (alpha 0 0));
      Testo.create "made once: the same picture wherever the letter is, another at another density" (fun () ->
          Glyph_picture.density := 1.;
          let a = image (Option.get (bar ~x:0.)) and b = image (Option.get (bar ~x:100.)) in
          Alcotest.(check bool) "the very picture" true (a == b);
          Glyph_picture.density := 2.;
          let c = image (Option.get (bar ~x:0.)) in
          Alcotest.(check (pair int int)) "twice the dots, less the edge's half pixel" (22, 6) (c.width, c.height);
          Glyph_picture.density := 1.;
          Alcotest.(check bool) "no ink, no picture" true
            (Glyph_picture.shape ~key:(" ", look, (0, 0, 0)) ~pen:2. ~strokes:(fun () -> []) ~x:0. ~baseline:0. = None));
      Testo.create "Stroke_text.glyph: one picture, or the pen's segments (letters=segments, opti=off)" (fun () ->
          let segments = with_letters Segments (fun () -> Stroke_text.glyph black look "A" ~x:0. ~baseline:0.) in
          Alcotest.(check bool) "the simple way: a shape a segment and a dot a point" true (List.length segments > 5);
          Alcotest.(check bool) "which is glyph_segments" true (segments = Stroke_text.glyph_segments black look "A" ~x:0. ~baseline:0.);
          with_letters Pictures (fun () ->
              let picture = Stroke_text.glyph black look "A" ~x:0. ~baseline:0. in
              Alcotest.(check int) "one shape" 1 (List.length picture);
              let underlined = Stroke_text.glyph black { look with underline = true } "A" ~x:0. ~baseline:0. in
              Alcotest.(check int) "its underline, a rectangle" 2 (List.length underlined);
              Alcotest.(check bool) "the same picture underlined" true (image (List.hd underlined) == image (List.hd picture));
              Mini_opti.enabled := false;
              Fun.protect ~finally:(fun () -> Mini_opti.enabled := true) (fun () ->
                  Alcotest.(check bool) "opti=off: the simple way, whatever is asked" true (Stroke_text.glyph black look "A" ~x:0. ~baseline:0. = segments))));
    ]
