(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Media.mli *)

type kind = Wav | Mp2 | Mp3 | Midi | Mod | Abc | Solfege | Png | Gif | Jpeg | Xpm | Y4m | Flic | Avi | Mpeg1 | Mpg | Webm | Ogg | Opus

let kind_name = function
  | Wav -> "WAV"
  | Mp2 -> "MP2"
  | Mp3 -> "MP3"
  | Midi -> "MIDI"
  | Mod -> "MOD"
  | Abc -> "ABC"
  | Solfege -> "solfege"
  | Png -> "PNG"
  | Gif -> "GIF"
  | Jpeg -> "JPEG"
  | Xpm -> "XPM"
  | Y4m -> "Y4M"
  | Flic -> "FLIC"
  | Avi -> "AVI"
  | Mpeg1 -> "MPEG-1"
  | Mpg -> "MPEG-1 system"
  | Webm -> "WebM"
  | Ogg -> "Ogg Vorbis"
  | Opus -> "Ogg Opus"

(*****************************************************************************)
(* What it is *)
(*****************************************************************************)

let starts (s : string) (at : int) (magic : string) : bool =
  String.length s >= at + String.length magic && String.sub s at (String.length magic) = magic

let by_bytes (s : string) : kind option =
  if starts s 0 "RIFF" && starts s 8 "WAVE" then Some Wav
  else if starts s 0 "RIFF" && starts s 8 "AVI " then Some Avi
  else if starts s 0 "MThd" then Some Midi
  else if String.length s >= 1084 && Mod.channels_of_tag (String.sub s 1080 4) <> None then Some Mod
  else if starts s 0 "\137PNG\r\n\026\n" then Some Png
  else if starts s 0 "GIF87a" || starts s 0 "GIF89a" then Some Gif
  else if starts s 0 "\255\216\255" then Some Jpeg
  else if starts s 0 "/* XPM */" then Some Xpm
  else if starts s 0 "YUV4MPEG2 " then Some Y4m
  else if starts s 0 "\000\000\001\xB3" then Some Mpeg1
  else if starts s 0 "\000\000\001\xBA" then Some Mpg
  else if Webm.sniff s then Some Webm
  else if starts s 0 "OggS" && starts s 28 "OpusHead" then Some Opus
  else if starts s 0 "OggS" then Some Ogg
  else if String.length s >= 128 && (starts s 4 "\x11\xAF" || starts s 4 "\x12\xAF") then Some Flic
  else if starts s 0 "X:" then Some Abc
  else
    match Mpeg_audio_header.at_start s with
    | Some { layer = 2; _ } -> Some Mp2
    | Some { layer = 3; _ } -> Some Mp3
    | _ -> None

let by_name (name : string) : kind option =
  let ends = Filename.check_suffix (String.lowercase_ascii name) in
  if ends ".mod" then Some Mod
  else if ends ".doremi" || ends ".txt" then Some Solfege
  else if ends ".abc" then Some Abc
  else None

let sniff ~(name : string) (bytes : string) : kind option =
  match by_bytes bytes with Some k -> Some k | None -> by_name name

(*****************************************************************************)
(* What it holds *)
(*****************************************************************************)

type media =
  | Sound of { samples : Signal.stereo; notes : Midi.note list }
  | Module of Mod.song
  | Picture of Rgba_image.t
  | Movie of { movie : Movie.t; sound : Signal.stereo option; mpeg : (Mpeg1.header * (int -> Mpeg1.info) * Movie.t Lazy.t) option }

(* an XPM's characters as pixels: each its palette's color, or
 * transparent ("None") *)
let xpm_picture (x : Xpm.t) : Rgba_image.t =
  let height = List.length x.rows in
  let width = List.fold_left (fun w r -> max w (String.length r)) 0 x.rows in
  let img = Rgba_image.create ~width ~height in
  List.iteri
    (fun y row ->
      String.iteri
        (fun cx ch ->
          match List.assoc_opt ch x.colors with
          | Some (Some (r, g, b)) ->
              let i = 4 * ((y * width) + cx) in
              img.rgba.{i} <- r;
              img.rgba.{i + 1} <- g;
              img.rgba.{i + 2} <- b;
              img.rgba.{i + 3} <- 255
          | _ -> ())
        row)
    x.rows;
  img

(* a GIF's frames as a movie; a delay under 0.02 s taken as 0.02 (the
 * browsers go further, making 0 and 0.01 s 0.1 s) -- a GIF of zero
 * delays would otherwise be frames of no time at all *)
let gif_movie (frames : (Rgba_image.t * float) list) : Movie.t = Movie.of_frames (List.map (fun (img, d) -> (img, Float.max 0.02 d)) frames)

(* a tune: played by the synthesizer's band, its notes read back from
 * the MIDI file it makes (Midi.of_tune), for the piano roll *)
