(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Window_tabs.mli *)
open Window_model
open Window_layout (* the model read: its geometry, its shown tab *)

(*****************************************************************************)
(* A tab's settings *)
(*****************************************************************************)

let settings (m : model) (tab : Browser_tab.t) : Browser_page.settings =
  {
    css = m.css;
    (* CSS 2.1's box model: Cascade, Computed, Box_layout *)
    engine = None;
    width = page_width m /. zoom_of m tab;
    (* the page area's, less with the panel open: CSS's 100vh *)
    height = area_height m /. zoom_of m tab;
    visited = (fun url -> List.mem url tab.visited);
    picture = (fun url -> List.assoc_opt url tab.pictures);
    sheet = (fun url -> List.assoc_opt url tab.sheets);
    (* a frame's document as its scripts have it (Browser_script.adopt) *)
    framed = (fun key -> Option.bind tab.script (fun s -> Browser_script.frame_tree s key));
  }

(* whose scripts run: every site's ("*"), the browser's setting, which
 * a click on the omnibox's "JS" turns off and on for all; or the
 * hosts named (scripts=host1,host2). It was a list of the few sites
 * whose scripts the engine could run (Hacker News, then the
 * Playground's programs, 9fans, Discourse, GitHub: docs/plans/
 * plan_sites.md), until those were the heavy ones *)
let everywhere = "*"
let default_allowed = [ everywhere ]
let scripts_on (m : model) : bool = List.mem everywhere m.allowed

let config (m : model) (id : int) : msg Browser_tab.config =
  {
    settings = settings m;
    (* the built-in site, and TinyTube in it *)
    about =
      (fun name ->
        match name with
        (* the jar as a page, made when asked for *)
        | "version" ->
            Some
              ( Browser_version.page ~threads:(Fetch.threads m.fetches) ~workers:Fetch.workers ~profile:m.profile_dir
                  ~cache:(Option.map (fun (c : Http_cache.store) -> c.place) (Fetch.cache m.fetches)),
                "text/html; charset=utf-8" )
        | "cache" -> Some (Browser_cache.page ~now:(Unix.gettimeofday ()) (Fetch.cache m.fetches), "text/html; charset=utf-8")
        | "memory" ->
            let cache = Option.map (fun (c : Http_cache.store) -> let es = c.entries ~now:(Unix.gettimeofday ()) in (List.length es, List.fold_left (fun n (_, size, _, _) -> n + size) 0 es, c.place)) (Fetch.cache m.fetches) in
            Some (Browser_memory.page ~samples:m.memory ~tabs:(List.map (fun (t : tab) -> Browser_memory.tab t.tab) m.tabs) ~cache ~profile:m.profile_dir, "text/html; charset=utf-8")
        | "bookmarks" -> Some (Bookmarks.page m.profile.bookmarks, "text/html; charset=utf-8")
        | "cookies" -> Some (Browser_cookies.page ~now:(Unix.gettimeofday ()) (Cookie_jar.cookies (Fetch.jar m.fetches)), "text/html; charset=utf-8")
        | _ -> ( match Tube.about name with Some x -> Some x | None -> Site.about name));
    got = (fun url r -> Got (id, url, r));
    got_picture = (fun url r -> Got_picture (id, url, r));
    got_answer = (fun rid url r -> Got_answer (id, rid, url, r));
    socket = (fun ask -> Socket (id, ask));
    fetch = (fun r -> Start_fetch r);
    connections = 6;
    visible = (match List.find_opt (fun t -> t.id = id) m.tabs with Some t -> visible_lines m t.tab | None -> 0);
    line_height;
    (* the built-in pages' scripts, and the allowed sites' *)
    scripts = (fun url -> Browser_url.starts_with "about:" url || scripts_on m || List.mem (host_of url) m.allowed);
    cookies = Fetch.jar m.fetches;
    seed = 1;
    epoch = Float.round (Unix.gettimeofday () *. 1000.);
  }

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
      let stamped = stamp m.time { t with tab } in
      (* opti: [f] left the tab as it was (a Tick's task of a
       * page whose scripts did nothing): the model is the one given,
       * not a copy of it, and the view of a page at rest can be seen
       * to be the same (Window_view.view).
       * Before: always
       *   ({ m with tabs = List.map (fun t' -> if t'.id = id then t else t') m.tabs }, cmd) *)
      if tab == t.tab && stamped.times = t.times then (m, cmd)
      else ({ m with tabs = List.map (fun t' -> if t'.id = id then stamped else t') m.tabs }, cmd)

let on_current m f = on_tab m m.current f
let scrolled (by : int) (m : model) : model = fst (on_current m (fun cfg tab -> (Browser_tab.scrolled cfg by tab, Cmd.none)))
(* the wheel's notches as lines: three a notch, a positive one up the page *)
let wheeled (notches : float) (m : model) : model = scrolled (-3 * int_of_float (Float.round notches)) m
let pages (m : model) (by : int) : int = by * (visible_lines m (current_tab m) - 2)

(* every tab's page laid out again (the window resized, a site
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

(* the profile changed: saved once it has been still for a
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

(* the window's size or the scale changed: the screen is the
 * window's dots in the program's units, and every page laid out again
 * at its width *)
let rescreened (m : model) : model =
  let w, h = m.window and s = scale_of m in
  let screen = (float_of_int w /. s, float_of_int h /. s) in
  if screen = m.screen then m else relaid_all { m with screen }

(* the shown page's site at the zoom [f] gives from its own *)
let zoomed (f : float -> float) (m : model) : model =
  let zooms = Browser_zoom.with_host m.profile.zooms (host_of (current_url m)) (f (zoom_of m (current_tab m))) in
  relaid_all (with_profile { m.profile with zooms } m)

(* the shown page's scrollbar, in lines: the page's, those the
 * area shows, those scrolled *)
let scrollbar (m : model) : Gui_scrollbar.t =
  let tab = current_tab m in
  { right = -.left m; top = area_top m; height = area_height m;
    total = float_of_int (Browser_tab.line_count (config m m.current) tab); shown = float_of_int (visible_lines m tab);
    offset = float_of_int tab.scroll }

let visit network url m = on_current { m with omnibox = None; selected = None } (fun cfg tab -> Browser_tab.visit cfg network url tab)
let load ?reload network url m = on_current m (fun cfg tab -> Browser_tab.load ?reload cfg network url tab)

(* a new tab, shown, loading [url] *)
let open_tab (network : < Cap.network ; .. >) (url : string) (m : model) : model * msg Cmd.t =
  let target, fragment = Browser_url.split_fragment url in
  let tab = { (Browser_tab.empty ~images:true) with visited = [ target ]; fragment } in
  let m = { m with tabs = m.tabs @ [ { id = m.next_id; tab; times = [] } ]; current = m.next_id; next_id = m.next_id + 1; selected = None } in
  load network target m

let close_tab (network : < Cap.network ; .. >) (id : int) (m : model) : model * msg Cmd.t =
  Web_sockets.close_tab (Fetch.sockets m.fetches) id;
  match List.filter (fun t -> t.id <> id) m.tabs with
  | [] -> open_tab network home { m with tabs = [] }
  | rest ->
      let current = if m.current = id then (List.nth rest (max 0 (List.length rest - 1))).id else m.current in
      ({ m with tabs = rest; current; selected = None }, Cmd.none)

(* the panel opened, closed or showing another view; the page
 * area's height is the pages' 100vh, so when it changes they are laid
 * out again *)
let with_panel (panel : panel) (m : model) : model =
  let m' = { m with panel } in
  if area_height m' = area_height m then m' else relaid_all m'

let toggle_panel (m : model) : model = with_panel (if m.panel = Closed then Elements else Closed) { m with inspecting = false }
