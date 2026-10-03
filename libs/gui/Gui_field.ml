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

type t = { text : string; caret : int; anchor : int }

let chars (f : t) : string list = Text.chars f.text
let length (f : t) : int = List.length (chars f)

(* all of it selected: what a click on a field at rest gives *)
let focused (text : string) : t = let f = { text; caret = 0; anchor = 0 } in { f with caret = length f }

let select_all (f : t) : t = { f with anchor = 0; caret = length f }
let selection (f : t) : int * int = (min f.anchor f.caret, max f.anchor f.caret)
let sub (f : t) (from : int) (until : int) : string = String.concat "" (List.filteri (fun i _ -> i >= from && i < until) (chars f))

let selected (f : t) : string = let a, b = selection f in sub f a b

(* the characters from a to b replaced by s, the caret after it *)
let replace (f : t) (a : int) (b : int) (s : string) : t =
  let at = a + List.length (Text.chars s) in
  { text = sub f 0 a ^ s ^ sub f b (length f); caret = at; anchor = at }

let typed (s : string) (f : t) : t = let a, b = selection f in replace f a b s

(* the selection gone; with none, the character before the caret, or after it *)
let backspace (f : t) : t = let a, b = selection f in if a < b then replace f a b "" else replace f (max 0 (a - 1)) a ""
let delete (f : t) : t = let a, b = selection f in if a < b then replace f a b "" else replace f a (min (length f) (a + 1)) ""

type move = Left | Right | Home | End

(* the caret moved; the selection goes with it if [select] (Shift
 * held), else ends -- and Left and Right first go to its nearer end *)
let moved ?(select : bool = false) (how : move) (f : t) : t =
  let a, b = selection f in
  let caret =
    match how with
    | Home -> 0
    | End -> length f
    | Left -> if a < b && not select then a else max 0 (f.caret - 1)
    | Right -> if a < b && not select then b else min (length f) (f.caret + 1)
  in
  { f with caret; anchor = (if select then f.anchor else caret) }

(* the caret put at a character (a click), the selection kept from where it was if [select] (a drag) *)
let caret_at ?(select : bool = false) (i : int) (f : t) : t =
  let caret = max 0 (min (length f) i) in
  { f with caret; anchor = (if select then f.anchor else caret) }

(* the part shown in room for [room] characters: from its first
 * character, the text's end in view and the caret too *)
let first_shown (f : t) ~(room : int) : int = min f.caret (max 0 (length f + 1 - room))

let shown (f : t) ~(room : int) : string = let from = first_shown f ~room in sub f from (from + room)

let box ~(x : float) ~(y : float) ~(w : float) : shape list =
  [ rectangle Gui_kit.edge (w +. 2.) 30. |> move (x +. (w /. 2.)) y; rectangle Gui_kit.white w 28. |> move (x +. (w /. 2.)) y ]

(* the selection's band and the caret's bar, for text set from [x] in
 * characters [cell] wide: drawn under the text *)
let marks (f : t) ~(room : int) ~(x : float) ~(y : float) ~(cell : float) : shape list =
  let from = first_shown f ~room in
  let place i = x +. (cell *. float_of_int (max 0 (min room (i - from)))) in
  let a, b = selection f in
  (if a < b then [ rectangle (rgb 180 213 254) (place b -. place a) 20. |> move ((place a +. place b) /. 2.) y ] else [])
  @ [ rectangle Gui_kit.ink 1. 18. |> move (place f.caret) y ]

(* the character under a point at [px], for [caret_at] *)
let index_at (f : t) ~(room : int) ~(x : float) ~(cell : float) (px : float) : int =
  first_shown f ~room + int_of_float (Float.round ((px -. x) /. cell))
