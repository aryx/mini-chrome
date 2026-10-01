(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Gui_scrollbar.mli *)
open Playground

type t = { right : float; top : float; height : float; total : float; shown : float; offset : float }
type hit = Thumb of float | Before | After

let width = 12.

(* what the content can be scrolled by, and what the thumb can travel *)
let range (b : t) : float = b.total -. b.shown
let length (b : t) : float = Float.min b.height (Float.max 24. (b.height *. b.shown /. b.total))

let thumb (b : t) : (float * float) option =
  if b.total <= b.shown || b.height <= 0. then None
  else
    let l = length b in
    Some (b.top -. ((b.height -. l) *. Float.max 0. (Float.min 1. (b.offset /. range b))), l)

let at (b : t) ((x, y) : float * float) : hit option =
  match thumb b with
  | Some (top, l) when x <= b.right && x >= b.right -. width && y <= b.top && y >= b.top -. b.height ->
      Some (if y > top then Before else if y < top -. l then After else Thumb (top -. y))
  | _ -> None

let dragged (b : t) ~(grab : float) (y : float) : float =
  let travel = b.height -. length b in
  if travel <= 0. then 0. else Float.max 0. (Float.min (range b) ((b.top -. (y +. grab)) /. travel *. range b))

let shapes (b : t) ~(lit : bool) : shape list =
  match thumb b with
  | Some (top, l) -> [ rectangle Gui_kit.ink (width -. 4.) (l -. 4.) |> fade (if lit then 0.5 else 0.25) |> move (b.right -. (width /. 2.)) (top -. (l /. 2.)) ]
  | None -> []
