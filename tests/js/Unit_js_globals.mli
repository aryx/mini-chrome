(* Js_globals: what libraries look for first -- Object's helpers
 * (defineProperty with a value or a getter, entries, values...),
 * Number's, isFinite, Symbol (a unique key, Symbol.for, hidden from
 * for-in), Map and Set (their order, NaN as a key, in a for-of and a
 * spread); and an undeclared name assigned to, a global *)
val tests : Testo.t list
