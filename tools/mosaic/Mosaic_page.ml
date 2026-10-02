(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Mosaic_page.mli *)

let pretty : Html_layout.breaker =
 fun ~measure units ->
  let space = Array.fold_left (fun s (u : Html_layout.unit_) -> if s = 0. then u.space else s) 0. units in
  let words = Array.map (fun (u : Html_layout.unit_) -> { Linebreak.text = ""; width = u.width }) units in
  Linebreak.optimal { measure; space; stretch = space; shrink = 0. } words
  |> List.map (fun (l : Linebreak.line) -> (l.first, l.last))

let engine ?(extensions = false) ?(css = false) ?(breaker = Html_layout.greedy) () : Browser_page.engine =
 fun ~visited ~picture ~width tree ->
  let picture_size src = Option.bind (picture src) Browser_picture.size in
  let root = { Browser_text.root_look with extensions } in
  let style = if css then Css.cascade (Css.parse (Css.page_sheet tree)) tree else fun _ -> [] in
  let layout = Mosaic_layout.layout Browser_text.metrics ~breaker ~picture_size ~style ~root ~width tree in
  (* the page's colour: the style sheets' for its <body> or <html>,
   * else Netscape's bgcolor= *)
  let body = List.nth_opt (Dom.find_all "body" tree) 0 in
  let sheets_colour =
    List.find_map
      (fun e -> Option.bind (List.find_map (fun (p, v) -> if p = "background-color" || p = "background" then Some v else None) (style e)) Looks.color_of_string)
      (Option.to_list body @ [ tree ])
  in
  let background =
    match sheets_colour with
    | Some c -> Some c
    | None when extensions -> Option.bind (Option.bind body (Dom.attribute ~extensions:true "bgcolor")) Looks.color_of_string
    | None -> None
  in
  (layout, Mosaic_draw.draw ~extensions ~visited ~picture_of:picture layout, background)
