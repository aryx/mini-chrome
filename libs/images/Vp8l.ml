(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Vp8l.mli *)

(*****************************************************************************)
(* Bits, the least significant first *)
(*****************************************************************************)

type reader = { s : string; mutable pos : int; mutable acc : int; mutable held : int }

let reader (s : string) (pos : int) : reader = { s; pos; acc = 0; held = 0 }

(* the next [n] bits (up to 32), the first read the lowest; past the
 * end, zeros *)
let bits (r : reader) (n : int) : int =
  while r.held < n do
    let byte = if r.pos < String.length r.s then Char.code (String.unsafe_get r.s r.pos) else 0 in
    r.acc <- r.acc lor (byte lsl r.held);
    r.held <- r.held + 8;
    r.pos <- r.pos + 1
  done;
  let v = r.acc land ((1 lsl n) - 1) in
  r.acc <- r.acc lsr n;
  r.held <- r.held - n;
  v

(*****************************************************************************)
(* Prefix codes *)
(*****************************************************************************)

(* a canonical code (Huffman), or the code of one symbol alone, which
 * takes no bit at all *)
type code = Single of int | Code of Huffman.t

let symbol (r : reader) (c : code) : int = match c with Single s -> s | Code h -> Huffman.decode (fun () -> bits r 1) h

let code_of_lengths (lengths : int array) : code =
  let used = List.filter (fun i -> lengths.(i) > 0) (List.init (Array.length lengths) Fun.id) in
  match used with [] -> Single 0 | [ only ] -> Single only | _ -> Code (Huffman.of_lengths lengths)

(* the order in which the lengths of the code that codes the lengths
 * are sent: the most used first, so that the list can stop early *)
let length_order = [| 17; 18; 0; 1; 2; 3; 4; 5; 16; 6; 7; 8; 9; 10; 11; 12; 13; 14; 15 |]

(* a prefix code for an alphabet of [size] symbols, as it is sent: the
 * simple way (one or two symbols), or its lengths, themselves coded *)
let read_code (r : reader) (size : int) : code =
  let lengths = Array.make size 0 in
  if bits r 1 = 1 then (
    let two = bits r 1 = 1 in
    let first = bits r (if bits r 1 = 1 then 8 else 1) in
    if first < size then lengths.(first) <- 1;
    if two then (
      let second = bits r 8 in
      if second < size then lengths.(second) <- 1);
    code_of_lengths lengths)
  else
    let count = 4 + bits r 4 in
    let of_lengths = Array.make 19 0 in
    for i = 0 to count - 1 do of_lengths.(length_order.(i)) <- bits r 3 done;
    let length_code = code_of_lengths of_lengths in
    (* how many length symbols are sent: all, or a count *)
    let left = ref (if bits r 1 = 0 then size else let n = 2 + (2 * bits r 3) in 2 + bits r n) in
    let i = ref 0 and previous = ref 8 in
    while !i < size && !left > 0 do
      decr left;
      match symbol r length_code with
      | l when l < 16 ->
          lengths.(!i) <- l;
          incr i;
          if l <> 0 then previous := l
      | sym ->
          (* 16: the last length that was not 0, again; 17, 18: zeros *)
          let times, value = match sym with 16 -> (3 + bits r 2, !previous) | 17 -> (3 + bits r 3, 0) | _ -> (11 + bits r 7, 0) in
          if !i + times > size then failwith "Vp8l: too many code lengths";
          Array.fill lengths !i times value;
          i := !i + times
    done;
    code_of_lengths lengths

