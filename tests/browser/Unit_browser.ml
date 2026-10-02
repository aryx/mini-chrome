(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_browser.mli *)

(* a page read with no pictures, nothing visited, 976 wide *)
let page (url : string) (html : string) : Browser_page.t =
  Browser_page.read
    { extensions = false; css = false; boxes = false; width = 976.; height = 768.; breaker = Html_layout.greedy; visited = (fun _ -> false); picture = (fun _ -> None); sheet = (fun _ -> None) }
    url 200 (Some "text/html") html

(* by the box model, [sheets] the style sheets it has, by URL *)
let styled (sheets : (string * string) list) (html : string) : Browser_page.t * Browser_page.settings =
  let s : Browser_page.settings =
    { extensions = true; css = true; boxes = true; width = 976.; height = 768.; breaker = Html_layout.greedy; visited = (fun _ -> false);
      picture = (fun _ -> None); sheet = (fun url -> List.assoc_opt url sheets) }
  in
  (Browser_page.read s "http://x.org/a/page.html" 200 (Some "text/html") html, s)

let element (p : Browser_page.t) (name : string) : Dom.element =
  List.find (fun e -> Dom.attribute "name" e = Some name) (Dom.find_all "input" p.tree)

let tests =
  Testo.categorize "Browser"
    [
      Testo.create "a picture without area is not drawn (<img width=0>)" (fun () ->
          let img = Rgba_image.create ~width:1 ~height:1 in
          Alcotest.(check int) "10 by 10: one shape" 1 (List.length (Browser_picture.drawn 10. 10. img));
          Alcotest.(check int) "no width" 0 (List.length (Browser_picture.drawn 0. 10. img));
          Alcotest.(check int) "no height" 0 (List.length (Browser_picture.drawn 10. 0. img));
          Alcotest.(check int) "squeezed past nothing" 0 (List.length (Browser_picture.drawn (-4.) 10. img)));
      Testo.create "the history: the worked example" (fun () ->
          let h = Browser_history.(visit "B" (visit "A" empty)) in
          (* at C, A and B behind *)
          let b, h = Option.get (Browser_history.back "C" h) in
          Alcotest.(check string) "Back: B" "B" b;
          Alcotest.(check (pair (list string) (list string))) "A behind, C ahead" ([ "A" ], [ "C" ]) (h.behind, h.ahead);
          let h = Browser_history.visit "B" h in
          (* at D now *)
          Alcotest.(check (pair (list string) (list string))) "visit D: C is gone" ([ "B"; "A" ], []) (h.behind, h.ahead);
          Alcotest.(check bool) "no forward" true (Browser_history.forward "D" h = None));
      Testo.create "the style sheets wanted: links, @imports, media" (fun () ->
          let html = {|<link rel=stylesheet href=main.css><link rel=stylesheet href=print.css media=print><link rel="alternate stylesheet" href=alt.css><p>x|} in
          let p, s = styled [] html in
          Alcotest.(check (list string)) "the link, not print's, not the alternate" [ "http://x.org/a/main.css" ] (Browser_page.sheets_wanted s p);
          let p, s = styled [ ("http://x.org/a/main.css", {|@import url("../colours.css"); p { color: red }|}) ] html in
          Alcotest.(check (list string)) "then its @import, resolved against it" [ "http://x.org/colours.css" ] (Browser_page.sheets_wanted s p);
          let p, s = styled [ ("http://x.org/a/main.css", {|@import "../colours.css";|}); ("http://x.org/colours.css", "p { color: blue }") ] html in
          Alcotest.(check (list string)) "all had" [] (Browser_page.sheets_wanted s p));
      Testo.create "100vh is the height of the window's page area, not a constant" (fun () ->
          (* example.com's body, which had a scrollbar for five lines *)
          let html = "<!doctype html><style>html, body { margin: 0 } body { min-height: 100vh; padding: 2em 0 20vh; box-sizing: border-box }</style><p>a line" in
          let p, s = styled [] html in
          Alcotest.(check (float 0.01)) "the settings' height" 768. p.layout.height;
          let p = Browser_page.laid_out { s with height = 400. } p in
          Alcotest.(check (float 0.01)) "laid out again in a lower window" 400. p.layout.height);
      Testo.create "a line's shapes are built when it is shown; opti=off, at once: the same shapes" (fun () ->
          let html = "<!doctype html><style>p { margin: 0; line-height: 20px; background: #eee } b { color: red }</style>" ^ String.concat "" (List.init 50 (fun i -> Printf.sprintf "<p>line <b>%d</b> of a <a href=/x>page</a></p>" i)) in
          (* the letters the pen's way on both sides: what is checked here
           * is when a line's shapes are built, not what a letter is *)
          let drawn optimized =
            Mini_opti.enabled := optimized;
            Fun.protect ~finally:(fun () -> Mini_opti.enabled := true) (fun () -> (fst (styled [] html)).drawn)
          in
          Mini_opti.letters := Segments;
          Fun.protect ~finally:(fun () -> Mini_opti.letters := Pictures) @@ fun () ->
          let built (d : Browser_draw.drawn) = List.length (List.filter (fun (_, _, s) -> Lazy.is_val s) d) in
          let lazy_ = drawn true and simple = drawn false in
          Alcotest.(check int) "as many things drawn" (List.length simple) (List.length lazy_);
          Alcotest.(check int) "opti=off: every shape built" (List.length simple) (built simple);
          (* the 50 backgrounds are built, the 50 lines are not *)
          Alcotest.(check int) "no line built yet" 50 (List.length lazy_ - built lazy_);
          let shown = Browser_draw.between ~top:0. ~bottom:100. lazy_ in
          Alcotest.(check int) "5 lines of 20 shown: 5 built" 45 (List.length lazy_ - built lazy_);
          Alcotest.(check bool) "the same as the simple way's" true (shown = Browser_draw.between ~top:0. ~bottom:100. simple);
          Alcotest.(check bool) "the whole page: the same shapes" true
            (Browser_draw.between ~top:0. ~bottom:infinity lazy_ = Browser_draw.between ~top:0. ~bottom:infinity simple));
      Testo.create "the network panel's lines" (fun () ->
          let requests : Browser_tab.request list =
            [ { url = "http://x.org/a.png"; kind = Picture; status = None; bytes = 0 };
              { url = "http://x.org/s.css"; kind = Sheet; status = Some 404; bytes = 10 };
              { url = "http://x.org/"; kind = Document; status = Some 200; bytes = 2048 } ]
          in
          let times url = match url with "http://x.org/" -> Some (1.0, Some 1.25) | "http://x.org/s.css" -> Some (1.25, Some 1.5) | _ -> Some (1.5, None) in
          match Browser_devtools.network requests ~times with
          | (summary, _) :: _ :: (page, _) :: _ ->
              Alcotest.(check string) "the summary: count, size, time, waiting" "3 requests, 2.0 KB, 0.50 s, 1 waiting" summary;
              Alcotest.(check bool) "the page first, its time" true (String.starts_with ~prefix:"200     page  2.0 KB     250 ms" page)
          | _ -> Alcotest.fail "lines");
      Testo.create "URLs: resolved, split" (fun () ->
          Alcotest.(check string)
            "relative" "http://info.cern.ch/hypertext/WWW/Help.html#people"
            (Browser_url.resolve "http://info.cern.ch/hypertext/WWW/TheProject.html" "Help.html#people");
          Alcotest.(check (pair string (option string))) "the fragment" ("a", Some "b") (Browser_url.split_fragment "a#b");
          Alcotest.(check (pair string (option string))) "the query" ("a", Some "q=1") (Browser_url.split_query "a?q=1"));
      Testo.create "a form sent: GET into the URL, POST into the body" (fun () ->
          let p = page "http://a/dir/page.html" "<form action=search><input name=q value=\"caf&eacute; au lait\"></form><form action=/order method=post><input name=n value=2></form>" in
          let get, post = match p.forms with [ g; o ] -> (g, o) | _ -> Alcotest.fail "two forms" in
          Alcotest.(check (pair string (option (pair string string))))
            "GET" ("http://a/dir/search?q=caf%C3%A9+au+lait", None)
            (Browser_forms.submission p get ~submitter:None);
          Alcotest.(check (pair string (option (pair string string))))
            "POST" ("http://a/order", Some ("application/x-www-form-urlencoded", "n=2"))
            (Browser_forms.submission p post ~submitter:None));
      Testo.create "clicks: a radio button is the one of its name" (fun () ->
          let p = page "about:x" "<form><input type=radio name=r value=1 checked><input type=radio name=r value=2 id=two></form>" in
          let radios = Dom.find_all "input" p.tree in
          let second = List.nth radios 1 in
          match Browser_forms.click p second with
          | Changed p ->
              Alcotest.(check (list bool)) "the first unchecked, the second checked" [ false; true ]
                (List.map (fun e -> (Browser_page.value_of p e).checked) radios)
          | _ -> Alcotest.fail "a change");
      Testo.create "keys: typed, Backspace, Return sends" (fun () ->
          let p = page "about:x" "<form action=about:echo><input name=q></form>" in
          let q = element p "q" in
          let p = Browser_forms.typed p q "hi!" in
          (match Browser_forms.key p q "backspace" with
          | Changed p' -> Alcotest.(check string) "hi" "hi" (Browser_page.value_of p' q).text
          | _ -> Alcotest.fail "a change");
          match Browser_forms.key p q "return" with
          | Submit { url; post = None; _ } -> Alcotest.(check string) "sent" "about:echo?q=hi%21" url
          | _ -> Alcotest.fail "a submission");
    ]
