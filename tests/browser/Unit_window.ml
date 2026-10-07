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
      Testo.create "a helper program: run on a file of the content, and one that is not there" (fun () ->
          let rule : Browser_helpers.rule = { site = None; kind = Some "application/postscript"; run = [ "true"; "%f" ] } in
          let page = Browser_helpers.opened caps rule ~url:"http://x.org/paper.ps" "%!PS-Adobe-3.0" in
          let has sub = Str.string_match (Str.regexp (".*" ^ Str.quote sub)) page 0 in
          Alcotest.(check bool) ("the tab told: " ^ page) true (has "Opened with <b>true</b>" && has "paper.ps");
          (* the rules that need no writing, the person's before them; a program not on the machine is no rule *)
          let own : Browser_helpers.t = [ { site = Some "youtube.com/watch"; kind = None; run = [ "sh"; "%u" ] }; { site = Some "x.org"; kind = None; run = [ "mini-chrome-no-such-program" ] } ] in
          let video = "https://www.youtube.com/watch?v=abc" in
          Alcotest.(check (option string)) "the person's rule first" (Some "sh") (Option.map Browser_helpers.name (Browser_helpers.for_url (Browser_helpers.table caps own) video));
          Alcotest.(check bool) "the default: a video of YouTube's to mpv" true
            (List.for_all (fun (r : Browser_helpers.rule) -> r.run = [ "mpv"; "%u" ] && r.kind = None) Browser_helpers.defaults
            && Option.map Browser_helpers.name (Browser_helpers.for_url Browser_helpers.defaults video) = Some "mpv");
          Alcotest.(check bool) "a program that is not there: no rule" true (Browser_helpers.for_url (Browser_helpers.table caps own) "http://x.org/" = None);
          Alcotest.(check bool) "a program that does not exist is an error, not a crash" true
            (match Browser_helpers.launch caps [ "mini-chrome-no-such-program" ] with Error _ -> true | Ok () -> false));
      Testo.create "the omnibox suggests and completes the pages seen" (fun () ->
          let now = Unix.gettimeofday () in
          let places =
            Places.create
              ~entries:
                [ { url = "https://dynamicland.org/"; title = "Dynamicland front shelf"; visits = 3; last = now };
                  { url = "https://news.ycombinator.com/"; title = "Hacker News"; visits = 9; last = now };
                  { url = "about:history"; title = "kept by hand: a built-in page all the same"; visits = 1; last = now -. (100. *. 86400.) } ]
              ()
          in
          let m = after caps (Window_update.init caps ~places (Browser_profile.empty, None) ~desktop:1. ~window:(800, 600) [ ("url", "about:home"); ("threads", "off") ]) in
          let send msg m = after caps (Window_update.update caps msg m) in
          let typed word m = List.fold_left (fun m c -> send (Typed (String.make 1 c)) m) m (List.init (String.length word) (String.get word)) in
          let field (m : Window_model.model) = match m.omnibox with Some f -> (f.text, Gui_field.selected f) | None -> ("", "") in
          let listed (m : Window_model.model) = match Window_layout.suggestions m with Some menu -> List.map (fun (i : string Gui_menu.item) -> i.value) menu.items | None -> [] in
          let opened = send Mouse_up (send Click { m with mouse = (Window_layout.omnibox_x m +. 30., Window_layout.toolbar_y m) }) in
          Alcotest.(check (list string)) "the address clicked, nothing typed: nothing suggested" [] (listed opened);
          let dyna = typed "dyna" opened in
          Alcotest.(check (pair string string)) "dyna: the site it begins, the rest selected" ("dynamicland.org", "micland.org") (field dyna);
          Alcotest.(check (list string)) "and listed under it" [ "https://dynamicland.org/" ] (listed dyna);
          Alcotest.(check (pair string string)) "Backspace takes the completion away, and no other comes" ("dyna", "") (field (send (Key "Backspace") dyna));
          Alcotest.(check string) "Enter: the page seen, its scheme and all" "https://dynamicland.org/" (Window_layout.current_url (send (Key "Return") dyna));
          let inside = typed "land" opened in
          Alcotest.(check (pair string string)) "land: the start of no address, nothing completed" ("land", "") (field inside);
          Alcotest.(check (list string)) "but found inside one" [ "https://dynamicland.org/" ] (listed inside);
          let chosen = send (Key "Down") inside in
          Alcotest.(check (option int)) "the arrow chooses it" (Some 0) chosen.suggested;
          Alcotest.(check string) "Enter goes there" "https://dynamicland.org/" (Window_layout.current_url (send (Key "Return") chosen));
          let both = typed "n" opened in
          Alcotest.(check (list string)) "n: the likeliest first (nine visits, three, one long ago)" [ "https://news.ycombinator.com/"; "https://dynamicland.org/"; "about:history" ] (listed both);
          (* a click on a line of the list *)
          let menu = Option.get (Window_layout.suggestions both) in
          let on_second = { both with mouse = (menu.left +. 20., Gui_menu.row menu 1) } in
          Alcotest.(check string) "a suggestion clicked is gone to" "https://dynamicland.org/" (Window_layout.current_url (send Click on_second)));
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
      Testo.create "a page that is a program: a key tapped between two of its frames is seen held" (fun () ->
          let m = window caps "about:chrome" in
          let script = match (Window_layout.current_tab m).script with Some s -> s | None -> Alcotest.fail "about:chrome runs scripts" in
          (* a program that reads, at each frame, the keys held *)
          (match
             Browser_script.eval script
               "var held = [], frames = [];\naddEventListener('keydown', function (e) { held.push(e.key) });\naddEventListener('keyup', function (e) { held = held.filter(function (k) { return k !== e.key }) });\naddEventListener('mousedown', function () { held.push('button') });\naddEventListener('mouseup', function () { held = held.filter(function (k) { return k !== 'button' }) });\nfunction frame() { frames.push(held.join('+')); requestAnimationFrame(frame) }\nrequestAnimationFrame(frame)"
           with
          | Ok _ -> ()
          | Error e -> Alcotest.fail e.message);
          let send msg m = after caps (Window_update.update caps msg m) in
          let frames () = match Browser_script.eval script "frames.slice(-3).join(' | ')" with Ok v -> Js_value.display v | Error e -> e.message in
          let m = { m with omnibox = None } in
          let m = tick caps 10. (tick caps 10.02 m) in
          (* down and up with no frame between: the up waits for the frame *)
          let m = send (Key_up "a") (send (Key "a") m) in
          Alcotest.(check int) "the key let go is kept" 1 (List.length m.late);
          let m = tick caps 10.04 m in
          Alcotest.(check string) "the frame saw it held" " |  | a" (frames ());
          Alcotest.(check bool) "then it was let go" true (m.late = [] && m.fresh = []);
          let m = tick caps 10.06 m in
          Alcotest.(check string) "and the next frame sees it up" " | a | " (frames ());
          (* a key held across a frame: its up is told at once *)
          let m = tick caps 10.08 (send (Key "ArrowLeft") m) in
          let m = send (Key_up "ArrowLeft") m in
          Alcotest.(check int) "nothing kept" 0 (List.length m.late);
          let m = tick caps 10.1 m in
          Alcotest.(check string) "held one frame, then up" " | ArrowLeft | " (frames ());
          (* the button, pressed and let go over the page in one frame *)
          let m = send Mouse_up (send Click (send (Mouse_move (0., 0.)) m)) in
          Alcotest.(check bool) "the button let go is kept" true (m.late = [ Mouse_up ]);
          let m = tick caps 10.12 m in
          Alcotest.(check string) "the frame saw it pressed" "ArrowLeft |  | button" (frames ());
          (* and its click: after the mouseup, with where it was (Gmail's
           * list took a click told before its mouseup for none) *)
          (match Browser_script.eval script "var order = [];\n['mousedown', 'mouseup', 'click'].forEach(function (t) { document.addEventListener(t, function (e) { order.push(t + ' ' + typeof e.clientX + ' ' + e.button) }) })" with
          | Ok _ -> ()
          | Error e -> Alcotest.fail e.message);
          let m = tick caps 10.14 m in
          let m = send Click m in
          let m = tick caps 10.16 m in
          let m = tick caps 10.18 (send Mouse_up m) in
          Alcotest.(check string) "down, up, click" {|["mousedown number 0", "mouseup number 0", "click number 0"]|} (match Browser_script.eval script "order" with Ok v -> Js_value.display v | Error e -> e.message);
          (* the page's clock is the time that passed, not a frame's
           * sixtieth of a second each Tick: a timer of two seconds comes
           * two seconds later, however few frames were drawn meanwhile *)
          (match Browser_script.eval script "var late = 'not yet'; setTimeout(function () { late = 'came' }, 2000)" with Ok _ -> () | Error e -> Alcotest.fail e.message);
          let late () = match Browser_script.eval script "late" with Ok v -> Js_value.display v | Error e -> e.message in
          let m = tick caps 10.2 m in
          let m = tick caps 11.2 m in
          Alcotest.(check string) "a second later, two frames: not due" "not yet" (late ());
          let m = tick caps 12.3 m in
          Alcotest.(check string) "two seconds later, three frames: due" "came" (late ());
          ignore m);
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
