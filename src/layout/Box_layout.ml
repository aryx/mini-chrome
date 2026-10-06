(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Box_layout.mli *)
open Box_types
open Box_tree (* a box read *)
open Box_inline (* words on lines *)
open Box_flow (* a block being laid out *)

(* a height known before the content is: a length, or percents of a
 * height itself known (CSS 2.1 section 10.5: else it is auto); the
 * content's, the padding and borders [chrome] taken off a border box *)
let definite (env : env) (s : Computed.t) ~(chrome : float) : float option =
  let content h = if s.border_box then Float.max 0. (h -. chrome) else h in
  match (s.height, env.known_height) with
  | Len l, _ when l.pct = 0. -> Some (content l.px)
  | Len l, Some h when not env.measuring -> Some (content (Css_values.resolve l h))
  | _ -> None

let rec layout_block (env : env) (floats : placed list ref) (e : Dom.element) (s : Computed.t) ~(cb_x : float) ~(cb_width : float)
    ~(y : float) ~(marker : Html_layout.marker option) ?content () : box * float =
  (* measuring an intrinsic size: a percentage width is auto (it would
   * be of the size being measured: CSS Sizing, "cyclic percentages") *)
  let s = match s.width with Len l when env.measuring && l.pct <> 0. -> { s with width = Auto } | _ -> s in
  let ml, cw, _ = horizontal s ~cb_width ?content () in
  let pt, pr, pb, pl = four (fun l -> Css_values.resolve l cb_width) s.padding in
  let bt, br, bb, bl = s.border_width in
  let own = own_context s in
  let floats = if own then ref [] else floats in
  let x = cb_x +. ml in
  let given = definite env s ~chrome:(pt +. pb +. bt +. bb) in
  (* its own list of the positioned boxes written in it *)
  let env = { env with positioned = ref [] } in
  let env =
    match s.position with
    | Static -> { env with known_height = given }
    | _ -> { env with known_height = given; containing = (x +. bl, y +. bt, pl +. cw +. pr, Option.map (fun h -> pt +. h +. pb) given) }
  in
  let centring =
    e.name = "center"
    || (e.name <> "table" && match Option.map String.lowercase_ascii (Dom.attribute ~extensions:true "align" e) with Some ("center" | "middle") -> true | _ -> false)
    || (env.centring && s.text_align = Align_center)
  in
  let env = if centring = env.centring then env else { env with centring } in
  let content_top = y +. bt +. pt in
  let ctx =
    { env; floats; block = s; x = x +. bl +. pl; width = cw; cursor = content_top; pending = 0.;
      absorbed = (not own) && pt +. bt = 0.; children = []; items = []; space = false; owner = e;
      link = (if e.name = "a" then Dom.attribute "href" e else None); counter = 0; decorations = [] }
  in
  (match s.display with
  (* a form's control laid out as a block (display: block, or an item
   * of a flex container: Google's search field): a line of its own
   * with the control on it, as wide as the block if its width is said *)
  | _ when e.name = "input" || e.name = "select" || e.name = "textarea" -> (
      match Html_layout.control_size env.metrics (look_of s ~link:None) e with
      | Some (w, h) when s.visible ->
          (* measuring: its own width, not the unlimited room's it is
           * measured in (a search field in a row of buttons took the row) *)
          let w = if (s.width <> Auto || content <> None) && not env.measuring then cw else Float.min w cw in
          add_word ctx (word_style s ~link:None) ~glue:false "" w ~owner:e ~boxed:(Ctl { element = e; control_height = h });
          flush_inline ctx
      | _ -> ())
  (* a picture laid out as a block (an item of a flex container or of
   * a grid: an icon in a button): a line of its own with it *)
  | _ when e.name = "svg" ->
      let w, h = svg_size ctx e s in
      add_word ctx (word_style s ~link:None) ~glue:false "" w ~owner:e ~boxed:(Pic { src = ""; height = h; middle = false });
      flush_inline ctx
  | _ when e.name = "img" && picture_size ctx e s <> None ->
      let w, h = Option.get (picture_size ctx e s) in
      add_word ctx (word_style s ~link:None) ~glue:false "" w ~owner:e ~boxed:(Pic { src = Option.value (picture_src e) ~default:""; height = h; middle = false });
      flush_inline ctx
  | Flex | Inline_flex -> flex_children ctx e s
  | Grid -> grid_children ctx e s
  | _ ->
      List.iter (walk ctx s (word_style s ~link:ctx.link)) (env.kids e);
      flush_inline ctx);
  (* the last child's bottom margin goes through, if nothing holds it *)
  let through = (not own) && pb +. bb = 0. && s.height = Auto in
  let content_bottom = if through then ctx.cursor else ctx.cursor +. ctx.pending in
  let content_bottom = if own then List.fold_left (fun m p -> Float.max m p.pbottom) content_bottom !floats else content_bottom in
  let auto_height = content_bottom -. content_top in
  (* a height in percents is at least the content's: what goes past
   * a box is not scrolled here, and a page whose <html> is 100% of the
   * window would end at the window's *)
  let ch =
    match (given, s.height) with
    | Some h, Len l when l.pct <> 0. -> Float.max h auto_height
    | Some h, _ -> h
    | None, _ -> auto_height
  in
  (* min-height and max-height, of the border box with box-sizing:
   * border-box (Google's buttons) *)
  let vchrome = if s.border_box then pt +. pb +. bt +. bb else 0. in
  let ch = match s.max_height with Len l when l.pct = 0. -> Float.min ch (l.px -. vchrome) | _ -> ch in
  let ch = Float.max ch (Css_values.resolve s.min_height 0. -. vchrome) in
  (* the boxes placed in it by their bottom, now that its height is
   * known (a tab's line under its label: an ::after, bottom: 0): those
   * written in it, at any depth, that still wait *)
  let edge = y +. bt +. pt +. ch +. pb in
  let rec settled ((l : box), bottom) =
    match bottom with
    | Some b -> decr env.late; (settle (moved 0. (edge -. b -. l.height -. l.y) l), None)
    | None -> (settle l, None)
  and settle (b : box) : box = { b with lifted = List.map settled b.lifted; children = List.map settle b.children } in
  let waiting = s.position <> Static && !(env.late) > 0 in
  let lifted = List.rev !(env.positioned) in
  let lifted = if waiting then List.map settled lifted else lifted in
  let children = List.rev ctx.children in
  let children = if waiting then List.map settle children else children in
  ( { element = Some e; style = s; x; y; width = bl +. pl +. cw +. pr +. br; height = bt +. pt +. ch +. pb +. bb;
      border = (bt, br, bb, bl); children; lines = []; backdrops = []; marker; lifted },
    if through then ctx.pending else 0. )

(* a flex container's items laid out (Flex_layout's arithmetic): each
 * measured, the lines cut, the room shared, the items placed along and
 * across *)
and flex_children (ctx : ctx) (e : Dom.element) (s : Computed.t) : unit =
  let env = ctx.env in
  let row = match s.flex_direction with Row | Row_reverse -> true | Column | Column_reverse -> false in
  let no_margins = Box_grid.no_margins in
  let items = Box_grid.items ~absolute:(add_absolute ctx) env e s in
  let items = match s.flex_direction with Row_reverse | Column_reverse -> List.rev items | _ -> items in
  let items = Array.of_list items in
  let measuring = env.measuring in
  let width = ctx.width in
  let gap_main = Css_values.resolve (if row then s.column_gap else s.row_gap) width in
  let gap_cross = Css_values.resolve (if row then s.row_gap else s.column_gap) width in
  let justify = if measuring then Computed.Start else s.justify_content in
  (* an item's chrome across the main axis: margins (auto ones 0, and
   * said), borders and paddings *)
  let chrome (cs : Computed.t) =
    let mt, mr, mb, ml = cs.margin in
    let pt, pr, pb, pl = four (fun l -> Css_values.resolve l width) cs.padding and bt, br, bb, bl = cs.border_width in
    let m x = Option.value (size x width) ~default:0. in
    if row then ((m ml, m mr), pl +. pr +. bl +. br, (ml = Auto, mr = Auto))
    else ((m mt, m mb), pt +. pb +. bt +. bb, (mt = Auto, mb = Auto))
  in
  let align_of (cs : Computed.t) =
    let a = match cs.align_self with Some a -> a | None -> s.align_items in
    (* stretched only if its cross size is auto *)
    if a = Stretch && (if row then cs.height <> Auto else cs.width <> Auto) then Computed.Start else a
  in
  let content_top = ctx.cursor in
  let boxes =
    if row then (
      (* the base sizes: flex-basis, width, or the content's *)
      let bases =
        Array.map
          (fun (c, (cs : Computed.t)) ->
            let (ml, mr), ch, _ = chrome cs in
            let given w = if cs.border_box then Float.max 0. (w -. ch) else w in
            (* measuring: a size in percents is of a room not known yet,
             * and so the content's (a button's label, width: 100%,
             * made its row as wide as the page) *)
            let percent (v : Computed.size) = measuring && match v with Len l -> l.pct <> 0. | Auto -> false in
            let base =
              match (cs.flex_basis, size cs.width width) with
              | Len l, _ when not (percent cs.flex_basis) -> given (Css_values.resolve l width)
              | Auto, Some w when not (percent cs.width) -> given w
              | _ -> shrink env c cs ~available:infinity
            in
            ml +. base +. ch +. mr)
          items
      in
      let total = Array.fold_left ( +. ) 0. bases +. (gap_main *. float_of_int (max 0 (Array.length items - 1))) in
      let fitem i =
        let _, (cs : Computed.t) = items.(i) in
        let (ml, mr), ch, (ab, aa) = chrome cs in
        let outer w = ml +. w +. ch +. mr in
        (* an item does not shrink below its content (min-width: auto),
         * measured only when it has to shrink *)
        let min_size =
          if cs.min_width.px > 0. || cs.min_width.pct > 0. then outer (Css_values.resolve cs.min_width width)
          else if total > width && (not cs.overflow_hidden) && not measuring then
            outer (Float.min (shrink env (fst items.(i)) cs ~available:0.) (bases.(i) -. ml -. ch -. mr))
          else 0.
        in
        (* measuring: no growing, and no shrinking either -- a row that
         * does not wrap is as wide as its items, even at its narrowest *)
        let max_size = match size cs.max_width width with Some m -> outer m | None -> infinity in
        (* the least it shrinks to is its content's, but not more than
         * the most it may be (css-flexbox 4.5): GitHub's README, max-width:
         * 100%, whose widest line of code would else widen the page *)
        let min_size = Float.min min_size max_size in
        { Flex_layout.base = bases.(i); grow = (if measuring then 0. else cs.flex_grow); shrink = (if measuring then 0. else cs.flex_shrink); min_size;
          max_size;
          auto_before = ab && not measuring; auto_after = aa && not measuring }
      in
      let fitems = Array.init (Array.length items) fitem in
      let top = ref content_top and boxes = ref [] in
      List.iter
        (fun (first, last) ->
          let line = Array.sub fitems first (last - first + 1) in
          let sizes = Flex_layout.resolve ~room:width ~gap:gap_main line in
          let starts = Flex_layout.place ~justify ~room:width ~gap:gap_main line sizes in
          let laid =
            Array.mapi
              (fun k main ->
                let c, (cs : Computed.t) = items.(first + k) in
                let (ml, mr), ch, _ = chrome cs in
                let mt, _, mb, _ = cs.margin in
                let mt = Option.value (size mt width) ~default:0. and mb = Option.value (size mb width) ~default:0. in
                (* its size is decided (Flex_layout, with its min and max): a
                 * max-width in percents is not asked again, of the item's own
                 * width (GitHub's buttons, max-width: 70%, made 70% of themselves) *)
                let cs_in = { cs with margin = no_margins; max_width = Auto; min_width = Css_values.zero } in
                let b, _ =
                  layout_block env (ref []) c cs_in ~cb_x:(ctx.x +. starts.(k) +. ml) ~cb_width:(main -. ml -. mr) ~y:(!top +. mt) ~marker:None
                    ~content:(Float.max 0. (main -. ml -. mr -. ch)) ()
                in
                (b, cs, mt, mb))
              sizes
          in
          let cross = Array.fold_left (fun m (b, _, mt, mb) -> Float.max m (mt +. b.height +. mb)) 0. laid in
          (* a single line is as tall as its container, if its height is
           * given (section 9.4) *)
          let cross = match env.known_height with Some h when (not s.flex_wrap) && not measuring -> Float.max cross h | _ -> cross in
          Array.iter
            (fun ((b : box), cs, mt, mb) ->
              let offset, outer = Flex_layout.cross ~align:(align_of cs) ~line:cross ~size:(mt +. b.height +. mb) in
              boxes := relative ctx cs (moved 0. offset { b with height = outer -. mt -. mb }) :: !boxes)
            laid;
          (* measuring: the line's end, its last item's right margin
           * included, marked by an empty box -- a box's edge is inside
           * its margin, and the measure reads edges *)
          (if measuring then
             let last = Array.length sizes - 1 in
             let edge = ctx.x +. starts.(last) +. sizes.(last) in
             boxes :=
               { element = None; style = s; x = edge; y = !top; width = 0.; height = 0.; border = (0., 0., 0., 0.); children = [];
                 lines = []; backdrops = []; marker = None; lifted = [] }
               :: !boxes);
          top := !top +. cross +. gap_cross)
        (Flex_layout.lines ~wrap:s.flex_wrap ~room:width ~gap:gap_main fitems);
      ctx.cursor <- (if !boxes = [] then content_top else !top -. gap_cross);
      List.rev !boxes)
    else (
      (* a column: each item laid out at its width first (stretched, or
       * shrunk to fit), its height its base *)
      let laid =
        Array.map
          (fun (c, (cs : Computed.t)) ->
            let _, _, _, ml = cs.margin and _, mr, _, _ = cs.margin in
            let ml' = Option.value (size ml width) ~default:0. and mr' = Option.value (size mr width) ~default:0. in
            let _, pr, _, pl = four (fun l -> Css_values.resolve l width) cs.padding and _, br, _, bl = cs.border_width in
            let hchrome = pl +. pr +. bl +. br in
            let content =
              match (align_of cs, size cs.width width) with
              | _, Some _ -> None
              | Stretch, None -> Some (Float.max 0. (width -. ml' -. mr' -. hchrome))
              | _, None -> Some (shrink env c cs ~available:(width -. ml' -. mr' -. hchrome))
            in
            let lay cs = fst (layout_block env (ref []) c { cs with Computed.margin = no_margins } ~cb_x:0. ~cb_width:width ~y:0. ~marker:None ?content ()) in
            let b = lay cs in
            let rec holds (b : box) = b.lifted <> [] || List.exists holds b.children in
            (* laid out again at the height the container gives it, if
             * it holds positioned boxes: they are placed in its height
             * (an application's frame: a column, its one item filling
             * the window, everything in it absolute) *)
            let again = if holds b then Some (fun (h : float) -> lay { cs with height = Len { Css_values.zero with px = h }; border_box = true }) else None in
            let x_offset =
              match align_of cs with
              | End -> width -. b.width -. mr'
              | Center -> (width -. b.width) /. 2.
              | _ -> ml'
            in
            (c, cs, b, x_offset, again))
          items
      in
      let fitems =
        Array.map
          (fun (_, (cs : Computed.t), (b : box), _, _) ->
            let (mt, mb), _, (ab, aa) = chrome cs in
            (* a height in percents is of the container's when that is
             * known; else auto, the item's own (YouTube's one card of
             * its first page, height: 100% in a column as tall as it
             * holds, was 0 high) *)
            let said =
              match (cs.height, env.known_height) with
              | Len l, Some h when l.pct <> 0. && not measuring -> Some (Css_values.resolve l h)
              | Len l, _ when l.pct <> 0. -> None
              | h, _ -> size h 0.
            in
            let base = match (cs.flex_basis, said) with Len l, _ when l.pct = 0. -> l.px | _, Some h -> h | _ -> b.height in
            { Flex_layout.base = mt +. base +. mb; grow = cs.flex_grow; shrink = cs.flex_shrink;
              min_size = (if cs.overflow_hidden then 0. else mt +. b.height +. mb); max_size = infinity;
              auto_before = ab; auto_after = aa })
          laid
      in
      (* the room along: the container's height if it has one, else the
       * items' own *)
      let room =
        match env.known_height with
        | Some h when not measuring -> h
        | _ -> Array.fold_left (fun t (it : Flex_layout.item) -> t +. it.base) 0. fitems +. (gap_main *. float_of_int (max 0 (Array.length fitems - 1)))
      in
      let sizes = Flex_layout.resolve ~room ~gap:gap_main fitems in
      let starts = Flex_layout.place ~justify ~room ~gap:gap_main fitems sizes in
      ctx.cursor <- content_top +. (if Array.length sizes = 0 then 0. else room);
      Array.to_list
        (Array.mapi
           (fun k (_, cs, (b : box), x_offset, again) ->
             let (mt, mb), _, _ = chrome cs in
             let b = match again with Some lay when (not measuring) && Float.abs (sizes.(k) -. mt -. mb -. b.height) > 0.5 -> lay (sizes.(k) -. mt -. mb) | _ -> b in
             relative ctx cs (moved (ctx.x +. x_offset -. b.x) (content_top +. starts.(k) +. mt -. b.y) { b with height = sizes.(k) -. mt -. mb }))
           laid))
  in
  ctx.children <- List.rev boxes;
  ctx.pending <- 0.

(* a grid container's items laid out (Box_grid, over
 * Grid_layout's arithmetic), which asks here for what is the
 * recursion's: an item laid out as a block, its content measured *)
and grid_children (ctx : ctx) (e : Dom.element) (s : Computed.t) : unit =
  let env = ctx.env in
  Box_grid.children ctx e s
    ~lay_out:(fun c cs ~x ~y ~width ~content -> fst (layout_block env (ref []) c cs ~cb_x:x ~cb_width:width ~y ~marker:None ?content ()))
    ~measure:(fun c cs ~available -> shrink env c cs ~available)
    ~absolute:(add_absolute ctx) ~relative:(relative ctx)

(* shrink-to-fit (CSS 2.1 section 10.3.5): the content's widest line,
 * at most [available], at least its widest word *)
and shrink (env : env) (e : Dom.element) (s : Computed.t) ~(available : float) : float =
  let env = { env with measuring = true; known_height = None } in
  let s' = { s with width = Auto; min_width = Css_values.zero; max_width = Auto; margin = (Len Css_values.zero, Len Css_values.zero, Len Css_values.zero, Len Css_values.zero) } in
  let _, _, _, pl = four (fun l -> Css_values.resolve l 0.) s.padding and _, _, _, bl = s.border_width in
  (* before the memo (a Wikipedia article: 89,903 blocks laid out, 88,200
   * of them measuring, each measure measuring its subtree again, at each
   * level; notes_opti_ocaml.md section 11):
   *   let measure w =
   *     let b, _ = layout_block env (ref []) e s' ... ~content:w () in
   *     Float.max 0. (inner_right b -. b.x -. pl -. bl) *)
  let measure w =
    let key = Hashtbl.hash (Dom.hash e, w) in
    match List.find_opt (fun (e', d, w', _) -> e' == e && d = s.display && w' = w) (Hashtbl.find_all env.measured key) with
    | Some (_, _, _, r) -> r
    | None ->
        let b, _ = layout_block env (ref []) e s' ~cb_x:0. ~cb_width:1e6 ~y:0. ~marker:None ~content:w () in
        let r = Float.max 0. (inner_right b -. b.x -. pl -. bl) in
        Hashtbl.add env.measured key (e, s.display, w, r);
        r
  in
  let preferred = measure 1e6 in
  if preferred <= available then preferred else Float.max (measure 0.) available

(* a block placed in the flow, below what is stacked *)
and add_block (ctx : ctx) (e : Dom.element) (s : Computed.t) : unit =
  flush_inline ctx;
  let env = ctx.env in
  let mt = top_margin env e s ~cb_width:ctx.width in
  let _, _, mb, _ = s.margin in
  let mb = Option.value (size mb ctx.width) ~default:0. in
  let margin = if ctx.absorbed then 0. else collapse ctx.pending mt in
  let y = ctx.cursor +. margin in
  let y =
    match s.clear with
    | Side_none -> y
    | Side_left -> cleared !(ctx.floats) [ On_left ] y
    | Side_right -> cleared !(ctx.floats) [ On_right ] y
    | Side_both -> cleared !(ctx.floats) [ On_left; On_right ] y
  in
  let marker =
    if s.display <> List_item then None
    else (
      ctx.counter <- ctx.counter + 1;
      match s.list_style with
      | "none" -> None
      | "disc" | "circle" | "square" -> Some Html_layout.Bullet
      | _ -> Some (Number ctx.counter))
  in
  (* a formatting context of its own beside floats: narrowed *)
  let cb_x, cb_width = if own_context s then room !(ctx.floats) ~x:ctx.x ~width:ctx.width ~top:y ~height:1. else (ctx.x, ctx.width) in
  let box, through =
    match s.display with
    | Table -> (layout_table env e s ~cb_x ~cb_width ~y, 0.)
    | _ -> layout_block env ctx.floats e s ~cb_x ~cb_width ~y ~marker ()
  in
  (* in a <center>: a block narrower than the line, its margins not
   * auto, centred *)
  let box =
    let _, mr, _, ml = s.margin in
    if ctx.env.centring && (not ctx.env.measuring) && ml <> Auto && mr <> Auto && box.width < cb_width then moved (cb_x +. ((cb_width -. box.width) /. 2.) -. box.x) 0. box
    else box
  in
  let box = relative ctx s box in
  let empty = box.height = 0. && box.children = [] in
  ctx.children <- box :: ctx.children;
  if empty && not ctx.absorbed then ctx.pending <- collapse (collapse ctx.pending mt) (collapse mb through)
  else (
    ctx.cursor <- y +. box.height;
    ctx.pending <- collapse mb through;
    ctx.absorbed <- false)

(* transform: translate(...), the box moved once laid out, its percents
 * of its own size (a list whose rows are all at the top, each moved
 * down to its place: how an application draws thousands of them) *)
and translated (s : Computed.t) (b : box) : box =
  match s.translate with
  | None -> b
  | Some (x, y) -> moved (Css_values.resolve x b.width) (Css_values.resolve y b.height) b

(* position: relative, the box moved by its offsets; and a transform's
 * move *)
and relative (ctx : ctx) (s : Computed.t) (b : box) : box =
  let b = translated s b in
  if s.position <> Relative then b
  else
    let dx = match (size s.left ctx.width, size s.right ctx.width) with Some l, _ -> l | None, Some r -> -.r | None, None -> 0. in
    let dy = match (size s.top 0., size s.bottom 0.) with Some t, _ -> t | None, Some b -> -.b | None, None -> 0. in
    moved dx dy b

(* position: absolute or fixed, out of the flow *)
and add_absolute (ctx : ctx) (e : Dom.element) (s : Computed.t) : unit =
  let env = ctx.env in
  let cx, cy, cw, ch = match s.position with Fixed -> (0., 0., fst env.viewport, Some (snd env.viewport)) | _ -> env.containing in
  let static_x = ctx.x and static_y = ctx.cursor +. ctx.pending in
  let left = size s.left cw and right = size s.right cw in
  let _, _, _, ml = s.margin in
  let ml = Option.value (size ml cw) ~default:0. in
  let content =
    match (s.width, left, right) with
    | Auto, Some l, Some r ->
        let _, pr, _, pl = four (fun l -> Css_values.resolve l cw) s.padding and _, br, _, bl = s.border_width in
        Some (Float.max 0. (cw -. l -. r -. pl -. pr -. bl -. br))
    | Auto, _, _ -> Some (shrink env e s ~available:cw)
    | _ -> None
  in
  (* down: top and bottom are of the containing block's height, when
   * it is known; both said and no height, the box fills between them *)
  let top = size s.top (Option.value ch ~default:0.) and bottom = Option.bind ch (fun h -> size s.bottom h) in
  let height =
    match (s.height, top, bottom, ch) with
    | Computed.Auto, Some t, Some b, Some h -> Computed.Len { Css_values.zero with px = Float.max 0. (h -. t -. b) }
    | _ -> s.height
  in
  let filling = height != s.height in
  let s_in = { s with height; border_box = s.border_box || filling; margin = (let t, r, b, _ = s.margin in (t, r, b, Len Css_values.zero)) } in
  let env = { env with known_height = ch } in
  (* a positioned <svg> is a picture still, a box of one line: its
   * percents of the window if it is fixed (a Playground program's
   * page is one svg, 100% by 100%) *)
  let box =
    if e.name = "svg" then picture_box ctx e s ~src:"" (svg_size ctx e s ~within:(cw, match s.position with Fixed -> snd env.viewport | _ -> 0.))
    else fst (layout_block env (ref []) e s_in ~cb_x:0. ~cb_width:cw ~y:0. ~marker:None ?content ())
  in
  let x = match (left, right) with Some l, _ -> cx +. l +. ml | None, Some r -> cx +. cw -. r -. box.width | None, None -> static_x +. ml in
  let y =
    match (top, bottom, ch) with
    | Some t, _, _ -> cy +. t
    | None, Some b, Some h -> cy +. h -. b -. box.height
    | _ -> static_y
  in
  (* by its bottom alone, in a height not known yet: left where it is,
   * and said so (layout_block moves it when it knows) *)
  let late = match (top, ch, size s.bottom 0.) with None, None, Some b -> Some b | _ -> None in
  let dx, dy =
    match s.translate with
    | None -> (x -. box.x, y -. box.y)
    | Some (tx, ty) -> (x -. box.x +. Css_values.resolve tx box.width, y -. box.y +. Css_values.resolve ty box.height)
  in
  if late <> None then incr env.late;
  ctx.env.positioned := (moved dx dy box, late) :: !(ctx.env.positioned)

(* a float, laid out shrink-to-fit where it is, placed with the lines *)
and float_item (ctx : ctx) (e : Dom.element) (s : Computed.t) : item =
  let env = ctx.env in
  let margin = four (fun m -> Option.value (size m ctx.width) ~default:0.) s.margin in
  let box =
    if e.name = "img" then image_box ctx e s
    else
      let content = match s.width with Auto -> Some (shrink env e s ~available:ctx.width) | _ -> None in
      let s_in = { s with margin = (Len Css_values.zero, Len Css_values.zero, Len Css_values.zero, Len Css_values.zero) } in
      fst (layout_block env (ref []) e s_in ~cb_x:0. ~cb_width:ctx.width ~y:0. ~marker:None ?content ())
  in
  (* measuring: every float on the left -- only its width counts, and a
   * right one would be at the far end of an unlimited line *)
  let fside = if s.float = Side_right && not env.measuring then On_right else On_left in
  Float { fbox = box; fside; fmargin = margin; placed = false }

(* a picture's size: its style's width and height, one of them and its
 * ratio, or its own once it has come; max-width applied *)
and picture_size (ctx : ctx) (e : Dom.element) (s : Computed.t) : (float * float) option =
  let src = Option.value (picture_src e) ~default:"" in
  (* a height in percents is of the block's when that is known, else
   * auto: the picture's own ratio (CSS 2.1 section 10.5) *)
  let h = match (s.height, ctx.env.known_height) with Len l, k when l.pct <> 0. && (k = None || ctx.env.measuring) -> None | sz, k -> size sz (Option.value k ~default:0.) in
  let w = size s.width ctx.width in
  let own = ctx.env.picture_size src in
  let wh =
    match (w, h, own) with
    | Some w, Some h, _ -> Some (w, h)
    | Some w, None, Some (iw, ih) when iw > 0. -> Some (w, w *. ih /. iw)
    | None, Some h, Some (iw, ih) when ih > 0. -> Some (h *. iw /. ih, h)
    | None, None, Some wh -> Some wh
    | _ -> None
  in
  match (wh, size s.max_width ctx.width) with
  | Some (w, h), Some m when w > m && w > 0. -> Some (m, h *. m /. w)
  | _ -> wh

and svg_size ?within (ctx : ctx) (e : Dom.element) (s : Computed.t) : float * float =
  let cw, ch = Option.value within ~default:(ctx.width, 0.) in
  let view_box =
    match Option.map (fun v -> List.filter_map float_of_string_opt (String.split_on_char ' ' (String.map (fun c -> if c = ',' then ' ' else c) v))) (Dom.attribute "viewbox" e) with
    | Some [ _; _; w; h ] when w > 0. && h > 0. -> Some (w, h)
    | _ -> None
  in
  (* a height in percents: of the block's when that is known, else
   * auto, as a picture's *)
  let h = match (s.height, within, ctx.env.known_height) with
    | Len l, None, k when l.pct <> 0. -> if ctx.env.measuring then None else Option.map (Css_values.resolve l) k
    | sz, _, _ -> size sz ch
  in
  match (size s.width cw, h, view_box) with
  | Some w, Some h, _ -> (w, h)
  | Some w, None, Some (vw, vh) -> (w, w *. vh /. vw)
  | None, Some h, Some (vw, vh) -> (h *. vw /. vh, h)
  | None, None, Some wh -> wh
  | Some w, None, None -> (w, 150.)
  | None, Some h, None -> (300., h)
  | None, None, None -> (300., 150.)

(* a floated picture as a box of one line *)
and image_box (ctx : ctx) (e : Dom.element) (s : Computed.t) : box =
  picture_box ctx e s ~src:(Option.value (picture_src e) ~default:"") (Option.value (picture_size ctx e s) ~default:(0., 0.))

and picture_box (ctx : ctx) (e : Dom.element) (s : Computed.t) ~(src : string) ((w, h) : float * float) : box =
  let ws = word_style s ~link:ctx.link in
  let frag : Html_layout.fragment =
    { text = ""; look = ws.look; x = 0.; width = w; baseline = h; picture = Some { src; height = h; middle = false }; control = None; element = e }
  in
  { element = Some e; style = s; x = 0.; y = 0.; width = w; height = h; border = (0., 0., 0., 0.); children = [];
    lines = [ { top = 0.; height = h; baseline = h; fragments = [ frag ]; anchors = [] } ]; backdrops = []; marker = None; lifted = [] }

(* a node inside a block: inline content gathered, a block placed *)
and walk (ctx : ctx) (parent : Computed.t) (ws : word_style) (node : Dom.node) : unit =
  match node with
  | Text t -> add_text ctx parent ws t
  | Element e -> (
      let s = ctx.env.style e in
      match s.display with
      | Display_none -> ()
      (* a form's control is one, positioned or not (its options are not
       * text of the page: Wikipedia's absolute <select>) *)
      | _ when (e.name = "select" || e.name = "textarea") && (s.position = Absolute || s.position = Fixed || s.float <> Side_none) -> (
          let look = look_of s ~link:ctx.link in
          match Html_layout.control_size ctx.env.metrics look e with
          | Some (w, h) when s.visible -> add_word ctx (word_style s ~link:ctx.link) ~glue:false "" w ~owner:e ~boxed:(Ctl { element = e; control_height = h })
          | _ -> ())
      | _ when s.position = Absolute || s.position = Fixed -> add_absolute ctx e s
      | _ when s.float <> Side_none -> ctx.items <- float_item ctx e s :: ctx.items
      | Contents -> List.iter (walk ctx s (word_style s ~link:ctx.link)) (ctx.env.kids e)
      | _ when e.name = "video" || e.name = "audio" ->
          (* a player's box: a video's size its style's (its width= and
           * height=, one of them at 4:3), else 320 by 240; an audio's
           * controls 300 by 32 (the browser draws what plays in it) *)
          let w, h =
            if e.name = "audio" then (Option.value (size s.width ctx.width) ~default:300., 32.)
            else
              match (size s.width ctx.width, size s.height 0.) with
              | Some w, Some h -> (w, h)
              | Some w, None -> (w, w *. 3. /. 4.)
              | None, Some h -> (h *. 4. /. 3., h)
              | None, None -> (320., 240.)
          in
          add_word ctx (word_style s ~link:ctx.link) ~glue:false "" w ~owner:e ~boxed:(Pic { src = ""; height = h; middle = s.vertical_align = Middle })
      | _ when e.name = "svg" ->
          (* a picture drawn from its own tree (Browser_boxes): its
           * size its style's (its width= and height=), else its
           * viewBox's, else CSS's 300 by 150 *)
          let w, h = svg_size ctx e s in
          add_word ctx (word_style s ~link:ctx.link) ~glue:false "" w ~owner:e
            ~boxed:(Pic { src = ""; height = h; middle = s.vertical_align = Middle })
      | _ when e.name = "img" -> (
          match picture_size ctx e s with
          | Some (w, h) ->
              let src = Option.value (picture_src e) ~default:"" in
              add_word ctx (word_style s ~link:ctx.link) ~glue:false "" w ~owner:e
                ~boxed:(Pic { src; height = h; middle = s.vertical_align = Middle })
          | None -> (
              match Dom.attribute "alt" e with
              | Some alt when String.trim alt <> "" -> add_text ctx s (word_style s ~link:ctx.link) alt
              | _ -> ()))
      | _ when (e.name = "input" || e.name = "select" || e.name = "textarea") -> (
          let look = look_of s ~link:ctx.link in
          match Html_layout.control_size ctx.env.metrics look e with
          | Some (w, h) when s.visible -> add_word ctx (word_style s ~link:ctx.link) ~glue:false "" w ~owner:e ~boxed:(Ctl { element = e; control_height = h })
          (* hidden (opacity: 0, a styled checkbox's): its room only *)
          | Some (w, _) -> add_word ctx (word_style s ~link:ctx.link) ~glue:false "" w ~owner:e
          | None -> ())
      | Inline -> (
          (match (if e.name = "a" then Dom.attribute "name" e else None) with Some n -> ctx.items <- Anchor n :: ctx.items | None -> ());
          (match Dom.attribute "id" e with Some id -> ctx.items <- Anchor id :: ctx.items | None -> ());
          match e.name with
          | "br" ->
              ctx.items <- Break :: ctx.items;
              (match s.clear with
              | Side_left -> ctx.items <- Clear [ On_left ] :: ctx.items
              | Side_right -> ctx.items <- Clear [ On_right ] :: ctx.items
              | Side_both -> ctx.items <- Clear [ On_left; On_right ] :: ctx.items
              | Side_none -> ());
              ctx.space <- false
          | _ ->
              let outer_owner = ctx.owner and outer_link = ctx.link in
              ctx.owner <- e;
              (if e.name = "a" then match Dom.attribute "href" e with Some h -> ctx.link <- Some h | None -> ());
              let ws = word_style s ~link:ctx.link in
              (* its margin, border and padding: spacers at its two
               * ends, joined to its first and last words; its box drawn
               * under its words if it has a background or a border *)
              let _, pr, _, pl = four (fun l -> Css_values.resolve l ctx.width) s.padding and bt, br, bb, bl = s.border_width in
              let _, mr, _, ml = four (fun m -> Option.value (size m ctx.width) ~default:0.) s.margin in
              let outer_decorations = ctx.decorations in
              if s.background.a > 0. || bt +. br +. bb +. bl > 0. then ctx.decorations <- ctx.decorations @ [ { de = e; ds = s; dml = ml; dmr = mr } ];
              if ml +. bl +. pl > 0. then add_word ctx ws ~edge:Lead ~glue:false "" (ml +. bl +. pl);
              List.iter (walk ctx s ws) (ctx.env.kids e);
              if mr +. br +. pr > 0. then (
                let space = ctx.space in
                ctx.space <- false;
                add_word ctx ws ~edge:Trail ~glue:false "" (mr +. br +. pr);
                ctx.space <- space);
              ctx.decorations <- outer_decorations;
              ctx.owner <- outer_owner;
              ctx.link <- outer_link)
      | Inline_block | Inline_flex ->
          let margin = four (fun m -> Option.value (size m ctx.width) ~default:0.) s.margin in
          let mt, mr, mb, ml = margin in
          let content = match s.width with Auto -> Some (shrink ctx.env e s ~available:(ctx.width -. ml -. mr)) | _ -> None in
          let s_in = { s with margin = (Len Css_values.zero, Len Css_values.zero, Len Css_values.zero, Len Css_values.zero) } in
          let ib, _ = layout_block ctx.env (ref []) e s_in ~cb_x:0. ~cb_width:ctx.width ~y:0. ~marker:None ?content () in
          let outer = ctx.link in
          (if e.name = "a" then match Dom.attribute "href" e with Some h -> ctx.link <- Some h | None -> ());
          add_word ctx (word_style s ~link:ctx.link) ~glue:false "" (ml +. ib.width +. mr) ~owner:e ~boxed:(Inline { ib; ml; mt; mb });
          ctx.link <- outer
      | Block | List_item | Flex | Grid | Table | Table_row_group | Table_row | Table_cell | Table_caption -> add_block ctx e s)

(* a table (CSS 2.1 chapter 17, the automatic layout): Table_layout's
 * grid and widths, each cell measured at width 0 and without limit,
 * each row as tall as its tallest cell *)
and layout_table (env : env) (table : Dom.element) (s : Computed.t) ~(cb_x : float) ~(cb_width : float) ~(y : float) : box =
  (* measuring: a percentage width is auto, as a block's (layout_block) *)
  let s = match s.width with Len l when env.measuring && l.pct <> 0. -> { s with width = Auto } | _ -> s in
  let cells, _ = Table_layout.grid table in
  (* the cells shown (not display: none: GitHub's small screens' cells),
   * their columns counted again without the others *)
  (* and the rows shown: Hacker News folds a thread by display: none on
   * its replies' rows *)
  let hidden_rows =
    let rec rows (e : Dom.element) =
      List.concat_map
        (fun (n : Dom.node) ->
          match n with
          | Element ({ name = "tr"; _ } as tr) -> [ tr ]
          | Element ({ name = "thead" | "tbody" | "tfoot"; _ } as g) -> rows g
          | _ -> [])
        e.children
    in
    List.filter (fun tr -> (env.style tr).display = Display_none) (rows table)
  in
  let in_hidden_row (c : Table_layout.cell) =
    List.exists (fun (tr : Dom.element) -> List.exists (fun (n : Dom.node) -> match n with Element td -> td == c.element | Text _ -> false) tr.children) hidden_rows
  in
  let cells = List.filter (fun (c : Table_layout.cell) -> (env.style c.element).display <> Display_none && not (in_hidden_row c)) cells in
  let cells =
    List.rev
      (snd
         (List.fold_left
            (fun ((row, column), acc) (c : Table_layout.cell) ->
              let column = if c.row = row then column else 0 in
              ((c.row, column + c.span), { c with column } :: acc))
            ((-1, 0), []) cells))
  in
  let n = List.fold_left (fun n (c : Table_layout.cell) -> max n (c.column + c.span)) 0 cells in
  if cells = [] then fst (layout_block env (ref []) table { s with display = Block } ~cb_x ~cb_width ~y ~marker:None ())
  else
    let spacing =
      match (Option.bind (Dom.attribute "cellspacing" table) float_of_string_opt, s.border_spacing) with
      | Some sp, _ when sp >= 0. -> sp
      | _, Some sp -> sp
      | _ -> 2.
    in
    let bt, br, bb, bl = s.border_width in
    let _, pr, _, pl = four (fun l -> Css_values.resolve l cb_width) s.padding in
    let style_of (c : Table_layout.cell) = env.style c.element in
    (* a cell's chrome: its padding and border, across *)
    let chrome (cs : Computed.t) =
      let _, pr, _, pl = four (fun l -> Css_values.resolve l 0.) cs.padding and _, br, _, bl = cs.border_width in
      pl +. pr +. bl +. br
    in
    let cell_box (c : Table_layout.cell) ~x ~width ~y =
      let cs = style_of c in
      let cs = { cs with width = Auto; margin = (Len Css_values.zero, Len Css_values.zero, Len Css_values.zero, Len Css_values.zero) } in
      fst (layout_block env (ref []) c.element cs ~cb_x:x ~cb_width:width ~y ~marker:None ~content:(Float.max 0. (width -. chrome cs)) ())
    in
    let measured =
      List.map
        (fun (c : Table_layout.cell) ->
          let cs = style_of c in
          let lo = shrink env c.element cs ~available:0. +. chrome cs and hi = shrink env c.element cs ~available:1e6 +. chrome cs in
          (* a cell's width= (a hint) is its minimum *)
          let asked = match size cs.width cb_width with Some w -> w | None -> 0. in
          (c, (Float.max lo asked, Float.max hi (Float.max lo asked))))
        cells
    in
    let columns = Table_layout.columns n measured ~spacing in
    let frame = bl +. pl +. pr +. br +. (spacing *. float_of_int (n + 1)) in
    let asked = Option.map (fun w -> if s.border_box then w else w +. bl +. pl +. pr +. br) (size s.width cb_width) in
    let room = Option.value asked ~default:cb_width -. frame in
    let widths =
      if s.table_fixed && asked <> None then (
        (* the first row's cells say the columns; one no cell is in has none *)
        let first = Array.make n (Some 0.) and top = List.fold_left (fun r (c : Table_layout.cell) -> min r c.row) max_int cells in
        List.iter
          (fun (c : Table_layout.cell) ->
            if c.row = top then
              let w = Option.map (fun w -> w /. float_of_int c.span) (size (style_of c).width room) in
              for i = c.column to c.column + c.span - 1 do first.(i) <- w done)
          cells;
        Table_layout.fixed ~room first)
      else Table_layout.widths ~room ~fixed:(asked <> None) columns
    in
    let width = Array.fold_left ( +. ) frame widths in
    let _, mr, _, ml = s.margin in
    let x =
      match (size ml cb_width, size mr cb_width) with
      | None, None -> cb_x +. Float.max 0. ((cb_width -. width) /. 2.)
      | None, Some mr -> cb_x +. cb_width -. width -. mr
      | Some ml, _ -> cb_x +. ml
    in
    let sum i j = let t = ref 0. in for k = i to j - 1 do t := !t +. widths.(k) done; !t in
    let column_x i = x +. bl +. pl +. spacing +. sum 0 i +. (spacing *. float_of_int i) in
    let cell_width (c : Table_layout.cell) = sum c.column (c.column + c.span) +. (spacing *. float_of_int (c.span - 1)) in
    let caption =
      Option.map
        (fun e -> fst (layout_block env (ref []) e (env.style e) ~cb_x:x ~cb_width:width ~y ~marker:None ()))
        (Table_layout.caption table)
    in
    let top = match caption with Some c -> y +. c.height | None -> y in
    (* the rows, in Table_layout's order (an empty one too: Hacker News'
     * spacers), for their heights and backgrounds *)
    let trs =
      let rec trs (e : Dom.element) =
        List.concat_map
          (fun (n : Dom.node) ->
            match n with
            | Element ({ name = "tr"; _ } as tr) -> [ tr ]
            | Element ({ name = "thead" | "tbody" | "tfoot"; _ } as g) -> trs g
            | _ -> [])
          e.children
      in
      Array.of_list (trs table)
    in
    let rows = List.fold_left (fun m (c : Table_layout.cell) -> max m (c.row + 1)) (Array.length trs) cells in
    let tr_of (c : Table_layout.cell) = if c.row < Array.length trs then Some trs.(c.row) else None in
    let row_top = ref (top +. bt +. spacing) and boxes = ref [] in
    for r = 0 to rows - 1 do
      let row = List.filter (fun (c : Table_layout.cell) -> c.row = r) cells in
      let laid = List.map (fun c -> (c, cell_box c ~x:(column_x c.column) ~width:(cell_width c) ~y:0.)) row in
      let row_height = List.fold_left (fun m (_, (b : box)) -> Float.max m b.height) 0. laid in
      (* a cell's height *)
      let row_height =
        List.fold_left (fun m ((c : Table_layout.cell), _) -> match size (style_of c).height 0. with Some h -> Float.max m h | None -> m) row_height laid
      in
      (* and the row's own (Hacker News' spacer rows, height: 5px) *)
      let row_height =
        match (if r < Array.length trs then size (env.style trs.(r)).height 0. else None) with
        | Some h -> Float.max row_height h
        | None -> row_height
      in
      List.iter
        (fun ((c : Table_layout.cell), (b : box)) ->
          let cs = style_of c in
          let offset = match cs.vertical_align with Top | Baseline | Text_top -> 0. | Bottom | Text_bottom -> row_height -. b.height | _ -> (row_height -. b.height) /. 2. in
          let b = moved 0. (!row_top +. offset) b in
          (* the cell's box is its rectangle, its row's background if
           * it has none *)
          let style =
            match tr_of c with
            | Some tr when b.style.background.a = 0. -> { b.style with background = (env.style tr).background }
            | _ -> b.style
          in
          boxes := { b with y = !row_top; height = row_height; style } :: !boxes)
        laid;
      (* the row's own box, for its borders top and bottom (a table
       * whose borders collapse: a list's lines between its rows); its
       * background is its cells' already *)
      (if r < Array.length trs then
         let ts = env.style trs.(r) in
         let wt, _, wb, _ = ts.border_width in
         if wt > 0. || wb > 0. then
           boxes :=
             { element = Some trs.(r); style = { ts with background = { ts.background with a = 0. }; border_width = (wt, 0., wb, 0.) };
               x = x +. bl; y = !row_top; width = width -. bl -. br; height = row_height; border = (wt, 0., wb, 0.); children = []; lines = []; backdrops = []; marker = None; lifted = [] }
             :: !boxes);
      row_top := !row_top +. row_height +. spacing
    done;
    { element = Some table; style = s; x; y; width; height = !row_top +. bb -. y; border = (bt, br, bb, bl);
      children = Option.to_list caption @ List.rev !boxes; lines = []; backdrops = []; marker = None; lifted = [] }

let layout (metrics : Html_layout.metrics) ?(picture_size = fun _ -> None) ?(kids = fun (e : Dom.element) -> e.children) ~(viewport : float * float) (style : Dom.element -> Computed.t)
    (root : Dom.element) : box =
  let env = { metrics; picture_size; style; kids; viewport; positioned = ref []; late = ref 0; measuring = false; centring = false; containing = (0., 0., fst viewport, Some (snd viewport)); known_height = Some (snd viewport);
      measured = Hashtbl.create 1024 } in
  let s = style root in
  (* the root is its own formatting context: its floats inside it *)
  let s = { s with overflow_hidden = true } in
  let page, _ = layout_block env (ref []) root s ~cb_x:0. ~cb_width:(fst viewport) ~y:0. ~marker:None () in
  (* the positioned boxes, wherever they were written, after the flow *)
  let rec gather (b : box) : box list = List.concat_map (fun (l, _) -> l :: gather l) b.lifted @ List.concat_map gather b.children in
  let positioned = gather page in
  let bottom = List.fold_left (fun m (b : box) -> Float.max m (b.y +. b.height)) page.height positioned in
  { page with height = bottom; children = page.children @ positioned }
