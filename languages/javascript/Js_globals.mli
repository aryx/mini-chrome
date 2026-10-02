(* Js_globals: the rest of the standard library, what libraries look
   for before they do anything -- the helpers of Object, Array and
   Number, Symbol, Map and Set.

   Js_builtins has what a page's own script uses (strings, arrays,
   Math, JSON, Date). A library (jQuery, React, Underscore) starts by
   taking stock of the engine: "var _isFinite = isFinite", "typeof
   Symbol === 'function' && Symbol.for", "Object.defineProperty(exports,
   '__esModule', { value: true })" -- and stops at the first that is
   not there. They are here:

     isFinite, globalThis
     Number.isFinite .isInteger .isNaN .MAX_SAFE_INTEGER .EPSILON ...
     Object.defineProperty .defineProperties .getOwnPropertyNames
           .getOwnPropertyDescriptor .entries .values .fromEntries
           .freeze .isFrozen .seal .setPrototypeOf ...
     Array.of
     Symbol(), Symbol.for, Symbol.iterator
     Map, Set, WeakMap, WeakSet

   Three of them are less than the real thing, and say so:

   **Object.defineProperty** sets a value, or a getter and a setter
   (Js_value's Accessor). Its flags -- writable, enumerable,
   configurable -- are not kept: every property can be written and
   deleted. So **freeze** freezes nothing, and isFrozen says false.

   **A symbol is a string**, "@@iterator" or "@@7:description": unique,
   usable as a property's key, which is all the libraries here do with
   one. typeof gives "string" where JavaScript says "symbol", and such
   a key is left out of for-in and Object.keys by its "@@".

   **Map and Set** keep their entries in a list, in the order they
   came: get and has look through it (SameValueZero: === but NaN is
   NaN). Right for the tens of entries a page has; a hash table is the
   real one. keys(), values() and entries() give arrays, not iterators:
   a for-of or a spread goes through them the same. WeakMap and WeakSet
   are Map and Set: nothing is collected.

   Reference: ECMA-262, sections 20.1 (Object), 20.4 (Symbol), 21.1
   (Number), 24.1 and 24.2 (Map, Set). *)

(* a symbol's string: "@@" and what it is *)
val is_symbol : string -> bool

(* [install ~call ~lookup define]: the globals above [define]d, their
 * statics added to the constructors [lookup] finds (Object, Array,
 * Number: Js_builtins'); [call] a function called (a Map's forEach) *)
val install :
  call:(Js_value.value -> this:Js_value.value -> Js_value.value list -> Js_value.value) ->
  lookup:(string -> Js_value.value option) ->
  (string -> Js_value.value -> unit) ->
  unit
