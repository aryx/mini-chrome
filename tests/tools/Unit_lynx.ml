(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_lynx.mli *)

let tests caps =
  let with_site f () = Testutil_httpd.with_server caps Testutil_httpd.site f in
  let opened address : Lynx.page = match Lynx.open_ caps address with Ok p -> p | Error why -> Alcotest.fail why in
  Testo.categorize "Lynx"
    [
      Testo.create "the worked example: a page shown"
        (with_site (fun base ->
             let p = opened (base ^ "/") in
             Alcotest.(check string) "its title and address, its lines, its links by their numbers"
               (String.concat "\n"
                  [ "Menu  (" ^ base ^ "/)"; ""; "                                      Menu"; ""; "Soup of the day. See the recipes[1] or go back home[2].";
                    ""; "[1] " ^ base ^ "/recipes.html"; "[2] " ^ base ^ "/"; "" ])
               (Lynx.show p);
             let narrow = match Lynx.open_ caps ~width:30 (base ^ "/") with Ok p -> p | Error why -> Alcotest.fail why in
             Alcotest.(check (list string)) "in 30 columns" [ "             Menu"; ""; "Soup of the day. See the"; "recipes[1] or go back home[2]." ] narrow.lines));
      Testo.create "what is typed: a number, b, an address, q"
        (with_site (fun base ->
             let home = opened (base ^ "/") in
             let titles (s : Lynx.t) = List.map (fun (p : Lynx.page) -> p.title) s in
             let go session typed = match Lynx.step caps session typed with Go s -> s | Stay why -> Alcotest.fail ("stayed: " ^ why) | Quit -> Alcotest.fail "quit" in
             let s = go [ home ] "1" in
             Alcotest.(check (list string)) "link 1 followed: the page before kept" [ "Recipes"; "Menu" ] (titles s);
             Alcotest.(check (list string)) "b: back" [ "Menu" ] (titles (go s "b"));
             Alcotest.(check (list string)) "an address typed" [ ""; "Recipes"; "Menu" ] (titles (go s (base ^ "/notes/a.txt")));
             Alcotest.(check (list string)) "nothing typed: the same page" [ "Recipes"; "Menu" ] (titles (go s ""));
             let stays session typed = match Lynx.step caps session typed with Stay why -> why | _ -> "moved" in
             Alcotest.(check (list string)) "no such link; nothing before; a page not there"
               [ "no link 9: this page has 2"; "no link 0: this page has 2"; "no page before this one"; base ^ "/nope: 404 Not Found" ]
               [ stays [ home ] "9"; stays [ home ] "0"; stays [ home ] "b"; stays [ home ] (base ^ "/nope") ];
             Alcotest.(check bool) "q" true (Lynx.step caps s " q " = Quit)));
      Testo.create "a file; a text that is not HTML"
        (with_site (fun base ->
             let dir = Testutil_httpd.directory [ ("page.html", "<title>Local</title><ul><li>one<li><a href=two.html>two</a></ul>") ] in
             let p = opened (Filename.concat dir "page.html") in
             Alcotest.(check (triple string (list string) (list string))) "a file's page, its links beside it"
               ("Local", [ "  * one"; "  * two[1]" ], [ "file://" ^ dir ^ "/two.html" ])
               (p.title, p.lines, p.links);
             let t = opened (base ^ "/notes/a.txt") in
             Alcotest.(check (pair (list string) (list string))) "text/plain: its lines as they are" ([ "a note"; "" ], []) (t.lines, t.links)));
    ]
