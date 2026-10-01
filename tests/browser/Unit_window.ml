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

let tests =
  Testo.categorize "Window"
    [
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
