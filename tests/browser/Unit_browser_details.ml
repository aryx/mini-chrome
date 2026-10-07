(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_browser_details.mli *)

let tree (html : string) : Dom.element = Html_tree.of_string html
let first (name : string) (root : Dom.element) : Dom.element = List.hd (Dom.find_all name root)

let page = "<details id=outer><summary>More <b>here</b></summary><p>Inside.</p><details id=inner><summary>Deeper</summary><p>Deep.</p></details></details><p id=after>After.</p>"

(* the ids of the <details> that are open *)
let opened (root : Dom.element) : string list =
  List.filter_map (fun d -> if Browser_details.is_open d then Dom.attribute "id" d else None) (Dom.find_all "details" root)

let tests =
  Testo.categorize "Browser_details"
    [
      Testo.create "the worked example: a click in a summary opens, another closes" (fun () ->
          let root = tree page in
          let outer = first "details" root in
          Alcotest.(check (option string)) "a click on the summary's bold word: its details" (Some "outer")
            (Option.bind (Browser_details.clicked root (first "b" root)) (Dom.attribute "id"));
          Alcotest.(check bool) "on what is inside, or after: none" true
            (Browser_details.clicked root (first "p" root) = None && Browser_details.clicked root (List.nth (Dom.find_all "p" root) 2) = None);
          let once = Browser_details.toggled root outer in
          Alcotest.(check (list string)) "opened" [ "outer" ] (opened once);
          Alcotest.(check (list string)) "closed again" [] (opened (Browser_details.toggled once (first "details" once)));
          Alcotest.(check bool) "the tree is a value: the old one is as it was, what is beside is shared" true
            (opened root = [] && List.nth (Dom.find_all "p" root) 2 == List.nth (Dom.find_all "p" once) 2));
      Testo.create "a details in a details: the innermost" (fun () ->
          let root = tree page in
          let inner_summary = List.nth (Dom.find_all "summary" root) 1 in
          Alcotest.(check (option string)) "its own" (Some "inner") (Option.bind (Browser_details.clicked root inner_summary) (Dom.attribute "id"));
          let root = Browser_details.toggled root (Option.get (Browser_details.clicked root inner_summary)) in
          Alcotest.(check (list string)) "open, the outer one not" [ "inner" ] (opened root));
      Testo.create "the page folds and unfolds: the layout's height" (fun () ->
          let settings : Browser_page.settings =
            { css = true; engine = None; width = 600.; height = 400.; visited = (fun _ -> false); picture = (fun _ -> None); sheet = (fun _ -> None); framed = (fun _ -> None) }
          in
          let p = Browser_page.read settings "http://x.test/" 200 (Some "text/html") page in
          let opened_page = Browser_page.with_tree settings p (Browser_details.toggled p.tree (first "details" p.tree)) in
          Alcotest.(check bool) "taller when open" true (opened_page.layout.height > p.layout.height +. 10.));
    ]
