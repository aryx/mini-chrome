(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Css_animation.mli *)

open Css_syntax

type ends = (string, (string * component list) list) Hashtbl.t

(* "to", "100%", or a list with one of them: the last step *)
let is_last (prelude : component list) : bool =
  List.exists
    (fun (c : component) -> match c with Token (Ident w) -> String.lowercase_ascii w = "to" | Token (Percentage p) -> p = 100. | _ -> false)
    prelude

let ends ~(media : component list -> bool) (sheets : rule list list) : ends =
  let table = Hashtbl.create 16 in
  let rec go (rules : rule list) =
    List.iter
      (fun (r : rule) ->
        match r with
        | At_rule { name = "keyframes" | "-webkit-keyframes"; prelude; block = Some b } -> (
            let last = List.filter_map (fun (r : rule) -> match r with Style_rule { prelude; declarations } when is_last prelude -> Some declarations | _ -> None) (rules_of_block b) in
            match (trim prelude, List.rev last) with
            | [ Token (Ident name | String name) ], ds :: _ -> Hashtbl.replace table name (List.map (fun (d : declaration) -> (d.name, d.value)) ds)
            | _ -> ())
        | At_rule { name = "media"; prelude; block = Some b } -> if media prelude then go (rules_of_block b)
        | At_rule { name = "supports" | "layer"; block = Some b; _ } -> go (rules_of_block b)
        | _ -> ())
      rules
  in
  List.iter go sheets;
  table

let ended (ends : ends Lazy.t) (winning : (string * component list) list) : (string * component list) list =
  let words (name : string) : string list =
    match List.assoc_opt name winning with
    | Some value -> List.filter_map (fun (c : component) -> match c with Token (Ident w | String w) -> Some w | _ -> None) value
    | None -> []
  in
  match words "animation-name" @ words "animation" with
  | [] -> winning
  | names -> (
      let fills = words "animation-fill-mode" @ words "animation" in
      if not (List.exists (fun w -> w = "forwards" || w = "both") fills) then winning
      else
        match List.find_map (fun name -> Hashtbl.find_opt (Lazy.force ends) name) names with
        | Some last -> List.filter (fun (name, _) -> not (List.mem_assoc name last)) winning @ last
        | None -> winning)
