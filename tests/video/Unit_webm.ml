(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_webm.mli *)

let read (file : string) : string = In_channel.with_open_bin file In_channel.input_all

(* a clip's frames decoded, each against the reference's checksum (the
 * MD5 of its raw frame, a line a frame): how many were shown, and
 * which were wrong *)
let differences (name : string) : int * int list =
  let webm = Webm.parse (read ("data/" ^ name ^ ".webm")) in
  let sums = Array.of_list (List.filter (( <> ) "") (String.split_on_char '\n' (read ("data/" ^ name ^ ".md5")))) in
  let _, frames = Option.get (Webm.video webm) in
  let decoder = Vp8_video.create () in
  let shown = ref 0 and wrong = ref [] in
  List.iter
    (fun (_, data) ->
      if Vp8_video.decode decoder data then (
        if !shown >= Array.length sums || Digest.to_hex (Digest.string (Vp8_video.yuv decoder)) <> sums.(!shown) then wrong := !shown :: !wrong;
        incr shown))
    frames;
  (!shown, List.rev !wrong)

let exact (name : string) (count : int) () : unit =
  let shown, wrong = differences name in
  Alcotest.(check int) "its frames, all shown" count shown;
  Alcotest.(check (list int)) "every byte of every frame the reference's: none wrong" [] wrong

let tests =
  Testo.categorize "Webm"
    [
      Testo.create "the file read: its track, its frames and their times" (fun () ->
          let webm = Webm.parse (read "data/plain.webm") in
          let track, frames = Option.get (Webm.video webm) in
          Alcotest.(check (triple string int int)) "a VP8 track, 96 by 64" ("V_VP8", 96, 64) (track.codec, track.width, track.height);
          Alcotest.(check int) "24 frames" 24 (List.length frames);
          Alcotest.(check (list (float 1e-6))) "ten a second" [ 0.; 0.1; 0.2 ] (List.filteri (fun i _ -> i < 3) (List.map fst frames));
          Alcotest.(check (float 0.01)) "2.4 s" 2.4 webm.duration;
          Alcotest.(check bool) "what is not one" true (Webm.sniff (read "data/plain.webm") && not (Webm.sniff "RIFF....WEBP")));
      Testo.create "a sound's track: its fields, Vorbis's three headers laced" (fun () ->
          Alcotest.(check (list string)) "the .mli's example" [ "abc"; "d"; "e" ] (Webm.laced "\002\003\001abcde");
          Alcotest.(check (list string)) "a size of 255 and more"
            [ String.make 258 'x'; ""; "end" ]
            (Webm.laced ("\002\255\003\000" ^ String.make 258 'x' ^ "end"));
          Alcotest.(check (list string)) "nothing" [] (Webm.laced "");
          let webm = Webm.parse (read "data/sound.webm") in
          Alcotest.(check bool) "no video" true (Webm.video webm = None);
          let track, packets = Option.get (Webm.audio webm) in
          Alcotest.(check (triple string int (float 0.))) "Vorbis, two channels, 22,050 Hz" ("A_VORBIS", 2, 22050.) (track.codec, track.channels, track.rate);
          Alcotest.(check (list string)) "its headers: identification, comments, setup"
            [ "\001vorbis"; "\003vorbis"; "\005vorbis" ]
            (List.map (fun h -> String.sub h 0 7) (Webm.laced track.setup));
          Alcotest.(check bool) "its packets, in time" true (List.length packets > 5 && List.map fst packets = List.sort compare (List.map fst packets));
          Alcotest.(check bool) "a video has no sound" true (Webm.audio (Webm.parse (read "data/plain.webm")) = None));
      Testo.create "a WebM's Vorbis decoded: libvorbis's samples, a rounding apart" (fun () ->
          let track, packets = Option.get (Webm.audio (Webm.parse (read "data/sound.webm"))) in
          let decoder = match Webm.laced track.setup with [ identification; _; setup ] -> Vorbis.create ~identification ~setup | _ -> Alcotest.fail "headers" in
          let parts = List.map (fun (_, packet) -> Vorbis.decode decoder packet) packets in
          let expected = read "data/sound.s16" in
          let frames = String.length expected / 4 in
          List.iter
            (fun c ->
              let ours = Array.concat (List.map (fun (p : float array array) -> p.(c)) parts) in
              Alcotest.(check bool) "as many samples, a block apart at most" true (abs (Array.length ours - frames) <= 2048);
              let worst = ref 0 in
              for i = 0 to min frames (Array.length ours) - 1 do
                let theirs = String.get_int16_le expected ((4 * i) + (2 * c)) in
                worst := max !worst (abs (theirs - max (-32768) (min 32767 (int_of_float (Float.round (ours.(i) *. 32768.))))))
              done;
              if !worst > 2 then Alcotest.failf "channel %d: %d away" c !worst)
            [ 0; 1 ]);
      Testo.create "frames predicted from the one before" (exact "plain" 24);
      Testo.create "motion: new vectors, split macroblocks, quarter pixels" (exact "motion" 30);
      Testo.create "a size that is not a multiple of 16" (exact "odd" 20);
      Testo.create "noise that moves" (exact "life" 25);
      Testo.create "several key frames, four partitions" (exact "keys" 30);
      Testo.create "version 1: two-pixel filters, the simple loop filter" (exact "prof1" 16);
      Testo.create "version 3: whole-pixel chroma" (exact "prof3" 16);
      Testo.create "a still's key frame, by both decoders" (fun () ->
          let _, frames = Option.get (Webm.video (Webm.parse (read "data/plain.webm"))) in
          let first = snd (List.hd frames) in
          let decoder = Vp8_video.create () in
          ignore (Vp8_video.decode decoder first);
          let ours = Vp8_video.picture decoder and still = Vp8.decode first in
          let same = ref true in
          for i = 0 to (4 * ours.width * ours.height) - 1 do if ours.rgba.{i} <> still.rgba.{i} then same := false done;
          Alcotest.(check bool) "the same picture" true !same;
          Alcotest.check_raises "a predicted frame with no frame before it" (Failure "Vp8_video: a frame predicted from one that is not there") (fun () ->
              ignore (Vp8_video.decode (Vp8_video.create ()) (snd (List.nth frames 1)))));
    ]
