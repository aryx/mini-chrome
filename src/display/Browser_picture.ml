(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Browser_picture.mli *)

type t = Waiting | Arrived of Rgba_image.t | Broken

let decode (bytes : string) : t =
  let starts magic = String.length bytes >= String.length magic && String.sub bytes 0 (String.length magic) = magic in
  try
    if starts "GIF8" then Arrived (Gif.decode bytes)
    else if starts "\x89PNG" then Arrived (Png.decode bytes)
    else if starts "\xFF\xD8" then Arrived (Jpeg.decode bytes)
    else if Webp.sniff bytes then Arrived (Webp.decode bytes)
    (* a site's icon (/favicon.ico): one of the file's pictures *)
    else if Ico.sniff bytes then Arrived (Ico.decode bytes)
    else if Svg.sniff bytes then
      (* drawn at its own size (a picture without one: CSS's 300 by 150) *)
      match Svg.parse bytes with
      | Some svg ->
          let w, h = Option.value (Svg.size svg) ~default:(300., 150.) in
          Arrived (Svg.render svg ~width:(int_of_float (Float.round w)) ~height:(int_of_float (Float.round h)))
      | None -> Broken
    else Broken
  with _ -> Broken

(* opti: the pictures a thread of the pool decoded ahead ([warm], as
 * it fetched them), kept until asked for by those very bytes (==): a
 * picture's decoding is then not a frame's work (GitHub's page, its
 * README's fourteen screenshots: 4.5 s of the window's thread) *)
let ahead : (string * t) list ref = ref []
let lock = Mutex.create ()

let warm (bytes : string) : unit =
  (* not an SVG: it is drawn with the letters' tables, the window's own *)
  if !Mini_opti.enabled && not (Svg.sniff bytes) then (
    let pic = decode bytes in
    Mutex.lock lock;
    (* a few: one not asked for (its tab closed) is let go *)
    ahead := (bytes, pic) :: List.filteri (fun i _ -> i < 15) !ahead;
    Mutex.unlock lock)

let decode (bytes : string) : t =
  Mutex.lock lock;
  let found = List.find_opt (fun (b, _) -> b == bytes) !ahead in
  ahead := List.filter (fun (b, _) -> b != bytes) !ahead;
  Mutex.unlock lock;
  match found with Some (_, pic) -> pic | None -> Stopwatch.time "pictures" (fun () -> decode bytes)

(* how many bytes of pictures decoded a tab keeps besides its shown
 * page's (four a dot): 128 MB, three photographs of a camera or
 * a few hundred of a page *)
let kept_bytes = 128 * 1024 * 1024

let broken_size = 24.

let drawn (w : float) (h : float) (img : Rgba_image.t) : Playground.shape list =
  if w > 0. && h > 0. && img.width > 0 && img.height > 0 then [ Playground.bitmap w h img ] else []

let size (t : t) : (float * float) option =
  match t with
  | Arrived img -> Some (float_of_int img.width, float_of_int img.height)
  | Broken -> Some (broken_size, broken_size)
  | Waiting -> None
