(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Gui_field.mli *)
open Playground

type t = { text : string; fresh : bool }

let focused (text : string) : t = { text; fresh = true }
let typed (s : string) (f : t) : t = { text = (if f.fresh then s else f.text ^ s); fresh = false }

let backspace (f : t) : t =
  let cs = Text.chars f.text in
  { text = (if f.fresh then "" else String.concat "" (List.filteri (fun i _ -> i < List.length cs - 1) cs)); fresh = false }

let shown (f : t) : string = f.text ^ "_"

let box ~(x : float) ~(y : float) ~(w : float) : shape list =
  [ rectangle Gui_kit.edge (w +. 2.) 30. |> move (x +. (w /. 2.)) y; rectangle Gui_kit.white w 28. |> move (x +. (w /. 2.)) y ]
