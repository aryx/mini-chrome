(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_js_modern.mli *)

let run (s : string) : string =
  let t = Js_eval.create () in
  match Js_eval.eval t s with Ok v -> Js_value.display v | Error e -> Printf.sprintf "line %d: %s" e.line e.message

let check (what : string) (s : string) (expected : string) : unit = Alcotest.(check string) what expected (run s)

let tests =
  Testo.categorize "Js modern"
    [
      Testo.create "template literals" (fun () ->
          check "values among the text" "var n = 3, who = 'you'; [`${n} for ${who}, ${n * 2} in all`]" "[\"3 for you, 6 in all\"]";
          check "no value; nothing at all" "[`plain`, ``]" "[\"plain\", \"\"]";
          check "lines kept, escapes read" "[`a\nb\\tc`.length, `\\${x}`, `\\``]" "[5, \"${x}\", \"`\"]";
          check "an expression of any kind: an object, a string with a brace, a call" "var o = {k: 'v'}; [`${ {a: 1}.a }-${'}'}-${[1, 2].map(x => x * 2)}-${o['k']}`]"
            "[\"1-}-2,4-v\"]";
          check "a regular expression with a quote in it" "[`<${'a\"b'.replace(/\"/g, \"'\")}>`]" "[\"<a'b>\"]";
          check "a template in a template" "var xs = ['a', 'b']; [`<ul>${xs.map(x => `<li>${x}</li>`).join('')}</ul>`]" "[\"<ul><li>a</li><li>b</li></ul>\"]";
          check "an object's and undefined's strings" "[`${[1, 2]} ${undefined} ${null}`]" "[\"1,2 undefined null\"]";
          check "its line" "var a = `x\ny`;\nnone" "line 3: ReferenceError: none is not defined");
      Testo.create "destructuring: declarations" (fun () ->
          check "an object's properties" "const { a, b } = { a: 1, b: 2, c: 3 }; [a, b]" "[1, 2]";
          check "another name, a default, one inside another" "let { a: x, missing = 'd', in: { deep } } = { a: 1, in: { deep: 'yes' } }; [x, missing, deep]"
            "[1, \"d\", \"yes\"]";
          check "the rest of an object" "var { a, ...others } = { a: 1, b: 2, c: 3 }; [a, others.b, others.c, 'a' in others]" "[1, 2, 3, false]";
          check "an array's items: one skipped, a default, the rest" "let [first, , third = 'd', fourth = 'd', ...more] = [1, 2, undefined, 4, 5, 6]; [first, third, fourth, more]"
            "[1, \"d\", 4, [5, 6]]";
          check "a string's characters; too few" "const [h, i, none] = 'hi'; [h, i, none]" "[\"h\", \"i\", undefined]";
          check "a computed key" "const k = 'dyn'; const { [k]: v } = { dyn: 7 }; v" "7";
          check "of nothing" "const { a } = null" "line 1: TypeError: Cannot destructure 'null' as it is null.";
          check "in a for-of" "var r = []; for (const [k, { n }] of [['a', { n: 1 }], ['b', { n: 2 }]]) r.push(k + n); r" "[\"a1\", \"b2\"]");
      Testo.create "destructuring: assignments" (fun () ->
          check "a swap" "var a = 1, b = 2; [a, b] = [b, a]; [a, b]" "[2, 1]";
          check "into properties; a default; the rest" "var o = {}, r; [o.x, o.y = 9, ...r] = [1, undefined, 3, 4]; [o.x, o.y, r]" "[1, 9, [3, 4]]";
          check "an object's, in parentheses" "var a, c, d; ({ a, b: c, d = 4 } = { a: 1, b: 2 }); [a, c, d]" "[1, 2, 4]";
          check "its value is the right side" "var a, b; var v = ([a, b] = [1, 2]); v" "[1, 2]");
      Testo.create "parameters: defaults, the rest, patterns" (fun () ->
          check "a default, when undefined is given or nothing" "function f(a, b = a + 1) { return [a, b] } [f(1), f(1, undefined), f(1, null), f(1, 5)]" "[[1, 2], [1, 2], [1, null], [1, 5]]";
          check "the rest" "function f(first, ...others) { return [first, others.length, others] } f(1, 2, 3)" "[1, 2, [2, 3]]";
          check "the rest of nothing" "((...xs) => xs)()" "[]";
          check "an object taken apart, with defaults" "function box({ w = 10, h = w }, [x, y] = [0, 0]) { return [w, h, x, y] } [box({}), box({ w: 2 }, [5, 6])]" "[[10, 10, 0, 0], [2, 2, 5, 6]]";
          check "an arrow's" "[[1, 2], [3, 4]].map(([a, b]) => a + b)" "[3, 7]");
      Testo.create "spread" (fun () ->
          check "in an array" "var xs = [2, 3]; [1, ...xs, 4, ...'ab', ...[]]" "[1, 2, 3, 4, \"a\", \"b\"]";
          check "in a call, and a new" "function sum(a, b, c) { return a + b + c } function P(x, y) { this.x = x; this.y = y } var p = new P(...[1, 2]); [sum(...[1, 2, 3]), Math.max(0, ...[5, 2]), p.x + p.y]"
            "[6, 5, 3]";
          check "in an object: copied, the later one wins" "var a = { x: 1, y: 2 }; var b = { ...a, y: 3, ...{ z: 4 } }; [b.x, b.y, b.z, a.y]" "[1, 3, 4, 2]";
          check "what is not a list" "[...5]" "line 1: TypeError: 5 is not iterable";
          check "a hole" "[1, , 3]" "[1, undefined, 3]");
      Testo.create "an object literal's short forms" (fun () ->
          check "a name alone, a method, a computed key, a keyword and a number as keys" "var x = 1, k = 'dyn'; var o = { x, twice() { return this.x * 2 }, [k + '!']: 3, if: 4, 5: 6 }; [o.x, o.twice(), o['dyn!'], o.if, o[5]]"
            "[1, 2, 3, 4, 6]";
          check "get and set are names too" "var o = { get: 1, set: 2, get() { return 3 } }; [typeof o.get, o.set]" "[\"function\", 2]");
      Testo.create "getters and setters" (fun () ->
          check "read by calling, assigned by calling" "var log = []; var o = { _v: 1, get v() { log.push('get'); return this._v }, set v(x) { log.push('set ' + x); this._v = x * 2 } }; o.v = 5; [o.v, log]"
            "[10, [\"set 5\", \"get\"]]";
          check "a getter alone: assigning does nothing" "var o = { get now() { return 7 } }; o.now = 1; o.now" "7";
          check "inherited" "var base = { get full() { return this.first + ' ' + this.last } }; var p = Object.create(base); p.first = 'Ada'; p.last = 'L'; [p.full]" "[\"Ada L\"]";
          check "++ on one" "var n = 0; var o = { get c() { return n }, set c(x) { n = x } }; o.c++; o.c += 10; n" "11");
    ]
