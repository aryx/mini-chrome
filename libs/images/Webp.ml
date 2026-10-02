(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Webp.mli *)

let u32 (s : string) (i : int) : int =
  Char.code s.[i] lor (Char.code s.[i + 1] lsl 8) lor (Char.code s.[i + 2] lsl 16) lor (Char.code s.[i + 3] lsl 24)

let u24 (s : string) (i : int) : int = Char.code s.[i] lor (Char.code s.[i + 1] lsl 8) lor (Char.code s.[i + 2] lsl 16)

let sniff (s : string) : bool = String.length s >= 12 && String.sub s 0 4 = "RIFF" && String.sub s 8 4 = "WEBP"

(* the chunks of [s] from [from] to [until]: each its four letters and
 * its bytes; a chunk of odd length is followed by a byte of padding *)
let rec chunks (s : string) (from : int) (until : int) : (string * string) list =
  if from + 8 > until then []
  else
    let size = u32 s (from + 4) in
    let size = min size (until - from - 8) in
    (String.sub s from 4, String.sub s (from + 8) size) :: chunks s (from + 8 + size + (size land 1)) until

(* the alpha of a picture that is otherwise lossy (the ALPH chunk): a
 * byte a pixel, as they are or as a lossless picture's green, each
 * first lessened by its neighbour (left, above, or both less the one
 * between: the filter), to be added back *)
let alpha (data : string) ~(width : int) ~(height : int) : int array =
  if data = "" then failwith "Webp: an empty ALPH chunk";
  let flags = Char.code data.[0] in
  let filter = (flags lsr 2) land 3 in
  let body = String.sub data 1 (String.length data - 1) in
  let a =
    match flags land 3 with
    | 0 -> Array.init (width * height) (fun i -> if i < String.length body then Char.code body.[i] else 0)
    | 1 -> Vp8l.plane body ~width ~height
    | _ -> failwith "Webp: an alpha compression not known"
  in
  if filter <> 0 then
    for i = 1 to (width * height) - 1 do
      let x = i mod width and y = i / width in
      let left = a.(i - 1) and above = if y > 0 then a.(i - width) else 0 in
      let guess =
        if y = 0 then left
        else if x = 0 then above
        else
          match filter with
          | 1 -> left
          | 2 -> above
          | _ -> max 0 (min 255 (left + above - a.(i - width - 1)))
      in
      a.(i) <- (a.(i) + guess) land 0xff
    done;
  a

(* a picture from the chunks that make one: lossless, or lossy with its
 * alpha beside it if it has one *)
let picture (parts : (string * string) list) : Rgba_image.t =
  match (List.assoc_opt "VP8L" parts, List.assoc_opt "VP8 " parts) with
  | Some lossless, _ -> Vp8l.decode lossless
  | None, Some lossy -> (
      let img = Vp8.decode lossy in
      match List.assoc_opt "ALPH" parts with
      | Some data ->
          Array.iteri (fun i a -> img.rgba.{(4 * i) + 3} <- a) (alpha data ~width:img.width ~height:img.height);
          img
      | None -> img)
  | None, None -> failwith "Webp: no picture in it"

let decode (s : string) : Rgba_image.t =
  if not (sniff s) then failwith "Webp: not a WebP file";
  let parts = chunks s 12 (min (String.length s) (8 + u32 s 4)) in
  match List.assoc_opt "ANMF" parts with
  (* an animation: its first frame (16 bytes of where and how long,
   * then the frame's own chunks) *)
  | Some frame when String.length frame > 16 -> picture (chunks frame 16 (String.length frame))
  | _ -> picture parts

let size (s : string) : (int * int) option =
  if not (sniff s) then None
  else
    let parts = chunks s 12 (String.length s) in
    match (List.assoc_opt "VP8X" parts, List.assoc_opt "VP8L" parts, List.assoc_opt "VP8 " parts) with
    | Some x, _, _ when String.length x >= 10 -> Some (u24 x 4 + 1, u24 x 7 + 1)
    | _, Some l, _ -> Vp8l.size l
    | _, _, Some v when String.length v >= 10 -> Some ((Char.code v.[6] lor (Char.code v.[7] lsl 8)) land 0x3fff, (Char.code v.[8] lor (Char.code v.[9] lsl 8)) land 0x3fff)
    | _ -> None
