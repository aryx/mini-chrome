(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_node_host.mli *)

(* a directory with [files] in it *)
let directory (files : (string * string) list) : string =
  let dir = Filename.temp_file "mini-node" "" in
  Sys.remove dir;
  Sys.mkdir dir 0o700;
  List.iter (fun (name, text) -> Out_channel.with_open_bin (Filename.concat dir name) (fun ch -> output_string ch text)) files;
  dir

(* main.js of [files] run: what it printed and what was complained of
 * (" | " between lines), whether it went well, and how long the loop
 * slept, in the test's milliseconds *)
let run caps ?(argv = []) (files : (string * string) list) : string * bool * float =
  let dir = directory files in
  let out = Buffer.create 64 and clock = ref 0. in
  let t =
    Node_host.create caps ~print:(Buffer.add_string out)
      ~complain:(fun s -> Buffer.add_string out ("! " ^ Filename.basename s ^ "\n"))
      ~now:(fun () -> !clock)
      ~sleep:(fun ms -> clock := !clock +. ms)
      ~argv:("main.js" :: argv) ()
  in
  let ok = Node_host.run_file t (Filename.concat dir "main.js") in
  (String.concat " | " (String.split_on_char '\n' (String.trim (Buffer.contents out))), ok, !clock)

let tests caps =
  let check what ?argv files expected = let out, _, _ = run caps ?argv files in Alcotest.(check string) what expected out in
  let main text = [ ("main.js", text) ] in
  Testo.categorize "Node host"
    [
      Testo.create "the loop: the script, its jobs, then the timers" (fun () ->
          let out, ok, slept =
            run caps (main {|setTimeout(() => console.log("c"), 10)
Promise.resolve().then(() => console.log("b"))
console.log("a")|})
          in
          Alcotest.(check string) "the worked example" "a | b | c" out;
          Alcotest.(check (pair bool (float 0.001))) "it slept until the timer was due, and ended" (true, 10.) (ok, slept);
          check "the earliest first; a timer's arguments; one cleared" (main {|
setTimeout(console.log, 30, "third")
setTimeout(() => console.log("first"), 10)
const never = setTimeout(() => console.log("never"), 15)
setTimeout(() => { clearTimeout(never); console.log("second") }, 12)|}) "first | second | third";
          let out, _, slept =
            run caps (main {|let n = 0; const i = setInterval(() => { console.log(++n); if (n === 3) clearInterval(i) }, 100)|})
          in
          Alcotest.(check (pair string (float 0.001))) "an interval, until it is cleared" ("1 | 2 | 3", 300.) (out, slept);
          check "a timer awaited; a job before the next timer" (main {|
const sleep = ms => new Promise(done => setTimeout(done, ms));
(async () => { console.log("start"); await sleep(50); console.log("50"); await sleep(50); console.log("100") })()
setTimeout(() => console.log("75"), 75)
setImmediate(() => console.log("at once"))
process.nextTick(() => console.log("tick"))|}) "start | tick | at once | 50 | 75 | 100");
      Testo.create "modules" (fun () ->
          let lib = ("lib.js", {|let calls = 0
exports.twice = x => { calls++; return x * 2 }
exports.calls = () => calls|}) in
          check "the worked example: exports, a file run once"
            [ ("main.js", {|const lib = require("./lib")
console.log(lib.twice(4), lib.twice(5))
console.log(require("./lib.js") === lib)|}); lib ]
            "8 10 | true";
          check "a module's variables are its own; module.exports replaced; what a module knows of itself"
            [ ("main.js", {|const f = require("./f"); console.log(f(1), typeof secret, typeof module, __filename.endsWith("main.js"), this === exports)|});
              ("f.js", {|const secret = 41; module.exports = x => x + secret|}) ]
            "42 undefined object true true";
          check "two that require each other end: the first's exports so far"
            [ ("main.js", {|const a = require("./a"); console.log(a.name, a.other)|});
              ("a.js", {|exports.name = "a"; exports.other = require("./b").saw|});
              ("b.js", {|exports.saw = "b saw " + require("./a").name|}) ]
            "a b saw a";
          check "a script's first line" (main "#!/usr/bin/env mini-node\nconsole.log('run')") "run";
          check "not there" (main {|try { require("./nope") } catch (e) { console.log(e.message.startsWith("Cannot find module")) }
try { require("express") } catch (e) { console.log(e.message) }|})
            "true | Cannot find module 'express'");
      Testo.create "fs and process" (fun () ->
          check "a file written, read, there" (main {|const fs = require("fs"), path = __dirname + "/out.txt"
fs.writeFileSync(path, "kept\n")
console.log(fs.readFileSync(path).trim(), fs.existsSync(path), fs.existsSync(path + ".no"))
try { fs.readFileSync(path + ".no") } catch (e) { console.log(e.message.slice(0, 6)) }|}) "kept true false | ENOENT";
          check "argv, env, stdout" ~argv:[ "one"; "two" ] (main {|process.stdout.write("no "); process.stdout.write("newline\n")
console.log(process.argv, typeof process.env.PATH, process.env.NOT_SET_ANYWHERE)|})
            "no newline | [\"mini-node\", \"main.js\", \"one\", \"two\"] string undefined");
      Testo.create "errors: said, with their file and line" (fun () ->
          let out, ok, _ = run caps (main "console.log('before')\nnull.f()\nconsole.log('after')") in
          Alcotest.(check (pair string bool)) "the program's" ("before | ! main.js:2: TypeError: Cannot read properties of null (reading 'f')", false) (out, ok);
          let out, ok, _ = run caps [ ("main.js", "const x = 1\nrequire('./worse')"); ("worse.js", "\n\nundefined_name") ] in
          Alcotest.(check (pair string bool)) "a module's" ("! worse.js:3: ReferenceError: undefined_name is not defined", false) (out, ok);
          let out, ok, _ = run caps (main "setTimeout(() => { throw new Error('late') }, 5)\nsetTimeout(() => console.log('still run'), 9)") in
          Alcotest.(check (pair string bool)) "a timer's: the loop goes on" ("! main.js:1: Error: late | still run", false) (out, ok);
          let out, _, _ = run caps (main "Promise.reject(new Error('lost'))") in
          Alcotest.(check string) "a rejection nobody handled" "Uncaught (in promise) Error: lost" out);
      Testo.create "a console's lines" (fun () ->
          let t = Node_host.create caps ~print:ignore ~complain:ignore ~argv:[] () in
          let line l = match Node_host.line t l with Ok (Some s) -> s | Ok None -> "(nothing)" | Error e -> "error: " ^ e in
          Alcotest.(check (list string)) "a declaration stays for the next line; a value shown; a mistake said"
            [ "(nothing)"; "21"; "'s'"; "[1, {b: 2}]"; "error: ReferenceError: nope is not defined"; "error: SyntaxError: expected an expression, not the end" ]
            (List.map line [ "let a = 20"; "a + 1"; "'s'"; "[1, { b: 2 }]"; "nope"; "f(" ]));
    ]
