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
 * Ctrl and + (or =), Ctrl and -, Ctrl and the wheel **zoom**
 * the page, Ctrl and 0 back to 100% (Browser_zoom: Chrome's steps,
 * each site its own zoom). The whole page grows, not its fonts alone:
 * laid out at the window's width divided by the zoom, and drawn
 * scaled; the zoom shows in the omnibox when not 100%.
 *
 * a page longer than the window has a **scrollbar** at its
 * right (Gui_scrollbar), over the page's edge: its thumb dragged, its
 * track clicked above or below for a page up or down.
 *
 * the words of the command line that are not flags are the
 * first pages, a tab each, as Chrome's: an address
 * (mini-chrome news.ycombinator.com) or words to search.
 *
 * the whole window is drawn at a **scale**, a browser's device
 * scale factor: the desktop's (Gui_scale: 2 where GNOME says a screen
 * has twice the dots, and the chrome's letters of 6 could not be read),
 * or the one chosen with Ctrl, Shift and + or - (Ctrl Shift 0: the
 * desktop's again), kept in the profile. The program still works in
 * its own units, the window being that many times fewer of them: the
 * view is scaled whole, the pointer and the window's size divided. A
 * site's zoom (Ctrl +) multiplies it, for that site's pages.
 *
 * a **right click** on the page opens Chrome's context menu
 * (Browser_menu, drawn by libs/gui's Gui_menu): on a link, Open link in new tab (a tab behind the
 * one shown) and Inspect; elsewhere Back, Forward, Reload, Inspect.
 * A click on an item does it; any click, Escape, the wheel close it.
 *
 * the **profile** (Browser_profile) is what is kept from one
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
 * times bigger; opti=off, the simple code where an optimized one
 * replaced it (Mini_opti). And the Playground's, with a
 * dash: -v (or -verbose) says on the terminal each file and URL
 * opened, -debug more (the keys pressed), -quiet nothing (Logs).
 *
 * Uses: appkit_browser (the tab, the page, Browser_boxes,
 * Browser_devtools, the forms), the web engine (Cascade, Computed, Box_layout,
 * Flex_layout, and Hit through the page's Html_layout view),
 * libs/images (Svg) through Browser_boxes and Browser_picture,
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
open Window_model

(* this file is the program's main: the profile read, the
 * capabilities handed down, the Playground run. The program itself is
 * src/window's: Window_model (the state and the messages),
 * Window_layout (the model read), Window_tabs (the model changed),
 * Window_update and Window_view. *)

(* the profile, read before the window is made (its size is in
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

(* the profile not saved yet, and where it goes: what is
 * written when the program ends (main's at_exit). The Playground has
 * no message for the window closed -- it exits -- so the model's last
 * state is kept here, after each update *)
let unsaved : (string * Browser_profile.t) option ref = ref None

(* the cookies with a date are kept in the profile's directory
 * (Browser_cookies): read into the jar at the start, written when the
 * jar has changed -- at most every few seconds while pages load (each
 * answer may set one), and when the program ends. [written]: the jar's
 * count of changes at the last writing, and when that was *)
let cookies_of (caps : < Cap.open_in ; .. >) (dir : string option) : Cookie_jar.t =
  let kept =
    match Option.map (fun dir -> Browser_cookies.load caps ~now:(Unix.gettimeofday ()) ~dir) dir with
    | Some (Ok cookies) -> cookies
    | Some (Error why) ->
        Logs.warn (fun m -> m "the cookies kept are not used: %s" why);
        []
    | None -> []
  in
  Cookie_jar.create ~cookies:kept ()

let written : (int * float) ref = ref (0, 0.)

let save_cookies (caps : < Cap.open_out ; .. >) ?(now = false) (dir : string option) (jar : Cookie_jar.t) : unit =
  match dir with
  | Some dir when Cookie_jar.changes jar <> fst !written && (now || Unix.gettimeofday () -. snd !written >= 5.) ->
      written := (Cookie_jar.changes jar, Unix.gettimeofday ());
      (match Browser_cookies.save caps ~dir (Cookie_jar.cookies jar) with Ok () -> () | Error why -> Logs.warn (fun m -> m "the cookies are not saved: %s" why))
  | _ -> ()

let app (caps : < Cap.network ; Cap.open_out ; .. >) (profile : Browser_profile.t * string option) ~(jar : Cookie_jar.t) ~(desktop : float) ~(window : int * int) =
  {
    Playground.init = Window_update.init caps ~jar profile ~desktop ~window;
    update =
      (fun msg m ->
        let m, cmd = Window_update.update caps msg m in
        (match msg with Tick _ -> save_cookies caps m.profile_dir jar | _ -> ());
        unsaved := (match m.profile_dir with Some dir when m.profile <> m.saved -> Some (dir, m.profile) | _ -> None);
        (m, cmd));
    view = Window_view.view;
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
      (* -v, -debug and -quiet are the Playground's, read by
       * flags (): Logs' level. A line at a time, the answers coming
       * from the pool's threads too (Tls_client's roots) *)
      let lock = Mutex.create () in
      Logs.set_reporter_mutex ~lock:(fun () -> Mutex.lock lock) ~unlock:(fun () -> Mutex.unlock lock);
      Logs.info (fun m -> m "ran as %s from %s" (CapSys.argv caps).(0) (Sys.getcwd ()));
      let flags = if List.mem_assoc "threads" flags then flags else ("threads", "on") :: flags in
      (* opti=off: the simple code, where an optimized one
       * replaced it (Mini_opti.mli) *)
      if List.assoc_opt "opti" flags = Some "off" then begin
        Mini_opti.enabled := false;
        Logs.info (fun m -> m "opti=off: the simple code paths")
      end;
      (* letters=segments: a letter drawn as its pen's strokes,
       * the simple way, rather than as one picture (Glyph_picture) *)
      (match List.assoc_opt "letters" flags with
      | Some "segments" -> Mini_opti.letters := Segments
      | Some "pictures" -> Mini_opti.letters := Pictures
      | _ -> ());
      (* pdf=strokes: a PDF file's text drawn with our own letters at
       * the file's widths, not with the fonts it carries; and
       * -gradients, -clips, -pictures, -transparency, or plain for the
       * simplest rendering (Pdf_render.options) *)
      Option.iter (fun words -> Pdf_viewer.options := Pdf_render.options_of_string words) (List.assoc_opt "pdf" flags);
      (* an application's window: resized, the page is laid out
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
      (* the window closed (the Playground exits), -dump-frame's
       * frame written: what changed in the last second is saved *)
      let jar = cookies_of caps profile_dir in
      at_exit (fun () ->
          Logs.info (fun m -> m "quitting");
          save_cookies caps ~now:true profile_dir jar;
          Option.iter (fun (dir, p) -> ignore (Browser_profile.save caps ~dir p)) !unsaved);
      (* opti: a frame whose view is the list of the frame before
       * is not drawn again (Window_view.view gives it back when the
       * window has nothing new to show) *)
      Playground_platform.run_app ~flags
        ~window:{ Playground.default_window with screen_size = Some window; follows_window = true; skip_same_view = true } (app caps (profile, profile_dir) ~jar ~desktop ~window)))
