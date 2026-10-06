(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Looks.mli *)

type color = int * int * int
type align = Left | Center | Right

type t = {
  size : float;
  bold : bool;
  italic : bool;
  underline : bool;
  strike : bool;
  monospace : bool;
  color : color;
  link : string option;
  pre : bool;
  align : align;
  link_color : color;
  visited_color : color;
  base : float;
  extensions : bool;
}

let root ?(extensions = false) ~(size : float) () : t =
  {
    size;
    bold = false;
    italic = false;
    underline = false;
    strike = false;
    monospace = false;
    color = (0, 0, 0);
    link = None;
    pre = false;
    align = Left;
    link_color = (0, 0, 238);
    visited_color = (85, 26, 139);
    base = size;
    extensions;
  }

let leading = 1.2

let colors =
  [
    ("black", (0, 0, 0)); ("silver", (192, 192, 192)); ("gray", (128, 128, 128)); ("white", (255, 255, 255));
    ("maroon", (128, 0, 0)); ("red", (255, 0, 0)); ("purple", (128, 0, 128)); ("fuchsia", (255, 0, 255));
    ("green", (0, 128, 0)); ("lime", (0, 255, 0)); ("olive", (128, 128, 0)); ("yellow", (255, 255, 0));
    ("navy", (0, 0, 128)); ("blue", (0, 0, 255)); ("teal", (0, 128, 128)); ("aqua", (0, 255, 255));
  ]

let color_of_string (s : string) : color option =
  let s = String.lowercase_ascii (String.trim s) in
  (* the # was often left out, and browsers took the digits anyway;
   * CSS's #rgb is #rrggbb, each digit twice *)
  let hex =
    match String.length s with
    | 7 when s.[0] = '#' -> Some (String.sub s 1 6)
    | 6 -> Some s
    | 4 when s.[0] = '#' -> Some (String.concat "" (List.map (fun i -> String.make 2 s.[i]) [ 1; 2; 3 ]))
    | _ -> None
  in
  (* CSS's rgb(r, g, b) *)
  let rgb =
    if String.length s > 5 && String.sub s 0 4 = "rgb(" && s.[String.length s - 1] = ')' then
      match List.map (fun x -> int_of_string_opt (String.trim x)) (String.split_on_char ',' (String.sub s 4 (String.length s - 5))) with
      | [ Some r; Some g; Some b ] -> Some (min 255 r, min 255 g, min 255 b)
      | _ -> None
    else None
  in
  match (List.assoc_opt s colors, hex, rgb) with
  | Some c, _, _ -> Some c
  | None, Some h, _ -> (
      match int_of_string_opt ("0x" ^ h) with
      | Some n -> Some ((n lsr 16) land 255, (n lsr 8) land 255, n land 255)
      | None -> None)
  | None, None, rgb -> rgb

let font_scale (s : string) : float option =
  let scale = [| 0.625; 0.8125; 1.; 1.125; 1.5; 2.; 3. |] in
  let s = String.trim s in
  let n =
    if s <> "" && (s.[0] = '+' || s.[0] = '-') then
      Option.map (fun d -> 3 + d) (int_of_string_opt (if s.[0] = '+' then String.sub s 1 (String.length s - 1) else s))
    else int_of_string_opt s
  in
  Option.map (fun n -> scale.(max 1 (min 7 n) - 1)) n
