(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Opus.mli *)

let fail (what : string) = failwith ("Opus: " ^ what)

type t = {
  channels : int;
  pre_skip : int; (* samples at the start that are the encoder's own, to drop *)
  gain : float;
  celt : Celt.t;
}

let rate = 48000

let create ~(head : string) : t =
  if String.length head < 19 || String.sub head 0 8 <> "OpusHead" then fail "a header that is not one";
  let channels = Char.code head.[9] in
  if Char.code head.[18] <> 0 || channels < 1 || channels > 2 then fail "more than two channels";
  let gain = String.get_int16_le head 16 in
  { channels; pre_skip = String.get_uint16_le head 10; gain = Float.pow 10. (float_of_int gain /. (20. *. 256.)); celt = Celt.create ~channels }

let channels (t : t) : int = t.channels
let pre_skip (t : t) : int = t.pre_skip

(* a packet's first byte: how its frames are coded (0 to 31), in one
 * or two channels; then its frames, one to 48 *)
let frames (packet : string) : int * bool * string list =
  let len = String.length packet in
  if len = 0 then fail "an empty packet";
  let toc = Char.code packet.[0] in
  (* a frame's size: a byte, or two when the first is over 251 *)
  let size at = if at >= len then fail "a packet cut short" else
      let first = Char.code packet.[at] in
      if first < 252 then (first, at + 1) else if at + 1 >= len then fail "a packet cut short" else ((4 * Char.code packet.[at + 1]) + first, at + 2)
  in
  let cut at sizes =
    let at = ref at in
    List.map (fun size -> if !at + size > len then fail "a packet cut short"; at := !at + size; String.sub packet (!at - size) size) sizes
  in
  let frames =
    match toc land 3 with
    | 0 -> [ String.sub packet 1 (len - 1) ]
    | 1 -> if (len - 1) land 1 = 1 then fail "two frames of one size in an odd number of bytes" else cut 1 [ (len - 1) / 2; (len - 1) / 2 ]
    | 2 ->
        let first, at = size 1 in
        if at + first > len then fail "a packet cut short";
        cut at [ first; len - at - first ]
    | _ ->
        if len < 2 then fail "a packet cut short";
        let count = Char.code packet.[1] land 63 and vbr = Char.code packet.[1] land 0x80 <> 0 and padded = Char.code packet.[1] land 0x40 <> 0 in
        if count = 0 then fail "a packet of no frame";
        (* padding: its length as bytes of 255 (254 more each) and a last one *)
        let rec padding at sum = if at >= len then fail "a packet cut short" else
            let b = Char.code packet.[at] in
            if b = 255 then padding (at + 1) (sum + 254) else (sum + b, at + 1)
        in
        let pad, at = if padded then padding 2 0 else (0, 2) in
        if vbr then (
          let at = ref at in
          let sizes = List.init (count - 1) (fun _ -> let s, next = size !at in at := next; s) in
          let last = len - pad - !at - List.fold_left ( + ) 0 sizes in
          if last < 0 then fail "a packet cut short";
          cut !at (sizes @ [ last ]))
        else (
          let all = len - pad - at in
          if all < 0 || all mod count <> 0 then fail "frames of one size that do not divide their bytes";
          cut at (List.init count (fun _ -> all / count)))
  in
  (toc lsr 3, toc land 4 <> 0, frames)

let decode (t : t) (packet : string) : float array array =
  let config, stereo, frames = frames packet in
  let parts =
    List.map
      (fun frame ->
        if config >= 16 then
          (* CELT alone: the band it stops at (4, 8, 12 or 20 kHz), and 2.5 ms doubled 0 to 3 times *)
          Celt.decode t.celt ~stream_channels:(if stereo then 2 else 1) ~lm:(config land 3) ~stop:[| 13; 17; 19; 21 |].((config - 16) / 4) frame
        else (
          (* SILK, alone or under CELT: not decoded, its time kept as silence *)
          let ms = if config < 12 then [| 10; 20; 40; 60 |].(config land 3) else [| 10; 20 |].(config land 1) in
          Array.init t.channels (fun _ -> Array.make (ms * 48) 0.)))
      frames
  in
  Array.init t.channels (fun c -> Array.map (fun v -> v *. t.gain) (Array.concat (List.map (fun (p : float array array) -> p.(c)) parts)))

let sound (t : t) (packets : string list) : float array array =
  let parts = List.map (decode t) packets in
  Array.init t.channels (fun c ->
      let all = Array.concat (List.map (fun (p : float array array) -> p.(c)) parts) in
      Array.sub all (min t.pre_skip (Array.length all)) (max 0 (Array.length all - t.pre_skip)))

let of_packets (packets : string list) : t * float array array =
  match packets with
  | head :: _comments :: packets ->
      let t = create ~head in
      (t, sound t packets)
  | _ -> fail "fewer than its two headers"

let of_ogg (bytes : string) : t * float array array =
  let t, sound = of_packets (Ogg.packets bytes) in
  match Ogg.length bytes with
  | Some n -> (t, Array.map (fun (c : float array) -> if Array.length c > n - t.pre_skip then Array.sub c 0 (max 0 (n - t.pre_skip)) else c) sound)
  | None -> (t, sound)
