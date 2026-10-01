(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)
(* A small version of Google Chrome (September 2008), meant for the web
 * as it is. It started as elm-playground's TinyChrome, the last of a
 * family (TinyMosaic, TinyNetscape and TinyFirefox show how a browser
 * grew), and grows here past its 5,000 lines.
 *
 * It tries to show real pages mostly right (plan_tiny_chrome.md in
 * elm-playground: which sites, and what they ask). Its engine is CSS's
 * own, from scratch in languages/css and src/layout:
 *
 *   bytes -> tree -> Cascade (the page's sheets over the browser's,
 *   ua.css; @media, var(), the attributes' hints) -> Computed (a record
 *   of values per element) -> Box_layout (CSS 2.1's box model: margins,
 *   borders, paddings, auto margins centring, collapsing margins,
 *   floats, inline-blocks shrunk to fit, positioning, tables, lists;
 *   and flexbox, Flex_layout)
 *   -> Browser_boxes (backgrounds, borders, the words, SVG)
 *
 * where the teaching browsers have Mosaic's looks and Html_layout. Each
 * tab is theirs (Browser_tab: the page, its history, its pictures), with
 * Browser_page's setting boxes on: a page's <link rel=stylesheet>s and
 * their @imports are then fetched with its pictures, ahead of them, and
 * the page laid out again as each arrives -- shown at once plain, then
 * dressed (Chrome waits a moment instead, to spare that flash).
 *
 * Chrome's window: the **tabs** on top, in the frame (click one to see
 * it, its x to close it, + for a new one), each a Browser_tab of its
 * own, its answers routed to it by its number; below, Back, Forward,
 * Reload, and the **omnibox** (click it, type, Return): an address, or
 * words -- then a search, Wikipedia's (search_url: the engines' pages
 * without scripts that answer a program; DuckDuckGo's, search=duckduckgo,
 * its links going through a <meta http-equiv=refresh>, which the tab
 * follows). A
 * link's address shows in a bubble at the bottom left, as Chrome's
 * status bubble. JavaScript is off on the web, as in Chrome with it
 * disabled -- most sites' scripts are more than our engine reads, and
 * many sites are written to work without (a <noscript> is then shown)
 * -- and on for the built-in pages (the plan's C8: a few sites' too).
 * The arrows, Page Up and Down, Space and the wheel scroll, Backspace
 * goes back.
 *
 * claude: Ctrl and + (or =), Ctrl and -, Ctrl and the wheel **zoom**
 * the page, Ctrl and 0 back to 100% (Browser_zoom: Chrome's steps,
 * each site its own zoom). The whole page grows, not its fonts alone:
 * laid out at the window's width divided by the zoom, and drawn
 * scaled; the zoom shows in the omnibox when not 100%.
 *
 * claude: a page longer than the window has a **scrollbar** at its
 * right (Gui_scrollbar), over the page's edge: its thumb dragged, its
 * track clicked above or below for a page up or down.
 *
 * claude: the words of the command line that are not flags are the
 * first pages, a tab each, as Chrome's: an address
 * (mini-chrome news.ycombinator.com) or words to search.
 *
 * claude: the whole window is drawn at a **scale**, a browser's device
 * scale factor: the desktop's (Gui_scale: 2 where GNOME says a screen
 * has twice the dots, and the chrome's letters of 6 could not be read),
 * or the one chosen with Ctrl, Shift and + or - (Ctrl Shift 0: the
 * desktop's again), kept in the profile. The program still works in
 * its own units, the window being that many times fewer of them: the
 * view is scaled whole, the pointer and the window's size divided. A
 * site's zoom (Ctrl +) multiplies it, for that site's pages.
 *
 * claude: a **right click** on the page opens Chrome's context menu
 * (Browser_menu, drawn by libs/gui's Gui_menu): on a link, Open link in new tab (a tab behind the
 * one shown) and Inspect; elsewhere Back, Forward, Reload, Inspect.
 * A click on an item does it; any click, Escape, the wheel close it.
 *
 * claude: the **profile** (Browser_profile) is what is kept from one
 * run to the next, in ~/.config/mini-chrome (Preferences, JSON): the
 * window's size and the sites' zooms, read at the start and written a
 * second after one changes, and when the program ends. It is the one place the
 * program touches the file system, with Cap.open_in and Cap.open_out
 * from Cap.main, as it reaches the network with Cap.network.
 *
 * The **developer tools** (F12, or the wrench), after Chrome's Web
 * Inspector: Elements -- click Inspect, then an element of the page:
 * its place in the tree, its box (outlined on the page), its children,
 * and its styles, each declaration that won with the rule and the sheet
 * it came from (Browser_devtools, over Cascade.explain) -- and Network,
 * each request of the page, its status, kind, size and time, stamped
 * by this program's clock as the tab's log changes.
 *
 *   dune exec mini-chrome
 *
 * flags url= (about:chrome), the first page; css=off, the browser's
 * own sheet alone (what a page looks like unstyled); panel=elements or
 * panel=network, the tools open; search=duckduckgo, the omnibox's
 * engine (wikipedia); profile=DIR, the profile's directory, or
 * profile=off, nothing read nor kept; scale=N, everything drawn N
 * times bigger. And the Playground's, with a
 * dash: -v (or -verbose) says on the terminal each file and URL
 * opened, -debug more (the keys pressed), -quiet nothing (Logs).
 *
 * Uses: appkit_browser (the tab, the page, Browser_boxes,
 * Browser_devtools, the forms), the web engine (Cascade, Computed, Box_layout,
 * Flex_layout, and Hit through the page's Html_layout view),
 * graphics/images/svg (Svg) through Browser_boxes and Browser_picture,
 * the built-in site (Site). Its own: the chrome, the tabs, the panel.
 *
 * Tried live: Hacker News (its tables, attributes and news.css), a
 * Wikipedia article (its two sheets from load.php; its header and tabs
 * flex rows; its contents a grid column, here above the article),
 * Google's home page (its no-script version: a search needs
 * JavaScript), a GitHub repository (41 sheets; its file list's
 * messages written by its scripts, so missing), DuckDuckGo's searches.
 * Their logos and icons are SVG: HN's "Y" and vote arrows, Wikipedia's
 * wordmark and icons, GitHub's octicons.
 *
 * <video> and <audio> play (Browser_media, over TinyMediaPlayer's
 * readers: MPEG-1 and MP2, AVI, FLC, Y4M, GIF, MP3), and about:tube is
 * a video site of our own (Tube).
 *
 * To come (plan_tiny_chrome.md): speed (C10).
 *)
