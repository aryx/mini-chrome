(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Bookmarks.mli *)
open Playground

type entry = { url : string; title : string }
type t = entry list

let has (t : t) (url : string) : bool = List.exists (fun e -> e.url = url) t

let toggle (t : t) ~(url : string) ~(title : string) : t =
  if has t url then List.filter (fun e -> e.url <> url) t else t @ [ { url; title = (if String.trim title = "" then url else String.trim title) } ]

let to_json (t : t) : Json.t = Array (List.map (fun e -> Json.Object [ ("url", String e.url); ("title", String e.title) ]) t)

let of_json (j : Json.t) : t =
  let entry (j : Json.t) = match (Json.member "url" j, Json.member "title" j) with Some (String url), Some (String title) when url <> "" -> Some { url; title } | _ -> None in
  match j with Array es -> List.filter_map entry es | _ -> []

let page (t : t) : string =
  let esc = Browser_text.escape_html in
  let row e = Printf.sprintf "<li><a href=\"%s\">%s</a> <small>%s</small></li>\n" (esc e.url) (esc e.title) (esc e.url) in
  Printf.sprintf
    {|<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><title>Bookmarks</title>
<link rel="stylesheet" href="chrome.css">
</head><body><main><h1>Bookmarks</h1>
<p>%s</p>
<ul>
%s</ul></main></body></html>
|}
    (if t = [] then "None yet: the star at the omnibox's end, or Ctrl+D, keeps the page shown."
     else "The pages kept, in the order they were; the star, or Ctrl+D, on a page lets it go. They are the profile's (Preferences, \"bookmarks\").")
    (String.concat "" (List.map row t))

(*****************************************************************************)
(* The bar *)
(*****************************************************************************)

type bar = { left : float; y : float; room : float; entries : t }

let bar_height = 24.

(* a name: its title's first letters *)
let label (e : entry) : string =
  let title = String.map (fun c -> if Char.code c < 128 then c else '?') e.title in
  Gui_text.head 22 title

(* each name's left edge and width, as many as the room holds *)
let places (b : bar) : (entry * float * float) list =
  let _, placed =
    List.fold_left
      (fun (x, acc) e ->
        let w = Gui_text.width (label e) +. 16. in
        if x +. w > b.left +. b.room then (x, acc) else (x +. w +. 4., (e, x, w) :: acc))
      (b.left, []) b.entries
  in
  List.rev placed

let at (b : bar) (point : float * float) : string option =
  List.find_map (fun (e, x, w) -> if Gui_kit.near x b.y w (bar_height -. 4.) point then Some e.url else None) (places b)

let shapes (b : bar) ~(pointer : float * float) : shape list =
  List.concat_map
    (fun (e, x, w) ->
      (if at b pointer = Some e.url then [ rectangle Gui_kit.lit w (bar_height -. 4.) |> move (x +. (w /. 2.)) b.y ] else [])
      @ Gui_text.monospace (x +. 8.) b.y Gui_kit.ink (label e))
    (places b)

let star ~(kept : bool) (x : float) (y : float) : shape list =
  (* five points, every other one near the centre *)
  let points r = List.init 10 (fun i -> let a = (Float.pi /. 2.) +. (float_of_int i *. Float.pi /. 5.) and r = if i mod 2 = 0 then r else r *. 0.42 in (r *. cos a, r *. sin a)) in
  if kept then [ polygon (rgb 240 180 20) (points 8.) |> move x y ] else [ polygon Gui_kit.muted (points 8.) |> move x y; polygon Gui_kit.white (points 5.5) |> move x y ]
