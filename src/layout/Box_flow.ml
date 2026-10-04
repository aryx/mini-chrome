(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Box_flow.mli *)
open Box_types

(*****************************************************************************)
(* Sizes and margins *)
(*****************************************************************************)

(* a size in pixels, a percentage of [base]; auto None *)
let size (s : Computed.size) (base : float) : float option =
  match s with Auto -> None | Len l -> Some (Css_values.resolve l base)

(* a box that lays out its own content apart: its floats its own, its
 * margins not collapsed with its children's *)
let own_context (s : Computed.t) : bool =
  s.overflow_hidden || s.float <> Side_none
  || (match s.position with Absolute | Fixed -> true | _ -> false)
  || match s.display with Inline_block | Inline_flex | Flex | Grid | Table_cell | Table | Table_caption -> true | _ -> false

(* the larger margin, a negative one subtracted (CSS 2.1 section 8.3.1) *)
let collapse (a : float) (b : float) : float = if a >= 0. && b >= 0. then Float.max a b else if a <= 0. && b <= 0. then Float.min a b else a +. b

(*****************************************************************************)
(* A block's content *)
(*****************************************************************************)

let is_space (c : char) : bool = c = ' ' || c = '\n' || c = '\t' || c = '\r' || c = '\012'

let add_word ?boxed ?owner ?(edge = Body) (ctx : ctx) (ws : word_style) ~(glue : bool) (text : string) (width : float) : unit =
  let rec after_word items = match items with Word _ :: _ -> true | (Anchor _ | Float _) :: rest -> after_word rest | _ -> false in
  let space_before = ctx.space && after_word ctx.items in
  let space = if space_before then ctx.env.metrics ws.look " " else 0. in
  let owner = Option.value owner ~default:ctx.owner in
  ctx.items <-
    Word { text; ws; space_before; glue = glue && space_before; space; width; boxed; owner; decorations = ctx.decorations; edge } :: ctx.items;
  ctx.space <- false

(* U+00A0 (UTF-8's two bytes C2 A0) as a space *)
let nbsp_to_space (text : string) : string =
  let b = Buffer.create (String.length text) in
  let n = String.length text in
  let i = ref 0 in
  while !i < n do
    if !i + 1 < n && text.[!i] = '\xc2' && text.[!i + 1] = '\xa0' then (Buffer.add_char b ' '; i := !i + 2)
    else (Buffer.add_char b text.[!i]; incr i)
  done;
  Buffer.contents b

let add_text (ctx : ctx) (s : Computed.t) (ws : word_style) (text : string) : unit =
  let text = if s.uppercase then String.uppercase_ascii text else text in
  (* a no-break space (U+00A0, &nbsp;) joins two words, and is a space *)
  let word text =
    let text = if String.contains text '\xa0' then nbsp_to_space text else text in
    add_word ctx ws ~glue:(s.white_space = Nowrap) text (ctx.env.metrics ws.look text)
  in
  match s.white_space with
  | Pre | Pre_wrap ->
      List.iteri
        (fun i part ->
          if i > 0 then ctx.items <- Break :: ctx.items;
          if part <> "" then (
            ctx.space <- false;
            if s.white_space = Pre then word part
            else
              (* pre-wrap: the line's spaces kept, and it is cut where it
               * does not fit -- at a space, as words are; of several
               * spaces the first is the words' own, the others stay
               * with the word after them *)
              let n = String.length part in
              let rec pieces from ~first =
                if from < n then (
                  let j = ref from in
                  while !j < n && part.[!j] = ' ' do incr j done;
                  let spaces = !j - from in
                  while !j < n && part.[!j] <> ' ' do incr j done;
                  let kept = if first then spaces else max 0 (spaces - 1) in
                  ctx.space <- (not first) && spaces > 0;
                  word (String.make kept ' ' ^ String.sub part (from + spaces) (!j - from - spaces));
                  pieces !j ~first:false)
              in
              pieces 0 ~first:true))
        (String.split_on_char '\n' text)
  | Normal | Nowrap | Pre_line ->
      let b = Buffer.create 16 in
      let end_word () =
        if Buffer.length b > 0 then (
          word (Buffer.contents b);
          Buffer.clear b)
      in
      String.iter
        (fun c ->
          if c = '\n' && s.white_space = Pre_line then (
            end_word ();
            ctx.items <- Break :: ctx.items;
            ctx.space <- false)
          else if is_space c then (
            end_word ();
            ctx.space <- true)
          else Buffer.add_char b c)
        text;
      end_word ()

(* the block's inline content so far set on lines, in an anonymous box *)
let flush_inline (ctx : ctx) : unit =
  let items = List.rev ctx.items in
  ctx.items <- [];
  ctx.space <- false;
  if items <> [] then (
    let has_content = List.exists (fun i -> match i with Word _ | Break | Clear _ -> true | _ -> false) items in
    (* a float among blocks is placed below the margin pending *)
    let top = ctx.cursor +. if has_content then ctx.pending else 0. in
    let floats_top = ctx.cursor +. ctx.pending in
    let strut = Box_inline.word_style ctx.block ~link:None in
    let align = if ctx.env.measuring then Looks.Left else (Box_inline.look_of ctx.block ~link:None).align in
    let pre = ctx.block.white_space = Pre in
    let lines, boxes, backdrops, bottom =
      Box_inline.set_lines ctx.floats strut align ~pre ~x:ctx.x ~width:ctx.width ~top:(if has_content then top else floats_top) items
    in
    ctx.children <-
      { element = None; style = ctx.block; x = ctx.x; y = top; width = ctx.width; height = (if has_content then bottom -. top else 0.);
        border = (0., 0., 0., 0.); children = boxes; lines; backdrops; marker = None; lifted = [] }
      :: ctx.children;
    if has_content then (
      ctx.cursor <- bottom;
      ctx.pending <- 0.;
      ctx.absorbed <- false))

(* the first thing in an element's flow, if it is a block: whose top
 * margin collapses with the element's *)
let rec first_block (env : env) (e : Dom.element) : (Dom.element * Computed.t) option =
  let rec go (nodes : Dom.node list) =
    match nodes with
    | [] -> None
    | Text t :: rest -> if String.for_all is_space t then go rest else None
    | Element c :: rest -> (
        let s = env.style c in
        match s.display with
        | Display_none -> go rest
        | _ when s.float <> Side_none || s.position = Absolute || s.position = Fixed -> go rest
        | Contents -> ( match first_block env c with Some _ as found -> found | None -> go rest)
        | Inline | Inline_block | Inline_flex -> None
        | _ -> Some (c, s))
  in
  go e.children

let top_padding_border (s : Computed.t) : float =
  let t, _, _, _ = s.padding and bt, _, _, _ = s.border_width in
  Css_values.resolve t 0. +. bt

(* the margin above an element: its own collapsed with its first
 * child's, through no border and no padding *)
let rec top_margin (env : env) (e : Dom.element) (s : Computed.t) ~(cb_width : float) : float =
  let mt, _, _, _ = s.margin in
  let own = Option.value (size mt cb_width) ~default:0. in
  if own_context s || top_padding_border s > 0. then own
  else match first_block env e with Some (c, cs) -> collapse own (top_margin env c cs ~cb_width) | None -> own

(* the horizontal equation (CSS 2.1 section 10.3.3): margin-left,
 * content width, margin-right; [content] a width already decided
 * (shrink-to-fit, a table's cell) *)
let horizontal (s : Computed.t) ~(cb_width : float) ?content () : float * float * float =
  let _, mr, _, ml = s.margin in
  let _, pr, _, pl = Box_inline.four (fun l -> Css_values.resolve l cb_width) s.padding in
  let _, br, _, bl = s.border_width in
  let chrome = pl +. pr +. bl +. br in
  let clamp w =
    let w = match size s.max_width cb_width with Some m -> Float.min w (if s.border_box then m -. chrome else m) | None -> w in
    Float.max w ((if s.border_box then -.chrome else 0.) +. Css_values.resolve s.min_width cb_width)
  in
  let given = match content with Some w -> Some w | None -> Option.map (fun w -> if s.border_box then Float.max 0. (w -. chrome) else w) (size s.width cb_width) in
  (* a width decided: the margins auto share the rest *)
  let solved w =
    let rest = cb_width -. w -. chrome in
    match (size ml cb_width, size mr cb_width) with
    | None, None -> (Float.max 0. (rest /. 2.), w, Float.max 0. (rest /. 2.))
    | None, Some mr -> (rest -. mr, w, mr)
    | Some ml, None -> (ml, w, rest -. ml)
    | Some ml, Some _ -> (ml, w, rest -. ml)
  in
  match given with
  | None ->
      let ml' = Option.value (size ml cb_width) ~default:0. and mr' = Option.value (size mr cb_width) ~default:0. in
      let natural = Float.max 0. (cb_width -. ml' -. mr' -. chrome) in
      let w = clamp natural in
      (* max-width met: solved again with it as the width (10.4), so
       * that margins auto centre a column *)
      if w <> natural then solved w else (ml', natural, mr')
  | Some w -> solved (clamp w)
