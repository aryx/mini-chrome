(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Computed.mli *)
open Css_syntax
module V = Css_values

module Custom = Map.Make (String)

type display =
  | Inline
  | Block
  | Inline_block
  | List_item
  | Flex
  | Inline_flex
  | Grid
  | Table
  | Table_row_group
  | Table_row
  | Table_cell
  | Table_caption
  | Display_none
  | Contents

type position = Static | Relative | Absolute | Fixed | Sticky
type size = Auto | Len of Css_values.length
type family = Serif | Sans_serif | Monospace
type white_space = Normal | Pre | Nowrap | Pre_wrap | Pre_line
type text_align = Align_left | Align_right | Align_center | Align_justify
type vertical_align = Baseline | Middle | Top | Bottom | Text_top | Text_bottom | Sub | Super
type line_height = Line_normal | Factor of float | Line_px of float
type side = Side_none | Side_left | Side_right | Side_both
type flex_direction = Row | Row_reverse | Column | Column_reverse
type align = Start | End | Center | Stretch | Space_between | Space_around | Space_evenly | Align_baseline

type t = {
  display : display;
  position : position;
  z_index : int option; (* z-index: its place in the drawing's order among the positioned boxes; None for auto *)
  float : side;
  clear : side;
  (* transform: its translation (translate, translateX, translateY,
   * translate3d), the percents of the box's own size; the rest of a
   * transform (a rotation, a scale) is not applied *)
  translate : (Css_values.length * Css_values.length) option;
  (* transform: scale(k), scale(kx, ky), scaleX, scaleY -- how many
   * times its own size the box is drawn, around transform-origin (a
   * point of the box: its middle, unless said) *)
  scale : float * float;
  origin : Css_values.length * Css_values.length;
  top : size;
  right : size;
  bottom : size;
  left : size;
  width : size;
  height : size;
  min_width : Css_values.length;
  min_height : Css_values.length;
  max_width : size;
  max_height : size;
  margin : size * size * size * size;
  padding : Css_values.length * Css_values.length * Css_values.length * Css_values.length;
  border_width : float * float * float * float;
  border_color : Css_values.color * Css_values.color * Css_values.color * Css_values.color;
  border_box : bool;
  table_fixed : bool;
  border_spacing : float option;
  color : Css_values.color;
  background : Css_values.color;
  background_image : string option;
  mask_image : string option;
  font_size : float;
  bold : bool;
  italic : bool;
  family : family;
  line_height : line_height;
  text_align : text_align;
  underline : bool;
  line_through : bool;
  uppercase : bool;
  white_space : white_space;
  vertical_align : vertical_align;
  list_style : string;
  visible : bool;
  overflow_hidden : bool;
  flex_direction : flex_direction;
  flex_wrap : bool;
  justify_content : align;
  align_items : align;
  align_self : align option;
  flex_grow : float;
  flex_shrink : float;
  flex_basis : size;
  row_gap : Css_values.length;
  column_gap : Css_values.length;
  grid_columns : Css_grid.track list;
  grid_rows : Css_grid.track list;
  grid_areas : string list list;
  grid_area : Css_grid.placement;
  align_content : align option;
  custom : Css_syntax.component list Custom.t;
}

let zero = V.zero
let black = V.black

let initial : t =
  {
    display = Inline;
    position = Static;
    z_index = None;
    float = Side_none;
    clear = Side_none;
    translate = None;
    scale = (1., 1.);
    origin = ({ px = 0.; pct = 50. }, { px = 0.; pct = 50. });
    top = Auto;
    right = Auto;
    bottom = Auto;
    left = Auto;
    width = Auto;
    height = Auto;
    min_width = zero;
    min_height = zero;
    max_width = Auto;
    max_height = Auto;
    margin = (Len zero, Len zero, Len zero, Len zero);
    padding = (zero, zero, zero, zero);
    border_width = (0., 0., 0., 0.);
    border_color = (black, black, black, black);
    border_box = false;
    table_fixed = false;
    border_spacing = None;
    color = black;
    background = V.transparent;
    background_image = None;
    mask_image = None;
    font_size = 16.;
    bold = false;
    italic = false;
    family = Serif;
    line_height = Line_normal;
    text_align = Align_left;
    underline = false;
    line_through = false;
    uppercase = false;
    white_space = Normal;
    vertical_align = Baseline;
    list_style = "disc";
    visible = true;
    overflow_hidden = false;
    flex_direction = Row;
    flex_wrap = false;
    justify_content = Start;
    align_items = Stretch;
    align_self = None;
    flex_grow = 0.;
    flex_shrink = 1.;
    flex_basis = Auto;
    row_gap = zero;
    column_gap = zero;
    grid_columns = [];
    grid_rows = [];
    grid_areas = [];
    grid_area = Auto_placed;
    align_content = None;
    custom = Custom.empty;
  }

(*****************************************************************************)
(* Shorthands *)
(*****************************************************************************)

let ident (c : component) : string option = match c with Token (Ident s) -> Some (String.lowercase_ascii s) | _ -> None
let sides = [ "top"; "right"; "bottom"; "left" ]

(* one to four values: top, right, bottom, left *)
let four (vs : component list) : component list list option =
  match V.parts vs with
  | [ a ] -> Some [ [ a ]; [ a ]; [ a ]; [ a ] ]
  | [ a; b ] -> Some [ [ a ]; [ b ]; [ a ]; [ b ] ]
  | [ a; b; c ] -> Some [ [ a ]; [ b ]; [ c ]; [ b ] ]
  | [ a; b; c; d ] -> Some [ [ a ]; [ b ]; [ c ]; [ d ] ]
  | _ -> None

let border_styles = [ "none"; "hidden"; "dotted"; "dashed"; "solid"; "double"; "groove"; "ridge"; "inset"; "outset" ]

let is_width (c : component) =
  match c with
  | Token (Dimension _) | Token (Number 0.) -> true
  (* calc(...) and its kin: a length; rgb(...), hsl(...): a colour *)
  | Func (f, _) -> List.mem (String.lowercase_ascii f) [ "calc"; "min"; "max"; "clamp"; "var"; "env" ]
  | Token (Ident s) -> List.mem (String.lowercase_ascii s) [ "thin"; "medium"; "thick" ]
  | _ -> false

(* "1px solid #ccc", in any order *)
let border_parts (vs : component list) : (string * component list) list =
  List.fold_left
    (fun acc c ->
      match ident c with
      | Some s when List.mem s border_styles -> ("style", [ c ]) :: acc
      | _ when is_width c -> ("width", [ c ]) :: acc
      | _ -> ("color", [ c ]) :: acc)
    [] (V.parts vs)

(* a url(x) or url("x"): x *)
let url_of (c : component) : string option =
  match c with
  | Token (Url u) -> Some u
  | Func (f, args) when String.lowercase_ascii f = "url" -> ( match Css_syntax.trim args with [ Token (String u) ] -> Some u | _ -> None)
  | _ -> None

let rec expand ((name, value) : string * component list) : (string * component list) list =
  match Css_logical.physical (name, value) with
  (* a side named by the text's direction: the physical one, which may
   * be a shorthand too (border-inline-start: 1px solid) *)
  | Some physical -> List.concat_map expand physical
  | None -> expand_physical (name, value)

and expand_physical ((name, value) : string * component list) : (string * component list) list =
  let per_side prefix suffix =
    match four value with
    | Some vs -> List.map2 (fun s v -> (prefix ^ s ^ suffix, v)) sides vs
    | None -> []
  in
  match name with
  | "margin" -> per_side "margin-" ""
  | "padding" -> per_side "padding-" ""
  | "inset" -> per_side "" ""
  | "border-width" -> per_side "border-" "-width"
  | "border-style" -> per_side "border-" "-style"
  | "border-color" -> per_side "border-" "-color"
  | "border" ->
      (* a border's style, if not said, is none: "border: 1px red" draws
       * nothing; its width, medium *)
      let ps = border_parts value in
      let with_defaults = ps @ (if List.mem_assoc "style" ps then [] else [ ("style", [ Token (Ident "none") ]) ]) in
      List.concat_map (fun s -> List.map (fun (k, v) -> ("border-" ^ s ^ "-" ^ k, v)) with_defaults) sides
  | "border-top" | "border-right" | "border-bottom" | "border-left" ->
      let ps = border_parts value in
      let ps = ps @ if List.mem_assoc "style" ps then [] else [ ("style", [ Token (Ident "none") ]) ] in
      List.map (fun (k, v) -> (name ^ "-" ^ k, v)) ps
  | "background" ->
      (* its colour, where it has one (an image alone makes it
       * transparent), and its picture, its first url() *)
      (match List.find_opt (fun c -> V.color ~current:black [ c ] <> None) (V.parts value) with
      | Some c -> [ ("background-color", [ c ]) ]
      | None -> [ ("background-color", [ Token (Ident "transparent") ]) ])
      @ [ ("background-image", match List.find_opt (fun c -> url_of c <> None) (V.parts value) with Some c -> [ c ] | None -> [ Token (Ident "none") ]) ]
  | "font" -> (
      (* [style] [variant] [weight] size[/line-height] family *)
      let rec go acc = function
        | [] -> acc
        | c :: rest -> (
            match ident c with
            | Some ("italic" | "oblique") -> go (("font-style", [ c ]) :: acc) rest
            | Some ("bold" | "bolder" | "lighter") -> go (("font-weight", [ c ]) :: acc) rest
            | Some ("normal" | "small-caps") -> go acc rest
            | _ -> (
                match c with
                | Token (Number n) when n >= 100. -> go (("font-weight", [ c ]) :: acc) rest
                | _ -> (
                    let acc = ("font-size", [ c ]) :: acc in
                    match rest with
                    | Token (Delim '/') :: lh :: family -> ("line-height", [ lh ]) :: ("font-family", family) :: acc
                    | family -> ("font-family", family) :: acc)))
      in
      go [] (V.parts value))
  | "flex" -> (
      let num c = match c with Token (Number n) -> Some n | _ -> None in
      let n f = [ Token (Number f) ] in
      match V.parts value with
      | [ c ] when ident c = Some "none" -> [ ("flex-grow", n 0.); ("flex-shrink", n 0.); ("flex-basis", [ Token (Ident "auto") ]) ]
      | [ c ] when ident c = Some "auto" -> [ ("flex-grow", n 1.); ("flex-shrink", n 1.); ("flex-basis", [ Token (Ident "auto") ]) ]
      | [ c ] when num c <> None -> [ ("flex-grow", [ c ]); ("flex-shrink", n 1.); ("flex-basis", [ Token (Percentage 0.) ]) ]
      | [ c ] -> [ ("flex-grow", n 1.); ("flex-shrink", n 1.); ("flex-basis", [ c ]) ]
      | [ g; s ] when num s <> None -> [ ("flex-grow", [ g ]); ("flex-shrink", [ s ]); ("flex-basis", [ Token (Percentage 0.) ]) ]
      | [ g; b ] -> [ ("flex-grow", [ g ]); ("flex-shrink", n 1.); ("flex-basis", [ b ]) ]
      | [ g; s; b ] -> [ ("flex-grow", [ g ]); ("flex-shrink", [ s ]); ("flex-basis", [ b ]) ]
      | _ -> [])
  | "gap" | "grid-gap" -> (
      match V.parts value with [ a ] -> [ ("row-gap", [ a ]); ("column-gap", [ a ]) ] | [ a; b ] -> [ ("row-gap", [ a ]); ("column-gap", [ b ]) ] | _ -> [])
  | "list-style" -> (
      match List.find_opt (fun c -> match ident c with Some s -> s <> "inside" && s <> "outside" | None -> false) (V.parts value) with
      | Some c -> [ ("list-style-type", [ c ]) ]
      | None -> [])
  | "overflow" | "overflow-x" | "overflow-y" -> [ ("overflow", value) ]
  | "text-decoration-line" -> [ ("text-decoration", value) ]
  (* grid-template: "rows / columns"; with strings, the areas
   * (a row a string, its size after it), then "/ columns" *)
  | "grid-template" -> (
      let strings = List.filter (fun c -> match c with Token (String _) -> true | _ -> false) value in
      match split_on (Delim '/') value with
      | [ rows; columns ] when strings = [] -> [ ("grid-template-rows", rows); ("grid-template-columns", columns) ]
      | rows :: rest ->
          let sizes = List.filter (fun c -> match c with Token (String _) -> false | _ -> true) rows in
          (if strings = [] then [] else [ ("grid-template-areas", strings); ("grid-template-rows", sizes) ])
          @ (match rest with [ columns ] -> [ ("grid-template-columns", columns) ] | _ -> [])
      | [] -> [])
  (* place-content: align-content, then justify-content (the same if one) *)
  | "place-content" -> (
      match V.parts value with
      | [ a ] -> [ ("align-content", [ a ]); ("justify-content", [ a ]) ]
      | [ a; j ] -> [ ("align-content", [ a ]); ("justify-content", [ j ]) ]
      | _ -> [])
  | "place-items" -> ( match V.parts value with a :: _ -> [ ("align-items", [ a ]) ] | [] -> [])
  | "flex-flow" ->
      List.map (fun c -> match ident c with Some ("wrap" | "nowrap" | "wrap-reverse") -> ("flex-wrap", [ c ]) | _ -> ("flex-direction", [ c ])) (V.parts value)
  | _ -> [ (name, value) ]

(*****************************************************************************)
(* The properties *)
(*****************************************************************************)

let inherited =
  [ "color"; "font-size"; "font-weight"; "font-style"; "font-family"; "line-height"; "text-align"; "text-transform";
    "white-space"; "visibility"; "list-style-type"; "text-decoration" ]

let is_inherited (name : string) : bool = List.exists (String.equal name) inherited

let display_of (s : string) : display option =
  match s with
  | "inline" -> Some Inline
  | "block" | "flow-root" | "block flow" -> Some Block
  | "inline-block" | "inline-grid" | "inline-table" -> Some Inline_block
  | "list-item" -> Some List_item
  | "flex" -> Some Flex
  | "inline-flex" -> Some Inline_flex
  | "grid" -> Some Grid
  | "table" -> Some Table
  | "table-row-group" | "table-header-group" | "table-footer-group" -> Some Table_row_group
  | "table-row" -> Some Table_row
  | "table-cell" -> Some Table_cell
  | "table-caption" -> Some Table_caption
  | "none" | "table-column" | "table-column-group" -> Some Display_none
  | "contents" -> Some Contents
  | _ -> None

let align_of (s : string) : align option =
  match s with
  | "flex-start" | "start" | "left" | "self-start" | "normal" -> Some Start
  | "flex-end" | "end" | "right" | "self-end" -> Some End
  | "center" -> Some Center
  | "stretch" -> Some Stretch
  | "space-between" -> Some Space_between
  | "space-around" -> Some Space_around
  | "space-evenly" -> Some Space_evenly
  | "baseline" | "first baseline" -> Some Align_baseline
  | _ -> None

let width_keyword (s : string) : float option = match s with "thin" -> Some 1. | "medium" -> Some 3. | "thick" -> Some 5. | _ -> None

let compute (m : Cascade.media) ~(root_font_size : float) ~(parent : t) (declared : (string * component list) list) : t =
  (* the custom properties first: inherited, overridden by this element's *)
  let custom =
    List.fold_left
      (fun acc (n, v) -> if String.length n > 2 && String.sub n 0 2 = "--" then Custom.add n v acc else acc)
      parent.custom declared
  in
  let lookup n = Custom.find_opt n custom in
  let decls =
    declared
    |> List.filter (fun (n, _) -> not (String.length n > 2 && String.sub n 0 2 = "--"))
    |> List.filter_map (fun (n, v) -> Option.map (fun v -> (n, v)) (V.substitute lookup v))
    |> List.concat_map expand
  in
  (* a property's value: this element's, else (if inherited) its
   * parent's -- None, the caller's initial value *)
  (* before: the declarations turned round and gone through for each
   * of a hundred properties, with the comparison of any two values
   *   match List.assoc_opt name (List.rev decls) with
   * opti: a table of them, the last said winning. A style pass on
   * GitHub's page, in instructions: 1.7 G -> 1.3 *)
  let said : (string, component list) Hashtbl.t = Hashtbl.create 32 in
  if !Mini_opti.enabled then List.iter (fun (n, v) -> Hashtbl.replace said n v) decls;
  let get (name : string) : component list option =
    match if !Mini_opti.enabled then Hashtbl.find_opt said name else List.assoc_opt name (List.rev decls) with
    | Some v -> (
        match V.parts v with
        | [ Token (Ident k) ] when String.lowercase_ascii k = "inherit" -> Some [ Token (Ident "inherit") ]
        | [ Token (Ident k) ] when String.lowercase_ascii k = "initial" -> None
        | [ Token (Ident k) ] when List.mem (String.lowercase_ascii k) [ "unset"; "revert"; "revert-layer" ] ->
            if is_inherited name then Some [ Token (Ident "inherit") ] else None
        | _ -> Some v)
    | None -> if is_inherited name then Some [ Token (Ident "inherit") ] else None
  in
  let is_inherit v = match v with Some [ Token (Ident "inherit") ] -> true | _ -> false in
  let word name = match get name with Some v -> ( match V.parts v with [ c ] -> ident c | cs -> Some (String.lowercase_ascii (to_string cs))) | None -> None in
  (* font-size first: an em here is the parent's *)
  let font_size =
    let pctx : V.context = { em = parent.font_size; rem = root_font_size; viewport_width = m.width; viewport_height = m.height } in
    match get "font-size" with
    | v when is_inherit v -> parent.font_size
    | Some v -> (
        match V.parts v with
        | [ Token (Percentage p) ] -> parent.font_size *. p /. 100.
        | [ Token (Ident k) ] -> (
            match String.lowercase_ascii k with
            | "xx-small" -> 9.
            | "x-small" -> 10.
            | "small" -> 13.
            | "medium" -> 16.
            | "large" -> 18.
            | "x-large" -> 24.
            | "xx-large" -> 32.
            | "xxx-large" -> 48.
            | "larger" -> parent.font_size *. 1.2
            | "smaller" -> parent.font_size /. 1.2
            | _ -> parent.font_size)
        | [ c ] -> ( match V.length pctx c with Some l -> Float.max 0. (V.resolve l parent.font_size) | None -> parent.font_size)
        | _ -> parent.font_size)
    | None -> 16.
  in
  let ctx : V.context = { em = font_size; rem = root_font_size; viewport_width = m.width; viewport_height = m.height } in
  let len_of v = match V.parts v with [ c ] -> V.length ctx c | _ -> None in
  (* a property: [f] of its value, [inh] the parent's, [init] else *)
  let prop name ~inh ~init f =
    match get name with
    | v when is_inherit v -> inh
    | Some v -> ( match f v with Some x -> x | None -> if is_inherited name then inh else init)
    | None -> init
  in
  (* [inh] the parent's value: what inherit asks, even of a property
   * not inherited by default *)
  let length name ~inh ~init = prop name ~inh ~init len_of in
  let size name ~inh ~init =
    prop name ~inh ~init (fun v -> match V.parts v with [ c ] when ident c = Some "auto" || ident c = Some "none" -> Some Auto | _ -> Option.map (fun l -> Len l) (len_of v))
  in
  let (pmt, pmr, pmb, pml), (ppt, ppr, ppb, ppl) = (parent.margin, parent.padding) in
  let color = prop "color" ~inh:parent.color ~init:black (fun v -> V.color ~current:parent.color v) in
  let colour name = prop name ~inh:color ~init:color (fun v -> V.color ~current:color v) in
  let border s =
    let style = word ("border-" ^ s ^ "-style") in
    let visible = match style with Some ("none" | "hidden") | None -> false | Some _ -> true in
    let w =
      prop ("border-" ^ s ^ "-width") ~inh:3. ~init:3. (fun v ->
          match V.parts v with
          | [ Token (Ident k) ] -> width_keyword (String.lowercase_ascii k)
          | _ -> Option.map (fun l -> V.resolve l 0.) (len_of v))
    in
    ((if visible then w else 0.), colour ("border-" ^ s ^ "-color"))
  in
  let (bt, ct), (br, cr), (bb, cb), (bl, cl) = (border "top", border "right", border "bottom", border "left") in
  let decoration = word "text-decoration" in
  let has_decoration k = match decoration with Some d -> List.mem k (String.split_on_char ' ' d) | None -> false in
  {
    display =
      (match get "display" with
      | Some v -> ( match display_of (String.lowercase_ascii (to_string (V.parts v |> List.filteri (fun i _ -> i = 0)))) with Some d -> d | None -> Inline)
      | None -> Inline);
    z_index = Option.bind (get "z-index") (fun v -> int_of_string_opt (String.trim (to_string v)));
    position =
      (match word "position" with Some "relative" -> Relative | Some "absolute" -> Absolute | Some "fixed" -> Fixed | Some "sticky" -> Sticky | _ -> Static);
    float = (match word "float" with Some "left" -> Side_left | Some "right" -> Side_right | _ -> Side_none);
    clear = (match word "clear" with Some "left" -> Side_left | Some "right" -> Side_right | Some "both" -> Side_both | _ -> Side_none);
    translate =
      prop "transform" ~inh:parent.translate ~init:None (fun v ->
          (* the functions' moves added up; the others passed *)
          let zero = Css_values.zero in
          let sum (a : Css_values.length) (b : Css_values.length) : Css_values.length = { px = a.px +. b.px; pct = a.pct +. b.pct } in
          let add (x, y) (dx, dy) = Some (sum x dx, sum y dy) in
          List.fold_left
            (fun acc c ->
              match c with
              | Css_syntax.Func (f, args) -> (
                  let lens = List.map (fun a -> match V.parts a with [ c ] -> Option.value (V.length ctx c) ~default:zero | _ -> zero) (Css_syntax.split_on Comma args) in
                  let at = Option.value acc ~default:(zero, zero) in
                  match (String.lowercase_ascii f, lens) with
                  | ("translate" | "translate3d"), x :: y :: _ -> add at (x, y)
                  | "translate", [ x ] | "translatex", [ x ] -> add at (x, zero)
                  | "translatey", [ y ] -> add at (zero, y)
                  | _ -> acc)
              | _ -> acc)
            None v
          |> Option.some);
    scale =
      (match get "transform" with
      | None -> (1., 1.)
      | Some v ->
          List.fold_left
            (fun (sx, sy) c ->
              match c with
              | Css_syntax.Func (f, args) -> (
                  (* a number, or a calc() that is one: a ratio of two
                   * lengths (scale(calc(22px / 192px)): an icon drawn at 192
                   * shown at 22), a product *)
                  let rec number (cs : Css_syntax.component list) : float option =
                    let side cs =
                      match V.parts cs with
                      | [ Css_syntax.Token (Number n) ] -> Some n
                      | [ (Css_syntax.Func ("calc", _) | Block ('(', _)) ] as inner -> number inner
                      | [ c ] -> Option.map (fun (l : Css_values.length) -> l.px) (V.length ctx c)
                      | _ -> None
                    in
                    match V.parts cs with
                    | [ Css_syntax.Token (Number n) ] -> Some n
                    | [ (Css_syntax.Func ("calc", inner) | Block ('(', inner)) ] -> (
                        match (Css_syntax.split_on (Delim '/') inner, Css_syntax.split_on (Delim '*') inner) with
                        | [ a; b ], _ -> ( match (side a, side b) with Some a, Some b when b <> 0. -> Some (a /. b) | _ -> None)
                        | _, [ a; b ] -> ( match (side a, side b) with Some a, Some b -> Some (a *. b) | _ -> None)
                        | _ -> side inner)
                    | _ -> None
                  in
                  let nums = List.filter_map number (Css_syntax.split_on Comma args) in
                  match (String.lowercase_ascii f, nums) with
                  | "scale", [ k ] -> (sx *. k, sy *. k)
                  | ("scale" | "scale3d"), kx :: ky :: _ -> (sx *. kx, sy *. ky)
                  | "scalex", [ k ] -> (sx *. k, sy)
                  | "scaley", [ k ] -> (sx, sy *. k)
                  | _ -> (sx, sy))
              | _ -> (sx, sy))
            (1., 1.) v);
    origin =
      (let half : Css_values.length = { px = 0.; pct = 50. } in
       match Option.map V.parts (get "transform-origin") with
       | None -> (half, half)
       | Some parts -> (
           let one c : Css_values.length option =
             match String.lowercase_ascii (String.trim (to_string [ c ])) with
             | "left" | "top" -> Some { px = 0.; pct = 0. }
             | "center" -> Some half
             | "right" | "bottom" -> Some { px = 0.; pct = 100. }
             | _ -> V.length ctx c
           in
           match List.filter_map one parts with x :: y :: _ -> (x, y) | [ x ] -> (x, half) | [] -> (half, half)));
    top = size "top" ~inh:parent.top ~init:Auto;
    right = size "right" ~inh:parent.right ~init:Auto;
    bottom = size "bottom" ~inh:parent.bottom ~init:Auto;
    left = size "left" ~inh:parent.left ~init:Auto;
    width = size "width" ~inh:parent.width ~init:Auto;
    height = size "height" ~inh:parent.height ~init:Auto;
    min_width = length "min-width" ~inh:parent.min_width ~init:zero;
    min_height = length "min-height" ~inh:parent.min_height ~init:zero;
    max_width = size "max-width" ~inh:parent.max_width ~init:Auto;
    max_height = size "max-height" ~inh:parent.max_height ~init:Auto;
    margin =
      ( size "margin-top" ~inh:pmt ~init:(Len zero),
        size "margin-right" ~inh:pmr ~init:(Len zero),
        size "margin-bottom" ~inh:pmb ~init:(Len zero),
        size "margin-left" ~inh:pml ~init:(Len zero) );
    padding =
      (* never negative: what a calc() makes less than nothing is
       * nothing (LWN centres its article with padding-left: calc(50% *
       * var(--centre) - 32em), which is -32em for a reader who did not
       * ask for it: the column began half a screen left of the window) *)
      (let side name inh = match length name ~inh ~init:zero with (l : Css_values.length) when l.pct = 0. && l.px < 0. -> zero | l -> l in
       (side "padding-top" ppt, side "padding-right" ppr, side "padding-bottom" ppb, side "padding-left" ppl));
    border_width = (bt, br, bb, bl);
    border_color = (ct, cr, cb, cl);
    border_box = word "box-sizing" = Some "border-box";
    table_fixed = word "table-layout" = Some "fixed";
    border_spacing = (match get "border-spacing" with Some v -> ( match V.parts v with c :: _ -> Option.map (fun l -> V.resolve l 0.) (V.length ctx c) | [] -> None) | None -> None);
    color;
    background =
      (let c = prop "background-color" ~inh:V.transparent ~init:V.transparent (fun v -> V.color ~current:color v) in
       (* opacity between 0 and 1: the box's own colour that much fainter
        * (what is in it is drawn as it is: a dialog's backdrop, black at
        * 0.6, was a black page) *)
       match Option.bind (get "opacity") (fun v -> float_of_string_opt (String.trim (to_string v))) with
       | Some o when o > 0. && o < 1. -> { c with a = c.a *. o }
       | _ -> c);
    background_image = (match get "background-image" with Some v -> List.find_map url_of (V.parts v) | None -> None);
    mask_image =
      (match get "mask-image" with
      | Some v -> List.find_map url_of (V.parts v)
      | None -> ( match get "-webkit-mask-image" with Some v -> List.find_map url_of (V.parts v) | None -> None));
    font_size;
    bold =
      prop "font-weight" ~inh:parent.bold ~init:false (fun v ->
          match V.parts v with
          | [ Token (Number n) ] -> Some (n >= 600.)
          | [ c ] -> ( match ident c with Some ("bold" | "bolder") -> Some true | Some ("normal" | "lighter") -> Some false | _ -> None)
          | _ -> None);
    italic = prop "font-style" ~inh:parent.italic ~init:false (fun v -> match V.parts v with [ c ] -> Option.map (fun s -> s = "italic" || s = "oblique") (ident c) | _ -> None);
    family =
      prop "font-family" ~inh:parent.family ~init:Serif (fun v ->
          (* the first family we can tell: our pens have three faces *)
          let names = List.map (fun f -> String.lowercase_ascii (to_string (trim f))) (split_on Comma v) in
          List.find_map
            (fun n ->
              let n = String.concat "" (String.split_on_char '"' n) in
              if List.mem n [ "monospace"; "courier"; "courier new"; "consolas"; "menlo"; "monaco"; "sfmono-regular"; "ui-monospace"; "dejavu sans mono" ] then Some Monospace
              else if List.mem n [ "serif"; "times"; "times new roman"; "georgia"; "linux libertine" ] then Some Serif
              else if List.mem n [ "sans-serif"; "arial"; "helvetica"; "verdana"; "system-ui"; "-apple-system"; "roboto"; "segoe ui"; "helvetica neue" ] then Some Sans_serif
              else None)
            names);
    line_height =
      prop "line-height" ~inh:parent.line_height ~init:Line_normal (fun v ->
          match V.parts v with
          | [ Token (Number n) ] -> Some (Factor n)
          | [ Token (Percentage p) ] -> Some (Line_px (font_size *. p /. 100.))
          | [ c ] when ident c = Some "normal" -> Some Line_normal
          | [ c ] -> Option.map (fun l -> Line_px (V.resolve l 0.)) (V.length ctx c)
          | _ -> None);
    text_align =
      prop "text-align" ~inh:parent.text_align ~init:Align_left (fun v ->
          match V.parts v with
          | [ c ] -> (
              match ident c with
              | Some ("left" | "start") -> Some Align_left
              | Some ("right" | "end") -> Some Align_right
              | Some ("center" | "-webkit-center" | "-moz-center") -> Some Align_center
              | Some "justify" -> Some Align_justify
              | _ -> None)
          | _ -> None);
    underline = (if decoration = None then parent.underline else has_decoration "underline");
    line_through = (if decoration = None then parent.line_through else has_decoration "line-through");
    uppercase = prop "text-transform" ~inh:parent.uppercase ~init:false (fun v -> match V.parts v with [ c ] -> Option.map (fun s -> s = "uppercase") (ident c) | _ -> None);
    white_space =
      prop "white-space" ~inh:parent.white_space ~init:Normal (fun v ->
          match V.parts v with
          | [ c ] -> (
              match ident c with
              | Some "pre" -> Some Pre
              | Some "nowrap" -> Some Nowrap
              | Some ("pre-wrap" | "break-spaces") -> Some Pre_wrap
              | Some "pre-line" -> Some Pre_line
              | Some "normal" -> Some Normal
              | _ -> None)
          | _ -> None);
    vertical_align =
      (match word "vertical-align" with
      | Some "middle" -> Middle
      | Some "top" -> Top
      | Some "bottom" -> Bottom
      | Some "text-top" -> Text_top
      | Some "text-bottom" -> Text_bottom
      | Some "sub" -> Sub
      | Some "super" -> Super
      | _ -> Baseline);
    list_style = prop "list-style-type" ~inh:parent.list_style ~init:"disc" (fun v -> match V.parts v with [ c ] -> ident c | _ -> None);
    visible =
      prop "visibility" ~inh:parent.visible ~init:true (fun v -> match V.parts v with [ c ] -> Option.map (fun s -> s = "visible") (ident c) | _ -> None)
      (* opacity: 0, what hides a checkbox that a label stands for: not
       * drawn either (and nor is what is in it) *)
      && (match get "opacity" with Some v -> ( match float_of_string_opt (String.trim (to_string v)) with Some o -> o > 0. | None -> true) | None -> true);
    (* auto and scroll: a box that scrolls, here clipped (no scrollbar) *)
    (* "hidden auto": x, then y; either clipping clips here *)
    overflow_hidden =
      (match get "overflow" with
      | Some v -> List.exists (fun c -> match ident c with Some ("hidden" | "clip" | "auto" | "scroll") -> true | _ -> false) (V.parts v)
      | None -> false);
    flex_direction =
      (match word "flex-direction" with Some "row-reverse" -> Row_reverse | Some "column" -> Column | Some "column-reverse" -> Column_reverse | _ -> Row);
    flex_wrap = (match word "flex-wrap" with Some ("wrap" | "wrap-reverse") -> true | _ -> false);
    justify_content = (match Option.bind (word "justify-content") align_of with Some a -> a | None -> Start);
    align_items = (match Option.bind (word "align-items") align_of with Some Start when word "align-items" = Some "normal" -> Stretch | Some a -> a | None -> Stretch);
    align_self = (match word "align-self" with Some "auto" | None -> None | Some s -> align_of s);
    flex_grow = prop "flex-grow" ~inh:0. ~init:0. (fun v -> match V.parts v with [ Token (Number n) ] -> Some n | _ -> None);
    flex_shrink = prop "flex-shrink" ~inh:1. ~init:1. (fun v -> match V.parts v with [ Token (Number n) ] -> Some n | _ -> None);
    flex_basis = size "flex-basis" ~inh:parent.flex_basis ~init:Auto;
    row_gap = length "row-gap" ~inh:parent.row_gap ~init:zero;
    column_gap = length "column-gap" ~inh:parent.column_gap ~init:zero;
    grid_columns = (match get "grid-template-columns" with Some v -> Css_grid.tracks ctx v | None -> []);
    grid_rows = (match get "grid-template-rows" with Some v -> Css_grid.tracks ctx v | None -> []);
    grid_areas = (match get "grid-template-areas" with Some v -> Css_grid.areas v | None -> []);
    grid_area =
      (match (get "grid-area", get "grid-row", get "grid-column") with
      | Some v, _, _ -> Css_grid.placement v
      | None, None, None -> Auto_placed
      | None, row, column ->
          let axis v = match v with Some v -> Css_grid.axis v | None -> (Css_grid.Auto, Css_grid.Auto) in
          Lines { row = axis row; column = axis column });
    align_content = (match word "align-content" with Some ("normal" | "stretch") | None -> None | Some s -> align_of s);
    custom;
  }

(*****************************************************************************)
(* The browser's own sheet, and every element's style *)
(*****************************************************************************)

let user_agent_sheet : Cascade.sheet = { origin = User_agent; rules = parse_stylesheet Ua_sheet.text }

(* quirks mode's rules (WHATWG HTML, "Rendering", tables in quirks
 * mode): a table does not inherit its surroundings' fonts and
 * alignment -- pages of the 1990s <center>ed a table, not its text *)
let quirks_sheet : Cascade.sheet =
  {
    origin = User_agent;
    rules =
      parse_stylesheet
        "table { font-weight: initial; font-style: initial; font-size: initial; line-height: initial; white-space: initial; text-align: initial }";
  }

(* the browser's sheets, before the page's *)
let browser_sheets ~(quirks : bool) : Cascade.sheet list = if quirks then [ user_agent_sheet; quirks_sheet ] else [ user_agent_sheet ]

(* opti: a style kept from one styling to the next, by the element's
 * key (Cascade's: its ancestry, its place, itself), if it is of the
 * very declarations and the very parent's style it was computed from
 * (==: the cascade's memo gives the same lists back, and a parent
 * found here is the same record). The styles of a tree that changed
 * little are then mostly found. One media's at a time. The numbers
 * are Cascade's (its memo and this one together: YouTube's video
 * page, 74 s of styles to 17) *)
let kept : (Cascade.media * (Cascade.key, (string * component list) list * t * float * t) Hashtbl.t) ref = ref ({ Cascade.width = 0.; height = 0. }, Hashtbl.create 1)

let styles_all ?visited ?(quirks = false) (m : Cascade.media) (sheets : Cascade.sheet list) (root : Dom.element) : (Dom.element -> t) * (Dom.element -> Dom.node list) =
  let ua = browser_sheets ~quirks in
  let declared, kids, key_of = Cascade.cascade_keyed ?visited m (ua @ sheets) root in
  let table : (int, Dom.element * t) Hashtbl.t = Hashtbl.create 1024 in
  if fst !kept <> m || Hashtbl.length (snd !kept) > 200_000 then kept := (m, Hashtbl.create 4096);
  let memo = snd !kept in
  let compute ~root_font_size ~parent (e : Dom.element) : t =
    let ds = declared e in
    (* a ::before or an ::after has no key: computed each time *)
    match if !Mini_opti.enabled then key_of e else None with
    | None -> compute m ~root_font_size ~parent ds
    | Some key -> (
        match Hashtbl.find_opt memo key with
        | Some (ds', parent', size', style) when ds' == ds && parent' == parent && size' = root_font_size -> style
        | _ ->
            let style = compute m ~root_font_size ~parent ds in
            Hashtbl.replace memo key (ds, parent, root_font_size, style);
            style)
  in
  let root_style = compute ~root_font_size:16. ~parent:initial root in
  (* each element's from its parent's, down the tree *)
  let rec go (e : Dom.element) (style : t) =
    Hashtbl.add table (Dom.hash e) (e, style);
    List.iter
      (fun (n : Dom.node) ->
        match n with
        | Element c -> go c (compute ~root_font_size:root_style.font_size ~parent:style c)
        | Text _ -> ())
      (kids e)
  in
  go root root_style;
  ((fun e -> match Cascade.find_element table e with Some s -> s | None -> initial), kids)

let styles ?visited ?quirks (m : Cascade.media) (sheets : Cascade.sheet list) (root : Dom.element) : Dom.element -> t =
  fst (styles_all ?visited ?quirks m sheets root)
