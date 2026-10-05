(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Js_bench.mli *)

let loops : (string * string) list =
  [
    ("a loop, 3M turns", "(function () { var s = 0; for (var i = 0; i < 3000000; i = i + 1 | 0) { s = (s + i) | 0 } return s })()");
    ("calls, 1M", "(function () { function f(a, b) { return (a + b) | 0 } var s = 0; for (var i = 0; i < 1000000; i++) { s = f(s, i) } return s })()");
    ("properties, 1M", "(function () { var o = { a: 1, b: 2, n: 0 }; for (var i = 0; i < 1000000; i++) { o.n = o.n + o.b } return o.n })()");
    ("arrays, 1M", "(function () { var a = [1, 2, 3], s = 0; for (var i = 0; i < 1000000; i++) { s = s + a[i % 3] } return s })()");
    ("closures, 300,000", "(function () { var s = 0; for (var i = 0; i < 300000; i++) { s = (function (x) { return function () { return x + 1 } })(s)() } return s })()");
  ]

let timed (f : unit -> 'a) : 'a * float =
  let t0 = Sys.time () in
  let v = f () in
  (v, Sys.time () -. t0)

let () =
  let args = List.tl (Array.to_list Sys.argv) in
  if List.mem "opti=off" args then Mini_opti.enabled := false;
  if List.mem "compile=off" args then Mini_opti.compiled := false;
  let no_loops = List.mem "loops=off" args in
  let args = List.filter (fun a -> a <> "opti=off" && a <> "loops=off" && a <> "compile=off") args in
  if not !Mini_opti.enabled then print_endline "opti=off";
  if not !Mini_opti.compiled then print_endline "compile=off";
  List.iter
    (fun (name, text) ->
      let engine = Js_eval.create () in
      Js_eval.set_budget engine max_int;
      let r, s = timed (fun () -> Js_eval.eval engine text) in
      Printf.printf "%-20s %7.0f ms   %s\n%!" name (s *. 1000.) (match r with Ok v -> Js_value.display v | Error e -> "error: " ^ e.message))
    (if no_loops then [] else loops);
  match args with
  | [] -> ()
  (* read=FILE.js: what reading a script costs, stage by stage (a
   * bundle of megabytes is seconds before its first line runs) *)
  | file :: _ when String.length file > 5 && String.sub file 0 5 = "read=" ->
      let text = In_channel.with_open_bin (String.sub file 5 (String.length file - 5)) In_channel.input_all in
      let words () = (Gc.quick_stat ()).minor_words +. (Gc.quick_stat ()).major_words -. (Gc.quick_stat ()).promoted_words in
      let stage name f =
        let w0 = words () in
        let v, s = timed f in
        Printf.printf "%-28s %7.0f ms   %5.0f MB made\n%!" name (s *. 1000.) ((words () -. w0) *. 8. /. 1e6);
        v
      in
      Printf.printf "%s: %.1f MB\n" file (float_of_int (String.length text) /. 1e6);
      let tokens = stage "Js_lexer.tokenize" (fun () -> Js_lexer.tokenize text) in
      Printf.printf "    %d tokens\n" (List.length tokens);
      (match stage "Js_parse.parse (lexes again)" (fun () -> Js_parse.parse text) with
      | Ok program -> ignore (stage "Js_quicken.program" (fun () -> Js_quicken.program program))
      | Error e -> Printf.printf "error, line %d: %s\n" e.line e.message)
  | file :: rest ->
      let frames = match rest with n :: _ -> int_of_string n | [] -> 10 in
      let html = In_channel.with_open_bin file In_channel.input_all in
      let t = Browser_script.create ~base:"http://localhost/" (Html_tree.of_string html) in
      let answer () = List.iter (fun (r : Script_types.request) -> Browser_script.answer t r.rid (Error "no network here")) (Browser_script.take_requests t) in
      let (), s = timed (fun () -> Browser_script.run_scripts t) in
      Printf.printf "%-20s %7.0f ms\n%!" "the page's scripts" (s *. 1000.);
      answer ();
      let times =
        List.init frames (fun _ ->
            let (), s = timed (fun () -> Browser_script.advance t 16.) in
            answer ();
            s *. 1000.)
      in
      Printf.printf "%-20s %7.0f ms   (%s)\n" "a frame, the median" (List.nth (List.sort compare times) (frames / 2))
        (String.concat " " (List.map (Printf.sprintf "%.0f") times));
      List.iter (fun l -> print_endline ("console: " ^ l)) (Browser_script.console t)
