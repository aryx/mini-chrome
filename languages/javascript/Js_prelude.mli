(* Js_prelude: the standard library's later additions, written in
   JavaScript -- data/prelude/library.js, embedded.

   The engine's built-ins are OCaml (Js_builtins: what ES5 had, and
   what needs the engine's insides). But most of what the standard
   added to Array, String, Math and Promise since 2016 needs nothing
   the language does not give: Array.prototype.at is three lines over
   length and an index, flat is a loop, Promise.withResolvers is a
   promise made. So they are written in the language they extend, and
   run in every engine before any script ([Js_eval.create]):

     at, fill, flat, flatMap, findLast, findLastIndex, reduceRight,
       copyWithin, toSorted, toReversed, toSpliced, with       (arrays)
     at, replaceAll, padEnd, trimEnd, codePointAt, matchAll,
       localeCompare, normalize; String.fromCodePoint, String.raw
     Object.groupBy, Number.parseFloat and parseInt; a number's
       toString(radix), toExponential, toPrecision
     Math's cbrt, hypot, log2, log10, log1p, expm1, sinh, cosh, tanh,
       clz32, imul, fround
     Promise.withResolvers; WeakRef, FinalizationRegistry,
       AggregateError; BigInt as a number (10n is 10: the lexer's);
       ArrayBuffer and DataView (whole numbers of 1, 2 and 4 bytes)
     JSON.stringify's toJSON, replacer and indentation
     Date, whole: the calendar's arithmetic over the engine's clock
       (the days of a date and back, a text parsed, the setters, the
       ways a date is written), in one zone, UTC

   Each is added as a built-in is: not listed by for-in, and only if
   it is not there already. The text is parsed once for the program,
   and run once for each engine.

   others:
   A library written in its own language is how these were written
   before they were standard: a polyfill (Remy Sharp's word, 2010),
   the script a page loaded so that an old browser had the new
   methods -- es5-shim, then core-js, which is in a large share of
   the web's bundles still. What is here is that, turned round: the
   engine brings its own.

   modern:
   And it is how real engines write much of theirs. V8's built-ins
   were JavaScript for years (with natives underneath), then moved to
   a language of its own, Torque, compiled ahead of time: a built-in
   in the user's language is easy to write and starts slow, each page
   paying to parse and warm it. Here the parse is shared and the
   functions are few.

   What they are not: exact. A string is its UTF-8 bytes here, so
   at and codePointAt count bytes, not UTF-16 units; localeCompare
   compares bytes, normalize changes nothing, fround does not round.

   Reference: ECMAScript 2016 to 2024, the sections of each method;
   github.com/zloirock/core-js for how carefully it can be done. *)

(* data/prelude/library.js *)
val text : string
