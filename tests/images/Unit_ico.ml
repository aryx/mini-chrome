(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_ico.mli *)

let le16 n = String.init 2 (fun i -> Char.chr ((n lsr (8 * i)) land 255))
let le32 n = String.init 4 (fun i -> Char.chr ((n lsr (8 * i)) land 255))

(* an icon file of these pictures: (width, bits, the picture's bytes) *)
let file (pictures : (int * int * string) list) : string =
  let n = List.length pictures in
  let head = "\000\000" ^ le16 1 ^ le16 n in
  let _, entries =
    List.fold_left
      (fun (at, acc) (w, bits, data) -> (at + String.length data, acc ^ String.make 1 (Char.chr w) ^ String.make 1 (Char.chr w) ^ "\000\000" ^ le16 1 ^ le16 bits ^ le32 (String.length data) ^ le32 at))
      (6 + (16 * n), "") pictures
  in
  head ^ entries ^ String.concat "" (List.map (fun (_, _, d) -> d) pictures)

(* a bitmap's header: 40 bytes, the height said twice over *)
let header ~w ~h ~bits = le32 40 ^ le32 w ^ le32 (2 * h) ^ le16 1 ^ le16 bits ^ String.make 24 '\000'
let pixel (img : Rgba_image.t) x y = List.init 4 (fun k -> img.rgba.{(4 * ((y * img.width) + x)) + k})

let tests =
  Testo.categorize "Ico"
    [
      Testo.create "the worked example: a bitmap of 32 bits, bottom row first, blue green red alpha" (fun () ->
          (* 2 by 2: the bottom row red then green, the top row blue then nothing *)
          let rows = "\000\000\255\255" ^ "\000\255\000\255" ^ "\255\000\000\255" ^ "\000\000\000\000" in
          let mask = String.make 8 '\000' in
          let img = Ico.decode (file [ (2, 32, header ~w:2 ~h:2 ~bits:32 ^ rows ^ mask) ]) in
          Alcotest.(check (pair int int)) "its size" (2, 2) (img.width, img.height);
          Alcotest.(check (list (list int))) "top: blue, clear; bottom: red, green"
            [ [ 0; 0; 255; 255 ]; [ 0; 0; 0; 0 ]; [ 255; 0; 0; 255 ]; [ 0; 255; 0; 255 ] ]
            [ pixel img 0 0; pixel img 1 0; pixel img 0 1; pixel img 1 1 ]);
      Testo.create "a palette and a mask: one bit a dot, the masked dot not drawn" (fun () ->
          (* 2 by 1, 1 bit: index 1 then index 0; the palette black, then orange; the mask hides the second dot *)
          let palette = "\000\000\000\000" ^ "\000\102\255\000" in
          let img = Ico.decode (file [ (2, 1, header ~w:2 ~h:1 ~bits:1 ^ palette ^ "\128\000\000\000" ^ "\064\000\000\000") ]) in
          Alcotest.(check (list (list int))) "orange, then nothing" [ [ 255; 102; 0; 255 ]; [ 0; 0; 0; 0 ] ] [ pixel img 0 0; pixel img 1 0 ]);
      Testo.create "several pictures: the nearest to the size asked; a PNG as it is" (fun () ->
          let png w = Png.encode (Rgba_image.create ~width:w ~height:w) in
          let f = file [ (16, 32, png 16); (48, 32, png 48); (32, 32, png 32) ] in
          Alcotest.(check bool) "an icon file" true (Ico.sniff f && not (Ico.sniff (png 16)));
          Alcotest.(check int) "32 by default" 32 (Ico.decode f).width;
          Alcotest.(check int) "16 asked" 16 (Ico.decode ~size:16 f).width;
          Alcotest.(check int) "40 asked: 48, the larger of two as near" 48 (Ico.decode ~size:40 f).width;
          Alcotest.(check bool) "cut short: a failure, not a crash" true (match Ico.decode (String.sub f 0 30) with _ -> false | exception Failure _ -> true));
    ]
