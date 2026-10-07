(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_browser_memory.mli *)

let has (text : string) (word : string) : bool =
  let n = String.length word in
  let rec at i = i + n <= String.length text && (String.sub text i n = word || at (i + 1)) in
  at 0

let tests caps =
  Testo.categorize "Browser_memory"
    [
      Testo.create "the memory held is read, and drawn a bar a sample" (fun () ->
          let now = Browser_memory.resident caps in
          Alcotest.(check bool) "some megabytes, not a terabyte" true (now > 0 && now < 1_000_000);
          Alcotest.(check int) "three samples, three bars" 3 (List.length (Browser_memory.graph [ 300; 200; 100 ] ~x:0. ~y:0.));
          Alcotest.(check int) "thirty at most" 30 (List.length (Browser_memory.graph (List.init 50 (fun i -> i + 1)) ~x:0. ~y:0.));
          Alcotest.(check int) "none measured: nothing drawn" 0 (List.length (Browser_memory.graph [] ~x:0. ~y:0.)));
      Testo.create "about:memory: the samples, a tab's pictures, the cache on disk" (fun () ->
          let page =
            Browser_memory.page ~samples:[ 412; 300; 95 ]
              ~tabs:[ { title = "A <page>"; kept = 2; pictures = 8; pixels_mb = 352 } ]
              ~cache:(Some (120, 30 * 1_048_576, "/home/x/.cache/mini-chrome")) ~profile:None
          in
          List.iter
            (fun word -> if not (has page word) then Alcotest.failf "%S is not on the page" word)
            [ "412 MB"; "from 95 to 412 MB"; "A &lt;page&gt;"; "<td>2</td><td>8</td><td>352 MB</td>"; "120, 30 MB"; "none (profile=off)" ];
          Alcotest.(check bool) "not measured: said" true (has (Browser_memory.page ~samples:[] ~tabs:[] ~cache:None ~profile:None) "not measured"));
    ]
