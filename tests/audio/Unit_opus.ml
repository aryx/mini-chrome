(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_opus.mli *)

let t = Testo.create
let read_file (file : string) : string = In_channel.with_open_bin (Filename.concat "data" file) In_channel.input_all

(* a file's sound is libopus's, a rounding apart: as many samples, none
 * further than 2 of 32,768 *)
let check_file (name : string) ~(channels : int) () =
  let d, ours = Opus.of_ogg (read_file (name ^ ".opus")) and theirs = read_file (name ^ ".s16") in
  Alcotest.(check int) "channels" channels (Opus.channels d);
  Alcotest.(check int) "samples" (String.length theirs / (2 * channels)) (Array.length ours.(0));
  let worst = ref 0 and loud = ref 0 in
  Array.iteri
    (fun c (samples : float array) ->
      Array.iteri
        (fun i v ->
          let expected = String.get_int16_le theirs (2 * ((i * channels) + c)) in
          worst := max !worst (abs (expected - int_of_float (Float.round (v *. 32768.))));
          loud := max !loud (abs expected))
        samples)
    ours;
  if !worst > 2 then Alcotest.failf "%s: %d away from libopus's" name !worst;
  if !loud < 5000 then Alcotest.failf "%s: too quiet (%d)" name !loud

(* the .mli's examples *)
let test_frames () =
  let config, stereo, frames = Opus.frames "\xFCabc" in
  Alcotest.(check (triple int bool (list string))) "FC: CELT, 20 kHz, 20 ms; two channels; one frame" (31, true, [ "abc" ]) (config, stereo, frames);
  let frames packet = let _, _, f = Opus.frames packet in f in
  Alcotest.(check (list string)) "code 1: two halves" [ "ab"; "cd" ] (frames "\xF9abcd");
  Alcotest.(check (list string)) "code 2: the first's size said" [ "a"; "bcd" ] (frames "\xFA\001abcd");
  Alcotest.(check (list string)) "code 3, one size: a count" [ "ab"; "cd"; "ef" ] (frames "\xFB\003abcdef");
  Alcotest.(check (list string)) "code 3, sizes said, and padding" [ "a"; "bc"; "def" ] (frames "\xFB\xC3\002\001\002abcdef\000\000");
  let big = String.make 300 'x' in
  Alcotest.(check (list int)) "a size over 251: two bytes (252 + 4 x 12)" [ 300; 1 ] (List.map String.length (frames ("\xFA\252\012" ^ big ^ "y")));
  List.iter
    (fun (why, packet) -> match Opus.frames packet with exception Failure _ -> () | _ -> Alcotest.fail why)
    [ ("empty", ""); ("two halves of an odd size", "\xF9abc"); ("a first frame longer than the packet", "\xFA\009abc"); ("no frame", "\xFB\000"); ("a count that does not divide", "\xFB\002abc") ]

let test_head () =
  let head = "OpusHead\001\002\056\001\128\187\000\000\000\000\000" in
  let d = Opus.create ~head in
  Alcotest.(check (pair int int)) "two channels, 312 samples to drop" (2, 312) (Opus.channels d, Opus.pre_skip d);
  List.iter
    (fun (why, head) -> match Opus.create ~head with exception Failure _ -> () | _ -> Alcotest.fail why)
    [ ("Vorbis's", "\001vorbis.............."); ("six channels", "OpusHead\001\006\056\001\128\187\000\000\000\000\001\002\000") ]

(* SILK is silence of its length; a frame of one byte too; a frame of
 * one channel is played on two *)
let test_not_decoded () =
  let d, sound = Opus.of_ogg (read_file "speech.opus") in
  Alcotest.(check int) "one channel" 1 (Opus.channels d);
  Alcotest.(check bool) "half a second" true (abs (Array.length sound.(0) - 24000) <= 960);
  Alcotest.(check bool) "of silence" true (Array.for_all (fun v -> v = 0.) sound.(0));
  let d = Opus.create ~head:"OpusHead\001\002\000\000\128\187\000\000\000\000\000" in
  let lost = Opus.decode d "\xFC" in
  Alcotest.(check (pair int int)) "a frame of nothing: 20 ms, two channels" (2, 960) (Array.length lost, Array.length lost.(0));
  match Ogg.packets (read_file "short.opus") with
  | _ :: _ :: packets ->
      let both = Opus.sound d packets in
      Alcotest.(check bool) "a sound" true (Array.exists (fun v -> Float.abs v > 0.1) both.(0));
      Alcotest.(check bool) "the same on both" true (both.(0) = both.(1))
  | _ -> Alcotest.fail "short.opus's packets"

(* the reference's table of V(n, k), and Celt_bands.mli's example *)
let test_pulses () =
  let v n k = let u = Celt_bands.counts n k in u.(k) + u.(k + 1) in
  Alcotest.(check (list int)) "V(3, 0..5)" [ 1; 6; 18; 38; 66; 102 ] (List.init 6 (v 3));
  Alcotest.(check (list int)) "V(2..6, 2)" [ 8; 18; 32; 50; 72 ] (List.init 5 (fun i -> v (i + 2) 2));
  let all n k = List.init (v n k) (fun i -> Array.to_list (Celt_bands.vector_of_index n k i)) in
  Alcotest.(check (list (list int))) "the eight of (2, 2), in the standard's order"
    [ [ 2; 0 ]; [ 1; 1 ]; [ 1; -1 ]; [ 0; 2 ]; [ 0; -2 ]; [ -2; 0 ]; [ -1; 1 ]; [ -1; -1 ] ]
    (all 2 2);
  List.iter
    (fun (n, k) ->
      let vectors = all n k in
      Alcotest.(check int) "all different" (List.length vectors) (List.length (List.sort_uniq compare vectors));
      Alcotest.(check bool) "each of k pulses" true (List.for_all (fun y -> List.fold_left (fun s x -> s + abs x) 0 y = k) vectors))
    [ (2, 2); (3, 4); (5, 3); (8, 2) ];
  Alcotest.(check (list int)) "the table's steps: 0 to 7, then eighths of an octave"
    [ 0; 1; 7; 8; 9; 15; 16; 18; 30; 32; 36 ]
    (List.map Celt_rate.pulses_of [ 0; 1; 7; 8; 9; 15; 16; 17; 23; 24; 25 ])

let test_range_decoder () =
  let d = Range_decoder.create "\000\000\000\000\000\000\000\005" in
  Alcotest.(check (pair int int)) "a new decoder has used a bit" (1, 8) (Range_decoder.tell d, Range_decoder.tell_frac d);
  Alcotest.(check int) "plain bits, from the end" 5 (Range_decoder.bits d 3);
  Alcotest.(check int) "counted" 4 (Range_decoder.tell d);
  (* zeros are the likely side of every flag, ones the other; a flag
   * costs what it tells: 1 in 8 is three bits, 7 in 8 a fifth of one *)
  let flags data =
    let d = Range_decoder.create data in
    let half = Range_decoder.bit d 1 in
    let eighth = Range_decoder.bit d 3 in
    (half, eighth, Range_decoder.tell_frac d)
  in
  Alcotest.(check (triple bool bool int)) "zeros: no, no; 2 bits and a quarter" (false, false, 18) (flags (String.make 8 '\000'));
  Alcotest.(check (triple bool bool int)) "ones: yes, yes; 5 bits" (true, true, 40) (flags (String.make 8 '\255'));
  Alcotest.(check (list int)) "how many bits a number takes" [ 0; 1; 2; 3; 3; 4 ] (List.map Range_decoder.ilog [ 0; 1; 2; 4; 7; 8 ])

let tests =
  Testo.categorize "Opus"
    [
      t "a packet's first byte and its frames" test_frames;
      t "OpusHead" test_head;
      t "the range decoder" test_range_decoder;
      t "pulses counted and numbered" test_pulses;
      t "SILK, a lost frame, one channel on two" test_not_decoded;
      t "music.opus (two channels, attacks, a pitch)" (check_file "music" ~channels:2);
      t "thin.opus (24 kbit/s: bands folded)" (check_file "thin" ~channels:2);
      t "short.opus (frames of 2.5 ms)" (check_file "short" ~channels:1);
      t "packed.opus (three frames a packet)" (check_file "packed" ~channels:1);
      t "narrow.opus (4 kHz, frames of 10 ms)" (check_file "narrow" ~channels:1);
    ]