let tune (t : Abc.tune) : media =
  let notes = match Midi.parse (Midi.of_tune t) with Ok score -> score.notes | Error _ -> [] in
  Sound { samples = Synth.render_stereo (Music.to_sound t); notes }

(* an MP2 or MP3, at our sample rate *)
let mpeg_sound (bytes : string) : (Signal.stereo, string) result =
  Result.map
    (fun ((h : Mpeg_audio_header.t), (s : Signal.stereo)) ->
      let at_our_rate x = if h.sample_rate = Signal.rate then x else Resample.to_rate Cubic h.sample_rate x in
      { Signal.left = at_our_rate s.left; right = at_our_rate s.right })
    (Mpeg_audio.decode bytes)

(* an MPEG-1 video stream, and for the analyzer its decisions and what
 * was sent *)
let mpeg1_movie (bytes : string) ~(sound : Signal.stereo option) : media =
  let header, movie, info = Mpeg1.of_string bytes in
  let sent = lazy (let _, m, _ = Mpeg1.of_string ~residual:true bytes in m) in
  Movie { movie; sound; mpeg = Some (header, info, sent) }

(* [s] starting [seconds] later (earlier if negative): silence added
 * before it, or its start cut *)
let delayed (seconds : float) (s : Signal.t) : Signal.t =
  let n = int_of_float (Float.round (seconds *. float_of_int Signal.rate)) in
  if n >= 0 then Array.append (Array.make n 0.) s else Array.sub s (min (-n) (Array.length s)) (max 0 (Array.length s + n))

(* an .mpg: its first video stream, and its first audio stream moved so
 * that its time 0 is the first picture's (their first timestamps) --
 * the player shows the frame at the sound's position *)
let mpg (bytes : string) : (media, string) result =
  let streams = Mpeg_system.of_string bytes in
  match Mpeg_system.video streams with
  | None -> Error "no video stream"
  | Some video ->
      let sound =
        match Mpeg_system.audio streams with
        | None -> None
        | Some audio -> (
            match mpeg_sound audio.bytes with
            | Error _ -> None
            | Ok s ->
                let offset = match (audio.first_pts, video.first_pts) with Some a, Some v -> a -. v | _ -> 0. in
                Some { Signal.left = delayed offset s.left; right = delayed offset s.right })
      in
      Ok (mpeg1_movie video.bytes ~sound)

(* a decoder's channels (libs/audio's Vorbis, Opus), at our sample
 * rate: the first two, or the one twice *)
let decoded_sound (rate : int) (channels : float array array) : Signal.stereo =
  let at_our_rate x = if rate = Signal.rate then x else Resample.to_rate Cubic rate x in
  match channels with
  | [||] -> { left = [||]; right = [||] }
  | [| mono |] -> Signal.both (at_our_rate mono)
  | _ -> { left = at_our_rate channels.(0); right = at_our_rate channels.(1) }

(* a WebM file's sound, if it has one that is Vorbis or Opus: the
 * track's headers (Vorbis's three, Opus's one), then its packets,
 * decoded whole; [from], the time the picture starts at *)
let webm_sound (webm : Webm.t) ~(from : float) : Signal.stereo option =
  match Webm.audio webm with
  | Some (({ codec = "A_VORBIS"; _ } as track), ((first, _) :: _ as packets)) -> (
      match Webm.laced track.setup with
      | [ identification; _; setup ] ->
          let decoder = Vorbis.create ~identification ~setup in
          let parts = List.map (fun (_, packet) -> Vorbis.decode decoder packet) packets in
          let whole = Array.init (Vorbis.channels decoder) (fun c -> Array.concat (List.map (fun (p : float array array) -> p.(c)) parts)) in
          let s = decoded_sound (Vorbis.rate decoder) whole in
          Some { left = delayed (first -. from) s.left; right = delayed (first -. from) s.right }
      | _ | (exception (Failure _ | Invalid_argument _)) -> None)
  | Some (({ codec = "A_OPUS"; _ } as track), ((first, _) :: _ as packets)) -> (
      match Opus.create ~head:track.setup with
      | decoder ->
          let s = decoded_sound Opus.rate (Opus.sound decoder (List.map snd packets)) in
          Some { left = delayed (first -. from) s.left; right = delayed (first -. from) s.right }
      | exception Failure _ -> None)
  | _ -> None

(* a WebM file (libs/video). Its video: VP8's frames, decoded as they
 * are asked for, each from the one before -- a frame that is not shown
 * (one kept only to predict from) decoded on the way to the next. Its
 * sound: Vorbis's or Opus's. A file of sound alone is a sound *)
