(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Decode.mli *)

(* an .ogg or .opus file decoded by libs/audio to raw samples (32-bit
 * floats, the channels in turn), to compare with another decoder's or
 * to listen to (ffplay -f f32le -ar 48000 -ac 2 out.f32):
 *   Decode.exe sound.opus out.f32 *)
let () =
  match Sys.argv with
  | [| _; input; output |] ->
      let bytes = In_channel.with_open_bin input In_channel.input_all in
      let opus = match Ogg.packets bytes with head :: _ -> String.length head >= 8 && String.sub head 0 8 = "OpusHead" | [] -> false in
      let rate, sound = if opus then (Opus.rate, snd (Opus.of_ogg bytes)) else let t, s = Vorbis.of_ogg bytes in (Vorbis.rate t, s) in
      let n = Array.length sound.(0) and channels = Array.length sound in
      let b = Bytes.create (4 * n * channels) in
      for i = 0 to n - 1 do
        for c = 0 to channels - 1 do Bytes.set_int32_le b (4 * ((i * channels) + c)) (Int32.bits_of_float sound.(c).(i)) done
      done;
      Out_channel.with_open_bin output (fun oc -> Out_channel.output_bytes oc b);
      Printf.printf "%s, %d Hz, %d channel(s), %d samples\n" (if opus then "Opus" else "Vorbis") rate channels n
  | _ ->
      prerr_endline "usage: Decode.exe file.ogg|file.opus out.f32";
      exit 2
