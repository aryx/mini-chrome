(* Js_props: an object's properties -- read, written, asked about,
   listed -- and the chain of prototypes behind them.

   (notes_javascript.md section 6.) A JavaScript object is a list of
   properties and a link to another object, its **prototype**; what it
   does not have itself it has from that one, and so on up:

     var p = new Point(1, 2)        p            {x: 1, y: 2}
     p.sum()                         -> Point.prototype   {sum: function, constructor: Point}
     p.hasOwnProperty("x")              -> Object.prototype   {hasOwnProperty: ...}

   [get] follows that chain. A value that is no object has one all the
   same: a string's methods are String.prototype's, an array's
   Array.prototype's -- the built-ins' prototypes ([Js_builtins.protos]),
   given to each function here, so that this module knows nothing of
   the interpreter. A function's own "prototype" (what its new objects
   will link to) is made the first time it is asked for.

   An array's indices and length, a string's characters and length, and
   a host object's properties (the DOM's: Script_host) are not in the
   list: they are answered here from what the value is.

   Writing ([set]) is always to the object itself, never up the chain.

   [enumerable_keys] is for (k in o)'s list: the object's own keys in
   the order they were set, then those of the prototypes it was given
   -- not the built-in ones', whose methods do not show in a for-in,
   nor a prototype's "constructor". (There is no flag a property for
   "enumerable": that rule stands for it.)

   Reference: ECMA-262 5.1, sections 8.12 (an object's internal
   methods: [[Get]], [[Put]], [[HasProperty]]), 12.6.4 (for-in), 15.3.5.3
   (instanceof). *)

(* the array index a key names, if it is one: "3", not "03" nor "-1" *)
val index_of_key : string -> int option

(* a value as a property's key: 3 is "3", 1.5 is "1.5", else its string *)
val key_of : Js_value.value -> string

(* an object's prototype: its own, else its kind's (an array's is
 * Array.prototype), Object.prototype last, and nothing after it *)
val proto_of : Js_builtins.protos -> Js_value.obj -> Js_value.obj option

(* [get protos v k]: v.k, up the prototypes; TypeError if [v] is
 * undefined or null *)
val get : Js_builtins.protos -> Js_value.value -> string -> Js_value.value

(* k in o: its own or its prototypes' *)
val has : Js_builtins.protos -> Js_value.obj -> string -> bool

(* v instanceof F: F.prototype is in v's chain *)
val instance_of : Js_builtins.protos -> Js_value.value -> Js_value.value -> bool

(* v.k = x: on the object itself (an array grown, its length set; a
 * host object asked); lost on a primitive; TypeError on undefined or
 * null *)
val set : Js_value.value -> string -> Js_value.value -> unit

(* the keys a for (k in v) goes through *)
val enumerable_keys : Js_value.value -> string list