let webm_movie (bytes : string) : (media, string) result =
  let webm = Webm.parse bytes in
  match Webm.video webm with
  | None -> (
      match (webm_sound webm ~from:0., Webm.audio webm) with
      | Some samples, _ -> Ok (Sound { samples; notes = [] })
      | None, Some (track, _) -> Error (Printf.sprintf "a WebM file whose sound is %s: only Vorbis and Opus are decoded" track.codec)
      | None, None -> Error "a WebM file with no video and no sound in it")
  | Some (track, _) when track.codec <> "V_VP8" -> Error (Printf.sprintf "a WebM file whose video is %s: only VP8 is decoded" track.codec)
  | Some (track, frames) ->
      let packets = Array.of_list frames in
      (* a frame's first byte says whether it is shown *)
      let shown = List.filter (fun (_, data) -> data <> "" && Char.code data.[0] land 0x10 <> 0) frames in
      if shown = [] then Error "a WebM file with no frame to show"
      else
        let times = Array.of_list (List.map fst shown) in
        let sound = webm_sound webm ~from:times.(0) in
        let times = Array.map (fun t -> t -. times.(0)) times in
        let last = times.(Array.length times - 1) in
        (* the last frame lasts as long as the one before it did *)
        let duration = last +. if Array.length times > 1 then last /. float_of_int (Array.length times - 1) else 0.04 in
        let rec next ((decoder, i) : Vp8_video.t * int) =
          if i >= Array.length packets then ((decoder, i), Vp8_video.picture decoder)
          else if Vp8_video.decode decoder (snd packets.(i)) then ((decoder, i + 1), Vp8_video.picture decoder)
          else next (decoder, i + 1)
        in
        Ok (Movie { movie = Movie.sequential ~width:track.width ~height:track.height ~times ~duration ~start:(fun () -> (Vp8_video.create (), 0)) ~next; sound; mpeg = None })

let open_ ~(name : string) (bytes : string) : (kind * media, string) result =
  match sniff ~name bytes with
  | None -> Error (name ^ ": not a kind of file this player knows")
  | Some kind -> (
      (* decoded inside the match below: what a decoder raises on a
       * broken file is caught there *)
      let media () =
        match kind with
        | Wav -> Result.map (fun s -> Sound { samples = Signal.both s; notes = [] }) (Wav.of_string bytes)
        | Mp2 | Mp3 -> Result.map (fun samples -> Sound { samples; notes = [] }) (mpeg_sound bytes)
        | Midi -> Result.map (fun (score : Midi.score) -> Sound { samples = Signal.both (Music.render_score score); notes = score.notes }) (Midi.parse bytes)
        | Mod -> Result.map (fun song -> Module song) (Mod.of_string bytes)
        | Abc -> Result.map tune (Abc.parse bytes)
        | Solfege -> Result.map tune (Doremi.parse bytes)
        (* the decoders raise on a broken file: caught below *)
        | Png -> Ok (Picture (Png.decode bytes))
        | Jpeg -> Ok (Picture (Jpeg.decode bytes))
        | Gif -> Ok (match Gif.animation bytes with [ (image, _) ] -> Picture image | frames -> Movie { movie = gif_movie frames; sound = None; mpeg = None })
        | Xpm -> Ok (Picture (xpm_picture (Xpm.parse bytes)))
        | Y4m -> Ok (Movie { movie = snd (Y4m.of_string bytes); sound = None; mpeg = None })
        | Flic -> Ok (Movie { movie = snd (Fli.of_string bytes); sound = None; mpeg = None })
        | Avi ->
            let _, movie, sound = Avi.of_string bytes in
            Ok (Movie { movie; sound = Option.map Signal.both sound; mpeg = None })
        | Mpeg1 -> Ok (mpeg1_movie bytes ~sound:None)
        | Mpg -> mpg bytes
        | Webm -> webm_movie bytes
        | Ogg ->
            let decoder, channels = Vorbis.of_ogg bytes in
            Ok (Sound { samples = decoded_sound (Vorbis.rate decoder) channels; notes = [] })
        | Opus -> Ok (Sound { samples = decoded_sound Opus.rate (snd (Opus.of_ogg bytes)); notes = [] })
      in
      match media () with Ok m -> Ok (kind, m) | Error e -> Error (name ^ ": " ^ e) | exception e -> Error (name ^ ": " ^ Printexc.to_string e))

(* a module played to its end by its own player (five minutes at
 * most: a module may loop by itself) *)
let module_sound (song : Mod.song) : Signal.stereo =
  let player = Mod_player.create ~loop:false song and size = 4096 in
  let rec go parts count =
    if Mod_player.finished player || count * size > 300 * Signal.rate then List.rev parts
    else (
      let chunk : Signal.stereo = { left = Array.make size 0.; right = Array.make size 0. } in
      Mod_player.fill player chunk;
      go (chunk :: parts) (count + 1))
  in
  let parts = go [] 0 in
  { left = Array.concat (List.map (fun (c : Signal.stereo) -> c.left) parts); right = Array.concat (List.map (fun (c : Signal.stereo) -> c.right) parts) }

let duration (m : media) : float option =
  match m with
  | Sound s -> Some (float_of_int (Array.length s.samples.left) /. float_of_int Signal.rate)
  | Movie { movie; _ } -> Some movie.duration
  | Module _ | Picture _ -> None