(*****************************************************************************)
(* An image's data *)
(*****************************************************************************)

(* where the pixels close by are, by their distance code (1 to 120):
 * (dx, dy), the nearest first -- the one above, the one before... *)
let near =
  [| (0, 1); (1, 0); (1, 1); (-1, 1); (0, 2); (2, 0); (1, 2); (-1, 2); (2, 1); (-2, 1); (2, 2); (-2, 2); (0, 3); (3, 0); (1, 3); (-1, 3); (3, 1); (-3, 1);
     (2, 3); (-2, 3); (3, 2); (-3, 2); (0, 4); (4, 0); (1, 4); (-1, 4); (4, 1); (-4, 1); (3, 3); (-3, 3); (2, 4); (-2, 4); (4, 2); (-4, 2); (0, 5);
     (3, 4); (-3, 4); (4, 3); (-4, 3); (5, 0); (1, 5); (-1, 5); (5, 1); (-5, 1); (2, 5); (-2, 5); (5, 2); (-5, 2); (4, 4); (-4, 4); (3, 5); (-3, 5);
     (5, 3); (-5, 3); (0, 6); (6, 0); (1, 6); (-1, 6); (6, 1); (-6, 1); (2, 6); (-2, 6); (6, 2); (-6, 2); (4, 5); (-4, 5); (5, 4); (-5, 4); (3, 6);
     (-3, 6); (6, 3); (-6, 3); (0, 7); (7, 0); (1, 7); (-1, 7); (5, 5); (-5, 5); (7, 1); (-7, 1); (4, 6); (-4, 6); (6, 4); (-6, 4); (2, 7); (-2, 7);
     (7, 2); (-7, 2); (3, 7); (-3, 7); (7, 3); (-7, 3); (5, 6); (-5, 6); (6, 5); (-6, 5); (8, 0); (4, 7); (-4, 7); (7, 4); (-7, 4); (8, 1); (8, 2);
     (6, 6); (-6, 6); (8, 3); (5, 7); (-5, 7); (7, 5); (-7, 5); (8, 4); (6, 7); (-6, 7); (7, 6); (-7, 6); (8, 5); (7, 7); (-7, 7); (8, 6); (8, 7) |]

(* a length or a distance from its prefix code: the small ones are the
 * code itself, the others a base and extra bits *)
let extended (r : reader) (prefix : int) : int =
  if prefix < 4 then prefix + 1
  else
    let extra = (prefix - 2) lsr 1 in
    ((2 + (prefix land 1)) lsl extra) + bits r extra + 1

let blocks (size : int) (shift : int) : int = (size + (1 lsl shift) - 1) lsr shift

(* an image of [width] by [height] pixels, each 0xAARRGGBB. [main]: the
 * picture itself, which may have several groups of codes, by place *)
let rec image (r : reader) ~(main : bool) ~(width : int) ~(height : int) : int array =
  let cache_bits = if bits r 1 = 1 then bits r 4 else 0 in
  if cache_bits > 11 then failwith "Vp8l: a colour cache too large";
  let cache = Array.make (if cache_bits > 0 then 1 lsl cache_bits else 0) 0 in
  let remember (argb : int) = if cache_bits > 0 then cache.(((0x1e35a7bd * argb) land 0xffffffff) lsr (32 - cache_bits)) <- argb in
  (* which group of codes each block of the picture uses *)
  let group_bits, group_width, groups_of =
    if main && bits r 1 = 1 then
      let shift = bits r 3 + 2 in
      let w = blocks width shift in
      (shift, w, image r ~main:false ~width:w ~height:(blocks height shift))
    else (0, 0, [||])
  in
  let group_count = Array.fold_left (fun m px -> max m (((px lsr 8) land 0xffff) + 1)) 1 groups_of in
  (* a group: the codes of green (and lengths, and the cache), red,
   * blue, alpha, and distances *)
  let groups =
    Array.init group_count (fun _ ->
        let green = read_code r (256 + 24 + Array.length cache) in
        let red = read_code r 256 in
        let blue = read_code r 256 in
        let alpha = read_code r 256 in
        (green, red, blue, alpha, read_code r 40))
  in
  let total = width * height in
  let out = Array.make total 0 in
  let at = ref 0 in
  while !at < total do
    let green, red, blue, alpha, distance =
      if group_width = 0 then groups.(0)
      else
        let x = !at mod width and y = !at / width in
        groups.((groups_of.(((y lsr group_bits) * group_width) + (x lsr group_bits)) lsr 8) land 0xffff)
    in
    let s = symbol r green in
    if s < 256 then (
      (* a pixel, each of its four numbers by its own code *)
      let rd = symbol r red in
      let bl = symbol r blue in
      let al = symbol r alpha in
      let argb = (al lsl 24) lor (rd lsl 16) lor (s lsl 8) lor bl in
      out.(!at) <- argb;
      remember argb;
      incr at)
    else if s < 280 then (
      (* pixels seen before, copied: how many, from how far back *)
      let length = extended r (s - 256) in
      let code = extended r (symbol r distance) in
      let back = if code > 120 then code - 120 else let dx, dy = near.(code - 1) in max 1 (dx + (dy * width)) in
      if back > !at then failwith "Vp8l: a copy from before the picture";
      for _ = 1 to min length (total - !at) do
        let argb = out.(!at - back) in
        out.(!at) <- argb;
        remember argb;
        incr at
      done)
    else (
      (* a colour seen lately, by its place in the cache *)
      let index = s - 280 in
      if index >= Array.length cache then failwith "Vp8l: a colour not in the cache";
      let argb = cache.(index) in
      out.(!at) <- argb;
      remember argb;
      incr at)
  done;
  out

(*****************************************************************************)
(* Transforms *)
(*****************************************************************************)

type transform =
  | Predictor of int * int array (* its blocks' size as a shift, and each block's mode *)
  | Colour of int * int array (* the same, and each block's three multipliers *)
  | Subtract_green
  | Indexed of int array * int (* the colours, and how many pixels are packed in one: 1 lsl it *)

(* a + b, channel by channel, each kept to its byte *)
let add (a : int) (b : int) : int = (((a land 0xff00ff00) + (b land 0xff00ff00)) land 0xff00ff00) lor (((a land 0x00ff00ff) + (b land 0x00ff00ff)) land 0x00ff00ff)

(* the mean of two pixels, channel by channel *)
let average (a : int) (b : int) : int = (((a lxor b) land 0xfefefefe) lsr 1) + (a land b)

let channel (argb : int) (shift : int) : int = (argb lsr shift) land 0xff
let clamp (v : int) : int = if v < 0 then 0 else if v > 255 then 255 else v
let of_channels (f : int -> int) : int = (f 24 lsl 24) lor (f 16 lsl 16) lor (f 8 lsl 8) lor f 0

(* the left one or the one above, whichever is nearer what the three
 * neighbours suggest (left + top - top left) *)
let select (l : int) (t : int) (tl : int) : int =
  let far (px : int) = List.fold_left (fun sum sh -> sum + abs (channel l sh + channel t sh - channel tl sh - channel px sh)) 0 [ 24; 16; 8; 0 ] in
  if far l < far t then l else t

(* what a pixel is guessed to be from those before it, by one of the
 * fourteen ways *)
let predicted (mode : int) ~(l : int) ~(t : int) ~(tr : int) ~(tl : int) : int =
  match mode with
  | 0 -> 0xff000000
  | 1 -> l
  | 2 -> t
  | 3 -> tr
  | 4 -> tl
  | 5 -> average (average l tr) t
  | 6 -> average l tl
  | 7 -> average l t
  | 8 -> average tl t
  | 9 -> average t tr
  | 10 -> average (average l tl) (average t tr)
  | 11 -> select l t tl
  | 12 -> of_channels (fun sh -> clamp (channel l sh + channel t sh - channel tl sh))
  | 13 ->
      let a = average l t in
      of_channels (fun sh -> clamp (channel a sh + ((channel a sh - channel tl sh) / 2)))
  | _ -> 0xff000000

let signed (byte : int) : int = if byte >= 128 then byte - 256 else byte

(* a transform undone, on a picture [width] wide: the picture as it was
 * before it, and its width (the indexed one may widen it) *)
let undo (tr : transform) (px : int array) ~(width : int) ~(height : int) : int array * int =
  match tr with
  | Subtract_green ->
      Array.iteri
        (fun i p ->
          let g = channel p 8 in
          px.(i) <- (p land 0xff00ff00) lor (((channel p 16 + g) land 0xff) lsl 16) lor ((channel p 0 + g) land 0xff))
        px;
      (px, width)
  | Colour (shift, blocks_px) ->
      let bw = blocks width shift in
      Array.iteri
        (fun i p ->
          let e = blocks_px.((((i / width) lsr shift) * bw) + ((i mod width) lsr shift)) in
          let delta (mult : int) (c : int) = (signed mult * signed c) asr 5 in
          let g = channel p 8 in
          let red = (channel p 16 + delta (channel e 0) g) land 0xff in
          let blue = (channel p 0 + delta (channel e 8) g + delta (channel e 16) red) land 0xff in
          px.(i) <- (p land 0xff00ff00) lor (red lsl 16) lor blue)
        px;
      (px, width)
  | Predictor (shift, blocks_px) ->
      let bw = blocks width shift in
      for i = 0 to Array.length px - 1 do
        let x = i mod width and y = i / width in
        let guess =
          (* the borders have fewer neighbours: black first, then the
           * one before along the top, the one above down the left *)
          if i = 0 then 0xff000000
          else if y = 0 then px.(i - 1)
          else if x = 0 then px.(i - width)
          else
            (* at the right edge, "top right" is the row's first pixel *)
            let tr = if x = width - 1 then px.(i - x) else px.(i - width + 1) in
            predicted (channel blocks_px.(((y lsr shift) * bw) + (x lsr shift)) 8) ~l:px.(i - 1) ~t:px.(i - width) ~tr ~tl:px.(i - width - 1)
        in
        px.(i) <- add px.(i) guess
      done;
      (px, width)
  | Indexed (table, pack) ->
      (* a pixel's green is its colour's number; several small numbers
       * may be packed in one green, the first in its low bits *)
      let per = 1 lsl pack and each = 8 lsr pack in
      let wide = width in
      let packed_width = blocks wide pack in
      let colour (index : int) = if index < Array.length table then table.(index) else 0 in
      ( Array.init (wide * height) (fun i ->
            let x = i mod wide and y = i / wide in
            let g = channel px.((y * packed_width) + (x / per)) 8 in
            colour (if pack = 0 then g else (g lsr (each * (x mod per))) land ((1 lsl each) - 1))),
        wide )

(*****************************************************************************)
(* Entry points *)
(*****************************************************************************)

(* the transforms, then the picture, then the transforms undone, the
 * last read first *)
let stream (r : reader) ~(width : int) ~(height : int) : int array =
  let rec transforms (acc : (transform * int) list) (w : int) : (transform * int) list * int =
    if bits r 1 = 0 then (acc, w)
    else
      match bits r 2 with
      | 0 ->
          let shift = bits r 3 + 2 in
          transforms ((Predictor (shift, image r ~main:false ~width:(blocks w shift) ~height:(blocks height shift)), w) :: acc) w
      | 1 ->
          let shift = bits r 3 + 2 in
          transforms ((Colour (shift, image r ~main:false ~width:(blocks w shift) ~height:(blocks height shift)), w) :: acc) w
      | 2 -> transforms ((Subtract_green, w) :: acc) w
      | _ ->
          let size = bits r 8 + 1 in
          let table = image r ~main:false ~width:size ~height:1 in
          (* each colour is sent as its difference from the one before *)
          for i = 1 to size - 1 do table.(i) <- add table.(i) table.(i - 1) done;
          let pack = if size <= 2 then 3 else if size <= 4 then 2 else if size <= 16 then 1 else 0 in
          transforms ((Indexed (table, pack), w) :: acc) (blocks w pack)
  in
  let undone, w = transforms [] width in
  let px = image r ~main:true ~width:w ~height in
  (* each undone at the width the picture had when it was read *)
  fst (List.fold_left (fun (px, _) (tr, was) -> undo tr px ~width:was ~height) (px, w) undone)

let size (s : string) : (int * int) option =
  if String.length s >= 5 && s.[0] = '\x2f' then
    let r = reader s 1 in
    let w = bits r 14 + 1 in
    Some (w, bits r 14 + 1)
  else None

let decode (s : string) : Rgba_image.t =
  if String.length s < 5 || s.[0] <> '\x2f' then failwith "Vp8l: not a lossless WebP stream";
  let r = reader s 1 in
  let width = bits r 14 + 1 in
  let height = bits r 14 + 1 in
  let (_ : int) = bits r 1 in
  if bits r 3 <> 0 then failwith "Vp8l: a version not known";
  let px = stream r ~width ~height in
  let img = Rgba_image.create ~width ~height in
  Array.iteri
    (fun i argb ->
      img.rgba.{4 * i} <- channel argb 16;
      img.rgba.{(4 * i) + 1} <- channel argb 8;
      img.rgba.{(4 * i) + 2} <- channel argb 0;
      img.rgba.{(4 * i) + 3} <- channel argb 24)
    px;
  img

let plane (s : string) ~(width : int) ~(height : int) : int array = Array.map (fun argb -> channel argb 8) (stream (reader s 0) ~width ~height)
