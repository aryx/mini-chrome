(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_media.mli *)

let clip (name : string) : string = Lazy.force (List.assoc name Tube_clips.playlist)

let tests =
  Testo.categorize "Media"
    [
      Testo.create "a WebM file: recognized, its VP8 frames a movie" (fun () ->
          let bytes = clip "ball_and_square.webm" in
          Alcotest.(check (option string)) "by its first bytes, whatever its name" (Some "WebM") (Option.map Media.kind_name (Media.sniff ~name:"clip" bytes));
          match Media.open_ ~name:"ball_and_square.webm" bytes with
          | Ok (_, Movie { movie; sound; _ }) ->
              Alcotest.(check (pair int int)) "its size" (160, 120) (movie.width, movie.height);
              Alcotest.(check int) "its frames, 25 a second for two seconds" 50 (Movie.frame_count movie);
              Alcotest.(check (float 0.05)) "how long" 2.0 movie.duration;
              (match sound with
              | Some s ->
                  Alcotest.(check (float 0.1)) "its Vorbis sound, as long as the picture" 2.0 (float_of_int (Array.length s.left) /. float_of_int Signal.rate);
                  Alcotest.(check bool) "and heard" true (Array.exists (fun x -> Float.abs x > 0.2) s.left)
              | None -> Alcotest.fail "no sound");
              (* frames asked in order, then one before: decoded again from the key frame *)
              let pixels (img : Rgba_image.t) = List.init 64 (fun i -> img.rgba.{4 * i * 97 mod (4 * img.width * img.height)}) in
              let first = pixels (movie.frame 0) in
              let later = pixels (movie.frame 30) in
              Alcotest.(check bool) "the picture moves" true (first <> later);
              Alcotest.(check bool) "back to the start: the same first frame" true (pixels (movie.frame 0) = first);
              Alcotest.(check bool) "and to the later one: the same again" true (pixels (movie.frame 30) = later)
          | Ok _ -> Alcotest.fail "not a movie"
          | Error why -> Alcotest.fail why);
      Testo.create "Vorbis alone: a WebM of sound, an .ogg, the same packets" (fun () ->
          let read name = In_channel.with_open_bin ("../video/data/" ^ name) In_channel.input_all in
          let sound name =
            match Media.open_ ~name (read name) with
            | Ok (kind, Sound { samples; _ }) -> (Media.kind_name kind, samples)
            | Ok _ -> Alcotest.fail (name ^ ": not a sound")
            | Error why -> Alcotest.fail why
          in
          let webm_kind, webm = sound "sound.webm" and ogg_kind, ogg = sound "sound.ogg" in
          Alcotest.(check (pair string string)) "recognized" ("WebM", "Ogg Vorbis") (webm_kind, ogg_kind);
          (* 22,050 Hz in the files, the player's 44,100 here *)
          Alcotest.(check (float 0.06)) "half a second, at the player's rate" 0.5 (float_of_int (Array.length ogg.left) /. float_of_int Signal.rate);
          let n = min (Array.length webm.left) (Array.length ogg.left) in
          Alcotest.(check bool) "the same sound from both" true (Array.sub webm.left 0 n = Array.sub ogg.left 0 n && Array.sub webm.right 0 n = Array.sub ogg.right 0 n);
          Alcotest.(check bool) "two channels that differ" true (ogg.left <> ogg.right);
          Alcotest.(check bool) "an Ogg file that is not Vorbis's: said" true (Result.is_error (Media.open_ ~name:"x.ogg" "OggS and nothing")));
      Testo.create "what cannot be played is said, not raised" (fun () ->
          let bytes = clip "ball_and_square.webm" in
          Alcotest.(check bool) "a file cut short" true (Result.is_error (Media.open_ ~name:"cut.webm" (String.sub bytes 0 40)));
          Alcotest.(check bool) "a picture that is not one: the decoder's exception caught, for every format" true
            (Result.is_error (Media.open_ ~name:"broken.png" "\137PNG\r\n\026\nnot a picture"));
          Alcotest.(check bool) "about:tube's clip numbers start at 1" true (Tube.about "tube-0" = None && Tube.about "tube-1" <> None));
    ]
