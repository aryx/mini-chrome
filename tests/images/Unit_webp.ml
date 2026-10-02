(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_webp.mli *)

let read (file : string) : string = In_channel.with_open_bin file In_channel.input_all

(* a picture of data/, decoded by us, and what it must be *)
let pair (name : string) : Rgba_image.t * Rgba_image.t =
  (Webp.decode (read ("data/" ^ name ^ ".webp")), Png.decode (read ("data/" ^ name ^ ".png")))

(* how far two pictures of the same size are: the largest difference of
 * a channel of a pixel, and the mean of them all *)
let distance (a : Rgba_image.t) (b : Rgba_image.t) : int * float =
  let worst = ref 0 and sum = ref 0 in
  for i = 0 to (4 * a.width * a.height) - 1 do
    let d = abs (a.rgba.{i} - b.rgba.{i}) in
    if d > !worst then worst := d;
    sum := !sum + d
  done;
  (!worst, float_of_int !sum /. float_of_int (4 * a.width * a.height))

let exact (name : string) () : unit =
  let ours, theirs = pair name in
  Alcotest.(check (pair int int)) "its size" (theirs.width, theirs.height) (ours.width, ours.height);
  Alcotest.(check int) "every pixel the same" 0 (fst (distance ours theirs))

let tests =
  Testo.categorize "Webp"
    (List.map (fun name -> Testo.create ("lossy: " ^ name) (exact ("lossy-" ^ name))) [ "gradient"; "scene"; "large"; "odd"; "low"; "flat" ]
    @ [ Testo.create "lossy, with its alpha beside" (exact "alpha-scene") ]
    @ List.map
       (fun name -> Testo.create ("lossless: " ^ name) (exact ("lossless-" ^ name)))
       [ "1x1"; "gradient"; "scene"; "large"; "2-colours"; "4-colours"; "16-colours"; "17-colours"; "alpha" ]
    @ [ Testo.create "what is not a WebP file" (fun () ->
            Alcotest.(check bool) "sniffed by its first bytes" true (Webp.sniff (read "data/lossless-1x1.webp") && not (Webp.sniff "RIFF\x00\x00\x00\x00WAVE"));
            Alcotest.(check (option (pair int int))) "its size, without decoding it" (Some (300, 200)) (Webp.size (read "data/lossless-large.webp"));
            Alcotest.(check (option (pair int int))) "a lossy one's" (Some (32, 24)) (Webp.size (read "data/lossy-gradient.webp"));
            let tiny = read "data/lossless-1x1.webp" in
            Alcotest.(check (list (pair string int))) "the chunks of the smallest: one, of 17 bytes" [ ("VP8L", 17) ] (List.map (fun (name, bytes) -> (name, String.length bytes)) (Webp.chunks tiny 12 (String.length tiny)));
            Alcotest.(check int) "38 bytes, the padding counted" 38 (String.length tiny);
            Alcotest.check_raises "a file cut short is a Failure, not a crash" (Failure "x") (fun () ->
                try ignore (Webp.decode (String.sub (read "data/lossless-scene.webp") 0 200)) with Failure _ | Invalid_argument _ -> raise (Failure "x")))
      ])
