(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Pdf_viewer.mli *)

type t = { pdf : Pdf.t; cache : Pdf_render.cache; pages : Pdf.page array }

(* how much of a page's drawing is done (the flag pdf=): all of it, or
 * less, to see what each part adds *)
let options : Pdf_render.options ref = ref Pdf_render.full

(* a page's picture has this many dots for a pixel of the page shown:
 * sharp on a screen of two dots a pixel, and when zoomed a little *)
let density = 1.5

let sniff = Pdf.sniff

let open_ (bytes : string) : (t, string) result =
  match Pdf.of_string bytes with
  | pdf -> ( match Pdf.pages pdf with [] -> Error "a PDF file with no page" | pages -> Ok { pdf; cache = Pdf_render.cache (); pages = Array.of_list pages })
  | exception Failure why -> Error why
  | exception _ -> Error "Pdf: a file that cannot be read"

let src (n : int) : string = Printf.sprintf "pdf-page:%d" n

let page_of_src (s : string) : int option =
  if String.length s > 9 && String.sub s 0 9 = "pdf-page:" then int_of_string_opt (String.sub s 9 (String.length s - 9)) else None

(* the document as a page of ours: its pages one under the other, each
 * a picture of its size (a point is 1/72 inch, a pixel 1/96), white
 * until it is drawn *)
let html (t : t) ~(name : string) : string =
  let b = Buffer.create 1024 in
  Printf.bprintf b
    "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>%s</title><style>body { margin: 0; background: #525659; text-align: center } div { margin: 12px 0 } img { background: white; vertical-align: top }</style></head><body>"
    (Browser_text.escape_html name);
  Array.iteri
    (fun i p ->
      let w, h = Pdf_render.size p in
      Printf.bprintf b "<div><img src=\"%s\" width=\"%d\" height=\"%d\" alt=\"page %d\"></div>" (src (i + 1)) (int_of_float (Float.round (w *. 96. /. 72.))) (int_of_float (Float.round (h *. 96. /. 72.))) (i + 1))
    t.pages;
  Buffer.add_string b "</body></html>";
  Buffer.contents b

(* our stroke font's letter for a character, accents and all, as Pdf_render wants it *)
let stroke_glyph (code : int) : (float * float) list list * float =
  let b = Buffer.create 4 in
  Buffer.add_utf_8_uchar b (if Uchar.is_valid code then Uchar.of_int code else Uchar.rep);
  let g = Glyph_unicode.glyph (Buffer.contents b) and em = Hershey.units_per_em in
  (List.map (List.map (fun (x, y) -> (float_of_int (x - g.left) /. em, float_of_int (9 - y) /. em))) g.strokes, float_of_int (g.right - g.left) /. em)

let picture (t : t) (n : int) : Rgba_image.t =
  if n < 1 || n > Array.length t.pages then Rgba_image.create ~width:1 ~height:1
  else Pdf_render.render ~options:!options ~stroke_glyph t.pdf t.cache t.pages.(n - 1) ~scale:(density *. 96. /. 72.)
