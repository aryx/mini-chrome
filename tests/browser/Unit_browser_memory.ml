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
            Browser_memory.page ~cpu:(Browser_cpu.card [ { name = "tab domain <2>"; percent = 100 }; { name = "the window"; percent = 61 } ]) ~samples:[ 412; 300; 95 ]
              ~tabs:[ { title = "A <page>"; kept = 2; pictures = 8; pixels_mb = 352; heap_mb = 41 } ]
              ~cache:(Some (120, 30 * 1_048_576, "/home/x/.cache/mini-chrome")) ~profile:None
          in
          List.iter
            (fun word -> if not (has page word) then Alcotest.failf "%S is not on the page" word)
            [ "412 MB"; "from 95 to 412 MB"; "A &lt;page&gt;"; "<td>41 MB</td><td>2</td><td>8</td><td>352 MB</td>"; "120, 30 MB"; "none (profile=off)"; "tab domain &lt;2&gt;</td><td>100%"; "161% in all, of 2 threads" ];
          Alcotest.(check bool) "not measured: said" true (has (Browser_memory.page ~cpu:"" ~samples:[] ~tabs:[] ~cache:None ~profile:None) "not measured"));
      Testo.create "Browser_cpu: a task's ticks, what each did between two readings" (fun () ->
          Alcotest.(check (option int)) "the 14th and 15th fields, after a name with spaces and a parenthesis" (Some 46)
            (Browser_cpu.ticks "48213 (mini chrome) x) S 1 2 3 0 -1 4194560 100 0 0 0 40 6 0 0 20 0 9 0 1234 5678");
          Alcotest.(check (option int)) "not a stat line" None (Browser_cpu.ticks "nothing");
          let tasks = Browser_cpu.busy ~before:[ (1, 100); (2, 50); (3, 7) ] ~after:[ (2, 450); (1, 222); (4, 9) ] ~seconds:2. in
          Alcotest.(check (list int)) "ticks a second are percents of a core, the busiest first; a task just born is not counted" [ 200; 61 ]
            (List.map (fun (t : Browser_cpu.task) -> t.percent) tasks);
          Alcotest.(check int) "in all" 261 (Browser_cpu.total tasks);
          Alcotest.(check string) "none read: no card" "" (Browser_cpu.card []));
      Testo.create "Browser_cpu: this very thread, named and busy" (fun () ->
          Task_names.here "the test";
          let before = Browser_cpu.read caps and start = Unix.gettimeofday () in
          (* Linux alone has the files *)
          if before <> [] then (
            while Unix.gettimeofday () -. start < 0.3 do ignore (Sys.opaque_identity (ref 0)) done;
            let tasks = Browser_cpu.busy ~before ~after:(Browser_cpu.read caps) ~seconds:(Unix.gettimeofday () -. start) in
            match List.find_opt (fun (t : Browser_cpu.task) -> t.name = "the test") tasks with
            | Some t -> Alcotest.(check bool) (Printf.sprintf "a thread that never waited is near 100%% (%d)" t.percent) true (t.percent > 60 && t.percent < 140)
            | None -> Alcotest.fail "the thread that said its name is not among the tasks"));
    ]
