(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_js_scope.mli *)

let run (opti : bool) (s : string) : string =
  let before = !Mini_opti.enabled in
  Mini_opti.enabled := opti;
  Fun.protect ~finally:(fun () -> Mini_opti.enabled := before) @@ fun () ->
  let t = Js_eval.create () in
  match Js_eval.eval t s with Ok v -> Js_value.display v | Error e -> Printf.sprintf "line %d: %s" e.line e.message

(* the program on slots and on tables: the same answer, the one expected *)
let check (what : string) (s : string) (expected : string) : unit =
  Alcotest.(check string) (what ^ " (slots)") expected (run true s);
  Alcotest.(check string) (what ^ " (tables)") expected (run false s)

let many = String.concat "; " (List.init 40 (fun i -> Printf.sprintf "var v%d = %d" i i))

let tests =
  Testo.categorize "Js_scope"
    [
      Testo.create "the worked example" (fun () ->
          check "total found two scopes up, n in the call's frame"
            "var total = 0;\nfunction add(n) {\n  for (var i = 0; i < n; i++) { total = total + i }\n}\nadd(4); add(3); total" "9");
      Testo.create "a name shadowed" (fun () ->
          check "the nearest x, at each depth" "var x = 1; function f() { var x = 2; { let x = 3; return [x, g()] } function g() { return x } } [f(), x]"
            "[[3, 2], 1]";
          check "a parameter over a global" "var a = 1; function f(a) { return a } [f(5), f(), a]" "[5, undefined, 1]";
          check "a catch's name" "var e = 1; try { throw 2 } catch (e) { e = e + 1 } e" "1");
      Testo.create "one function, two callers" (fun () ->
          check "the same text run under two frames" "function make(k) { return function (x) { return x + k } } var a = make(1), b = make(10); [a(1), b(1), a(2)]"
            "[2, 11, 3]";
          check "recursion: a frame a call" "function fact(n) { var r = n < 2 ? 1 : n * fact(n - 1); return r } fact(10)" "3628800");
      Testo.create "a let per iteration, a var for all" (fun () ->
          check "let" "var fs = []; for (let i = 0; i < 3; i++) fs.push(function () { return i }); fs.map(function (f) { return f() })" "[0, 1, 2]";
          check "var" "var fs = []; for (var i = 0; i < 3; i++) fs.push(function () { return i }); fs.map(function (f) { return f() })" "[3, 3, 3]";
          check "a let in the body" "var fs = []; for (var i = 0; i < 3; i++) { let j = i * 2; fs.push(function () { return j }) } fs.map(function (f) { return f() })"
            "[0, 2, 4]");
      Testo.create "hoisting, arguments, a function's own name" (fun () ->
          check "a var before its line" "function f() { var a = typeof x; var x = 1; return [a, x] } f()" "[\"undefined\", 1]";
          check "a var and a parameter of one name" "function f(a) { var a; return a } function g(a) { var a = 2; return a } [f(1), g(1)]" "[1, 2]";
          check "arguments" "function f() { return arguments.length + arguments[1] } f(1, 2, 3)" "5";
          check "a name of its own" "var f = function again(n) { return n < 1 ? 0 : n + again(n - 1) }; var g = f; f = null; g(4)" "10";
          check "a declaration's name is the scope's" "function f() { return typeof f } var g = f; f = 1; g()" "number";
          check "a default sees the parameter before" "function f(a, b = a + 1) { return a + b } [f(1), f(1, 5)]" "[3, 6]";
          check "a rest and a pattern" "function f(a, ...r) { return a + r.length } function g({ x, y }, [z]) { return x + y + z } [f(1, 2, 3), g({ x: 1, y: 2 }, [3])]"
            "[3, 6]");
      Testo.create "names not known before the program runs" (fun () ->
          check "typeof of a name nobody declared, then declared" "function t() { return typeof late } var a = t(); late = 1; [a, t()]" "[\"undefined\", \"number\"]";
          check "a with's object first" "var x = 1, o = { x: 2 }; function f() { with (o) { return x } } var a = f(); delete o.x; [a, f()]" "[2, 1]";
          check "a switch entered by two cases" "function f(k) { var r = 0; switch (k) { case 1: r = r + 1; case 2: r = r + 2; break; default: r = 9 } return r } [f(1), f(2), f(3)]"
            "[3, 2, 9]";
          check "a global made by an assignment" "function f() { made = 5 } f(); made" "5");
      Testo.create "a function of many names" (fun () ->
          (* past sixteen: the frame's names by an index *)
          check "forty var's and a closure over them" ("function f(p) { " ^ many ^ "; return function () { return v0 + v17 + v39 + p } } f(1)()") "57";
          check "and more declared as it runs" ("function f() { " ^ many ^ "; let a = 1; const b = 2; function h() { return a + b + v20 } return h() } f()") "23");
      Testo.create "classes, generators, async: scopes kept alive" (fun () ->
          check "a class's methods see its scope" "var k = 2; class A { constructor(x) { this.x = x } twice() { return this.x * k } } class B extends A { twice() { return super.twice() + 1 } } new B(4).twice()"
            "9";
          check "a generator between two yields" "function* g(n) { var s = 0; for (var i = 0; i < n; i++) { s += i; yield s } } var out = []; for (var v of g(4)) out.push(v); out"
            "[0, 1, 3, 6]");
    ]
