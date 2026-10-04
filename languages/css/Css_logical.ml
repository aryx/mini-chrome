(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Css_logical.mli *)

(* a flow-relative side, as a physical one *)
let sides = [ ("block-start", "top"); ("block-end", "bottom"); ("inline-start", "left"); ("inline-end", "right") ]

(* an axis: its two sides *)
let axes = [ ("block", ("top", "bottom")); ("inline", ("left", "right")) ]

(* a corner: the block side, then the inline one *)
let corners = [ ("start-start", "top-left"); ("start-end", "top-right"); ("end-start", "bottom-left"); ("end-end", "bottom-right") ]

let sizes =
  [ ("inline-size", "width"); ("block-size", "height"); ("min-inline-size", "min-width"); ("min-block-size", "min-height");
    ("max-inline-size", "max-width"); ("max-block-size", "max-height") ]

(* "margin-" ^ logical ^ "" : the names with a side or an axis in them,
 * by what is before and after it; "inset" alone is the side *)
let families = [ ("margin-", ""); ("padding-", ""); ("inset-", ""); ("border-", ""); ("border-", "-width"); ("border-", "-style"); ("border-", "-color"); ("scroll-margin-", ""); ("scroll-padding-", "") ]

let physical ((name, value) : string * Css_syntax.component list) : (string * Css_syntax.component list) list option =
  let named prefix side suffix = if prefix = "inset-" then side else prefix ^ side ^ suffix in
  let of_family (prefix, suffix) =
    let middle =
      if String.starts_with ~prefix name && String.ends_with ~suffix name && String.length name > String.length prefix + String.length suffix then
        Some (String.sub name (String.length prefix) (String.length name - String.length prefix - String.length suffix))
      else None
    in
    match middle with
    | None -> None
    | Some m -> (
        match (List.assoc_opt m sides, List.assoc_opt m axes) with
        | Some side, _ -> Some [ (named prefix side suffix, value) ]
        | None, Some (first, second) ->
            (* a pair: one value for both sides, or one each; a
             * border's (1px solid) is the same for both *)
            let a, b =
              match Css_values.parts value with
              | [ a; b ] when prefix <> "border-" || suffix <> "" -> ([ a ], [ b ])
              | _ -> (value, value)
            in
            Some [ (named prefix first suffix, a); (named prefix second suffix, b) ]
        | None, None -> None)
  in
  match List.assoc_opt name sizes with
  | Some physical -> Some [ (physical, value) ]
  | None ->
      if String.length name > 14 && String.starts_with ~prefix:"border-" name && String.ends_with ~suffix:"-radius" name then
        Option.map (fun corner -> [ ("border-" ^ corner ^ "-radius", value) ]) (List.assoc_opt (String.sub name 7 (String.length name - 14)) corners)
      else List.find_map of_family families
