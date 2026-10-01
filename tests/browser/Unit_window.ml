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

let tests caps =
  Testo.categorize "Window"
    [
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
          Alcotest.(check string) "a scheme" "about:tube" (Window_tabs.typed_url "wikipedia" " about:tube ");
          Alcotest.(check string) "a host with a dot" "https://news.ycombinator.com" (Window_tabs.typed_url "wikipedia" "news.ycombinator.com");
          Alcotest.(check string) "a word" "https://en.wikipedia.org/w/index.php?search=ocaml" (Window_tabs.typed_url "wikipedia" "ocaml");
          Alcotest.(check string) "words with a dot" "https://html.duckduckgo.com/html/?q=ocaml+5.0" (Window_tabs.typed_url "duckduckgo" "ocaml 5.0"));
      Testo.create "the command line: the words that are not flags are pages" (fun () ->
          let pages = Window_update.first_pages "wikipedia" in
          Alcotest.(check (list string)) "none: the home page" [ "about:chrome" ] (pages [ ("profile", "off"); ("threads", "on") ]);
          Alcotest.(check (list string)) "an address" [ "https://news.ycombinator.com" ] (pages [ ("news.ycombinator.com", ""); ("scale", "2") ]);
          Alcotest.(check (list string)) "url= first, then the words; a query's = put back"
            [ "about:tube"; "about:history"; "https://x.org/?a=b" ]
            (pages [ ("about:history", ""); ("url", "about:tube"); ("https://x.org/?a", "b") ]);
          Alcotest.(check bool) "every flag read is named" true
            (List.for_all (fun f -> List.mem f Window_update.flag_names) [ "url"; "css"; "panel"; "search"; "scripts"; "threads"; "profile"; "scale"; "opti" ]));
    ]
