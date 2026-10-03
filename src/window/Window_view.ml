(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Window_view.mli *)
open Playground
open Window_model
open Window_layout (* the model read: where each part is *)

let resolve = Browser_url.resolve

(* Chrome 1.0 on Windows: the blue frame, the tab and toolbar light *)
let frame = Gui_kit.frame
let toolbar = Gui_kit.surface
let edge = Gui_kit.edge
let white = Gui_kit.white
let ink = Gui_kit.ink
let muted = Gui_kit.muted
let inspector_blue = Gui_kit.accent

(* the chrome's text, in cells (libs/gui) *)
let monospace = Gui_text.monospace

(* the status bubble: a link's address, or what is loading *)
let bubble (m : model) : shape list =
  let tab = current_tab m in
  let text =
    match (tab.state, hovered m) with
    | _, _ when m.inspecting -> Some "Inspect: click an element of the page"
    | Shown p, Some href -> Some (resolve p.url href)
    | Loading url, _ -> Some ("Waiting for " ^ url ^ "...")
    | Shown _, None when List.exists (fun u -> List.mem u tab.sheet_urls) tab.in_flight -> Some "Loading style sheets..."
    | Shown _, None when tab.in_flight <> [] -> Some "Loading pictures..."
    | _ -> None
  in
  match text with Some t -> Gui_text.bubble ~left:(left m) ~y:(area_bottom m +. 11.) t | None -> []

(* the page, and the element inspected outlined on it *)
let page_shapes (m : model) (p : Browser_page.t) : shape list =
  let tab = current_tab m in
  let scroll = float_of_int tab.scroll *. line_height and z = zoom_of m tab in
  (* the screen's dots for a unit of the page, said before any
   * of its letters is built below (the lines shown, the controls'
   * text, a player's time): each is a picture made for that density
   * (Glyph_picture); a Retina has two dots for each of the window's
   * points, which the platform draws on, not the program's scale *)
  Glyph_picture.density := z *. scale_of m *. m.dots;
  let outline =
    match (m.panel, m.selected) with
    | Elements, Some e -> (
        match Browser_devtools.box_of p e with
        | Some (x, y, w, h) ->
            Browser_draw.ready [ (y, y +. h, group [ rectangle inspector_blue w h |> fade 0.18 |> move (x +. (w /. 2.)) (-.(y +. (h /. 2.))); Browser_draw.frame inspector_blue x y w h ]) ]
        | None -> [])
    | _ -> []
  in
  (p.drawn
  @ Browser_draw.controls_drawn ~value:(Browser_page.value_of p) ~focus:tab.focus p.layout
  (* what plays in its <video>s and <audio>s, drawn at each frame *)
  @ Browser_media.draw ~now:m.time ~media:(fun u -> List.assoc_opt u tab.media) p
  @ outline)
  (* what the window shows of the page; a line's shapes are built
   * here, the first time it is shown (Browser_draw.later) *)
  |> Browser_draw.between ~top:scroll ~bottom:(scroll +. (area_height m /. z))
  |> group
  (* the page's units made the window's: zoomed, about its top left *)
  |> scale z
  |> move (area_left m) (area_top m +. (scroll *. z))
  |> fun s -> [ s ]

(* the developer tools: the header, then the view's lines *)
let panel (m : model) : shape list =
  let tab = current_tab m in
  let lines ~x ~max (ls : Browser_devtools.line list) =
    let rows = int_of_float ((panel_height m -. 20.) /. 14.) - 1 in
    List.concat
      (List.mapi
         (fun i ((text, (r, g, b)) : Browser_devtools.line) -> if i >= rows then [] else monospace ~max x (panel_header_y m -. 18. -. (14. *. float_of_int i)) (rgb r g b) text)
         ls)
  in
  let header name x active = [ rectangle (if active then white else toolbar) 60. 16. |> move (x +. 30.) (panel_header_y m) ] @ monospace (x +. 4.) (panel_header_y m) ink name in
  (* the characters a line of [w] units holds: a whole line of
   * the panel, or one of its two halves *)
  let chars w = int_of_float (w /. cell) in
  let x = left m +. 10. and half = chars ((width m /. 2.) -. 20.) in
  let body =
    match (m.panel, tab.state, m.selected) with
    | Network, _, _ -> lines ~x ~max:(chars (width m -. 40.)) (Browser_devtools.network tab.requests ~times:(fun url -> List.assoc_opt url (current m).times))
    | Elements, Shown p, Some e ->
        lines ~x ~max:half (Browser_devtools.element p e)
        @ [ rectangle edge 1. (panel_height m -. 20.) |> move 0. (panel_top m -. 20. -. ((panel_height m -. 20.) /. 2.)) ]
        @ lines ~x:6. ~max:half (Browser_devtools.styles (Window_tabs.settings m tab) p e)
    | Elements, _, _ -> lines ~x ~max:120 [ ("Click Inspect, then an element of the page.", (110, 110, 110)) ]
    | Closed, _, _ -> []
  in
  [ rectangle (rgb 250 250 250) (width m) (panel_height m) |> move_y (panel_top m -. (panel_height m /. 2.)); rectangle edge (width m) 1. |> move_y (panel_top m);
    rectangle toolbar (width m) 22. |> move_y (panel_header_y m) ]
  @ [ rectangle (if m.inspecting then inspector_blue else toolbar) 60. 16. |> move (x +. 30.) (panel_header_y m) ]
  @ monospace (x +. 4.) (panel_header_y m) (if m.inspecting then white else ink) "Inspect"
  @ header "Elements" (x +. 80.) (m.panel = Elements)
  @ header "Network" (x +. 160.) (m.panel = Network)
  @ body

let view_unscaled (m : model) : shape list =
  let tab = current_tab m in
  let body = match tab.state with Shown p -> page_shapes m p | Loading _ -> [] in
  let background = match tab.state with Shown { background = Some (r, g, b); _ } -> rgb r g b | _ -> white in
  (* the zoom, when not 100%, left of "JS" *)
  let percent = Browser_zoom.label (zoom_of m tab) in
  [ rectangle background (width m) (height m) ]
  @ body
  @ (let bar = Window_tabs.scrollbar m in
     Gui_scrollbar.shapes bar ~lit:(m.grab <> None || Gui_scrollbar.at bar m.mouse <> None))
  (* the chrome over what overflows *)
  @ [ rectangle frame (width m) 44. |> move_y (top m -. 22.);
      rectangle toolbar (width m) 42. |> move_y (area_top m +. 21.);
      rectangle edge (width m) 1. |> move_y (area_top m) ]
  @ Gui_tabs.shapes (strip m) ~time:m.time
  @ Gui_toolbar.shapes (buttons m)
  @ Omnibox.shapes (omnibox m)
  @ monospace (js_x m -. (cell *. float_of_int (String.length percent + 1))) (toolbar_y m) muted percent
  @ (let on = tab.script <> None in
     [ rectangle (if on then inspector_blue else rgb 200 204 210) 22. 16. |> move (js_x m +. 11.) (toolbar_y m) ]
     @ monospace (js_x m +. 5.) (toolbar_y m) white "JS")
  (* the wrench: Chrome's one menu, here the developer tools *)
  @ [ rectangle (if m.panel <> Closed then inspector_blue else rgb 70 90 120) 4. 18. |> rotate 45. |> move (wrench_x m) (toolbar_y m);
      circle (if m.panel <> Closed then inspector_blue else rgb 70 90 120) 5. |> move (wrench_x m -. 5.) (toolbar_y m +. 5.) ]
  @ (if m.panel <> Closed then panel m else [])
  @ bubble m
  @ (match m.menu with Some menu -> Gui_menu.shapes menu ~pointer:m.mouse | None -> [])

(* the window, its units made the screen's dots *)
let view_simple (m : model) : shape list = [ group (view_unscaled m) |> scale (scale_of m) ]

(*****************************************************************************)
(* The same view for the same model *)
(*****************************************************************************)

(* opti: see Window_view.mli. Whether the window moves by itself:
 * a tab's wheel turning while it loads, a video playing -- what the
 * view draws from the model's [time] *)
let animated (m : model) : bool =
  List.exists (fun (t : tab) -> loading t.tab) m.tabs
  || match (current_tab m).state with Shown p -> Browser_media.plays p | Loading _ -> false

(* the two models draw the same window: each field is the very value it
 * was (==), but the time. Every field is named, so that a new one is a
 * warning here until it is said whether the view reads it *)
let same_but_time
    ({ tabs; current; next_id; omnibox; mouse; time = _; css; panel; inspecting; selected; engine; allowed; fetches; screen; ctrl; profile;
       profile_dir; saved; changed; menu; window; desktop; dots; shift; grab; selecting; last_click = _; pressed = _ } :
      model) (m : model) : bool =
  tabs == m.tabs && current == m.current && next_id == m.next_id && omnibox == m.omnibox && mouse == m.mouse && css == m.css
  && panel == m.panel && inspecting == m.inspecting && selected == m.selected && engine == m.engine && allowed == m.allowed
  && fetches == m.fetches && screen == m.screen && ctrl == m.ctrl && profile == m.profile && profile_dir == m.profile_dir
  && saved == m.saved && changed == m.changed && menu == m.menu && window == m.window && desktop == m.desktop && dots == m.dots && shift == m.shift
  && grab == m.grab && selecting == m.selecting

(* the last model drawn, its shapes, and whether it moves by itself
 * (asked once a model, not once a frame: it reads the page's every
 * fragment, 3 ms on a long one) *)
let last : (model * shape list * bool) option ref = ref None

let view_opti (m : model) : shape list =
  match !last with
  | Some (m', shapes, false) when same_but_time m' m -> shapes
  | Some (m', _, true) when same_but_time m' m -> view_simple m
  | _ ->
      let shapes = view_simple m in
      last := Some (m, shapes, animated m);
      shapes

let view (m : model) : shape list = if !Mini_opti.enabled then view_opti m else view_simple m
