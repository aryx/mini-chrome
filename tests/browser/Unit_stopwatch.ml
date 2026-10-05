(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_stopwatch.mli *)

let tests =
  Testo.categorize "Stopwatch"
    [
      Testo.create "spans: counted, nested, their own time" (fun () ->
          Alcotest.(check int) "off: the function is run, nothing kept" 3 (Stopwatch.time "test-off" (fun () -> 3));
          Alcotest.(check bool) "no span" false (List.exists (fun (n, _, _, _) -> n = "test-off") (Stopwatch.spans ()));
          Stopwatch.enabled := true;
          Fun.protect
            ~finally:(fun () -> Stopwatch.enabled := false)
            (fun () ->
              let wait s = let t = Unix.gettimeofday () in while Unix.gettimeofday () -. t < s do () done in
              for _ = 1 to 2 do
                Stopwatch.time "test-outer" (fun () -> wait 0.02; Stopwatch.time "test-inner" (fun () -> wait 0.03))
              done;
              (try Stopwatch.time "test-raises" (fun () -> failwith "x") with Failure _ -> ());
              let span n = List.find (fun (n', _, _, _) -> n' = n) (Stopwatch.spans ()) in
              let _, times, own, whole = span "test-outer" and _, _, inner, _ = span "test-inner" in
              Alcotest.(check int) "twice" 2 times;
              Alcotest.(check bool) "the inner's time is in the outer's whole" true (whole >= own +. inner -. 1e-6);
              Alcotest.(check bool) "and not in its own" true (own >= 0.04 && own < whole && inner >= 0.06);
              let _, raised, _, _ = span "test-raises" in
              Alcotest.(check int) "a span that raises is closed" 1 raised;
              Alcotest.(check bool) "the report has a line a span" true (List.length (Stopwatch.report ~since:0.) >= 5)));
    ]
