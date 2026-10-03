(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_gui.mli *)

let number = Alcotest.float 0.0001

let hit : string Gui_tabs.hit option Alcotest.testable =
  Alcotest.testable
    (fun f h ->
      Format.pp_print_string f
        (match h with Some (Gui_tabs.Close v) -> "Close " ^ v | Some (Show v) -> "Show " ^ v | Some New -> "New" | None -> "none"))
    ( = )

let strip (n : int) (room : float) : string Gui_tabs.t =
  { left = -490.; y = 331.; room; current = "tab0"; tabs = List.init n (fun i -> { Gui_tabs.value = Printf.sprintf "tab%d" i; title = "A title"; busy = i = 1 }) }

let tests =
  Testo.categorize "Gui"
    [
      Testo.create "Gui_tabs, the worked example: two tabs in a room of 900" (fun () ->
          let s = strip 2 900. in
          Alcotest.(check number) "220 each" 220. (Gui_tabs.tab_width s);
          Alcotest.(check hit) "the first tab" (Some (Show "tab0")) (Gui_tabs.at s (-400., 331.));
          Alcotest.(check hit) "its close box" (Some (Close "tab0")) (Gui_tabs.at s (-290., 331.));
          Alcotest.(check hit) "the second tab" (Some (Show "tab1")) (Gui_tabs.at s (-250., 331.));
          Alcotest.(check hit) "the +" (Some New) (Gui_tabs.at s (-40., 331.));
          Alcotest.(check hit) "none" None (Gui_tabs.at s (100., 331.));
          Alcotest.(check hit) "under the strip" None (Gui_tabs.at s (-400., 300.)));
      Testo.create "Gui_tabs: tabs share a room too small, their titles cut" (fun () ->
          let s = strip 6 900. in
          Alcotest.(check number) "150 each" 150. (Gui_tabs.tab_width s);
          Alcotest.(check hit) "the fourth tab" (Some (Show "tab3")) (Gui_tabs.at s (-20., 331.));
          let letters (s : string Gui_tabs.t) = List.length (Gui_tabs.shapes s ~time:0.) in
          let long = { s with tabs = List.map (fun (t : string Gui_tabs.tab) -> { t with title = String.make 40 'x' }) s.tabs } in
          (* a tab: its trapezoid, its icon, the two strokes of its close box, its title's letters; then the +'s three *)
          Alcotest.(check int) "\"A title\": 6 letters, its space not drawn" ((6 * (4 + 6)) + 3) (letters s);
          Alcotest.(check int) "15 of 40: (150 - 60) / 6" ((6 * (4 + 15)) + 3) (letters long));
      Testo.create "Gui_toolbar, the worked example: a grey button is not clicked" (fun () ->
          let t : Gui_toolbar.t = { left = -476.; y = 288.; buttons = [ (Back, true); (Forward, false); (Reload, true) ] } in
          Alcotest.(check bool) "Back" true (Gui_toolbar.at t (-470., 290.) = Some Back);
          Alcotest.(check bool) "Forward, grey" true (Gui_toolbar.at t (-440., 290.) = None);
          Alcotest.(check bool) "between two" true (Gui_toolbar.at t (-420., 290.) = None);
          Alcotest.(check bool) "Reload" true (Gui_toolbar.at t (-400., 288.) = Some Reload);
          Alcotest.(check int) "2 shapes, 2 and 4" 8 (List.length (Gui_toolbar.shapes t)));
      Testo.create "Gui_text: what shows of a long text; the bubble" (fun () ->
          Alcotest.(check string) "the end kept" "def" (Gui_text.tail 3 "abcdef");
          Alcotest.(check string) "short: all of it" "ab" (Gui_text.tail 3 "ab");
          Alcotest.(check string) "characters, not bytes" "f\xc3\xa9" (Gui_text.tail 2 "caf\xc3\xa9");
          (* the edge, the card, the letters *)
          Alcotest.(check int) "bubble" 5 (List.length (Gui_text.bubble ~left:(-500.) ~y:(-339.) "a b c")));
      Testo.create "Gui_field, the worked example: a fresh field's text is replaced" (fun () ->
          let shown f = Gui_field.shown f in
          let f = Gui_field.focused "about:chrome" in
          Alcotest.(check string) "focused" "about:chrome_" (shown f);
          let f = Gui_field.typed "n" (Gui_field.typed "h" f) in
          Alcotest.(check string) "typed h, n" "hn_" (shown f);
          Alcotest.(check string) "backspace" "h_" (shown (Gui_field.backspace f));
          Alcotest.(check string) "a fresh field emptied" "_" (shown (Gui_field.backspace (Gui_field.focused "x")));
          Alcotest.(check string) "a character, not a byte" "caf_" (shown (Gui_field.backspace (Gui_field.typed "caf\xc3\xa9" (Gui_field.focused ""))));
          Alcotest.(check string) "nothing left to take" "_" (shown (Gui_field.backspace (Gui_field.backspace (Gui_field.typed "a" (Gui_field.focused "")))));
          Alcotest.(check int) "its box: the edge, the white" 2 (List.length (Gui_field.box ~x:0. ~y:0. ~w:100.)));
      Testo.create "Gui_scale, the worked example: xrdb's Xft.dpi" (fun () ->
          let scale = Alcotest.(option (float 0.0001)) in
          Alcotest.(check scale) "192: twice" (Some 2.) (Gui_scale.of_xrdb "Xft.dpi:\t192\nXft.antialias:\t1\n");
          Alcotest.(check scale) "144" (Some 1.5) (Gui_scale.of_xrdb "Xcursor.size:\t24\nXft.dpi:\t144\n");
          Alcotest.(check scale) "96: no scaling" (Some 1.) (Gui_scale.of_xrdb "Xft.dpi: 96");
          Alcotest.(check scale) "no Xft.dpi" None (Gui_scale.of_xrdb "Xft.antialias:\t1\n");
          Alcotest.(check scale) "not a number" None (Gui_scale.of_xrdb "Xft.dpi:\tbig\n");
          Alcotest.(check scale) "not believed" None (Gui_scale.of_xrdb "Xft.dpi:\t9600\n");
          Alcotest.(check scale) "nothing" None (Gui_scale.of_xrdb "");
          Alcotest.(check bool) "X's display" false (Gui_scale.of_launchd ":0");
          Alcotest.(check bool) "a host's" false (Gui_scale.of_launchd "localhost:10.0");
          Alcotest.(check bool) "launchd's socket: macOS" true
            (Gui_scale.of_launchd "/var/run/com.apple.launchd.xWCBaDyqgY/org.xquartz:0"));
      Testo.create "Gui_scrollbar, the worked example: the thumb, a drag, the track" (fun () ->
          let thumb = Alcotest.(option (pair number number)) in
          let bar : Gui_scrollbar.t = { right = 500.; top = 250.; height = 600.; total = 300.; shown = 60.; offset = 120. } in
          Alcotest.(check thumb) "120 long, from y = 10" (Some (10., 120.)) (Gui_scrollbar.thumb bar);
          Alcotest.(check bool) "a press on the thumb, 10 under its top" true (Gui_scrollbar.at bar (494., 0.) = Some (Thumb 10.));
          Alcotest.(check number) "dragged to -120: scrolled by 180" 180. (Gui_scrollbar.dragged bar ~grab:10. (-120.));
          Alcotest.(check number) "dragged past the end: all the way" 240. (Gui_scrollbar.dragged bar ~grab:10. (-900.));
          Alcotest.(check number) "past the start" 0. (Gui_scrollbar.dragged bar ~grab:10. 900.);
          Alcotest.(check bool) "above the thumb" true (Gui_scrollbar.at bar (494., 100.) = Some Before);
          Alcotest.(check bool) "below it" true (Gui_scrollbar.at bar (494., -200.) = Some After);
          Alcotest.(check bool) "left of the bar" true (Gui_scrollbar.at bar (480., 0.) = None);
          Alcotest.(check bool) "under the track" true (Gui_scrollbar.at bar (494., -360.) = None);
          Alcotest.(check int) "drawn: its thumb" 1 (List.length (Gui_scrollbar.shapes bar ~lit:false)));
      Testo.create "Gui_scrollbar: what fits has no bar; a long page's thumb is not too short" (fun () ->
          let bar : Gui_scrollbar.t = { right = 500.; top = 250.; height = 600.; total = 40.; shown = 60.; offset = 0. } in
          Alcotest.(check bool) "no thumb" true (Gui_scrollbar.thumb bar = None);
          Alcotest.(check bool) "nothing under a point" true (Gui_scrollbar.at bar (494., 0.) = None);
          Alcotest.(check int) "nothing drawn" 0 (List.length (Gui_scrollbar.shapes bar ~lit:true));
          let long = { bar with total = 100000.; offset = 99940. } in
          Alcotest.(check (option (pair number number))) "24 long, at the track's end" (Some (-326., 24.)) (Gui_scrollbar.thumb long));
      Testo.create "Gui_kit.near: a box from x, around the line y" (fun () ->
          Alcotest.(check bool) "inside" true (Gui_kit.near 10. 0. 20. 10. (15., 4.));
          Alcotest.(check bool) "left of it" false (Gui_kit.near 10. 0. 20. 10. (9., 0.));
          Alcotest.(check bool) "above it" false (Gui_kit.near 10. 0. 20. 10. (15., 6.)));
    ]
