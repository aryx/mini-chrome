(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Window_layout.mli *)
open Window_model

(*****************************************************************************)
(* The model's tabs and sites *)
(*****************************************************************************)

let home = "about:chrome"

let current (m : model) : tab = match List.find_opt (fun t -> t.id = m.current) m.tabs with Some t -> t | None -> List.hd m.tabs
let current_tab (m : model) : Browser_tab.t = (current m).tab

let current_url (m : model) : string = Browser_tab.current_url (current_tab m)

(* "news.ycombinator.com" of https://news.ycombinator.com/item?id=1 *)
let host_of (url : string) : string =
  match String.index_opt url ':' with
  | Some i when i + 3 <= String.length url && String.sub url (i + 1) 2 = "//" ->
      let rest = String.sub url (i + 3) (String.length url - i - 3) in
      let stop = List.fold_left (fun m c -> match String.index_opt rest c with Some j -> min m j | None -> m) (String.length rest) [ '/'; '?'; '#'; ':' ] in
      String.sub rest 0 stop
  | _ -> ""

(* a tab's zoom, its site's *)
let zoom_of (m : model) (tab : Browser_tab.t) : float = Browser_zoom.of_host m.profile.zooms (host_of (Browser_tab.current_url tab))

(* the scale everything is drawn at: the one chosen, else the
 * desktop's *)
let scale_of (m : model) : float = Option.value m.profile.scale ~default:m.desktop

let loading (tab : Browser_tab.t) : bool = (match tab.state with Loading _ -> true | Shown _ -> false) || tab.in_flight <> [] || tab.queue <> []

(*****************************************************************************)
(* The window's geometry *)
(*****************************************************************************)

(* the screen is the window, whatever its size (run_app
 * ~window's follows_window), the origin at its centre: everything is placed
 * from its edges -- the tabs and the toolbar hang from the top, the
 * panel sits on the bottom, the page takes what is left, the omnibox
 * stretches between the buttons and the wrench *)
let width (m : model) : float = fst m.screen
let height (m : model) : float = snd m.screen
let left (m : model) : float = -.(width m /. 2.)
let top (m : model) : float = height m /. 2.

(* the panel: its header, its two views' names, the Inspect button; at
 * the bottom, 370 high, less in a low window *)
let panel_height (m : model) : float = Float.min 370. (0.4 *. height m)
let panel_top (m : model) : float = panel_height m -. top m
let panel_header_y (m : model) : float = panel_top m -. 12.
let cell = Gui_text.cell

(* the page area, below the toolbar, above the panel if it is open *)
let area_top (m : model) : float = top m -. 86.
let area_left = left
let area_bottom (m : model) : float = if m.panel = Closed then -.top m else panel_top m
let area_height (m : model) : float = area_top m -. area_bottom m
let page_width = width
let line_height = 16.

(* the tab strip; the toolbar's buttons and the omnibox *)
let tab_y (m : model) : float = top m -. 19.
let tab_left (m : model) : float = left m +. 10.
let toolbar_y (m : model) : float = top m -. 62.
let button_x (m : model) (i : int) : float = left m +. 24. +. (38. *. float_of_int i)
let omnibox_x (m : model) : float = left m +. 138.
let omnibox_w (m : model) : float = width m -. 180.
(* the omnibox's "JS", the page's scripts on (blue) or off (grey) *)
let js_x (m : model) : float = omnibox_x m +. omnibox_w m -. 30.
let wrench_x (m : model) : float = -.left m -. 22.

(* the lines of the page that the area shows *)
let visible_lines (m : model) (tab : Browser_tab.t) : int = int_of_float (area_height m /. (line_height *. zoom_of m tab))

(*****************************************************************************)
(* The pointer, and the pieces built from the model *)
(*****************************************************************************)

(* a point of the window in the page's units, if it is on the page *)
let page_point_at (m : model) ((mx, my) : float * float) : (float * float) option =
  let z = zoom_of m (current_tab m) in
  if my <= area_top m && my >= area_bottom m then
    Some ((mx -. area_left m) /. z, ((area_top m -. my) /. z) +. (float_of_int (current_tab m).scroll *. line_height))
  else None

let page_point (m : model) : (float * float) option = page_point_at m m.mouse

let hovered (m : model) : string option =
  match ((current_tab m).state, page_point m) with Shown p, Some (x, y) -> Hit.link_at p.layout ~x ~y | _ -> None

let pointed_control (m : model) : Dom.element option =
  match ((current_tab m).state, page_point m) with
  | Shown p, Some (x, y) -> ( match Hit.fragment_at p.layout ~x ~y with Some { control = Some c; _ } -> Some c.element | _ -> None)
  | _ -> None

(* a control that is typed in *)
let is_text_control (e : Dom.element) : bool =
  e.name = "textarea"
  || e.name = "input"
     && List.mem (String.lowercase_ascii (Option.value ~default:"text" (Dom.attribute "type" e))) [ "text"; "search"; "email"; "url"; "password"; "tel"; "number"; "" ]

(* the chrome's pieces (libs/gui), built from the model: the
 * toolbar's buttons, the strip of tabs *)
let buttons (m : model) : Gui_toolbar.t =
  let tab = current_tab m in
  { left = button_x m 0; y = toolbar_y m;
    buttons = [ (Back, tab.history.behind <> []); (Forward, tab.history.ahead <> []); ((if loading tab then Stop else Reload), true) ] }

let strip (m : model) : int Gui_tabs.t =
  let title (t : Browser_tab.t) = match t.state with Shown p when p.title <> "" -> p.title | Shown p -> p.url | Loading _ -> "Loading..." in
  { left = tab_left m; y = tab_y m; room = width m -. 100.; current = m.current;
    tabs = List.map (fun t -> { Gui_tabs.value = t.id; title = title t.tab; busy = loading t.tab }) m.tabs }

let near (x0 : float) (y0 : float) (w : float) (h : float) (m : model) : bool = Gui_kit.near x0 y0 w h m.mouse

let on_omnibox (m : model) : bool = near (omnibox_x m) (toolbar_y m) (omnibox_w m) 28. m

(* the panel's header: its views' names and Inspect *)
let panel_button (m : model) : string option =
  if m.panel = Closed then None
  else if near (left m +. 10.) (panel_header_y m) 60. 16. m then Some "Inspect"
  else if near (left m +. 90.) (panel_header_y m) 60. 16. m then Some "Elements"
  else if near (left m +. 170.) (panel_header_y m) 60. 16. m then Some "Network"
  else None

(* the mouse's cursor for what is under it, as Chrome's: a hand over a
 * link, the I-beam where text is typed (the omnibox, a page's field),
 * the arrow elsewhere -- and over the right click's menu, whatever is
 * under it *)
let cursor_of (m : model) : Playground.cursor =
  if m.menu <> None then Arrow
  else if on_omnibox m then Text
  else if hovered m <> None then Hand
  else match pointed_control m with Some e when is_text_control e -> Text | _ -> Arrow
