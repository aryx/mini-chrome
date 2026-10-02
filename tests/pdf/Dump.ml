(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Dump.mli *)

let () =
  match Array.to_list Sys.argv with
  | _ :: "info" :: files ->
      List.iter
        (fun file ->
          let bytes = In_channel.with_open_bin file In_channel.input_all in
          match Pdf.of_string bytes with
          | exception Failure why -> Printf.printf "%s: %s\n" file why
          | pdf ->
              let pages = Pdf.pages pdf in
              Printf.printf "%s: %d page(s)\n" file (List.length pages);
              List.iteri
                (fun i (p : Pdf.page) ->
                  let x0, y0, x1, y1 = p.box and content = Pdf.content pdf p in
                  Printf.printf "  %d: %g x %g, %d bytes of content: %s\n" (i + 1) (x1 -. x0) (y1 -. y0) (String.length content)
                    (String.map (fun c -> if c < ' ' then ' ' else c) (String.sub content 0 (min 70 (String.length content)))))
                pages)
        files
  | [ _; how; file; page; scale; out ] when how = "render" || Pdf_render.options_of_string how <> Pdf_render.full ->
      let pdf = Pdf.of_string (In_channel.with_open_bin file In_channel.input_all) in
      let p = List.nth (Pdf.pages pdf) (int_of_string page - 1) in
      let t0 = Sys.time () in
      let img = Pdf_render.render ~options:(Pdf_render.options_of_string how) pdf (Pdf_render.cache ()) p ~scale:(float_of_string scale) in
      Printf.printf "%d x %d in %.2f s\n" img.width img.height (Sys.time () -. t0);
      (* a PPM: three bytes a pixel after a line of text *)
      Out_channel.with_open_bin out (fun oc ->
          Printf.fprintf oc "P6\n%d %d\n255\n" img.width img.height;
          for i = 0 to (img.width * img.height) - 1 do
            for c = 0 to 2 do Out_channel.output_char oc (Char.chr img.rgba.{(4 * i) + c}) done
          done)
  | [ _; "glyph"; file; which ] ->
      (* a font file's glyph: by its number (TrueType, CFF) or its name (Type 1) *)
      let bytes = In_channel.with_open_bin file In_channel.input_all in
      let outline =
        if String.length bytes > 2 && (bytes.[0] = '%' || bytes.[0] = '\128') then fst (Type1.glyph (Type1.of_string bytes) which)
        else if bytes.[0] = '\001' then (let f = Cff.of_string bytes in Printf.printf "matrix %s, %d glyphs\n" (String.concat " " (List.map string_of_float (Cff.matrix f))) (Cff.glyphs f); Cff.outline f (int_of_string which))
        else
          let f = Truetype.of_string bytes in
          match Truetype.cff f with Some c -> Cff.outline (Cff.of_string c) (int_of_string which) | None -> Truetype.outline f (int_of_string which)
      in
      List.iter
        (fun (c : Outline.contour) ->
          Printf.printf "M %g %g" (fst c.start) (snd c.start);
          List.iter (fun (sg : Outline.segment) -> match sg with Line (x, y) -> Printf.printf " L %g %g" x y | Quadratic ((a, b), (x, y)) -> Printf.printf " Q %g %g %g %g" a b x y | Cubic ((a, b), (c, d), (x, y)) -> Printf.printf " C %g %g %g %g %g %g" a b c d x y) c.segments;
          print_endline " Z")
        outline
  | [ _; "text"; file; page ] ->
      let pdf = Pdf.of_string (In_channel.with_open_bin file In_channel.input_all) in
      print_endline (Pdf_render.text pdf (Pdf_render.cache ()) (List.nth (Pdf.pages pdf) (int_of_string page - 1)))
  | _ ->
      prerr_endline "usage: Dump.exe info file.pdf... | render|OPTIONS file.pdf page scale out.ppm (OPTIONS as the flag pdf=: plain, strokes, -gradients...) | text file.pdf page | glyph font which";
      exit 2