open Playground

(*****************************************************************************)
(* The model *)
(*****************************************************************************)

(* a tab, and when each of its requests started and ended (the
 * network panel's times, this program's clock) *)
type tab = { id : int; tab : Browser_tab.t; times : (string * (float * float option)) list }

type panel = Closed | Elements | Network

type model = {
  tabs : tab list;
  current : int; (* the id of the tab shown *)
  next_id : int;
  omnibox : Gui_field.t option; (* claude: its text, while it is typed into (libs/gui); None, it shows the page's address *)
  mouse : float * float;
  time : float;
  css : bool; (* the page's style sheets honoured *)
  panel : panel;
  inspecting : bool; (* the next click on the page picks an element *)
  selected : Dom.element option;
  engine : string; (* the omnibox's searches: search_url *)
  allowed : string list; (* the sites whose scripts run (hosts): Chrome's per-site setting *)
  fetches : msg Fetch.t; (* the tabs' requests in flight, stepped on each Tick *)
  screen : float * float; (* claude: the window's size in the program's units (its dots, divided by the scale): the page's width *)
  ctrl : bool; (* claude: a Ctrl key held *)
  profile : Browser_profile.t; (* claude: what is kept between runs: the window's size, the sites zoomed *)
  profile_dir : string option; (* claude: where it is saved; None, it is not *)
  saved : Browser_profile.t; (* claude: the profile as it is on disk *)
  changed : float; (* claude: when the profile last changed (time) *)
  menu : Browser_menu.action Gui_menu.t option; (* claude: the right click's menu, while it is open *)
  window : int * int; (* claude: the window's size, in the screen's dots; [screen] is in the program's units *)
  desktop : float; (* claude: the desktop's scale (Gui_scale), when none is chosen *)
  shift : bool; (* claude: a Shift key held *)
  grab : float option; (* claude: the scrollbar's thumb held: how far under its top (Gui_scrollbar) *)
}

and msg =
  | Got of int * string * (Fetch.response, Fetch.error) result
  | Got_picture of int * string * (Fetch.response, Fetch.error) result
  | Start_fetch of msg Fetch.request (* a tab's request, to start *)
  | Tick of float
  | Key of string
  | Key_up of string
  | Typed of string
  | Wheel of float
  | Mouse_move of float * float
  | Click
  | Mouse_up
  | Right_click
  | Resized of int * int (* the window's new size *)

let home = "about:chrome"
let characters = Browser_text.characters
let resolve = Browser_url.resolve

(*****************************************************************************)
(* The window's geometry *)
(*****************************************************************************)

(* claude: the screen is the window, whatever its size (run_app's
 * screen_follows_window), the origin at its centre: everything is placed
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


(*****************************************************************************)
(* The tabs: Chrome's settings *)
(*****************************************************************************)

(* "news.ycombinator.com" of https://news.ycombinator.com/item?id=1 *)
let host_of (url : string) : string =
  match String.index_opt url ':' with
  | Some i when i + 3 <= String.length url && String.sub url (i + 1) 2 = "//" ->
      let rest = String.sub url (i + 3) (String.length url - i - 3) in
      let stop = List.fold_left (fun m c -> match String.index_opt rest c with Some j -> min m j | None -> m) (String.length rest) [ '/'; '?'; '#'; ':' ] in
      String.sub rest 0 stop
  | _ -> ""

(* claude: a tab's zoom, its site's *)
let zoom_of (m : model) (tab : Browser_tab.t) : float = Browser_zoom.of_host m.profile.zooms (host_of (Browser_tab.current_url tab))

(* claude: the lines of the page that the area shows *)
let visible_lines (m : model) (tab : Browser_tab.t) : int = int_of_float (area_height m /. (line_height *. zoom_of m tab))

let settings (m : model) (tab : Browser_tab.t) : Browser_page.settings =
  {
    extensions = true;
    css = m.css;
    (* CSS 2.1's box model: Cascade, Computed, Box_layout *)
    boxes = true;
    width = page_width m /. zoom_of m tab;
    breaker = Html_layout.greedy;
    visited = (fun url -> List.mem url tab.visited);
    picture = (fun url -> List.assoc_opt url tab.pictures);
    sheet = (fun url -> List.assoc_opt url tab.sheets);
  }

(* the sites whose scripts are small and old enough for our engine
 * (plan_tiny_chrome.md, "Famous sites with simple scripts") *)
let default_allowed = [ "news.ycombinator.com" ]

let config (m : model) (id : int) : msg Browser_tab.config =
  {
    settings = settings m;
    (* the built-in site, and TinyTube in it *)
    about = (fun name -> match Tube.about name with Some x -> Some x | None -> Site.about name);
    got = (fun url r -> Got (id, url, r));
    got_picture = (fun url r -> Got_picture (id, url, r));
    fetch = (fun r -> Start_fetch r);
    connections = 6;
    visible = (match List.find_opt (fun t -> t.id = id) m.tabs with Some t -> visible_lines m t.tab | None -> 0);
    line_height;
    (* the built-in pages' scripts, and the allowed sites' *)
    scripts = (fun url -> Browser_url.starts_with "about:" url || List.mem (host_of url) m.allowed);
    seed = 1;
  }

let current (m : model) : tab = match List.find_opt (fun t -> t.id = m.current) m.tabs with Some t -> t | None -> List.hd m.tabs
let current_tab (m : model) : Browser_tab.t = (current m).tab

(* a tab's requests given times: a new one its start, an answered one
 * its end *)
let stamp (time : float) (t : tab) : tab =
  let times =
    List.map
      (fun (r : Browser_tab.request) ->
        match List.assoc_opt r.url t.times with
        | Some (start, stop) ->
            (* asked for before the clock's first tick: from its first *)
            let start = if start = 0. && time > 0. && stop = None then time else start in
            (r.url, (start, match (stop, r.status) with Some e, _ -> Some e | None, Some _ -> Some time | None, None -> None))
        | None -> (r.url, (time, if r.status = None then None else Some time)))
      t.tab.requests
  in
  { t with times }

(* the tab [id] changed by [f] (its commands its own) *)
let on_tab (m : model) (id : int) (f : msg Browser_tab.config -> Browser_tab.t -> Browser_tab.t * msg Cmd.t) : model * msg Cmd.t =
  match List.find_opt (fun t -> t.id = id) m.tabs with
  | None -> (m, Cmd.none)
  | Some t ->
      let tab, cmd = f (config m id) t.tab in
      let t = stamp m.time { t with tab } in
      ({ m with tabs = List.map (fun t' -> if t'.id = id then t else t') m.tabs }, cmd)

let on_current m f = on_tab m m.current f
let current_url (m : model) : string = Browser_tab.current_url (current_tab m)
let scrolled (by : int) (m : model) : model = fst (on_current m (fun cfg tab -> (Browser_tab.scrolled cfg by tab, Cmd.none)))

(* claude: every tab's page laid out again (the window resized, a site
 * zoomed), its scroll moved with the page's new height, to stay near
 * what was read *)
let relaid_all (m : model) : model =
  let height (tab : Browser_tab.t) = match tab.state with Shown p -> p.layout.height | Loading _ -> 0. in
  let relaid (t : tab) =
    let cfg = config m t.id in
    let tab = Browser_tab.relaid cfg t.tab in
    let scroll = if height t.tab > 0. then int_of_float (float_of_int tab.scroll *. height tab /. height t.tab) else tab.scroll in
    { t with tab = Browser_tab.scrolled cfg 0 { tab with scroll } }
  in
  { m with tabs = List.map relaid m.tabs }

(* claude: the profile changed: saved once it has been still for a
 * second (Tick), so a window dragged to its size is written once, not
 * at each step of the drag; and when the program ends, if it changed
 * since (unsaved, below) *)
let with_profile (profile : Browser_profile.t) (m : model) : model =
  if profile = m.profile then m else { m with profile; changed = m.time }

let saved (caps : < Cap.open_out ; .. >) (m : model) : model =
  match m.profile_dir with
  | Some dir when m.profile <> m.saved && m.time -. m.changed >= 1. ->
      (* if it cannot be saved, the change is this run's; not tried again *)
      ignore (Browser_profile.save caps ~dir m.profile);
      { m with saved = m.profile }
  | _ -> m

(* claude: the scale everything is drawn at: the one chosen, else the
 * desktop's *)
let scale_of (m : model) : float = Option.value m.profile.scale ~default:m.desktop

(* claude: the window's size or the scale changed: the screen is the
 * window's dots in the program's units, and every page laid out again
 * at its width *)
let rescreened (m : model) : model =
  let w, h = m.window and s = scale_of m in
  let screen = (float_of_int w /. s, float_of_int h /. s) in
  if screen = m.screen then m else relaid_all { m with screen }

(* claude: the shown page's site at the zoom [f] gives from its own *)
let zoomed (f : float -> float) (m : model) : model =
  let zooms = Browser_zoom.with_host m.profile.zooms (host_of (current_url m)) (f (zoom_of m (current_tab m))) in
  relaid_all (with_profile { m.profile with zooms } m)

(* claude: the shown page's scrollbar, in lines: the page's, those the
 * area shows, those scrolled *)
let scrollbar (m : model) : Gui_scrollbar.t =
  let tab = current_tab m in
  { right = -.left m; top = area_top m; height = area_height m;
    total = float_of_int (Browser_tab.line_count (config m m.current) tab); shown = float_of_int (visible_lines m tab);
    offset = float_of_int tab.scroll }

let visit network url m = on_current { m with omnibox = None; selected = None } (fun cfg tab -> Browser_tab.visit cfg network url tab)
let load network url m = on_current m (fun cfg tab -> Browser_tab.load cfg network url tab)

(* a new tab, shown, loading [url] *)
let open_tab (network : < Cap.network ; .. >) (url : string) (m : model) : model * msg Cmd.t =
  let target, fragment = Browser_url.split_fragment url in
  let tab = { (Browser_tab.empty ~images:true) with visited = [ target ]; fragment } in
  let m = { m with tabs = m.tabs @ [ { id = m.next_id; tab; times = [] } ]; current = m.next_id; next_id = m.next_id + 1; selected = None } in
  load network target m

let close_tab (network : < Cap.network ; .. >) (id : int) (m : model) : model * msg Cmd.t =
  match List.filter (fun t -> t.id <> id) m.tabs with
  | [] -> open_tab network home { m with tabs = [] }
  | rest ->
      let current = if m.current = id then (List.nth rest (max 0 (List.length rest - 1))).id else m.current in
      ({ m with tabs = rest; current; selected = None }, Cmd.none)

(* where words typed in the omnibox are searched: an engine whose page
 * works without scripts and answers a program -- Wikipedia's (the
 * default: Google's needs JavaScript, and DuckDuckGo's page without
 * scripts, like Mojeek's, soon takes a program asking again and again
 * for a robot and asks it to pick ducks), or DuckDuckGo's
 * (search=duckduckgo) *)
let search_url (engine : string) (words : string) : string =
  match engine with
  | "duckduckgo" -> "https://html.duckduckgo.com/html/?" ^ Urlencoded.encode [ ("q", words) ]
  | _ -> "https://en.wikipedia.org/w/index.php?" ^ Urlencoded.encode [ ("search", words) ]

(* what is typed in the omnibox: an address (a scheme, or a host with a
 * dot), else words searched *)
let typed_url (engine : string) (s : string) : string =
  let s = String.trim s in
  if String.contains s ':' && not (String.contains s ' ') then s
  else if String.contains s '.' && not (String.contains s ' ') then "https://" ^ s
  else search_url engine s

(*****************************************************************************)
(* The pointer *)
(*****************************************************************************)

(* claude: a point of the window in the page's units, if it is on the page *)
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

let loading (tab : Browser_tab.t) : bool = (match tab.state with Loading _ -> true | Shown _ -> false) || tab.in_flight <> [] || tab.queue <> []

(* claude: the chrome's pieces (libs/gui), built from the model: the
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

(*****************************************************************************)
(* Update *)
(*****************************************************************************)

(* claude: the profile, read before the window is made (its size is in
 * it), and where it is saved. One that cannot be read (not JSON: fixed
 * by hand, a brace lost) is left as it is, not written over: this run
 * keeps nothing *)
let profile_of (caps : < Cap.open_in ; Cap.env ; .. >) (flags : flags) : Browser_profile.t * string option =
  let dir = match List.assoc_opt "profile" flags with Some "off" -> None | Some dir -> Some dir | None -> Browser_profile.default_dir caps in
  match Option.map (fun dir -> Browser_profile.load caps ~dir) dir with
  | Some (Ok p) -> (p, dir)
  | Some (Error why) ->
      Logs.warn (fun m -> m "the profile is not used, nor saved to: %s" why);
      (Browser_profile.empty, None)
  | None -> (Browser_profile.empty, None)

(* claude: the first pages: url=X, and the words of the command line
 * that are not a flag's name -- an address or words to search, as
 * typed in the omnibox (the Playground cuts a word at its first =: put
 * back, for an address with a query) *)
let flag_names = [ "url"; "css"; "panel"; "search"; "scripts"; "threads"; "profile"; "scale" ]

let first_pages (engine : string) (flags : flags) : string list =
  let words = List.filter (fun (name, _) -> not (List.mem name flag_names)) flags in
  match Option.to_list (List.assoc_opt "url" flags) @ List.map (fun (name, value) -> typed_url engine (if value = "" then name else name ^ "=" ^ value)) words with
  | [] -> [ home ]
  | urls -> urls

let init (network : < Cap.network ; .. >) ((profile, profile_dir) : Browser_profile.t * string option) ~(desktop : float) ~(window : int * int) (flags : flags) : model * msg Cmd.t =
  let panel = match List.assoc_opt "panel" flags with Some "elements" -> Elements | Some "network" -> Network | _ -> Closed in
  let m =
    { tabs = []; current = 0; next_id = 0; omnibox = None; mouse = (1000., 1000.); time = 0.;
      css = List.assoc_opt "css" flags <> Some "off"; panel; inspecting = false; selected = None;
      engine = Option.value (List.assoc_opt "search" flags) ~default:"wikipedia";
      allowed = (match List.assoc_opt "scripts" flags with Some "off" -> [] | Some hosts -> String.split_on_char ',' hosts | None -> default_allowed);
      (* threads on, as in TinyNetscape (N2): a name resolved, an
       * https:// page fetched, on threads of their own; threads=off,
       * the frame waits *)
      fetches = Fetch.create ~threads:(List.assoc_opt "threads" flags <> Some "off") ();
      (* claude: until the platform says (Resized, before the first frame) *)
      screen = (Playground.default_width, Playground.default_height); ctrl = false; profile; profile_dir; saved = profile; changed = 0.; menu = None; window; desktop; shift = false; grab = None }
  in
  (* claude: a tab a page, the first one shown *)
  let m, cmd =
    List.fold_left (fun (m, cmd) url -> let m, c = open_tab network url m in (m, Cmd.batch [ cmd; c ])) (m, Cmd.none) (first_pages m.engine flags)
  in
  let m = { m with current = 0 } in
  (* with the elements' view open, the page's <body> shown in it *)
  let selected = match (panel, (current_tab m).state) with Elements, Shown p -> List.nth_opt (Dom.find_all "body" p.tree) 0 | _ -> None in
  ({ m with selected }, cmd)

let edit_omnibox (network : < Cap.network ; .. >) (key : string) (field : Gui_field.t) (m : model) : model * msg Cmd.t =
  match key with
  | "enter" | "return" -> visit network (typed_url m.engine field.text) m
  | "escape" -> ({ m with omnibox = None }, Cmd.none)
  | "backspace" -> ({ m with omnibox = Some (Gui_field.backspace field) }, Cmd.none)
  | _ -> (m, Cmd.none)

let form (network : < Cap.network ; .. >) ~(keep_focus : bool) (outcome : Browser_forms.outcome) (m : model) : model * msg Cmd.t =
  on_current m (fun cfg tab -> Browser_tab.form_effect cfg network ~keep_focus outcome tab)

(* a task of the page's scripts done by [f], then the page laid out
 * again if its tree changed (Browser_tab.after_task) *)
let task (network : < Cap.network ; .. >) (m : model) (f : Browser_script.t -> bool) : model * msg Cmd.t * bool =
  match (current_tab m).script with
  | Some s ->
      let r = f s in
      let m, cmd = on_current m (fun cfg tab -> Browser_tab.after_task cfg network tab) in
      (m, cmd, r)
  | None -> (m, Cmd.none, false)

let click_page (network : < Cap.network ; .. >) (m : model) : model * msg Cmd.t =
  match ((current_tab m).state, page_point m) with
  | Shown p, Some (x, y) when m.inspecting -> ({ m with inspecting = false; selected = Hit.element_at p.layout ~x ~y }, Cmd.none)
  (* a player: played or paused *)
  | Shown p, Some (x, y)
    when (match Hit.fragment_at p.layout ~x ~y with
         | Some f -> Browser_media.click ~now:m.time ~media:(fun u -> List.assoc_opt u (current_tab m).media) p f.element
         | None -> false) ->
      (m, Cmd.none)
  | Shown p, Some (x, y) -> (
      (* the page's scripts first (the element under the pointer, its
       * click bubbling); then, unless one prevented it, the browser's *)
      let control = pointed_control m and link = hovered m in
      let m, cmd, prevented = task network m (fun s -> match Hit.element_at p.layout ~x ~y with Some e -> Browser_script.click s e | None -> false) in
      if prevented then (m, cmd)
      else
        let m, cmd2 =
          match (control, link, (current_tab m).state) with
          | Some e, _, Shown p -> form network ~keep_focus:false (Browser_forms.click p e) m
          | _, Some href, Shown p -> visit network (resolve p.url href) m
          | _ -> on_current m (fun _ tab -> ({ tab with focus = None }, Cmd.none))
        in
        (m, Cmd.batch [ cmd; cmd2 ]))
  | _ -> (m, Cmd.none)

let pages (m : model) (by : int) : int = by * (visible_lines m (current_tab m) - 2)

let toggle_panel (m : model) : model = { m with panel = (if m.panel = Closed then Elements else Closed); inspecting = false }

(* claude: what an item of the right click's menu does *)
let menu_action (network : < Cap.network ; .. >) (menu : Browser_menu.action Gui_menu.t) (action : Browser_menu.action) (m : model) : model * msg Cmd.t =
  match action with
  | Open_in_new_tab url ->
      (* behind the tab shown, which stays the current one *)
      let opened, cmd = open_tab network url m in
      ({ opened with current = m.current; selected = m.selected }, cmd)
  | Back -> on_current m (fun cfg tab -> Browser_tab.back cfg network tab)
  | Forward -> on_current m (fun cfg tab -> Browser_tab.forward cfg network tab)
  | Reload -> load network (current_url m) m
  | Inspect ->
      (* the element that was under the right click, in the tools *)
      let selected = match ((current_tab m).state, page_point_at m menu.at) with Shown p, Some (x, y) -> Hit.element_at p.layout ~x ~y | _ -> None in
      ({ m with panel = Elements; inspecting = false; selected }, Cmd.none)

let update (caps : < Cap.network ; Cap.open_out ; .. >) (msg : msg) (m : model) : model * msg Cmd.t =
  let network = (caps :> < Cap.network >) in
  (* claude: the menu is over a page that stays as it is: closed by what
   * moves the page, and by Escape *)
  let m = match msg with Wheel _ | Resized _ | Key ("Escape" | "escape") -> { m with menu = None } | _ -> m in
  Browser_media.install ();
  match msg with
  | Got (id, url, r) -> on_tab m id (fun cfg tab -> Browser_tab.got cfg network url r tab)
  | Got_picture (id, url, r) -> on_tab m id (fun cfg tab -> Browser_tab.got_picture cfg network url r tab)
  | Start_fetch r ->
      Fetch.perform m.fetches r;
      (m, Cmd.none)
  | Tick time ->
      (* the shown tab's timers on the frame clock (the others wait, as
       * Chrome slows a hidden tab's) *)
      let m, cmd, _ = task network (saved caps { m with time }) (fun s -> Browser_script.advance s (1000. /. 60.); false) in
      (* the requests in flight stepped: the answers, Got and
       * Got_picture, as the next messages *)
      let answered = Fetch.step m.fetches in
      (m, Cmd.batch (cmd :: List.map (fun msg -> Cmd.Msg msg) answered))
  (* claude: the wheel's notches, positive scrolling up (the platform's
   * meaning): the page goes up, so its scroll down the page decreases.
   * The system's natural scrolling, where it is the driver's (X11,
   * libinput), is in the notches already *)
  | Wheel notches when m.ctrl -> (zoomed (Browser_zoom.step (notches > 0.)) m, Cmd.none)
  | Wheel notches -> (scrolled (-3 * int_of_float (Float.round notches)) m, Cmd.none)
  (* claude: the pointer, from the window's dots to the program's units *)
  | Mouse_move (x, y) -> (
      let m = { m with mouse = (x /. scale_of m, y /. scale_of m) } in
      (* claude: the scrollbar's thumb held: the page follows the pointer *)
      match m.grab with
      | Some grab -> (scrolled (int_of_float (Float.round (Gui_scrollbar.dragged (scrollbar m) ~grab (snd m.mouse))) - (current_tab m).scroll) m, Cmd.none)
      | None -> (m, Cmd.none))
  | Mouse_up -> ({ m with grab = None }, Cmd.none)
  (* claude: the window's size changed (not the first time, when it is
   * told the size it started at): kept in the profile, and every tab's
   * page laid out again at its new width *)
  | Resized (w, h) ->
      let profile = if (w, h) = m.window then m.profile else { m.profile with window = Some (w, h) } in
      (rescreened (with_profile profile { m with window = (w, h) }), Cmd.none)
  (* claude: a right click on the page: its menu, for what is under the
   * pointer; elsewhere, an open menu closed *)
  | Right_click -> (
      let tab = current_tab m in
      match (tab.state, page_point m) with
      | Shown p, Some _ ->
          let items = Browser_menu.items ~link:(Option.map (resolve p.url) (hovered m)) ~back:(tab.history.behind <> []) ~forward:(tab.history.ahead <> []) in
          ({ m with menu = Some (Gui_menu.opened ~screen:m.screen ~at:m.mouse items); omnibox = None }, Cmd.none)
      | _ -> ({ m with menu = None }, Cmd.none))
  (* claude: a click with the menu open is the menu's: on an item, done;
   * anywhere, the menu closed, the page under it not clicked *)
  | Click when m.menu <> None -> (
      let menu = Option.get m.menu in
      let m = { m with menu = None } in
      match Gui_menu.chosen menu m.mouse with Some action -> menu_action network menu action m | None -> (m, Cmd.none))
  (* claude: a press on the scrollbar: its thumb held until the button
   * is let go, or a page up or down *)
  | Click when Gui_scrollbar.at (scrollbar m) m.mouse <> None -> (
      let m = { m with omnibox = None } in
      match Gui_scrollbar.at (scrollbar m) m.mouse with
      | Some (Thumb grab) -> ({ m with grab = Some grab }, Cmd.none)
      | Some Before -> (scrolled (pages m (-1)) m, Cmd.none)
      | Some After -> (scrolled (pages m 1) m, Cmd.none)
      | None -> (m, Cmd.none))
  | Click -> (
      let m = { m with omnibox = None } in
      if on_omnibox m then
        on_current { m with omnibox = Some (Gui_field.focused (current_url m)) } (fun _ tab -> ({ tab with focus = None }, Cmd.none))
      else if near (wrench_x m -. 12.) (toolbar_y m) 24. 28. m then (toggle_panel m, Cmd.none)
      else if near (js_x m) (toolbar_y m) 22. 20. m then
        (* the site's scripts on or off, and the page loaded again *)
        let host = host_of (current_url m) in
        let allowed = if List.mem host m.allowed then List.filter (( <> ) host) m.allowed else host :: m.allowed in
        load network (current_url m) { m with allowed }
      else
        match (Gui_tabs.at (strip m) m.mouse, panel_button m, Gui_toolbar.at (buttons m) m.mouse) with
        | Some (Close id), _, _ -> close_tab network id m
        | Some (Show id), _, _ -> ({ m with current = id; selected = None; inspecting = false }, Cmd.none)
        | Some New, _, _ -> open_tab network home m
        | None, Some "Inspect", _ -> ({ m with inspecting = not m.inspecting }, Cmd.none)
        | None, Some "Elements", _ -> ({ m with panel = Elements }, Cmd.none)
        | None, Some "Network", _ -> ({ m with panel = Network; inspecting = false }, Cmd.none)
        | None, _, Some Gui_toolbar.Back -> on_current m (fun cfg tab -> Browser_tab.back cfg network tab)
        | None, _, Some Gui_toolbar.Forward -> on_current m (fun cfg tab -> Browser_tab.forward cfg network tab)
        | None, _, Some Gui_toolbar.Reload -> load network (current_url m) m
        | None, _, Some Gui_toolbar.Stop -> on_current m (fun cfg tab -> (Browser_tab.stop cfg tab, Cmd.none))
        | _ -> if page_point m <> None then click_page network m else (m, Cmd.none))
  (* claude: Ctrl held (SDL's names, or the web's), and the page zoomed;
   * the character such a key may also type is not the omnibox's *)
  | Key ("Left Ctrl" | "Right Ctrl" | "left ctrl" | "right ctrl" | "Control") -> ({ m with ctrl = true }, Cmd.none)
  | Key ("Left Shift" | "Right Shift" | "left shift" | "right shift" | "Shift") -> ({ m with shift = true }, Cmd.none)
  | Key_up key ->
      let up names = List.mem (String.lowercase_ascii key) names in
      ({ m with ctrl = m.ctrl && not (up [ "left ctrl"; "right ctrl"; "control" ]); shift = m.shift && not (up [ "left shift"; "right shift"; "shift" ]) }, Cmd.none)
  (* claude: with Shift too, the window's scale: a step of the zoom's
   * levels, or the desktop's again (0) *)
  | Key key when m.ctrl && m.shift && Browser_zoom.key key <> None ->
      let scale = match Option.get (Browser_zoom.key key) with Reset -> None | change -> Some (Browser_zoom.apply change (scale_of m)) in
      (rescreened (with_profile { m.profile with scale } m), Cmd.none)
  | Key key when m.ctrl && Browser_zoom.key key <> None -> (zoomed (Browser_zoom.apply (Option.get (Browser_zoom.key key))) m, Cmd.none)
  | Typed s when m.ctrl && Browser_zoom.key s <> None -> (m, Cmd.none)
  | Typed s when m.omnibox <> None -> ({ m with omnibox = Option.map (Gui_field.typed s) m.omnibox }, Cmd.none)
  | Key key when m.omnibox <> None -> edit_omnibox network (String.lowercase_ascii key) (Option.get m.omnibox) m
  | Typed s when (current_tab m).focus <> None -> (
      match ((current_tab m).state, (current_tab m).focus) with
      | Shown p, Some e -> form network ~keep_focus:true (Changed (Browser_forms.typed p e s)) m
      | _ -> (m, Cmd.none))
  | Key key when (current_tab m).focus <> None && not (List.mem (String.lowercase_ascii key) [ "arrowdown"; "arrowup"; "pagedown"; "pageup" ]) -> (
      match ((current_tab m).state, (current_tab m).focus) with
      | Shown p, Some e -> form network ~keep_focus:true (Browser_forms.key p e (String.lowercase_ascii key)) m
      | _ -> (m, Cmd.none))
  | Typed _ -> (m, Cmd.none)
  | Key key -> (
      match String.lowercase_ascii key with
      | "arrowdown" | "down" -> (scrolled 2 m, Cmd.none)
      | "arrowup" | "up" -> (scrolled (-2) m, Cmd.none)
      | "pagedown" | " " | "space" -> (scrolled (pages m 1) m, Cmd.none)
      | "pageup" -> (scrolled (pages m (-1)) m, Cmd.none)
      | "home" -> (scrolled (-(current_tab m).scroll) m, Cmd.none)
      | "f12" -> (toggle_panel m, Cmd.none)
      | "backspace" -> on_current m (fun cfg tab -> Browser_tab.back cfg network tab)
      | _ -> (m, Cmd.none))

(*****************************************************************************)
(* View *)
(*****************************************************************************)

(* Chrome 1.0 on Windows: the blue frame, the tab and toolbar light *)
let frame = Gui_kit.frame
let toolbar = Gui_kit.surface
let edge = Gui_kit.edge
let white = Gui_kit.white
let ink = Gui_kit.ink
let muted = Gui_kit.muted
let inspector_blue = Gui_kit.accent

(* claude: the chrome's text, in cells (libs/gui) *)
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
  let outline =
    match (m.panel, m.selected) with
    | Elements, Some e -> (
        match Browser_devtools.box_of p e with
        | Some (x, y, w, h) ->
            [ (y, y +. h, group [ rectangle inspector_blue w h |> fade 0.18 |> move (x +. (w /. 2.)) (-.(y +. (h /. 2.))); Browser_draw.frame inspector_blue x y w h ]) ]
        | None -> [])
    | _ -> []
  in
  (p.drawn
  @ Browser_draw.controls_drawn ~value:(Browser_page.value_of p) ~focus:tab.focus p.layout
  (* what plays in its <video>s and <audio>s, drawn at each frame *)
  @ Browser_media.draw ~now:m.time ~media:(fun u -> List.assoc_opt u tab.media) p
  @ outline)
  |> List.filter (fun (top, bottom, _) -> bottom > scroll && top < scroll +. (area_height m /. z))
  |> List.map (fun (_, _, s) -> s)
  |> group
  (* claude: the page's units made the window's: zoomed, about its top left *)
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
  (* claude: the characters a line of [w] units holds: a whole line of
   * the panel, or one of its two halves *)
  let chars w = int_of_float (w /. cell) in
  let x = left m +. 10. and half = chars ((width m /. 2.) -. 20.) in
  let body =
    match (m.panel, tab.state, m.selected) with
    | Network, _, _ -> lines ~x ~max:(chars (width m -. 40.)) (Browser_devtools.network tab.requests ~times:(fun url -> List.assoc_opt url (current m).times))
    | Elements, Shown p, Some e ->
        lines ~x ~max:half (Browser_devtools.element p e)
        @ [ rectangle edge 1. (panel_height m -. 20.) |> move 0. (panel_top m -. 20. -. ((panel_height m -. 20.) /. 2.)) ]
        @ lines ~x:6. ~max:half (Browser_devtools.styles (settings m tab) p e)
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
  let editing = m.omnibox <> None in
  let omnibox = match m.omnibox with Some field -> Gui_field.shown field | None -> current_url m in
  (* the address as Chrome shows it: the scheme and host dark, the rest
   * grey *)
  let host_end =
    match String.index_from_opt omnibox (min (String.length omnibox) (try String.index omnibox ':' + 3 with Not_found -> 0)) '/' with
    | Some i when not editing -> i
    | _ -> String.length omnibox
  in
  (* claude: the zoom, when not 100%, left of "JS" *)
  let percent = Browser_zoom.label (zoom_of m tab) in
  let shown = Browser_text.tail (int_of_float ((omnibox_w m -. 52. -. (cell *. float_of_int (String.length percent + 1))) /. cell)) omnibox in
  let dark = String.sub shown 0 (min (String.length shown) host_end) in
  [ rectangle background (width m) (height m) ]
  @ body
  @ Gui_scrollbar.shapes (scrollbar m) ~lit:(m.grab <> None || Gui_scrollbar.at (scrollbar m) m.mouse <> None)
  (* the chrome over what overflows *)
  @ [ rectangle frame (width m) 44. |> move_y (top m -. 22.);
      rectangle toolbar (width m) 42. |> move_y (area_top m +. 21.);
      rectangle edge (width m) 1. |> move_y (area_top m) ]
  @ Gui_tabs.shapes (strip m) ~time:m.time
  @ Gui_toolbar.shapes (buttons m)
  @ Gui_field.box ~x:(omnibox_x m) ~y:(toolbar_y m) ~w:(omnibox_w m)
  @ monospace (omnibox_x m +. 10.) (toolbar_y m) muted shown
  @ monospace (omnibox_x m +. 10.) (toolbar_y m) ink dark
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

(* claude: the window, its units made the screen's dots *)
let view (m : model) : shape list = [ group (view_unscaled m) |> scale (scale_of m) ]

(*****************************************************************************)
(* The app *)
(*****************************************************************************)

(* claude: the profile not saved yet, and where it goes: what is
 * written when the program ends (main's at_exit). The Playground has
 * no message for the window closed -- it exits -- so the model's last
 * state is kept here, after each update *)
let unsaved : (string * Browser_profile.t) option ref = ref None

let app (caps : < Cap.network ; Cap.open_out ; .. >) (profile : Browser_profile.t * string option) ~(desktop : float) ~(window : int * int) =
  {
    Playground.init = init caps profile ~desktop ~window;
    update =
      (fun msg m ->
        let m, cmd = update caps msg m in
        unsaved := (match m.profile_dir with Some dir when m.profile <> m.saved -> Some (dir, m.profile) | _ -> None);
        (m, cmd));
    view;
    subscriptions =
      (fun _ ->
        Sub.batch
          [ Sub.on_animation_frame (fun t -> Tick t); Sub.on_key_down (fun key -> Key key); Sub.on_key_up (fun key -> Key_up key);
            Sub.on_typed (fun s -> Typed s); Sub.on_mouse_wheel (fun n -> Wheel n);
            Sub.on_mouse_move (fun (x, y) -> Mouse_move (x, y)); Sub.on_mouse_down (fun () -> Click); Sub.on_mouse_up (fun () -> Mouse_up); Sub.on_right_mouse_down (fun () -> Right_click);
            Sub.on_resize (fun w h -> Resized (w, h)) ]);
  }

(* threads on, as in TinyNetscape (N2): a name resolved, an https://
 * page fetched, on the platform's threads *)
let main = Program.main __MODULE__ (fun () ->
  Cap.main (fun caps ->
      let flags = Playground_platform.flags () in
      (* claude: -v, -debug and -quiet are the Playground's, read by
       * flags (): Logs' level. A line at a time, the answers coming
       * from the pool's threads too (Tls_client's roots) *)
      let lock = Mutex.create () in
      Logs.set_reporter_mutex ~lock:(fun () -> Mutex.lock lock) ~unlock:(fun () -> Mutex.unlock lock);
      Logs.info (fun m -> m "ran as %s from %s" (CapSys.argv caps).(0) (Sys.getcwd ()));
      let flags = if List.mem_assoc "threads" flags then flags else ("threads", "on") :: flags in
      (* claude: an application's window: resized, the page is laid out
       * again at its width rather than the picture scaled. It starts
       * at the size it was last, the profile's (-size WxH, the
       * Playground's, is stronger); the first time at 1280 by 900 of
       * its units, more dots at the desktop's scale. scale=N is a
       * scale chosen on the command line *)
      let profile, profile_dir = profile_of caps flags in
      let profile =
        match Option.bind (List.assoc_opt "scale" flags) float_of_string_opt with
        | Some s when s >= 0.25 && s <= 5. -> { profile with scale = Some s }
        | _ -> profile
      in
      let desktop = Gui_scale.desktop caps in
      let scale = Option.value profile.scale ~default:desktop in
      let window = Option.value profile.window ~default:(int_of_float (1280. *. scale), int_of_float (900. *. scale)) in
      (* claude: the window closed (the Playground exits), -dump-frame's
       * frame written: what changed in the last second is saved *)
      at_exit (fun () ->
          Logs.info (fun m -> m "quitting");
          Option.iter (fun (dir, p) -> ignore (Browser_profile.save caps ~dir p)) !unsaved);
      Playground_platform.run_app ~screen:window ~screen_follows_window:true ~flags (app caps (profile, profile_dir) ~desktop ~window)))
