(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Browser_zoom.mli *)

type t = (string * float) list

let empty : t = []
let levels = [ 0.25; 0.33; 0.5; 0.67; 0.75; 0.8; 0.9; 1.; 1.1; 1.25; 1.5; 1.75; 2.; 2.5; 3.; 4.; 5. ]

let step (up : bool) (z : float) : float =
  let beyond = List.filter (fun l -> if up then l > z +. 0.001 else l < z -. 0.001) levels in
  match if up then beyond else List.rev beyond with l :: _ -> l | [] -> z

let of_host (zooms : t) (host : string) : float = Option.value (List.assoc_opt host zooms) ~default:1.

let with_host (zooms : t) (host : string) (z : float) : t =
  (if z = 1. then [] else [ (host, z) ]) @ List.remove_assoc host zooms

type change = Up | Down | Reset

let key (name : string) : change option =
  match String.lowercase_ascii name with
  | "=" | "+" | "keypad +" -> Some Up
  | "-" | "keypad -" -> Some Down
  | "0" | "keypad 0" -> Some Reset
  | _ -> None

let apply (change : change) (z : float) : float = match change with Up -> step true z | Down -> step false z | Reset -> 1.

let label (z : float) : string = if z = 1. then "" else Printf.sprintf "%.0f%%" (100. *. z)
