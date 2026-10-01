(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Gui_kit.mli *)
open Playground

let frame = rgb 91 132 196
let surface = rgb 234 240 250
let edge = rgb 160 176 204
let white = rgb 255 255 255
let ink = rgb 32 33 36
let muted = rgb 120 124 130
let disabled = rgb 180 186 196
let accent = rgb 66 133 244
let lit = rgb 232 240 254

let near (x0 : float) (y0 : float) (w : float) (h : float) ((mx, my) : float * float) : bool =
  mx >= x0 && mx <= x0 +. w && Float.abs (my -. y0) <= h /. 2.
