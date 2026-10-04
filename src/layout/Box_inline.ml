(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Box_inline.mli *)
open Box_types

(*****************************************************************************)
(* A word's look and room *)
(*****************************************************************************)

let look_of (s : Computed.t) ~(link : string option) : Looks.t =
  let color = (s.color.r, s.color.g, s.color.b) in
  {
    size = s.font_size;
    bold = s.bold;
    italic = s.italic;
    underline = s.underline;
    strike = s.line_through;
    monospace = s.family = Monospace;
    color;
    link;
    pre = (match s.white_space with Pre | Pre_wrap -> true | _ -> false);
    align = (match s.text_align with Align_center -> Center | Align_right -> Right | Align_left | Align_justify -> Left);
    (* a link's colour is the style sheets' (:link, :visited), not the
     * look's *)
    link_color = color;
    visited_color = color;
    base = 16.;
    extensions = true;
  }

(* a function over the four sides: top, right, bottom, left *)
let four (f : 'a -> 'b) ((t, r, b, l) : 'a * 'a * 'a * 'a) : 'b * 'b * 'b * 'b = (f t, f r, f b, f l)

let line_height (s : Computed.t) : float =
  match s.line_height with Line_normal -> 1.2 *. s.font_size | Factor f -> f *. s.font_size | Line_px p -> p

let word_style (s : Computed.t) ~(link : string option) : word_style =
  let lh = line_height s and size = s.font_size in
  let shift = match s.vertical_align with Sub -> 0.2 *. size | Super -> -0.35 *. size | _ -> 0. in
  { look = look_of s ~link; above = (0.8 *. size) +. ((lh -. size) /. 2.); below = (0.2 *. size) +. ((lh -. size) /. 2.); shift; shown = s.visible }

(*****************************************************************************)
(* Lines beside floats *)
(*****************************************************************************)

(* the room for a line from [top], [height] high, beside the floats *)
let room (floats : placed list) ~(x : float) ~(width : float) ~(top : float) ~(height : float) : float * float =
  let l, r =
    List.fold_left
      (fun (l, r) p ->
        if p.ptop >= top +. height || p.pbottom <= top then (l, r)
        else match p.pside with On_left -> (Float.max l p.right, r) | On_right -> (l, Float.min r p.left))
      (x, x +. width) floats
  in
  (l, Float.max 0. (r -. l))

(* below the floats of [sides] *)
let cleared (floats : placed list) (sides : side list) (top : float) : float =
  List.fold_left (fun t p -> if List.mem p.pside sides then Float.max t p.pbottom else t) top floats

(* a word's extent above and below the baseline *)
let extent (ws : word_style) (boxed : boxed option) : float * float =
  match boxed with
  | Some (Pic { height; middle = false; _ }) -> (height, 0.)
  | Some (Pic { height; middle = true; _ }) -> (height /. 2., height /. 2.)
  | Some (Ctl { control_height = h; _ }) -> (0.75 *. h, 0.25 *. h)
  | Some (Inline { ib; mt; mb; _ }) ->
      let base = match Box_tree.last_baseline ib with Some b -> b -. ib.y | None -> ib.height in
      (mt +. base, ib.height -. base +. mb)
  | None -> (ws.above -. ws.shift, ws.below +. ws.shift)

(* a line's words placed, the line as tall as they need (at least the
 * block's strut); its inline-blocks moved into place *)
let set_line (strut : word_style) (align : Looks.align) ~(x : float) ~(width : float) ~(top : float) (words : item list) :
    Html_layout.line * box list * box list =
  let placed, line_width =
    List.fold_left
      (fun (placed, pen) item ->
        match item with
        | Word w ->
            let pen = if w.space_before then pen +. w.space else pen in
            (((w, pen) :: placed), pen +. w.width)
        | Break | Anchor _ | Float _ | Clear _ -> (placed, pen))
      ([], 0.) words
  in
  let placed = List.rev placed in
  let shift = match align with Left -> 0. | Center -> Float.max 0. ((width -. line_width) /. 2.) | Right -> Float.max 0. (width -. line_width) in
  let up, down =
    List.fold_left
      (fun (u, d) ((w : word), _) -> let a, b = extent w.ws w.boxed in (Float.max u a, Float.max d b))
      (strut.above, strut.below) placed
  in
  let baseline = top +. up in
  let fragments, boxes =
    List.fold_left
      (fun (frags, boxes) ((w : word), pen) ->
        let fx = x +. shift +. pen in
        (* hidden (visibility, opacity 0): its room, nothing drawn *)
        let picture = match w.boxed with Some (Pic p) when w.ws.shown -> Some p | _ -> None in
        let control = match w.boxed with Some (Ctl c) when w.ws.shown -> Some c | _ -> None in
        let text = if w.ws.shown then w.text else "" in
        let frag : Html_layout.fragment =
          { text; look = w.ws.look; x = fx; width = w.width; baseline = baseline +. w.ws.shift; picture; control; element = w.owner }
        in
        let boxes =
          match w.boxed with
          | Some (Inline { ib; ml; mt; _ }) ->
              let above, _ = extent w.ws w.boxed in
              Box_tree.moved (fx +. ml -. ib.x) (baseline -. above +. mt -. ib.y) ib :: boxes
          | _ -> boxes
        in
        (frag :: frags, boxes))
      ([], []) placed
  in
  (* each decorated inline element's box on this line: from its first
   * word to its last, its margins out where its edges are here, as tall
   * as its font and its vertical padding and border (which the line's
   * height ignores) *)
  let decorations =
    List.fold_left
      (fun acc ((w : word), _) -> List.fold_left (fun acc d -> if List.exists (fun d' -> d'.de == d.de) acc then acc else acc @ [ d ]) acc w.decorations)
      [] placed
  in
  let backdrops =
    List.map
      (fun d ->
        let mine = List.filter (fun ((w : word), _) -> List.exists (fun d' -> d'.de == d.de) w.decorations) placed in
        let at_edge edge = List.exists (fun ((w : word), _) -> w.edge = edge && w.owner == d.de) mine in
        let left = List.fold_left (fun m (_, pen) -> Float.min m pen) infinity mine in
        let right = List.fold_left (fun m ((w : word), pen) -> Float.max m (pen +. w.width)) neg_infinity mine in
        let left = x +. shift +. left +. (if at_edge Lead then d.dml else 0.) in
        let right = x +. shift +. right -. (if at_edge Trail then d.dmr else 0.) in
        let pt, _, pb, _ = four (fun l -> Css_values.resolve l 0.) d.ds.padding and bt, br, bb, bl = d.ds.border_width in
        let size = d.ds.font_size in
        let y = baseline -. (0.8 *. size) -. pt -. bt in
        { element = Some d.de; style = d.ds; x = left; y; width = Float.max 0. (right -. left); height = size +. pt +. pb +. bt +. bb;
          border = (bt, (if at_edge Trail then br else 0.), bb, (if at_edge Lead then bl else 0.)); children = []; lines = []; backdrops = []; marker = None })
      decorations
  in
  ( { top; height = up +. down; baseline; fragments = List.rev fragments; anchors = List.filter_map (fun i -> match i with Anchor a -> Some a | _ -> None) words },
    List.rev boxes, backdrops )

(* the words stuck together: a unit starts at a word with a space
 * before it that may break there *)
let units_of (words : item list) : item list list =
  let rec go current acc words =
    match words with
    | [] -> List.rev (if current = [] then acc else List.rev current :: acc)
    | (Word { space_before = true; glue = false; _ } as w) :: rest when current <> [] -> go [ w ] (List.rev current :: acc) rest
    | w :: rest -> go (w :: current) acc rest
  in
  go [] [] words

let rec starting_line (unit : item list) : item list =
  match unit with
  | Word w :: rest -> Word { w with space_before = false } :: rest
  | ((Anchor _ | Float _) as i) :: rest -> i :: starting_line rest
  | _ -> unit

let unit_size (unit : item list) : float * float =
  List.fold_left
    (fun (space, width) item ->
      match item with
      | Word w -> if width = 0. && space = 0. && w.space_before then (w.space, w.width) else (space, width +. w.width)
      | Break | Anchor _ | Float _ | Clear _ -> (space, width))
    (0., 0.) unit

(* a float put at [top] against its edge of the room there (below the
 * floats beside it if it does not fit); its box moved there *)
let place (floats : placed list ref) ~(x : float) ~(width : float) ~(top : float) (placed_boxes : box list ref) (item : item) : unit =
  match item with
  | Float f when not f.placed ->
      f.placed <- true;
      let mt, mr, mb, ml = f.fmargin in
      let w = ml +. f.fbox.width +. mr and h = mt +. f.fbox.height +. mb in
      let rec find top =
        let l, rw = room !floats ~x ~width ~top ~height:(Float.max h 1.) in
        let below = List.fold_left (fun m p -> if p.pbottom > top && p.ptop <= top then Float.min m p.pbottom else m) infinity !floats in
        (* to a hundredth of a point: a box made as wide as its floats
         * (shrink-to-fit) must hold them, whatever the sums' last bits *)
        if rw +. 0.01 >= w || below = infinity then (l, rw, top) else find below
      in
      let l, rw, top = find top in
      let fx = match f.fside with On_left -> l | On_right -> l +. rw -. w in
      floats := { pside = f.fside; left = fx; right = fx +. w; ptop = top; pbottom = top +. h } :: !floats;
      placed_boxes := Box_tree.moved (fx +. ml -. f.fbox.x) (top +. mt -. f.fbox.y) f.fbox :: !placed_boxes
  | _ -> ()

(* the items cut at the breaks, each run set on lines one at a time,
 * each as wide as the floats beside it leave (greedy); a float met at
 * a line's start put at its top, one inside it below it. The lines,
 * the boxes set in them (inline-blocks, floats), the bottom *)
let set_lines (floats : placed list ref) (strut : word_style) (align : Looks.align) ~(pre : bool) ~(x : float) ~(width : float) ~(top : float)
    (items : item list) : Html_layout.line list * box list * box list * float =
  let boxes = ref [] and backdrops = ref [] in
  let rec groups current acc items =
    match items with
    | [] -> List.rev (List.rev current :: acc)
    | Break :: rest -> groups [] (List.rev current :: acc) rest
    | w :: rest -> groups (w :: current) acc rest
  in
  let groups = groups [] [] items in
  let n = List.length groups in
  let set top acc words =
    let lx, lw = room !floats ~x ~width ~top ~height:1. in
    let line, inline_boxes, drops = set_line strut align ~x:lx ~width:lw ~top words in
    boxes := List.rev_append inline_boxes !boxes;
    backdrops := List.rev_append drops !backdrops;
    (top +. line.height, line :: acc)
  in
  let bottom, lines =
    List.fold_left
      (fun (top, acc) (i, group) ->
        let top = List.fold_left (fun top item -> match item with Clear sides -> cleared !floats sides top | _ -> top) top group in
        let group = List.filter (fun item -> match item with Clear _ -> false | _ -> true) group in
        let only_floats = List.for_all (fun item -> match item with Float _ | Anchor _ -> true | _ -> false) group in
        if group = [] && i = n - 1 then (top, acc)
        else if only_floats && group <> [] then (
          List.iter (place floats ~x ~width ~top boxes) group;
          (* anchors alone: a line of no height where they are *)
          if List.exists (fun item -> match item with Anchor _ -> true | _ -> false) group then
            let line, _, _ = set_line { strut with above = 0.; below = 0. } align ~x ~width ~top group in
            (top, line :: acc)
          else (top, acc))
        else if pre || group = [] then set top acc group
        else
          let units = Array.of_list (units_of group) in
          let sizes = Array.map unit_size units in
          let count = Array.length units in
          let strut_height = strut.above +. strut.below in
          let rec lines top start acc =
            if start >= count then (top, acc)
            else
              let rec leading items = match items with (Float _ as f) :: rest -> f :: leading rest | Anchor _ :: rest -> leading rest | _ -> [] in
              List.iter (place floats ~x ~width ~top boxes) (leading units.(start));
              let lx, lw = room !floats ~x ~width ~top ~height:strut_height in
              if snd sizes.(start) > lw && lw < width then
                (* no room beside the floats: below the first to end *)
                let below = List.fold_left (fun m p -> if p.ptop < top +. strut_height && p.pbottom > top then Float.min m p.pbottom else m) infinity !floats in
                if below = infinity then lines_from top start acc lx lw else lines below start acc
              else lines_from top start acc lx lw
          and lines_from top start acc lx lw =
            let rec extend j w =
              (* a hundredth of a pixel's slack: a box shrunk to fit its
               * line is exactly as wide as it, give or take rounding *)
              if j + 1 < count && w +. fst sizes.(j + 1) +. snd sizes.(j + 1) <= lw +. 0.01 then extend (j + 1) (w +. fst sizes.(j + 1) +. snd sizes.(j + 1)) else j
            in
            let j = extend start (snd sizes.(start)) in
            let words = List.concat (List.init (j - start + 1) (fun k -> if k = 0 then starting_line units.(start) else units.(start + k))) in
            let line, inline_boxes, drops = set_line strut align ~x:lx ~width:lw ~top words in
            boxes := List.rev_append inline_boxes !boxes;
            backdrops := List.rev_append drops !backdrops;
            let bottom = top +. line.height in
            List.iter (place floats ~x ~width ~top:bottom boxes) words;
            lines bottom (j + 1) (line :: acc)
          in
          lines top 0 acc)
      (top, [])
      (List.mapi (fun i g -> (i, g)) groups)
  in
  (List.rev lines, List.rev !boxes, List.rev !backdrops, bottom)
