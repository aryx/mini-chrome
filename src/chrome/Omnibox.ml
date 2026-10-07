(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Omnibox.mli *)
open Playground

type t = { x : float; y : float; w : float; room : int; address : string; field : Gui_field.t option }

let text_x (t : t) : float = t.x +. 10.
let at (t : t) (point : float * float) : bool = Gui_kit.near t.x t.y t.w 28. point

(* the character of a field's text a point is before *)
let index (t : t) (f : Gui_field.t) (px : float) : int = Gui_field.index_at f ~room:t.room ~x:(text_x t) ~cell:Gui_text.cell px

(* a click in it: the first takes the field, the address all selected
 * (to type another over it); then a click puts the caret, and a
 * double click selects all again *)
let clicked (t : t) ~(double : bool) (px : float) : Gui_field.t =
  match t.field with
  | None -> Gui_field.focused t.address
  | Some f -> if double then Gui_field.select_all f else Gui_field.caret_at (index t f px) f

(* the pointer moved with the button held since a click in it: the selection follows *)
let dragged (t : t) (px : float) : Gui_field.t option = Option.map (fun f -> Gui_field.caret_at ~select:true (index t f px) f) t.field

type outcome = Edit of Gui_field.t | Go of string | Leave | Nothing

let key ~(ctrl : bool) ~(shift : bool) (key : string) (f : Gui_field.t) : outcome =
  match String.lowercase_ascii key with
  | "enter" | "return" -> Go f.text
  | "escape" -> Leave
  | "backspace" -> Edit (Gui_field.backspace f)
  | "delete" -> Edit (Gui_field.delete f)
  (* the caret moved, the selection with it while Shift is held *)
  | "left" | "arrowleft" -> Edit (Gui_field.moved ~select:shift Left f)
  | "right" | "arrowright" -> Edit (Gui_field.moved ~select:shift Right f)
  | "home" -> Edit (Gui_field.moved ~select:shift Home f)
  | "end" -> Edit (Gui_field.moved ~select:shift End f)
  (* Ctrl with A, C, X, V: all selected; the selection copied, cut; the clipboard's text put in its place *)
  | "a" when ctrl -> Edit (Gui_field.select_all f)
  | ("c" | "x") as k when ctrl ->
      let selected = Gui_field.selected f in
      if selected <> "" then Gui_clipboard.set selected;
      if k = "x" && selected <> "" then Edit (Gui_field.backspace f) else Nothing
  | "v" when ctrl ->
      (* a line: what is pasted is cut at its first line's end *)
      Edit (Gui_field.typed (match String.split_on_char '\n' (Gui_clipboard.get ()) with first :: _ -> String.trim first | [] -> "") f)
  | _ -> Nothing

(* with Ctrl held a letter is a command ([key]), not text *)
let typed ~(ctrl : bool) (s : string) (f : Gui_field.t) : Gui_field.t = if ctrl then f else Gui_field.typed s f

(* what was typed: the text less a selection that goes to its end (a
 * completion's, or the whole address of a click: nothing typed yet) *)
let typed_part (f : Gui_field.t) : string =
  let selected = Gui_field.selected f in
  if selected <> "" && snd (Gui_field.selection f) = Gui_field.length f then String.sub f.text 0 (String.length f.text - String.length selected) else f.text

let completed (places : Places.t) ~(now : float) (f : Gui_field.t) : Gui_field.t =
  let typed = f.text in
  match Places.completion places ~now typed with
  | Some whole when Gui_field.selected f = "" && f.caret = Gui_field.length f && String.length whole > String.length typed ->
      let text = typed ^ String.sub whole (String.length typed) (String.length whole - String.length typed) in
      { text; caret = Gui_field.length (Gui_field.focused text); anchor = f.caret }
  | _ -> f

let suggestions (places : Places.t) ~(now : float) (f : Gui_field.t) : Places.entry list = Places.matching places ~now (typed_part f)

let label (e : Places.entry) : string =
  let cut n s = if String.length s > n then String.sub s 0 (n - 3) ^ "..." else s in
  let title = String.map (fun c -> if Char.code c < 128 then c else '?') (String.trim e.title) in
  (if title = "" then "" else cut 44 title ^ "  -  ") ^ cut 60 (Places.bare e.url)

(* where words are searched: an engine whose page works without
 * scripts and answers a program -- Wikipedia's (the default: Google's
 * needs JavaScript, and DuckDuckGo's page without scripts, like
 * Mojeek's, soon takes a program asking again and again for a robot
 * and asks it to pick ducks), or DuckDuckGo's (search=duckduckgo) *)
let search_url (engine : string) (words : string) : string =
  match engine with
  | "duckduckgo" -> "https://html.duckduckgo.com/html/?" ^ Urlencoded.encode [ ("q", words) ]
  | _ -> "https://en.wikipedia.org/w/index.php?" ^ Urlencoded.encode [ ("search", words) ]

(* what is typed: an address (a scheme, or a host with a dot), else words searched *)
let destination (engine : string) (s : string) : string =
  let s = String.trim s in
  if String.contains s ':' && not (String.contains s ' ') then s
  else if String.contains s '.' && not (String.contains s ' ') then "https://" ^ s
  else search_url engine s

let shapes (t : t) : shape list =
  let text = Gui_text.monospace (text_x t) t.y in
  Gui_field.box ~x:t.x ~y:t.y ~w:t.w
  @
  match t.field with
  (* typed into: its selection and its caret, under its text *)
  | Some f -> Gui_field.marks f ~room:t.room ~x:(text_x t) ~y:t.y ~cell:Gui_text.cell @ text Gui_kit.ink (Gui_field.shown f ~room:t.room)
  | None ->
      (* the address as Chrome shows it: the scheme and host dark, the rest grey; its end, if it is too long *)
      let host_end = match String.index_from_opt t.address (min (String.length t.address) (try String.index t.address ':' + 3 with Not_found -> 0)) '/' with Some i -> i | None -> String.length t.address in
      let shown = Gui_text.tail t.room t.address in
      text Gui_kit.muted shown @ text Gui_kit.ink (String.sub shown 0 (min (String.length shown) host_end))
