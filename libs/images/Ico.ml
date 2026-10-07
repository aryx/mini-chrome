(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Ico.mli *)

let u8 (s : string) (i : int) : int = Char.code s.[i]
let u16 (s : string) (i : int) : int = u8 s i lor (u8 s (i + 1) lsl 8)
let u32 (s : string) (i : int) : int = u16 s i lor (u16 s (i + 2) lsl 16)

let sniff (s : string) : bool = String.length s >= 22 && u16 s 0 = 0 && u16 s 2 = 1 && u16 s 4 > 0 && u16 s 4 < 64 && u8 s 9 = 0

(* a Windows bitmap as an icon has it: its header (40 bytes or more),
 * a palette, the colours' rows, the mask's *)
let bitmap (s : string) : Rgba_image.t =
  let header = u32 s 0 and width = u32 s 4 and height = u32 s 8 / 2 and bits = u16 s 14 in
  if u32 s 16 <> 0 then failwith "ICO: a compressed bitmap";
  if width <= 0 || height <= 0 || width > 1024 || height > 1024 then failwith "ICO: a bitmap's size";
  let colours = if bits <= 8 then (match u32 s 32 with 0 -> 1 lsl bits | n -> n) else 0 in
  let palette = header and pixels = header + (4 * colours) in
  (* a row's bytes: padded to four *)
  let row_bytes b = ((width * b) + 31) / 32 * 4 in
  let mask = pixels + (row_bytes bits * height) in
  let img = Rgba_image.create ~width ~height in
  let alphas = ref false in
  for y = 0 to height - 1 do
    (* the rows are from the bottom up *)
    let row = pixels + (row_bytes bits * (height - 1 - y)) and mrow = mask + (row_bytes 1 * (height - 1 - y)) in
    for x = 0 to width - 1 do
      let r, g, b, a =
        match bits with
        | 32 -> let i = row + (4 * x) in (u8 s (i + 2), u8 s (i + 1), u8 s i, u8 s (i + 3))
        | 24 -> let i = row + (3 * x) in (u8 s (i + 2), u8 s (i + 1), u8 s i, 255)
        | 1 | 4 | 8 ->
            let bit = x * bits in
            let index = (u8 s (row + (bit / 8)) lsr (8 - bits - (bit mod 8))) land ((1 lsl bits) - 1) in
            let i = palette + (4 * index) in
            (u8 s (i + 2), u8 s (i + 1), u8 s i, 255)
        | _ -> failwith "ICO: a bitmap's depth"
      in
      if bits = 32 && a <> 0 then alphas := true;
      (* the mask: a dot not drawn (when the file has it) *)
      let hidden = mrow + (x / 8) < String.length s && (u8 s (mrow + (x / 8)) lsr (7 - (x mod 8))) land 1 = 1 in
      let o = 4 * ((y * width) + x) in
      img.rgba.{o} <- r;
      img.rgba.{o + 1} <- g;
      img.rgba.{o + 2} <- b;
      img.rgba.{o + 3} <- (if hidden && bits < 32 then 0 else a)
    done
  done;
  (* 32 bits with every alpha at 0: an old file, opaque where its mask says *)
  if bits = 32 && not !alphas then
    for y = 0 to height - 1 do
      let mrow = mask + (row_bytes 1 * (height - 1 - y)) in
      for x = 0 to width - 1 do
        let hidden = mrow + (x / 8) < String.length s && (u8 s (mrow + (x / 8)) lsr (7 - (x mod 8))) land 1 = 1 in
        img.rgba.{(4 * ((y * width) + x)) + 3} <- (if hidden then 0 else 255)
      done
    done;
  img

let decode ?(size = 32) (s : string) : Rgba_image.t =
  if not (sniff s) then failwith "ICO: not an icon file";
  let entries =
    List.init (u16 s 4) (fun i ->
        let e = 6 + (16 * i) in
        if e + 16 > String.length s then failwith "ICO: cut in its directory";
        let width = match u8 s e with 0 -> 256 | w -> w in
        (width, u16 s (e + 6), u32 s (e + 8), u32 s (e + 12)))
  in
  (* the nearest to the size asked; of two as near, the larger, then the deeper *)
  let rank (w, depth, _, _) = (abs (w - size), -w, -depth) in
  match List.sort (fun a b -> compare (rank a) (rank b)) entries with
  | (_, _, length, start) :: _ when start + length <= String.length s && length > 40 ->
      let data = String.sub s start length in
      if String.sub data 0 4 = "\x89PNG" then Png.decode data else bitmap data
  | _ -> failwith "ICO: no picture"
