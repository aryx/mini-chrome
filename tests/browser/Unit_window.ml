(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_window.mli *)

(* the program run by hand: a message given to update, and the
 * messages its commands give back, as the platform does *)
let rec after caps ((m, cmd) : Window_model.model * Window_model.msg Cmd.t) : Window_model.model =
  match cmd with
  | Msg msg -> after caps (Window_update.update caps msg m)
  | Batch cmds -> List.fold_left (fun m c -> after caps (m, c)) m cmds
  | _ -> m

let tick caps (time : float) (m : Window_model.model) : Window_model.model = after caps (Window_update.update caps (Tick time) m)

(* a window showing a built-in page, at rest *)
let window caps (url : string) : Window_model.model =
  let m = after caps (Window_update.init caps (Browser_profile.empty, None) ~desktop:1. ~window:(800, 600) [ ("url", url); ("threads", "off") ]) in
  List.fold_left (fun m t -> tick caps (float_of_int t) m) m [ 1; 2; 3 ]

(* the cursors met with the pointer put all over the page's area, and all over the chrome above it *)
let cursors (m : Window_model.model) ~(page : bool) : Playground.cursor list =
  let top = Window_layout.area_top m in
  let found = ref [] in
  let w = Window_layout.width m and h = Window_layout.height m in
  for ix = 1 to int_of_float (w /. 8.) - 1 do
    for iy = 1 to int_of_float (h /. 6.) - 1 do
      let x = (float_of_int ix *. 8.) -. (w /. 2.) and y = (float_of_int iy *. 6.) -. (h /. 2.) in
      if (y < top -. 4.) = page then (
        let c = Window_layout.cursor_of { m with mouse = (x, y) } in
        if not (List.mem c !found) then found := c :: !found)
    done
  done;
  List.sort compare !found

let tests caps =
  Testo.categorize "Window"
    [
      Testo.create "the omnibox: clicked, its text selected; the keys, a drag, a double click, copy and paste" (fun () ->
          let m = window caps "about:home" in
          let send msg m = after caps (Window_update.update caps msg m) in
          let keys names m = List.fold_left (fun m k -> send (Key k) m) m names in
          let at_char i (m : Window_model.model) = { m with mouse = (Window_layout.omnibox_x m +. 10. +. (Gui_text.cell *. float_of_int i), Window_layout.toolbar_y m) } in
          let field (m : Window_model.model) = match m.omnibox with Some f -> (f.text, Gui_field.selected f, f.caret) | None -> ("", "", -1) in
          let check name expected m = Alcotest.(check (triple string string int)) name expected (field m) in
          let m = send Click (at_char 2 m) in
          check "a click: the address, all selected" ("about:home", "about:home", 10) m;
          let m = send Mouse_up m in
          let end_ = keys [ "End" ] m in
          check "End: the caret after it, nothing selected" ("about:home", "", 10) end_;
          check "typed there: added" ("about:home!", "", 11) (send (Typed "!") end_);
          (* Shift and arrows *)
          let shifted = keys [ "Left"; "Left"; "Left"; "Left" ] { end_ with shift = true } in
          check "Shift and four Lefts" ("about:home", "home", 6) shifted;
          (* a second click, later: the caret; the pointer moved with the button held: a selection *)
          let later = tick caps 9. m in
          let clicked = send Click (at_char 6 later) in
          check "a click in a field that has the keys: the caret" ("about:home", "", 6) clicked;
          let dragged = send (Mouse_move (fst (at_char 10 clicked).mouse *. Window_layout.scale_of clicked, snd clicked.mouse *. Window_layout.scale_of clicked)) clicked in
          check "dragged to the end" ("about:home", "home", 10) dragged;
          let released = send Mouse_up dragged in
          Alcotest.(check bool) "released: the pointer no longer selects" true (not released.selecting && field (send (Mouse_move (0., 0.)) released) = field released);
          (* copied, then pasted over everything *)
          let copied = keys [ "c" ] { released with ctrl = true } in
          Alcotest.(check string) "Ctrl+C: on the clipboard" "home" (Gui_clipboard.get ());
          check "and the field as it was" ("about:home", "home", 10) copied;
          let pasted = keys [ "a"; "v" ] copied in
          check "Ctrl+A, Ctrl+V: the line replaced" ("home", "", 4) pasted;
          check "a letter typed with Ctrl held is not text" ("home", "", 4) (send (Typed "v") pasted);
          let cut = keys [ "a"; "x" ] pasted in
          check "Ctrl+A, Ctrl+X: cut" ("", "", 0) cut;
          (* a double click selects the line; Backspace then deletes it *)
          let again = send Click (send Mouse_up (send Click (at_char 1 (keys [ "v"; "v" ] cut)))) in
          check "a double click: all selected" ("homehome", "homehome", 8) again;
          check "Backspace: the line gone" ("", "", 0) (keys [ "Backspace" ] { again with ctrl = false });
          Alcotest.(check bool) "Escape gives the keys back" true ((keys [ "Escape" ] again).omnibox = None));
      Testo.create "the cursor: a hand over a link, the I-beam where text is typed, the arrow elsewhere" (fun () ->
          let home = window caps "about:home" and form = window caps "about:form" in
          Alcotest.(check bool) "a page of links: the arrow and the hand" true (cursors home ~page:true = [ Playground.Arrow; Hand ]);
          Alcotest.(check bool) "a form: its text fields too" true (List.mem Playground.Text (cursors form ~page:true) && List.mem Playground.Arrow (cursors form ~page:true));
          let name (c : Playground.cursor) = match c with Arrow -> "arrow" | Hand -> "hand" | Text -> "text" | Crosshair -> "crosshair" | Hidden -> "hidden" in
          Alcotest.(check (list string)) "the chrome: the I-beam over the omnibox, the arrow over the rest" [ "arrow"; "text" ] (List.map name (cursors home ~page:false));
          (* a menu open: the arrow, whatever is under it *)
          let menu : Browser_menu.action Gui_menu.t option = Some { at = (0., 0.); left = 0.; top = 0.; items = [] } in
          Alcotest.(check bool) "under the right click's menu" true (cursors { home with menu } ~page:true = [ Playground.Arrow ]);
          Alcotest.(check bool) "a field that is typed in, one that is not" true
            (let el name attributes : Dom.element = { name; attributes; extensions = []; origin = Core; children = [] } in
             Window_layout.is_text_control (el "input" []) && Window_layout.is_text_control (el "textarea" []) && Window_layout.is_text_control (el "input" [ ("type", "Search") ])
             && (not (Window_layout.is_text_control (el "input" [ ("type", "checkbox") ]))) && not (Window_layout.is_text_control (el "button" []))));
      Testo.create "the view of a window at rest is the list of the frame before; opti=off, a new one" (fun () ->
          let m = window caps "about:history" in
          Alcotest.(check bool) "the page is shown" false (Window_layout.loading (Window_layout.current_tab m));
          let shapes = Window_view.view m in
          let later = tick caps 4. m in
          Alcotest.(check bool) "a Tick later: another model" true (later != m && later.time = 4.);
          Alcotest.(check bool) "the same list" true (Window_view.view later == shapes);
          Alcotest.(check bool) "equal to the one built anew" true (Window_view.view later = Window_view.view_simple later);
          let moved = after caps (Window_update.update caps (Mouse_move (10., 20.)) later) in
          Alcotest.(check bool) "the pointer moved: a new list" true (Window_view.view moved != shapes);
          let scrolled = after caps (Window_update.update caps (Key "space") later) in
          Alcotest.(check bool) "the page scrolled: a new list" true (Window_view.view scrolled != shapes);
          Alcotest.(check bool) "and the scrolled page" true (Window_view.view scrolled = Window_view.view_simple scrolled);
          (* a page with a player moves by itself *)
          let tube = window caps "about:tube" in
          Alcotest.(check bool) "a video: a new list at each frame" true (Window_view.view tube != Window_view.view (tick caps 4. tube));
          Mini_opti.enabled := false;
          Fun.protect ~finally:(fun () -> Mini_opti.enabled := true) (fun () ->
              Alcotest.(check bool) "opti=off: a new list at each frame" true (Window_view.view m != Window_view.view (tick caps 5. m))));
      Testo.create "a URL's host" (fun () ->
          Alcotest.(check string) "a page" "news.ycombinator.com" (Window_layout.host_of "https://news.ycombinator.com/item?id=1");
          Alcotest.(check string) "a port" "localhost" (Window_layout.host_of "http://localhost:8000/a");
          Alcotest.(check string) "no path" "x.org" (Window_layout.host_of "http://x.org");
          Alcotest.(check string) "a built-in page: none" "" (Window_layout.host_of "about:chrome"));
      Testo.create "what is typed in the omnibox: an address, or words searched" (fun () ->
          Alcotest.(check string) "a scheme" "about:tube" (Omnibox.destination "wikipedia" " about:tube ");
          Alcotest.(check string) "a host with a dot" "https://news.ycombinator.com" (Omnibox.destination "wikipedia" "news.ycombinator.com");
          Alcotest.(check string) "a word" "https://en.wikipedia.org/w/index.php?search=ocaml" (Omnibox.destination "wikipedia" "ocaml");
          Alcotest.(check string) "words with a dot" "https://html.duckduckgo.com/html/?q=ocaml+5.0" (Omnibox.destination "duckduckgo" "ocaml 5.0"));
      Testo.create "the command line: the words that are not flags are pages" (fun () ->
          let pages = Window_update.first_pages "wikipedia" in
          Alcotest.(check (list string)) "none: the home page" [ "about:chrome" ] (pages [ ("profile", "off"); ("threads", "on") ]);
          Alcotest.(check (list string)) "an address" [ "https://news.ycombinator.com" ] (pages [ ("news.ycombinator.com", ""); ("scale", "2") ]);
          Alcotest.(check (list string)) "url= first, then the words; a query's = put back"
            [ "about:tube"; "about:history"; "https://x.org/?a=b" ]
            (pages [ ("about:history", ""); ("url", "about:tube"); ("https://x.org/?a", "b") ]);
          Alcotest.(check bool) "every flag read is named" true
            (List.for_all (fun f -> List.mem f Window_update.flag_names) [ "url"; "css"; "panel"; "search"; "scripts"; "threads"; "profile"; "scale"; "opti"; "letters" ]));
    ]
