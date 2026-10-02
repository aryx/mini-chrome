(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Css_grid.mli *)
open Css_syntax

type breadth = Length of Css_values.length | Fr of float | Min_content | Max_content | Auto
type track = { min : breadth; max : breadth }

let auto = { min = Auto; max = Auto }

let breadth (ctx : Css_values.context) (c : component) : breadth option =
  match c with
  | Token (Dimension (n, unit)) when String.lowercase_ascii unit = "fr" -> Some (Fr n)
  | Token (Ident s) -> (
      match String.lowercase_ascii s with "min-content" -> Some Min_content | "max-content" -> Some Max_content | "auto" -> Some Auto | _ -> None)
  | _ -> Option.map (fun l -> Length l) (Css_values.length ctx c)

let rec tracks (ctx : Css_values.context) (value : component list) : track list =
  List.concat_map
    (fun (c : component) ->
      match c with
      | Func (f, args) when String.lowercase_ascii f = "minmax" -> (
          match List.map (fun a -> Css_values.parts a) (split_on Comma args) with
          | [ [ a ]; [ b ] ] -> (
              match (breadth ctx a, breadth ctx b) with
              (* a share cannot be the least: auto *)
              | Some (Fr _), Some max -> [ { min = Auto; max } ]
              | Some min, Some max -> [ { min; max } ]
              | _ -> [])
          | _ -> [])
      | Func (f, args) when String.lowercase_ascii f = "repeat" -> (
          match split_on Comma args with
          | count :: rest -> (
              match Css_values.parts count with
              | [ Token (Number n) ] when n >= 1. && n <= 1000. ->
                  let once = tracks ctx (List.concat rest) in
                  List.concat (List.init (int_of_float n) (fun _ -> once))
              | _ -> [])
          | [] -> [])
      | Func (f, _) when String.lowercase_ascii f = "fit-content" -> [ auto ]
      (* a line's name, "[main-start]": not a track *)
      | Block ('[', _) -> []
      | c -> (
          match breadth ctx c with
          (* "1fr" is minmax(auto, 1fr) *)
          | Some (Fr n) -> [ { min = Auto; max = Fr n } ]
          | Some b -> [ { min = b; max = b } ]
          | None -> []))
    (Css_values.parts value)

let areas (value : component list) : string list list =
  List.filter_map
    (fun (c : component) ->
      match c with
      | Token (String s) -> Some (List.filter (fun w -> w <> "") (String.split_on_char ' ' (String.map (fun ch -> if ch = '\t' || ch = '\n' then ' ' else ch) s)))
      | _ -> None)
    value

type line = Auto | Line of int | Span of int
type placement = Auto_placed | Area of string | Lines of { row : line * line; column : line * line }

(* a line's word: a number, "span n", or auto *)
let line (cs : component list) : line =
  match Css_values.parts cs with
  | [ Token (Number n) ] when n <> 0. -> Line (int_of_float n)
  | [ Token (Ident span); Token (Number n) ] when String.lowercase_ascii span = "span" && n >= 1. -> Span (int_of_float n)
  | [ Token (Ident span) ] when String.lowercase_ascii span = "span" -> Span 1
  | _ -> Auto

let axis (value : component list) : line * line =
  match split_on (Delim '/') value with [ one ] -> (line one, Auto) | first :: last :: _ -> (line first, line last) | [] -> (Auto, Auto)

let placement (value : component list) : placement =
  match split_on (Delim '/') value with
  | [ one ] -> (
      match Css_values.parts one with
      | [ Token (Ident name) ] when (match String.lowercase_ascii name with "auto" | "span" -> false | _ -> true) -> Area name
      | _ -> ( match line one with Auto -> Auto_placed | l -> Lines { row = (l, Auto); column = (Auto, Auto) }))
  (* row-start / column-start / row-end / column-end *)
  | parts ->
      let at i = match List.nth_opt parts i with Some cs -> line cs | None -> Auto in
      Lines { row = (at 0, at 2); column = (at 1, at 3) }
