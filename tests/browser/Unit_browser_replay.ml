(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_browser_replay.mli *)

let write (file : string) (text : string) : unit = Out_channel.with_open_bin file (fun oc -> Out_channel.output_string oc text)

let tests =
  Testo.categorize "Browser_replay"
    [
      Testo.create "a recording given again: the page first, an address's answers in order, a file by its path" (fun () ->
          let dir = Filename.temp_file "replay" "" in
          Sys.remove dir;
          Sys.mkdir dir 0o700;
          write (Filename.concat dir "page.html") "<p>the page";
          write (Filename.concat dir "app.js") "run()";
          (* what a live run writes: two answers to one address, whose query changes *)
          Browser_replay.record dir "https://site.test/sync?n=1" "first";
          Browser_replay.record dir "https://site.test/sync?n=2" "second";
          Alcotest.(check bool) "written in _seq" true (Array.length (Sys.readdir (Filename.concat dir "_seq")) = 2);
          let saved = Browser_replay.answers dir in
          Alcotest.(check (option string)) "the first address asked is the page's" (Some "<p>the page") (saved "https://site.test/");
          Alcotest.(check (option string)) "its first answer" (Some "first") (saved "https://site.test/sync?n=7");
          Alcotest.(check (option string)) "its second" (Some "second") (saved "https://site.test/sync?n=8");
          Alcotest.(check (option string)) "no third" None (saved "https://site.test/sync?n=9");
          Alcotest.(check (option string)) "a file under the directory, by the address's path" (Some "run()") (saved "https://site.test/app.js?v=3");
          Alcotest.(check (option string)) "nothing else: a 404, the network not asked" None (saved "https://other.test/"));
    ]
