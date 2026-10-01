(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Gui_text.mli *)
open Playground

let cell = 6.
let width (s : string) : float = cell *. float_of_int (List.length (Text.chars s))

let tail (n : int) (s : string) : string =
  let cs = Text.chars s in
  let k = List.length cs in
  if k <= n then s else String.concat "" (List.filteri (fun i _ -> i >= k - n) cs)

let monospace ?(max = 160) (x : number) (y : number) (color : color) (s : string) : shape list =
  Text.chars s
  |> List.mapi (fun i c -> (i, c))
  |> List.filter (fun (i, c) -> c <> " " && i < max)
  |> List.map (fun (i, c) -> words color c |> move (x +. (cell *. float_of_int i) +. (cell /. 2.)) y)

let bubble ~(left : float) ~(y : float) (s : string) : shape list =
  let s = tail 100 s in
  let w = width s +. 12. in
  [ rectangle Gui_kit.edge (w +. 2.) 20. |> move (left +. ((w +. 2.) /. 2.)) y; rectangle Gui_kit.surface w 18. |> move (left +. (w /. 2.)) y ]
  @ monospace (left +. 6.) y Gui_kit.ink s
