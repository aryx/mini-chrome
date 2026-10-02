(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Browser_draw.mli *)
open Playground

type drawn = (float * float * shape Lazy.t) list

let ready (things : (float * float * shape) list) : drawn = List.map (fun (top, bottom, s) -> (top, bottom, Lazy.from_val s)) things

(* opti: a line's shapes built when the line is first shown
 * (between, below), not all the page's at each relayout: 450 ms to 28
 * on a long page. The whole story, with its picture, is in
 * Browser_draw.mli. The simple way is the other branch: the shape
 * built now, a value like any other (Lazy.from_val). *)
let later (shape : unit -> shape) : shape Lazy.t = if !Mini_opti.enabled then Lazy.from_fun shape else Lazy.from_val (shape ())

(* the culling; and the one place a promised shape is asked for *)
let between ~(top : float) ~(bottom : float) (things : drawn) : shape list =
  List.filter_map (fun (t, b, s) -> if b > top && t < bottom then Some (Lazy.force s) else None) things

let characters = Browser_text.characters
let metrics = Browser_text.metrics

let frame ?(t = 1.) (color : color) (x : float) (y : float) (w : float) (h : float) : shape =
  group
    [ rectangle color w t |> move (x +. (w /. 2.)) (-.(y +. (t /. 2.)));
      rectangle color w t |> move (x +. (w /. 2.)) (-.(y +. h -. (t /. 2.)));
      rectangle color t h |> move (x +. (t /. 2.)) (-.(y +. (h /. 2.)));
      rectangle color t h |> move (x +. w -. (t /. 2.)) (-.(y +. (h /. 2.))) ]

let raised (x : float) (top : float) (w : float) (h : float) : shape list =
  [ rectangle (rgb 205 205 205) w h |> move (x +. (w /. 2.)) (-.(top +. (h /. 2.)));
    frame (rgb 120 120 120) x top w h;
    frame (rgb 240 240 240) x top (w -. 1.) (h -. 1.) ]

let sunken (x : float) (top : float) (w : float) (h : float) : shape list =
  [ rectangle (rgb 255 255 255) w h |> move (x +. (w /. 2.)) (-.(top +. (h /. 2.)));
    frame (rgb 240 240 240) x top w h;
    frame (rgb 120 120 120) x top (w -. 1.) (h -. 1.) ]

(*****************************************************************************)
(* Words and pictures *)
(*****************************************************************************)

(* a picture in its place: its pixels, once arrived; the room kept for
 * it (its width= and height=) until then; NCSA's broken image when it
 * could not be had; in a link, a border of the link's colour, as
 * Mosaic drew it (the one way to tell a picture that is a link) *)
let picture_shapes (state : Browser_picture.t option) (color : color) (f : Html_layout.fragment) (pic : Html_layout.picture)
    : shape list =
  let w = f.width and h = pic.height in
  let top = if pic.middle then f.baseline -. (h /. 2.) else f.baseline -. h in
  let center = (f.x +. (w /. 2.), -.(top +. (h /. 2.))) in
  let body =
    match state with
    | Some (Arrived img) -> List.map (move (fst center) (snd center)) (Browser_picture.drawn w h img)
    | Some Broken ->
        (* a torn picture: a white card, a red slash across *)
        [ rectangle (rgb 245 245 245) w h |> move (fst center) (snd center);
          frame (rgb 90 90 90) f.x top w h;
          rectangle (rgb 200 30 30) (w *. 1.2) 2. |> rotate 45. |> move (fst center) (snd center) ]
    | Some Waiting | None ->
        (* the room kept: a sunken, empty frame *)
        [ frame (rgb 130 130 130) f.x top w h; frame (rgb 235 235 235) (f.x +. 1.) (top +. 1.) (w -. 2.) (h -. 2.) ]
  in
  body @ match f.look.link with Some _ -> [ frame ~t:2. color (f.x -. 2.) (top -. 2.) (w +. 4.) (h +. 4.) ] | None -> []

(* a fragment's colour: a visited link's is Mosaic's purple, and every
 * browser's since (or the page's vlink=) *)
let color_of ~(visited : string -> bool) (f : Html_layout.fragment) : int * int * int =
  match f.look.link with Some href when visited href -> f.look.visited_color | _ -> f.look.color

