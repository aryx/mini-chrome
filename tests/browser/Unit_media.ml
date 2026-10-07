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
            | Ok (kind, (Sound { samples; stream; _ } as m)) ->
                (* an .ogg is decoded as it plays (Sound_stream): silent
                 * at first, then a second of it and no more, then all *)
                (match stream with
                | Some st ->
                    Alcotest.(check bool) (name ^ ": nothing decoded when opened") true (Sound_stream.ready st = 0 && Array.for_all (fun v -> v = 0.) samples.left);
                    Media.ahead m 0.1;
                    Alcotest.(check bool) (name ^ ": a tenth of a second asked, not the whole") true
                      (Sound_stream.ready st >= Signal.rate / 10 && Sound_stream.ready st < Array.length samples.left);
                    Media.ahead m 1000.;
                    Alcotest.(check int) (name ^ ": then all of it") (Array.length samples.left) (Sound_stream.ready st)
                | None -> Alcotest.(check bool) (name ^ ": decoded whole") true (name <> "sound.ogg"));
                (Media.kind_name kind, samples)
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
      Testo.create "Opus: an .opus file, a WebM of it, the same packets" (fun () ->
          let sound path name =
            match Media.open_ ~name (In_channel.with_open_bin path In_channel.input_all) with
            | Ok (kind, (Sound { samples; _ } as m)) ->
                Media.ahead m 1000.;
                (Media.kind_name kind, samples)
            | Ok _ -> Alcotest.fail (name ^ ": not a sound")
            | Error why -> Alcotest.fail why
          in
          let opus_kind, opus = sound "../audio/data/music.opus" "music.opus" and webm_kind, webm = sound "../video/data/opus.webm" "opus.webm" in
          Alcotest.(check (pair string string)) "recognized" ("Ogg Opus", "WebM") (opus_kind, webm_kind);
          (* 48,000 Hz in the files, the player's 44,100 here *)
          Alcotest.(check (float 0.03)) "half a second, at the player's rate" 0.5 (float_of_int (Array.length opus.left) /. float_of_int Signal.rate);
          (* but the file's last two samples, read past its end (Sound_stream) *)
          let n = min (Array.length webm.left) (Array.length opus.left) - 2 in
          Alcotest.(check bool) "the same sound from both" true (Array.sub webm.left 0 n = Array.sub opus.left 0 n && Array.sub webm.right 0 n = Array.sub opus.right 0 n);
          Alcotest.(check bool) "heard, and two channels that differ" true (Array.exists (fun v -> Float.abs v > 0.2) opus.left && opus.left <> opus.right));
      Testo.create "Sound_stream: decoded as it plays, the same samples as decoded whole" (fun () ->
          let read path = In_channel.with_open_bin path In_channel.input_all in
          (* decoded whole, the simple way: every packet, then the rate changed *)
          let whole (path : string) : Signal.stereo =
            let bytes = read path in
            let rate, channels = if Filename.check_suffix path ".opus" then (Opus.rate, snd (Opus.of_ogg bytes)) else let d, c = Vorbis.of_ogg bytes in (Vorbis.rate d, c) in
            let ours x = Resample.to_rate Cubic rate x in
            { left = ours channels.(0); right = ours channels.(if Array.length channels > 1 then 1 else 0) }
          in
          let streamed (path : string) : Signal.stereo =
            match Media.open_ ~name:(Filename.basename path) (read path) with
            | Ok (_, (Sound { samples; stream = Some _; _ } as m)) ->
                (* a few packets at a time, as a player asks *)
                let seconds = ref 0. in
                while !seconds < 2. do
                  Media.ahead m !seconds;
                  seconds := !seconds +. 0.05
                done;
                samples
            | _ -> Alcotest.fail (path ^ ": not a sound decoded as it plays")
          in
          List.iter
            (fun path ->
              let whole = whole path and streamed = streamed path in
              (* the stream is as long as the file says its sound is; decoded
               * whole, as long as its packets gave: a few hundredths of a
               * second apart, silent in the stream. And the last samples
               * are read past the end of what was decoded (a cubic's two
               * neighbours after, at a rate half ours), which is not the
               * same end *)
              let n = min (Array.length whole.left) (Array.length streamed.left) - 8 in
              Alcotest.(check bool) (path ^ ": as long, to a twentieth of a second") true (abs (Array.length whole.left - Array.length streamed.left) < Signal.rate / 20);
              Alcotest.(check bool) (path ^ ": the same samples, left and right") true
                (Array.sub whole.left 0 n = Array.sub streamed.left 0 n && Array.sub whole.right 0 n = Array.sub streamed.right 0 n);
              Alcotest.(check bool) (path ^ ": silent past what was decoded") true
                (let from = min (n + 16) (Array.length streamed.left) in
                 Array.for_all (fun v -> v = 0.) (Array.sub streamed.left from (Array.length streamed.left - from))))
            [ "../video/data/sound.ogg"; "../audio/data/stereo.ogg"; "../audio/data/bell.ogg"; "../audio/data/music.opus"; "../audio/data/speech.opus" ]);
      Testo.create "Audio_queue: a script's sounds mixed at their time" (fun () ->
          let block () : Signal.stereo =
            let out : Signal.stereo = { left = Array.make 4 0.1; right = Array.make 4 0. } in
            Audio_queue.mix out;
            out
          in
          let t0 = Audio_queue.now () in
          let sample = 1. /. float_of_int Signal.rate in
          (* two samples, to start six samples from now: across two blocks of four; and one at once *)
          Audio_queue.play ~at:(t0 +. (6. *. sample)) ~rate:Signal.rate [| 0.5; 0.25 |] [| -0.5; -0.25 |];
          Audio_queue.play ~at:0. ~rate:Signal.rate [| 1. |] [| 1. |];
          let a = block () in
          let b = block () in
          let c = block () in
          Alcotest.(check (list (float 1e-9))) "the first block: the one due now, added to what was there" [ 1.1; 0.1; 0.1; 0.1 ] (Array.to_list a.left);
          Alcotest.(check (list (float 1e-9))) "the second: the other, at its place" [ 0.1; 0.1; 0.6; 0.35 ] (Array.to_list b.left);
          Alcotest.(check (list (float 1e-9))) "its right channel" [ 0.; 0.; -0.5; -0.25 ] (Array.to_list b.right);
          Alcotest.(check (list (float 1e-9))) "then nothing more" [ 0.1; 0.1; 0.1; 0.1 ] (Array.to_list c.left);
          Alcotest.(check (float 1e-9)) "the clock moved by what was played" (12. *. sample) (Audio_queue.now () -. t0));
      Testo.create "about:tube: every file of it opens, as what it says" (fun () ->
          let kinds =
            List.map
              (fun (name, bytes) ->
                match Media.open_ ~name (Lazy.force bytes) with
                | Ok (kind, media) ->
                    (* what plays has a length; a module is rendered by the page's player *)
                    (match media with
                     | Module song -> Alcotest.(check bool) (name ^ ": a few seconds") true (Array.length (Media.module_sound song).left > Signal.rate)
                     | m -> Alcotest.(check bool) (name ^ ": a length") true (match Media.duration m with Some d -> d > 0.5 | None -> false));
                    (name, Media.kind_name kind)
                | Error why -> Alcotest.fail why)
              Tube_clips.playlist
          in
          Alcotest.(check (list (pair string string))) "the kinds"
            [ ("ball_and_square.avi", "AVI"); ("ball_and_square.flc", "FLIC"); ("ball_and_square.m1v", "MPEG-1"); ("ball_and_square.webm", "WebM");
              ("ball_and_square.y4m", "Y4M"); ("blips.wav", "WAV"); ("bouncing_ball.gif", "GIF"); ("chirps.mp2", "MP2"); ("chirps.ogg", "Ogg Vorbis");
              ("chirps.opus", "Ogg Opus"); ("chirps.webm", "WebM"); ("ffmpeg_muxed.mpg", "MPEG-1 system"); ("frere_jacques.mid", "MIDI"); ("lame_encoded.mp3", "MP3"); ("tiny_soundtracker.mod", "MOD");
              ("tune.abc", "ABC"); ("tune.doremi", "solfege"); ("tune.mid", "MIDI"); ("tune.mod", "MOD") ]
            (List.sort compare kinds);
          (* and the page names only files there are *)
          let page = fst (Option.get (Tube.about "tube")) in
          List.iter (fun (name, _) -> if not (String.length name > 0 && (let re = "about:clip/" ^ name in let n = String.length re in let rec has i = i + n <= String.length page && (String.sub page i n = re || has (i + 1)) in has 0)) then Alcotest.failf "%s is not on the page" name) Tube_clips.playlist);
      Testo.create "a PDF file: a page of pictures, one a page" (fun () ->
          let bytes = In_channel.with_open_bin "../pdf/data/tex.pdf" In_channel.input_all in
          Alcotest.(check bool) "by its first bytes" true (Pdf_viewer.sniff bytes && not (Pdf_viewer.sniff "<html>"));
          (match Pdf_viewer.open_ bytes with
           | Ok v ->
               let html = Pdf_viewer.html v ~name:"tex.pdf" in
               let count part = let n = String.length part in let rec go i acc = if i + n > String.length html then acc else go (i + 1) (if String.sub html i n = part then acc + 1 else acc) in go 0 0 in
               Alcotest.(check (list int)) "a title, two pages, each at its size in pixels (10 cm by 5)" [ 1; 2; 2; 1; 1 ]
                 (List.map count [ "<title>tex.pdf</title>"; "<img src=\"pdf-page:"; "width=\"378\" height=\"189\""; "pdf-page:1\""; "pdf-page:2\"" ]);
               let img = Pdf_viewer.picture v 2 in
               Alcotest.(check (pair int int)) "a page's picture, a dot and a half a pixel" (567, 284) (img.width, img.height);
               Alcotest.(check bool) "with ink on it" true (let dark = ref false in for i = 0 to (img.width * img.height) - 1 do if img.rgba.{4 * i} < 100 then dark := true done; !dark);
               Alcotest.(check (pair int int)) "no such page: a dot" (1, 1) (let i = Pdf_viewer.picture v 9 in (i.width, i.height))
           | Error why -> Alcotest.fail why);
          Alcotest.(check (list (option int))) "a page's address" [ Some 3; None; None ] (List.map Pdf_viewer.page_of_src [ Pdf_viewer.src 3; "picture.png"; "pdf-page:x" ]);
          Alcotest.(check bool) "what is not one: said" true (Result.is_error (Pdf_viewer.open_ "%PDF-1.4 and nothing"));
          (* the built-in site's sample *)
          match Site.about "pdf" with
          | Some (bytes, "application/pdf") -> Alcotest.(check bool) "about:pdf opens" true (Result.is_ok (Pdf_viewer.open_ bytes))
          | _ -> Alcotest.fail "about:pdf");
      Testo.create "what cannot be played is said, not raised" (fun () ->
          let bytes = clip "ball_and_square.webm" in
          Alcotest.(check bool) "a file cut short" true (Result.is_error (Media.open_ ~name:"cut.webm" (String.sub bytes 0 40)));
          Alcotest.(check bool) "a picture that is not one: the decoder's exception caught, for every format" true
            (Result.is_error (Media.open_ ~name:"broken.png" "\137PNG\r\n\026\nnot a picture"));
          Alcotest.(check bool) "about:tube's clip numbers start at 1" true (Tube.about "tube-0" = None && Tube.about "tube-1" <> None));
    ]
