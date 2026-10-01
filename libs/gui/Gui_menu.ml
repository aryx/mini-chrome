(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Gui_menu.mli *)
open Playground

type 'a item = { label : string; value : 'a; enabled : bool }
type 'a t = { at : float * float; left : float; top : float; items : 'a item list }

let item_height = 22.
let padding = 4.
let width (m : 'a t) : float = List.fold_left (fun w i -> Float.max w (Gui_text.width i.label)) 0. m.items +. 28.
let height (m : 'a t) : float = (item_height *. float_of_int (List.length m.items)) +. (2. *. padding)

let opened ~screen:((w, h) : float * float) ~at:((x, y) : float * float) (items : 'a item list) : 'a t =
  let m = { at = (x, y); left = x; top = y; items } in
  { m with left = Float.max (-.w /. 2.) (Float.min x ((w /. 2.) -. width m)); top = Float.min (h /. 2.) (Float.max y (height m -. (h /. 2.))) }

let index_at (m : 'a t) ((x, y) : float * float) : int option =
  let i = int_of_float (Float.floor ((m.top -. padding -. y) /. item_height)) in
  if x >= m.left && x <= m.left +. width m && y <= m.top -. padding && i < List.length m.items then Some i else None

let chosen (m : 'a t) (point : float * float) : 'a option =
  match Option.map (List.nth m.items) (index_at m point) with Some { enabled = true; value; _ } -> Some value | _ -> None

(* the y of an item's middle *)
let row (m : 'a t) (i : int) : float = m.top -. padding -. ((float_of_int i +. 0.5) *. item_height)

let shapes (m : 'a t) ~(pointer : float * float) : shape list =
  let w = width m and h = height m in
  let x = m.left +. (w /. 2.) and y = m.top -. (h /. 2.) in
  let pointed = index_at m pointer in
  [ rectangle black w h |> fade 0.15 |> move (x +. 3.) (y -. 3.); rectangle (rgb 160 176 204) (w +. 2.) (h +. 2.) |> move x y;
    rectangle white w h |> move x y ]
  @ List.concat
      (List.mapi
         (fun i (item : 'a item) ->
           (if pointed = Some i && item.enabled then [ rectangle (rgb 232 240 254) w item_height |> move x (row m i) ] else [])
           @ Gui_text.monospace (m.left +. 14.) (row m i) (if item.enabled then rgb 32 33 36 else rgb 180 186 196) item.label)
         m.items)
