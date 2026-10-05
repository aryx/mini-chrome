(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_browser_menu.mli *)

let labels (items : 'a Gui_menu.item list) = List.map (fun (i : 'a Gui_menu.item) -> (i.label, i.enabled)) items
let number = Alcotest.float 0.0001
let item ?(enabled = true) (label : string) : string Gui_menu.item = { label; value = label; enabled }

let tests =
  Testo.categorize "Gui_menu"
    [
      Testo.create "the worked example: a menu near the window's corner" (fun () ->
          let m = Gui_menu.opened ~screen:(1000., 700.) ~at:(480., -330.) [ item "Open link in new tab"; item "Inspect" ] in
          Alcotest.(check (pair number number)) "size" (148., 52.) (Gui_menu.width m, Gui_menu.height m);
          Alcotest.(check (pair number number)) "moved into the window" (352., -298.) (m.left, m.top);
          Alcotest.(check (pair number number)) "the point remembered" (480., -330.) m.at;
          Alcotest.(check (option int)) "the first item" (Some 0) (Gui_menu.index_at m (400., -310.));
          Alcotest.(check (option int)) "the second" (Some 1) (Gui_menu.index_at m (400., -335.));
          Alcotest.(check (option string)) "chosen" (Some "Inspect") (Gui_menu.chosen m (400., -335.));
          Alcotest.(check (option int)) "left of it" None (Gui_menu.index_at m (300., -310.));
          Alcotest.(check (option int)) "under it" None (Gui_menu.index_at m (400., -349.)));
      Testo.create "with room, its corner is the point; a grey item is not chosen" (fun () ->
          let m = Gui_menu.opened ~screen:(1000., 700.) ~at:(-100., 50.) [ item "Back"; item ~enabled:false "Forward" ] in
          Alcotest.(check (pair number number)) "at the point" (-100., 50.) (m.left, m.top);
          Alcotest.(check (option int)) "above it" None (Gui_menu.index_at m (-90., 60.));
          Alcotest.(check (option int)) "on Forward" (Some 1) (Gui_menu.index_at m (-90., 15.));
          Alcotest.(check (option string)) "not chosen" None (Gui_menu.chosen m (-90., 15.));
          (* the shadow, the edge, the card, 4 and 7 letters; and the lit item *)
          Alcotest.(check int) "shapes" 14 (List.length (Gui_menu.shapes m ~pointer:(0., 300.)));
          Alcotest.(check int) "Back lit" 15 (List.length (Gui_menu.shapes m ~pointer:(-90., 35.)));
          Alcotest.(check int) "Forward, grey, not lit" 14 (List.length (Gui_menu.shapes m ~pointer:(-90., 15.))));
      Testo.create "text in cells: a character a cell" (fun () ->
          Alcotest.(check number) "4 cells of 6" 24. (Gui_text.width "caf\xc3\xa9");
          Alcotest.(check int) "the space is an empty cell" 2 (List.length (Gui_text.monospace 100. 0. Playground.black "a b"));
          Alcotest.(check int) "no more than max" 3 (List.length (Gui_text.monospace ~max:3 0. 0. Playground.black "abcdef")));
      Testo.create "Browser_menu: a link's menu, the page's" (fun () ->
          let items = Browser_menu.items ~link:(Some "http://x.org/a") ~back:true ~forward:false () in
          Alcotest.(check (list (pair string bool))) "a link's" [ ("Open link in new tab", true); ("Inspect", true) ] (labels items);
          Alcotest.(check bool) "the link's address" true ((List.hd items).value = Browser_menu.Open_in_new_tab "http://x.org/a");
          Alcotest.(check (list (pair string bool))) "the page's" [ ("Back", true); ("Forward", false); ("Reload", true); ("Inspect", true) ]
            (labels (Browser_menu.items ~link:None ~back:true ~forward:false ()));
          (* a helper program for the address: Browser_helpers' worked example *)
          let rules = Browser_helpers.of_json (Result.get_ok (Json.parse {|[{"site": "youtube.com/watch", "run": ["mpv", "%u"]}, {"type": "application/postscript", "run": ["gv", "%f"]}, {"run": ["rm"]}, {"site": "x.org", "run": []}]|})) in
          Alcotest.(check int) "the rules read, those of no site and type or no program left out" 2 (List.length rules);
          Alcotest.(check bool) "written back as read" true (Browser_helpers.of_json (Browser_helpers.to_json rules) = rules);
          let video = "https://www.youtube.com/watch?v=abc" in
          let rule = Option.get (Browser_helpers.for_url rules video) in
          Alcotest.(check (list string)) "by an address: the host and the path's beginning" [ "mpv"; video ] (Browser_helpers.command rule ~url:video ~file:None);
          Alcotest.(check bool) "another path, another host: none" true
            (Browser_helpers.for_url rules "https://www.youtube.com/results" = None && Browser_helpers.for_url rules "https://notyoutube.com/watch" = None && Browser_helpers.for_url rules "about:chrome" = None);
          Alcotest.(check (option string)) "by a type, its parameters not looked at" (Some "gv")
            (Option.map Browser_helpers.name (Browser_helpers.for_type rules "Application/PostScript; x=1"));
          Alcotest.(check (list string)) "%f: the file" [ "gv"; "/tmp/a.ps" ]
            (Browser_helpers.command (Option.get (Browser_helpers.for_type rules "application/postscript")) ~url:"http://x.org/a.ps" ~file:(Some "/tmp/a.ps"));
          Alcotest.(check (list (pair string bool))) "the page's menu with it" [ ("Open with mpv", true); ("Back", false); ("Forward", false); ("Reload", true); ("Inspect", true) ]
            (labels (Browser_menu.items ~helper:("mpv", [ "mpv"; video ]) ~link:None ~back:false ~forward:false ()));
          Alcotest.(check (list (pair string bool))) "a link's" [ ("Open link in new tab", true); ("Open link with mpv", true); ("Inspect", true) ]
            (labels (Browser_menu.items ~helper:("mpv", [ "mpv"; video ]) ~link:(Some video) ~back:false ~forward:false ())));
    ]
