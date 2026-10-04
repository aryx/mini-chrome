(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Box_grid.mli *)
open Box_types
open Box_tree (* moved *)
open Box_inline (* four *)
open Box_flow (* size, is_space *)

let no_margins = (Computed.Len Css_values.zero, Computed.Len Css_values.zero, Computed.Len Css_values.zero, Computed.Len Css_values.zero)

let items ~(absolute : Dom.element -> Computed.t -> unit) (env : env) (e : Dom.element) (s : Computed.t) : (Dom.element * Computed.t) list =
  (* an item is a block (an inline one "blockified"); a run of text an
   * anonymous item in the container's style *)
  let blockify (cs : Computed.t) : Computed.t =
    { cs with display = (match cs.display with Inline | Inline_block | List_item -> Block | Inline_flex -> Flex | d -> d); float = Side_none }
  in
  List.concat_map
    (fun (n : Dom.node) ->
      match n with
      | Text t when String.for_all is_space t -> []
      | Text t ->
          [ ( Dom.element "span" [ Text t ],
              { s with display = Block; margin = no_margins; padding = (Css_values.zero, Css_values.zero, Css_values.zero, Css_values.zero);
                border_width = (0., 0., 0., 0.); width = Auto; height = Auto; min_width = Css_values.zero; max_width = Auto;
                flex_grow = 0.; flex_shrink = 1.; flex_basis = Auto; background = Css_values.transparent; position = Static;
                overflow_hidden = false; align_self = None; grid_area = Auto_placed; min_height = Css_values.zero } ) ]
      | Element c -> (
          let cs = env.style c in
          match cs.display with
          | Display_none -> []
          | _ when cs.position = Absolute || cs.position = Fixed ->
              absolute c cs;
              []
          | _ -> [ (c, blockify cs) ]))
    (env.kids e)

(* whether a track's size reads its content's narrowest, its widest.
 * An fr track reads neither in a room to share (it takes what is
 * left): its items are not measured -- Wikipedia's article, in
 * "minmax(0, 1fr)", would be laid out a second time at no limit just
 * to be told its width (22 ms of layout became 66) *)
let reads_least (t : Css_grid.track) : bool = match (t.min, t.max) with (Min_content | Auto | Fr _), _ | _, Min_content -> true | _ -> false
let reads_most (t : Css_grid.track) : bool = match (t.min, t.max) with Max_content, _ | _, (Max_content | Auto) -> true | _ -> false

let children ~lay_out ~measure ~absolute ~relative (ctx : ctx) (e : Dom.element) (s : Computed.t) : unit =
  let env = ctx.env in
  let measuring = env.measuring in
  let items = Array.of_list (items ~absolute env e s) in
  let n = Array.length items in
  (* measured at no limit, a grid has no room to share: its columns
   * are their contents *)
  let unlimited = measuring && ctx.width >= 1e5 in
  let width = ctx.width in
  let column_gap = Css_values.resolve s.column_gap (if unlimited then 0. else width) and row_gap = Css_values.resolve s.row_gap 0. in
  let cells, rows, columns =
    Grid_layout.place ~rows:(List.length s.grid_rows) ~columns:(List.length s.grid_columns) ~areas:s.grid_areas
      (Array.to_list (Array.map (fun (_, (cs : Computed.t)) -> cs.grid_area) items))
  in
  let cells = Array.of_list cells in
  let tracks said count = Array.init count (fun i -> match List.nth_opt said i with Some t -> t | None -> Css_grid.auto) in
  let column_tracks = tracks s.grid_columns columns and row_tracks = tracks s.grid_rows rows in
  (* an item's margins (auto ones 0) and what is round its content across *)
  let margins (cs : Computed.t) =
    let mt, mr, mb, ml = cs.margin in
    let m x = Option.value (size x (if unlimited then 0. else width)) ~default:0. in
    (m mt, m mr, m mb, m ml)
  in
  let chrome (cs : Computed.t) =
    let _, pr, _, pl = four (fun l -> Css_values.resolve l (if unlimited then 0. else width)) cs.padding and _, br, _, bl = cs.border_width in
    pl +. pr +. bl +. br
  in
  (* the columns: from the items' contents, measured only for a track
   * that reads them (Wikipedia's "12.25rem minmax(0, 1fr)" reads none) *)
  let column_contents =
    Grid_layout.contents ~base:width ~gap:column_gap column_tracks
      (List.init n (fun i ->
           let c, (cs : Computed.t) = items.(i) and (cell : Grid_layout.cell) = cells.(i) in
           let _, mr, _, ml = margins cs in
           let spanned = Array.sub column_tracks cell.column cell.columns in
           let outer w = ml +. w +. chrome cs +. mr in
           let own = Option.map (fun w -> if cs.border_box then Float.max 0. (w -. chrome cs) else w) (if unlimited then None else size cs.width width) in
           let content available =
             match own with Some w -> outer w | None -> outer (measure c cs ~available)
           in
           ( cell.column,
             cell.columns,
             { Grid_layout.least = (if Array.exists reads_least spanned then content 0. else 0.);
               most = (if unlimited || Array.exists reads_most spanned then content infinity else 0.) } )))
  in
  let stretch_columns = match s.justify_content with Start | Stretch -> true | _ -> false in
  let column_sizes =
    Grid_layout.sizes ~room:(if unlimited then None else Some width) ~base:width ~gap:column_gap ~stretch:(stretch_columns && not measuring) column_tracks
      column_contents
  in
  let grid_width = Array.fold_left ( +. ) 0. column_sizes +. (column_gap *. float_of_int (max 0 (columns - 1))) in
  let column_starts =
    Grid_layout.starts ~align:(if measuring then Start else s.justify_content) ~room:(if unlimited then grid_width else Float.max width grid_width) ~gap:column_gap
      column_sizes
  in
  (* an area's start and length, along tracks *)
  let span starts sizes gap first count = (starts.(first), Array.fold_left ( +. ) 0. (Array.sub sizes first count) +. (gap *. float_of_int (count - 1))) in
  (* each item laid out at its columns' width, at the grid's top: its
   * height. Its row is not known yet, and it is moved there after --
   * not at all if it is in the first, which spares a copy of all it
   * holds (Wikipedia's article is a grid's item) *)
  let top = ctx.cursor in
  let laid =
    Array.mapi
      (fun i (c, (cs : Computed.t)) ->
        let (cell : Grid_layout.cell) = cells.(i) in
        let mt, mr, mb, ml = margins cs in
        let x, area = span column_starts column_sizes column_gap cell.column cell.columns in
        (* filling its area across, unless it has a width *)
        let content = if size cs.width width = None then Some (Float.max 0. (area -. ml -. mr -. chrome cs)) else None in
        let b = lay_out c { cs with margin = no_margins } ~x:(ctx.x +. x +. ml) ~y:(top +. mt) ~width:(Float.max 0. (area -. ml -. mr)) ~content in
        (b, cs, cell, mt, mb))
      items
  in
  let row_contents =
    Grid_layout.contents ~base:0. ~gap:row_gap row_tracks
      (Array.to_list (Array.map (fun ((b : box), _, (cell : Grid_layout.cell), mt, mb) -> (cell.row, cell.rows, { Grid_layout.least = mt +. b.height +. mb; most = mt +. b.height +. mb })) laid))
  in
  (* the rows: in the container's height if it has one; else their
   * contents', and again in its min-height if that is more *)
  let inside (l : Css_values.length) =
    let pt, _, pb, _ = four (fun l -> Css_values.resolve l width) s.padding and bt, _, bb, _ = s.border_width in
    if s.border_box then Float.max 0. (l.px -. pt -. pb -. bt -. bb) else l.px
  in
  let stretch_rows = s.align_content = None in
  let row_sizes room = Grid_layout.sizes ~room ~base:0. ~gap:row_gap ~stretch:stretch_rows row_tracks row_contents in
  let total sizes = Array.fold_left ( +. ) 0. sizes +. (row_gap *. float_of_int (max 0 (rows - 1))) in
  let row_sizes, height =
    match s.height with
    | Len l when l.pct = 0. && not measuring -> (row_sizes (Some (inside l)), inside l)
    | _ ->
        let sizes = row_sizes None in
        let least = if measuring then 0. else inside s.min_height in
        if least > total sizes then (row_sizes (Some least), least) else (sizes, total sizes)
  in
  let row_starts = Grid_layout.starts ~align:(Option.value s.align_content ~default:Start) ~room:height ~gap:row_gap row_sizes in
  let boxes =
    Array.to_list
      (Array.map
         (fun ((b : box), (cs : Computed.t), (cell : Grid_layout.cell), mt, mb) ->
           let y, area = span row_starts row_sizes row_gap cell.row cell.rows in
           (* down its area: stretched if its height is its content's,
            * or at the start, the centre, the end *)
           let align = match cs.align_self with Some a -> a | None -> s.align_items in
           let outer = mt +. b.height +. mb in
           let offset, height =
             match align with
             | Stretch when cs.height = Auto -> (0., Float.max b.height (area -. mt -. mb))
             | Center -> (Float.max 0. ((area -. outer) /. 2.), b.height)
             | End -> (Float.max 0. (area -. outer), b.height)
             | _ -> (0., b.height)
           in
           relative cs (moved 0. (y +. offset) { b with height }))
         laid)
  in
  (* measured: the grid's right edge, marked by an empty box (a measure
   * reads the boxes' edges) *)
  let edge =
    if measuring then
      [ { element = None; style = s; x = ctx.x +. grid_width; y = top; width = 0.; height = 0.; border = (0., 0., 0., 0.); children = []; lines = [];
          backdrops = []; marker = None; lifted = [] } ]
    else []
  in
  ctx.children <- List.rev (boxes @ edge);
  ctx.cursor <- (if n = 0 then top else top +. height);
  ctx.pending <- 0.