(* the lines under and through a line's words, one for each run
 * of neighbours that share it -- a link of several words is underlined
 * from its first letter to its last, the spaces between its words too,
 * as browsers draw it. Before, each letter drew its own piece
 * (Stroke_text.glyph), and a space, which has no letter, had none:
 *
 *     a short history of the web        a short history of the web
 *     - ----- ------- -- --- ---        --------------------------
 *
 * Two words are of one run when they are neighbours on the line, of
 * the same link, colour and size, on the same baseline: a link's
 * words, or a <u>'s. A picture or a control ends a run. *)
let decorations ?(visited = fun (_ : string) -> false) (fragments : Html_layout.fragment list) : shape list =
  let text (f : Html_layout.fragment) = f.picture = None && f.control = None && f.text <> "" in
  let lines (has : Looks.t -> bool) (draw : color -> Style.t -> x:float -> width:float -> baseline:float -> shape) : shape list =
    let together (a : Html_layout.fragment) (b : Html_layout.fragment) =
      a.look.link = b.look.link && a.baseline = b.baseline && a.look.size = b.look.size && a.look.bold = b.look.bold
      && color_of ~visited a = color_of ~visited b
    in
    (* the runs: a first word, and the last one joined to it so far *)
    let runs =
      List.fold_left
        (fun runs (f : Html_layout.fragment) ->
          if not (text f && has f.look) then None :: runs
          else
            match runs with
            | Some (first, last) :: rest when together last f -> Some (first, f) :: rest
            | runs -> Some (f, f) :: runs)
        [] fragments
    in
    List.filter_map
      (Option.map (fun ((first : Html_layout.fragment), (last : Html_layout.fragment)) ->
           let r, g, b = color_of ~visited first in
           draw (rgb r g b) (Browser_text.style_of first.look) ~x:first.x ~width:(last.x +. last.width -. first.x) ~baseline:(-.first.baseline)))
      runs
  in
  lines (fun l -> l.underline) Stroke_text.underline @ lines (fun l -> l.strike) Stroke_text.strike

let glyphs ?(visited = fun (_ : string) -> false) ?(picture_of = fun (_ : string) -> None) ?(decorated = true) (f : Html_layout.fragment) :
    shape list =
  (* the letters alone: their lines are the run's (decorations) *)
  let style = { (Browser_text.style_of f.look) with underline = false; strike = false } in
  let (r, g, b) = color_of ~visited f in
  let color = rgb r g b in
  let baseline = -.f.baseline in
  (if decorated then decorations ~visited [ f ] else [])
  @
  match (f.picture, f.control) with
  | Some pic, _ -> picture_shapes (picture_of pic.src) color f pic
  (* a form's control: drawn with its value every frame (control_shapes) *)
  | None, Some _ -> []
  | None, None ->
      if f.look.monospace then
        let cell = Browser_text.cell_of f.look in
        characters f.text
        |> List.mapi (fun i c ->
               if c = " " then []
               else
                 let w = Stroke_text.metrics style c in
                 Stroke_text.glyph color style c ~x:(f.x +. (cell *. float_of_int i) +. ((cell -. w) /. 2.)) ~baseline)
        |> List.concat
      else
        let _, shapes =
          List.fold_left
            (fun (x, shapes) c -> (x +. Stroke_text.metrics style c, Stroke_text.glyph color style c ~x ~baseline :: shapes))
            (f.x, []) (characters f.text)
        in
        List.concat (List.rev shapes)

(*****************************************************************************)
(* Form controls *)
(*****************************************************************************)

(* text in a control: black, plain, fixed-width if [cells] *)
let text_shapes ?(cells = false) (look : Looks.t) (text : string) ~(x : float) ~(baseline : float) : shape list =
  let look = { look with color = (0, 0, 0); underline = false; link = None; bold = false; italic = false; monospace = cells } in
  glyphs { text; look; x; width = metrics look text; baseline; picture = None; control = None; element = Dom.element "span" [] }

let control_shapes ~(value : Dom.element -> Forms.value) ~(focused : bool) (f : Html_layout.fragment) (c : Html_layout.control)
    : shape list =
  match Forms.control c.element with
  | None -> []
  | Some control -> (
      let v = value c.element in
      let w = f.width and h = c.control_height and size = f.look.size in
      let top = f.baseline -. (0.75 *. h) and cell = Browser_text.cell_of f.look in
      let tail = Browser_text.tail in
      let caret x baseline = if focused then [ rectangle (rgb 0 0 0) 1.5 size |> move x (-.(baseline -. (0.35 *. size))) ] else [] in
      match control.kind with
      | Text | Password ->
          let shown = if control.kind = Password then String.make (List.length (characters v.text)) '*' else v.text in
          let shown = tail (int_of_float ((w -. 8.) /. cell) - 1) shown in
          sunken f.x top w h
          @ text_shapes ~cells:true f.look shown ~x:(f.x +. 4.) ~baseline:f.baseline
          @ caret (f.x +. 4. +. (cell *. float_of_int (List.length (characters shown)))) f.baseline
      | Checkbox ->
          (* Motif's toggle: a square, sunken and filled when on *)
          if v.checked then
            sunken f.x top w h
            @ [ rectangle (rgb 60 60 60) (w *. 0.5) (h *. 0.5) |> move (f.x +. (w /. 2.)) (-.(top +. (h /. 2.))) ]
          else raised f.x top w h
      | Radio ->
          (* Motif's radio button: a diamond, filled when on *)
          let center = (f.x +. (w /. 2.), -.(top +. (h /. 2.))) in
          let diamond color side = rectangle color side side |> rotate 45. |> move (fst center) (snd center) in
          [ diamond (rgb 120 120 120) (w *. 0.72); diamond (if v.checked then rgb 60 60 60 else rgb 225 225 225) (w *. 0.5) ]
      | Submit | Reset | Button ->
          let label = Forms.label control in
          raised f.x top w h @ text_shapes f.look label ~x:(f.x +. ((w -. metrics f.look label) /. 2.)) ~baseline:f.baseline
      | Select opts ->
          (* Motif's option menu: the choice, and its little bar *)
          let label = match List.nth_opt opts v.selected with Some (l, _) -> l | None -> "" in
          raised f.x top w h
          @ text_shapes f.look label ~x:(f.x +. (0.4 *. size)) ~baseline:f.baseline
          @ raised (f.x +. w -. (1.3 *. size)) (top +. (h /. 2.) -. (0.2 *. size)) (0.9 *. size) (0.4 *. size)
      | Textarea ->
          let rows = max 1 (int_of_float ((h -. 8.) /. (Looks.leading *. size))) in
          let lines = String.split_on_char '\n' v.text in
          let n = List.length lines in
          (* the last rows when typing into it, else the first *)
          let shown = List.filteri (fun i _ -> if focused then i >= n - rows else i < rows) lines in
          let baseline i = top +. 4. +. (0.95 *. size) +. (float_of_int i *. Looks.leading *. size) in
          let columns = int_of_float ((w -. 8.) /. cell) in
          sunken f.x top w h
          @ List.concat
              (List.mapi (fun i line -> text_shapes ~cells:true f.look (tail columns line) ~x:(f.x +. 4.) ~baseline:(baseline i)) shown)
          @ (match List.rev shown with
            | last :: _ ->
                caret (f.x +. 4. +. (cell *. float_of_int (List.length (characters (tail columns last))))) (baseline (List.length shown - 1))
            | [] -> [])
      | Hidden -> [])

(* opti: the controls of the last layout asked about, kept: as
 * Browser_media's players, they are found by reading the page's every
 * fragment, at each frame the view builds (3 ms of a scrolled frame on
 * a Wikipedia article, which has two). Their shapes are still built at
 * each frame: they change as one types. Before:
 *   Html_layout.fragments layout |> List.filter_map (fun f -> match f.control with Some c -> ... | None -> None) *)
let last_controls : (Html_layout.box * (Html_layout.fragment * Html_layout.control) list) option ref = ref None

let controls_of (layout : Html_layout.box) : (Html_layout.fragment * Html_layout.control) list =
  match !last_controls with
  | Some (l, controls) when l == layout -> controls
  | _ ->
      let controls =
        List.filter_map (fun (f : Html_layout.fragment) -> Option.map (fun c -> (f, c)) f.control) (Html_layout.fragments layout)
      in
      last_controls := Some (layout, controls);
      controls

let controls_drawn ~(value : Dom.element -> Forms.value) ~(focus : Dom.element option) (layout : Html_layout.box) : drawn =
  controls_of layout
  |> List.map (fun ((f : Html_layout.fragment), (c : Html_layout.control)) ->
         let focused = match focus with Some e -> e == c.element | None -> false in
         (f.baseline -. c.control_height, f.baseline +. c.control_height, group (control_shapes ~value ~focused f c)))
  |> ready

(*****************************************************************************)
(* The inspector *)
(*****************************************************************************)

let rec outlines (b : Html_layout.box) : drawn =
  let color = match b.kind with Anonymous -> rgb 0 150 0 | _ -> rgb 0 0 220 in
  ready
    ((b.y, b.y +. b.height, frame color b.x b.y b.width b.height)
    :: List.map (fun (l : Html_layout.line) -> (l.top, l.top +. l.height, frame (rgb 150 150 150) b.x l.top b.width l.height)) b.lines)
  @ List.concat_map outlines b.children
