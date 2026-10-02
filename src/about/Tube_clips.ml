(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Tube_clips.mli *)

(* An animated GIF of our own: a ball bouncing across 16 x 16 frames.
 * There is no GIF writer in graphics/images, and a real one would
 * compress (LZW builds its dictionary as it goes: Lzw.mli). This one
 * writes the LZW codes without compressing: each pixel its own code,
 * and a clear code every two pixels, before the dictionary would grow
 * past 3-bit codes -- a valid GIF89a any reader decodes, at 9 bits for
 * 2 pixels, the price of simplicity. *)
let bouncing_ball_gif : string =
  let b = Buffer.create 2048 in
  let u8 v = Buffer.add_char b (Char.chr (v land 0xFF)) and u16 v = Buffer.add_uint16_le b v in
  let w = 16 and h = 16 in
  Buffer.add_string b "GIF89a";
  u16 w;
  u16 h;
  (* a global table of 4 colors (2^(1+1)), 2 bits of color resolution *)
  u8 0x91;
  u8 0;
  u8 0;
  List.iter (fun (r, g, bl) -> u8 r; u8 g; u8 bl) [ (30, 30, 60); (120, 170, 240); (250, 210, 60); (240, 240, 240) ];
  (* loop forever: Netscape's extension *)
  Buffer.add_string b "\x21\xFF\x0BNETSCAPE2.0\x03\x01\x00\x00\x00";
  let frame k =
    (* the ball's center, bouncing: x across, y a parabola *)
    let cx = 3 + (k * 2) and cy = 12 - ((k * (5 - k)) / 1) in
    let pixel x y = if ((x - cx) * (x - cx)) + ((y - cy) * (y - cy)) <= 5 then 2 else if y >= 14 then 3 else 1 in
    (* the graphic control: 15 hundredths of a second *)
    Buffer.add_string b "\x21\xF9\x04\x04";
    u16 15;
    u8 0;
    u8 0;
    (* the image, the whole screen *)
    u8 0x2C;
    u16 0;
    u16 0;
    u16 w;
    u16 h;
    u8 0;
    (* the codes, 3 bits each, least significant first: clear (4), two
     * pixels, clear, two pixels, ..., end (5) *)
    u8 2;
    let bits = ref 0 and nbits = ref 0 and data = Buffer.create 512 in
    let code c =
      bits := !bits lor (c lsl !nbits);
      nbits := !nbits + 3;
      while !nbits >= 8 do
        Buffer.add_char data (Char.chr (!bits land 0xFF));
        bits := !bits lsr 8;
        nbits := !nbits - 8
      done
    in
    for i = 0 to (w * h) - 1 do
      if i mod 2 = 0 then code 4;
      code (pixel (i mod w) (i / w))
    done;
    code 5;
    if !nbits > 0 then Buffer.add_char data (Char.chr (!bits land 0xFF));
    (* in sub-blocks of at most 255 bytes, then an empty one *)
    let d = Buffer.contents data in
    let rec blocks at =
      if at < String.length d then (
        let n = min 255 (String.length d - at) in
        u8 n;
        Buffer.add_string b (String.sub d at n);
        blocks (at + n))
    in
    blocks 0;
    u8 0
  in
  List.iter frame [ 0; 1; 2; 3; 4; 5 ];
  u8 0x3B;
  Buffer.contents b

(* Our first video: the repository filming itself. Each frame drawn by
 * the 2D rasterizer of graphics/2d (Fill, Circle: the software
 * backend's own), then written raw as Y4M, in 4:2:0 and the studio
 * range (Y4m.mli) -- 160 x 120, 25 frames a second for 2 s: 50 frames
 * of 28,800 bytes, 1.4 MB for two seconds of a small picture, the size
 * the next formats of graphics/videos/ are about -- and as FLC, only
 * what changed from a frame to the next (Fli.mli), and as AVI, each
 * frame a JPEG, with a sound (Avi.mli); and as MPEG-1, by our own
 * encoder (Mpeg1_encode.mli, I and P pictures) and by ffmpeg's, once
 * (make_clips.sh), with B pictures. A ball bounces twice
 * and a square turns a quarter, so the clip loops without a jump; flat
 * colors, whose sharp edges show what 4:2:0 does to color. *)
let clip_frame (k : int) : Rgba_image.t =
  let w = 160 and h = 120 and ground = 96 in
  let fb = Framebuffer.create ~width:w ~height:h in
  Framebuffer.clear fb ~rgb:0x1e2a50;
  for y = ground to h - 1 do
    Framebuffer.fill_span fb ~y ~x0:0 ~x1:w ~rgb:0x3c8c46 ~alpha:1.
  done;
  let t = float_of_int k /. 50. (* 0 to 1 over the clip *) in
  (* the square, turning a quarter around (40, 50) *)
  let a = t *. Float.pi /. 2. in
  let corner i = let a = a +. (float_of_int i *. Float.pi /. 2.) in (40. +. (20. *. cos a), 50. +. (20. *. sin a)) in
  Fill.polygon fb (List.init 4 corner) ~rgb:0xf0c83c ~alpha:1.;
  (* the ball, two bounces: a parabola's height each half *)
  let phase = Float.rem (t *. 2.) 1. in
  let height = 240. *. phase *. (1. -. phase) in
  Circle.fill fb ~cx:(110 + int_of_float (20. *. sin (2. *. Float.pi *. t))) ~cy:(ground - 10 - int_of_float height) ~r:10 ~rgb:0xe03c32 ~alpha:1.;
  let img = Rgba_image.create ~width:w ~height:h in
  for y = 0 to h - 1 do
    for x = 0 to w - 1 do
      let rgb = Framebuffer.get_rgb fb ~x ~y and o = 4 * ((y * w) + x) in
      img.rgba.{o} <- (rgb lsr 16) land 0xFF;
      img.rgba.{o + 1} <- (rgb lsr 8) land 0xFF;
      img.rgba.{o + 2} <- rgb land 0xFF;
      img.rgba.{o + 3} <- 255
    done
  done;
  img

let clip : Rgba_image.t list Lazy.t = lazy (List.init 50 clip_frame)

(* and its sound, for the AVI: a blip each time the ball lands, at 0
 * and 1 s (Sfx's "ball on a paddle") *)
let clip_sound : Signal.t Lazy.t =
  lazy (let blip = Synth.render (Sfx.to_sound Sfx.blip) in
  let out = Array.make (2 * Signal.rate) 0. in
  List.iter (fun at -> Array.iteri (fun i v -> if at + i < Array.length out then out.(at + i) <- out.(at + i) +. v) blip) [ 0; Signal.rate ];
  out)

(* a tune for the formats that hold notes, not sound: Au clair de la
 * lune, in ABC; as a MIDI file; in solfege; and as a tracker's module,
 * whose one instrument is 32 bytes of a triangle wave (played at C-2's
 * rate, 8,287 bytes a second, it turns 259 times: a C) *)
let tune_abc = "X:1\nT:Au clair de la lune\nM:4/4\nL:1/4\nQ:1/4=120\nK:C\nC C C D | E2 D2 | C E D D | C4 |\n"
let tune_doremi = "% Au clair de la lune\ntempo 120\ndo do do re | mi:2 re:2 | do mi re re | do:4\n"

let tune_mod : string Lazy.t =
  lazy
    (let silent : Mod.instrument = { name = ""; finetune = 0; volume = 0; loop_start = 0; loop_length = 0; data = "" } in
     let triangle = Mod.data_of_floats (Array.init 32 (fun i -> if i < 16 then (float_of_int i /. 8.) -. 1. else 3. -. (float_of_int i /. 8.))) in
     let instruments = Array.init 31 (fun i -> if i = 0 then { silent with name = "triangle"; volume = 64; loop_length = 32; data = triangle } else silent) in
     (* a note a beat, four rows a beat, on the first of four channels *)
     let notes = [ (0, "C-2"); (4, "C-2"); (8, "C-2"); (12, "D-2"); (16, "E-2"); (24, "D-2"); (32, "C-2"); (36, "E-2"); (40, "D-2"); (44, "D-2"); (48, "C-2") ] in
     let pattern =
       Array.init 64 (fun row ->
           Array.init 4 (fun channel ->
               match List.assoc_opt row notes with
               | Some name when channel = 0 -> { Mod.instrument = 1; period = Option.get (Mod.period_of_name name); fx = 0; param = 0 }
               | _ -> Mod.empty_cell))
     in
     Mod.to_string { title = "au clair de la lune"; instruments; restart = 0; positions = [| 0 |]; patterns = [| pattern |]; tag = "M.K." })

let playlist : (string * string Lazy.t) list =
  [
    ("bouncing_ball.gif", Lazy.from_val bouncing_ball_gif);
    ("ball_and_square.y4m", lazy (Y4m.to_string ~rate:(25, 1) (Lazy.force clip)));
    ("ball_and_square.flc", lazy (Fli.to_string ~delay:0.04 (Lazy.force clip)));
    ("ball_and_square.avi", lazy (Avi.to_string ~sound:(Lazy.force clip_sound) ~rate:(25, 1) (Lazy.force clip)));
    (* the clip and its blips muxed by ffmpeg as an .mpg, once: its
     * MPEG-1 video and its MP2, interleaved *)
    ("ffmpeg_muxed.mpg", Lazy.from_val Tube_files.ball_and_square_mpg);
    (* the same clip as the web has it, by ffmpeg's libvpx, once: VP8
     * in a WebM file, no sound *)
    ("ball_and_square.webm", Lazy.from_val Tube_files.ball_and_square_webm);
    (* two chirps encoded by LAME, once: we decode MP3, we have no
     * encoder *)
    ("lame_encoded.mp3", Lazy.from_val Tube_files.stereo_mp3);
    (* the clip's video alone, by our own encoder (Mpeg1_encode: I and P pictures) *)
    ("ball_and_square.m1v", lazy (fst (Mpeg1_encode.encode ~rate:(25, 1) (Lazy.force clip))));
    (* the chirps again, by ffmpeg, once: Opus (libopus, CELT alone)
     * in its own file and in a WebM, Vorbis (libvorbis), MP2 *)
    ("chirps.opus", Lazy.from_val Tube_files.chirps_opus);
    ("chirps.webm", Lazy.from_val Tube_files.chirps_webm);
    ("chirps.ogg", Lazy.from_val Tube_files.chirps_ogg);
    ("chirps.mp2", Lazy.from_val Tube_files.chirps_mp2);
    (* the clip's blips as plain samples, by tiny_libs' writer *)
    ("blips.wav", lazy (Wav.to_string (Lazy.force clip_sound)));
    (* the tune: as text twice, as a MIDI file, as a module *)
    ("tune.abc", Lazy.from_val tune_abc);
    ("tune.mid", lazy (match Abc.parse tune_abc with Ok t -> Midi.of_tune t | Error why -> failwith why));
    ("tune.doremi", Lazy.from_val tune_doremi);
    ("tune.mod", tune_mod);
  ]
