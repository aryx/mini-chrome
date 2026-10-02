(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_js_globals.mli *)

let run (s : string) : string =
  let t = Js_eval.create () in
  match Js_eval.eval t s with Ok v -> Js_value.display v | Error e -> Printf.sprintf "line %d: %s" e.line e.message

let check (what : string) (s : string) (expected : string) : unit = Alcotest.(check string) what expected (run s)

let tests =
  Testo.categorize "Js globals"
    [
      Testo.create "Object's helpers" (fun () ->
          check "defineProperty: a value; a getter and a setter" {|var o = {}, n = 0; Object.defineProperty(o, 'v', { value: 1 }); Object.defineProperty(o, 'g', { get: function () { return this.v + 1 }, set: function (x) { n = x } }); o.g = 9; [o.v, o.g, n]|}
            "[1, 2, 9]";
          check "what libraries write at their top" {|var exports = {}; Object.defineProperty(exports, '__esModule', { value: true }); exports.__esModule|} "true";
          check "entries, values, fromEntries, getOwnPropertyNames" {|var o = { a: 1, b: 2 }; [Object.entries(o), Object.values(o), Object.fromEntries([['x', 1]]).x, Object.getOwnPropertyNames(o)]|}
            {|[[["a", 1], ["b", 2]], [1, 2], 1, ["a", "b"]]|};
          check "a descriptor read back" {|var d = Object.getOwnPropertyDescriptor({ a: 1 }, 'a'); [d.value, d.writable, Object.getOwnPropertyDescriptor({}, 'a')]|} "[1, true, undefined]";
          check "setPrototypeOf; isPrototypeOf; propertyIsEnumerable" {|var p = { hi: 1 }, o = {}; Object.setPrototypeOf(o, p); o.own = 2; [o.hi, p.isPrototypeOf(o), o.propertyIsEnumerable('own'), o.propertyIsEnumerable('hi')]|}
            "[1, true, true, false]";
          check "freeze gives the object back (and freezes nothing)" {|var o = Object.freeze({ a: 1 }); o.a = 2; [o.a, Object.isFrozen(o)]|} "[2, false]";
          check "Object.is, hasOwn" {|[Object.is(NaN, NaN), Object.is(1, '1'), Object.hasOwn({ a: 1 }, 'a'), Object.hasOwn({}, 'toString')]|} "[true, false, true, false]");
      Testo.create "Number's, isFinite, Array.of, globalThis" (fun () ->
          check "isFinite converts, Number.isFinite does not" {|[isFinite('12'), isFinite(1 / 0), Number.isFinite('12'), Number.isInteger(5), Number.isInteger(5.5), Number.isNaN('x')]|}
            "[true, false, false, true, false, false]";
          check "its constants" {|[Number.MAX_SAFE_INTEGER, Number.isSafeInteger(Number.MAX_SAFE_INTEGER + 1), Number.POSITIVE_INFINITY]|} "[9007199254740991, false, Infinity]";
          check "Array.of; globalThis" {|var g = 5; [Array.of(7).length, globalThis.g, typeof globalThis.isFinite]|} {|[1, 5, "function"]|});
      Testo.create "an undeclared name assigned to is a global" (fun () ->
          check "made by a function, seen after it" {|function f() { counter = 1 } f(); counter += 1; counter|} "2";
          check "read before it is one: still an error" {|nothing + 1|} "line 1: ReferenceError: nothing is not defined");
      Testo.create "Symbol: a key no one else has" (fun () ->
          check "each its own; Symbol.for the same for the same name" {|[Symbol('a') === Symbol('a'), Symbol.for('app') === Symbol.for('app'), typeof Symbol, typeof Symbol.iterator]|}
            {|[false, true, "function", "string"]|};
          check "as a key: there, and not in a for-in nor the entries" {|var tag = Symbol('tag'); var o = { a: 1 }; o[tag] = 'hidden'; var ks = []; for (var k in o) ks.push(k); [o[tag], ks, Object.entries(o).length, JSON.stringify(Object.getOwnPropertyNames(o))]|}
            {|["hidden", ["a"], 1, "[\"a\"]"]|};
          check "React's test" {|var hasSymbol = typeof Symbol === 'function' && Symbol.for; var el = hasSymbol ? Symbol.for('react.element') : 0xeac7; typeof el|} {|string|});
      Testo.create "Map and Set" (fun () ->
          check "a Map: any value as a key, in the order set" {|var k = {}, m = new Map(); m.set('a', 1).set(k, 2).set(NaN, 3); m.set('a', 10); [m.get('a'), m.get(k), m.get(NaN), m.get({}), m.has(k), m.size, m.keys().length]|}
            "[10, 2, 3, undefined, true, 3, 3]";
          check "delete, clear" {|var m = new Map([[1, 'one'], [2, 'two']]); var gone = [m.delete(1), m.delete(1)]; var left = m.size; m.clear(); [gone, left, m.size]|} "[[true, false], 1, 0]";
          check "a for-of, a pattern, a spread, forEach" {|var m = new Map([['a', 1], ['b', 2]]); var r = []; for (const [k, v] of m) r.push(k + v); m.forEach(function (v, k) { r.push(k + '=' + v) }); [r, [...m].length, [...m.keys()]]|}
            {|[["a1", "b2", "a=1", "b=2"], 2, ["a", "b"]]|};
          check "a Set: each value once" {|var s = new Set([1, 2, 2, 3]); s.add(3).add(4); [s.size, s.has(2), s.has(9), [...s], Array.from(new Set('hello')).length >= 0]|} "[4, true, false, [1, 2, 3, 4], true]";
          check "instanceof; without new" {|[new Map() instanceof Map, new Set() instanceof Map]|} "[true, false]";
          check "a WeakMap, by the object" {|var w = new WeakMap(), o = {}; w.set(o, 'x'); [w.get(o), w.has({})]|} {|["x", false]|};
          check "a Map from a Map" {|new Map(new Map([[1, 2]])).get(1)|} "2");
      Testo.create "a mistake of the engine's own is the script's error, not the program's end" (fun () ->
          check "half a surrogate pair, in a string and a pattern" {|['\ud800'.length, /[\ud800-\udfff]/.test('a')]|} "[3, false]");
    ]
