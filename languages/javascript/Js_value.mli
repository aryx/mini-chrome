(* Js_value: JavaScript's values, and how it converts one into another.

   (notes_javascript.md sections 4 and 7.) Seven kinds, less symbol
   and bigint:

     undefined  null  boolean  number (a float: 1 is 1.0)  string  object  function

   An **object** is a table from names to values, mutable, its keys kept
   in the order they were added. An **array** is an object whose items
   are a growable OCaml array, [length] and indexing done on it
   directly -- what engines do too, behind the same appearance. A
   **function** is an object holding a closure (its parameters, its
   body, and the scope it was created in: [scope]) or an OCaml function
   (a host function: console.log, and the browser's). Objects are
   compared, passed and stored by reference: [{} === {}] is false.

   A **host object** is the browser's: document, an element, whose
   properties are OCaml functions reading and changing the page (Js_eval
   calls [get] and [set] where it would look in the table).

   A string is OCaml's, UTF-8: its [length] and indexes count bytes, so
   "é".length is 2 where JavaScript, counting UTF-16 units, says 1. The
   pages of this repository are ASCII where it matters; counting code
   points is an exercise.

   **Conversions**, JavaScript's, which convert rather than refuse:
   [to_string], [to_number], [truthy] (false, 0, NaN, "", null and
   undefined are false; everything else, "0" and [] included, true), and
   [to_primitive] (an array is its items joined with commas, an object
   "[object Object]"). Section 7's table is Js_eval's [+], built on
   them. *)

type value =
  | Undefined
  | Null
  | Bool of bool
  | Number of float
  | String of string
  (* claude: a symbol (ES2015): a unique value, usable as a property's
   * key. What it holds is that key, "@@7:description" or a well-known
   * one's, "@@iterator": a string no script writes *)
  | Symbol of string
  | Object of obj

and obj = {
  id : int; (* for printing cycles and for tests; identity is (==) *)
  mutable props : (string * value ref) list; (* the newest first: keys in order, reversed *)
  kind : kind;
  mutable proto : obj option; (* its prototype: where a property it does not have is looked for next *)
}

and kind =
  | Plain
  | Array of items
  | Closure of closure
  | Host_function of string * (this:value -> value list -> value) (* its name, and it *)
  | Host_object of host
  | Regexp of Js_regexp.t (* a regular expression (its lastIndex a property) *)
  (* not an object a script sees: what a property is when it is a
   * getter and a setter ({ get k() { } }, Object.defineProperty): the
   * two functions, undefined for the one it has not. Reading the
   * property calls the first, assigning to it the second (Js_eval) *)
  | Accessor of value * value
  (* claude: new Proxy(target, handler): the target, seen through the
   * handler's traps -- reading a property calls handler.get, setting
   * one handler.set, "k in p" handler.has (Js_eval; a trap the handler
   * has not: the target's own way). What it is otherwise (an array, a
   * function, its keys) is what its target is *)
  | Proxy of obj * obj

(* an object whose properties are the host's functions: reading one
 * calls [get], writing one [set] (the spec's getters and setters) --
 * a page's element, whose textContent is its tree's text, not a value
 * stored; [show], how the console shows it *)
and host = { class_name : string; get : string -> value; set : string -> value -> unit; show : unit -> string }

and items = { mutable elements : value array; mutable length : int }

and closure = { func : Js_ast.func; scope : scope; this : value option (* an arrow's, captured *) }

(* a frame of names, and the frame around it *)
(* claude: [subject] is the object of a with (obj) { }: a name that is
 * a property of it is that property; [in_with] says whether this
 * frame or one around it has one (else no frame is asked) *)
and scope = { vars : (string, binding) Hashtbl.t; parent : scope option; subject : value option; in_with : bool }

and binding = { mutable value : value; constant : bool }

(* a JavaScript exception, thrown by [throw] or by the engine: any value,
 * usually an error object *)
exception Throw of value

(*****************************************************************************)
(* {1 Objects} *)
(*****************************************************************************)

val new_object : unit -> obj
val new_array : value list -> obj
val host_function : string -> (this:value -> value list -> value) -> value
val host_object : host -> value

(* a proxy's target, through proxies of proxies; any other object: itself *)
val target : obj -> obj

(* an own property, if the object has it *)
val get_own : obj -> string -> value option

(* set, or add at the end of the keys *)
val set_own : obj -> string -> value -> unit

(* the keys, in the order they were added *)
val keys : obj -> string list

val array_items : obj -> value list

(* an error object, {name, message}: [error "TypeError" "x is not a
 * function"] *)
val error : string -> string -> value

(* raise one: [throw "RangeError" "..."] *)
val throw : string -> string -> 'a

(*****************************************************************************)
(* {1 Conversions} *)
(*****************************************************************************)

val typeof : value -> string
val truthy : value -> bool
val to_primitive : value -> value
val to_string : value -> string
val to_number : value -> float

(* ===: the same kind and value; objects the same object; NaN is not
 * NaN *)
val strict_equal : value -> value -> bool

(* how the console shows a value: a string as it is at the top, quoted
 * inside; [1, "a"]; {a: 1, b: [2]}; function f *)
val display : value -> string

(* JSON.stringify's text: objects' keys in order, undefined and
 * functions left out of objects (null in arrays), a cycle an error *)
val to_json : value -> string option
