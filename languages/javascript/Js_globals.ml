(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Js_globals.mli *)
open Js_value

let arg (args : value list) (i : int) : value = Option.value (List.nth_opt args i) ~default:Undefined
let fn = host_function
let array (vs : value list) : value = Object (new_array vs)
let is_symbol (k : string) : bool = String.length k >= 2 && k.[0] = '@' && k.[1] = '@'

(* an object's own keys that show: not a symbol's *)
let own_keys (v : value) : string list =
  match (match v with Object o -> Object (target o) | v -> v) with
  | Object ({ kind = Array a; _ } as o) -> List.init a.length string_of_int @ List.filter (fun k -> not (is_symbol k)) (keys o)
  | Object o -> List.filter (fun k -> not (is_symbol k)) (keys o)
  | String s -> List.init (String.length s) string_of_int
  | _ -> []

(* a key's value, read without calling a getter: an array's item, a
 * string's character, an object's own *)
let own (v : value) (k : string) : value =
  match ((match v with Object o -> Object (target o) | v -> v), int_of_string_opt k) with
  | Object { kind = Array a; _ }, Some i when i >= 0 && i < a.length -> a.elements.(i)
  | String s, Some i when i >= 0 && i < String.length s -> String (String.make 1 s.[i])
  | Object o, _ -> Option.value (get_own o k) ~default:Undefined
  | _ -> Undefined

(* ===, but NaN is NaN: a Map's keys *)
let same_value (a : value) (b : value) : bool =
  match (a, b) with Number x, Number y when Float.is_nan x && Float.is_nan y -> true | _ -> strict_equal a b

(*****************************************************************************)
(* Object, Array, Number *)
(*****************************************************************************)

let object_statics : (string * value) list =
  (* a descriptor { value } or { get, set } made the property *)
  let define (o : obj) (k : string) (descriptor : value) : unit =
    match descriptor with
    | Object d -> (
        match (get_own d "get", get_own d "set") with
        | None, None -> set_own o k (Option.value (get_own d "value") ~default:Undefined)
        | g, s -> set_own o k (Object { (new_object ()) with kind = Accessor (Option.value g ~default:Undefined, Option.value s ~default:Undefined) }))
    | _ -> throw "TypeError" "Property description must be an object"
  in
  let pairs v = List.map (fun k -> array [ String k; own v k ]) (own_keys v) in
  [ ("defineProperty",
     fn "defineProperty" (fun ~this:_ args ->
         match arg args 0 with
         | Object o as target -> define o (to_string (arg args 1)) (arg args 2); target
         | _ -> throw "TypeError" "Object.defineProperty called on non-object"));
    ("defineProperties",
     fn "defineProperties" (fun ~this:_ args ->
         (match (arg args 0, arg args 1) with Object o, (Object ds as d) -> List.iter (fun k -> define o k (own d k)) (keys ds) | _ -> ());
         arg args 0));
    ("getOwnPropertyNames", fn "getOwnPropertyNames" (fun ~this:_ args -> array (List.map (fun k -> String k) (own_keys (arg args 0)))));
    ("getOwnPropertySymbols", fn "getOwnPropertySymbols" (fun ~this:_ _ -> array []));
    ("getOwnPropertyDescriptor",
     fn "getOwnPropertyDescriptor" (fun ~this:_ args ->
         let k = to_string (arg args 1) in
         match arg args 0 with
         | Object o when get_own o k <> None || List.mem k (own_keys (Object o)) -> (
             let d = new_object () in
             (match own (Object o) k with
             | Object { kind = Accessor (g, s); _ } -> set_own d "get" g; set_own d "set" s
             | v -> set_own d "value" v; set_own d "writable" (Bool true));
             set_own d "enumerable" (Bool true);
             set_own d "configurable" (Bool true);
             Object d)
         | _ -> Undefined));
    (* every own property's descriptor, by its key *)
    ("getOwnPropertyDescriptors",
     fn "getOwnPropertyDescriptors" (fun ~this:_ args ->
         let v = arg args 0 and all = new_object () in
         List.iter
           (fun k ->
             let d = new_object () in
             (match own v k with
             | Object { kind = Accessor (g, s); _ } -> set_own d "get" g; set_own d "set" s
             | x -> set_own d "value" x; set_own d "writable" (Bool true));
             set_own d "enumerable" (Bool true);
             set_own d "configurable" (Bool true);
             set_own all k (Object d))
           (own_keys v);
         Object all));
    ("values", fn "values" (fun ~this:_ args -> let v = arg args 0 in array (List.map (own v) (own_keys v))));
    ("entries", fn "entries" (fun ~this:_ args -> array (pairs (arg args 0))));
    ("fromEntries",
     fn "fromEntries" (fun ~this:_ args ->
         let o = new_object () in
         (match arg args 0 with
         | Object ({ kind = Array _; _ } as a) -> List.iter (fun pair -> set_own o (to_string (own pair "0")) (own pair "1")) (array_items a)
         | _ -> ());
         Object o));
    ("setPrototypeOf",
     fn "setPrototypeOf" (fun ~this:_ args ->
         (match (arg args 0, arg args 1) with Object o, Object p -> o.proto <- Some p | Object o, Null -> o.proto <- None | _ -> ());
         arg args 0));
    (* nothing is frozen: the flags of a property are not kept *)
    ("freeze", fn "freeze" (fun ~this:_ args -> arg args 0));
    ("seal", fn "seal" (fun ~this:_ args -> arg args 0));
    ("preventExtensions", fn "preventExtensions" (fun ~this:_ args -> arg args 0));
    ("isFrozen", fn "isFrozen" (fun ~this:_ _ -> Bool false));
    ("isSealed", fn "isSealed" (fun ~this:_ _ -> Bool false));
    ("isExtensible", fn "isExtensible" (fun ~this:_ _ -> Bool true));
    ("is", fn "is" (fun ~this:_ args -> Bool (same_value (arg args 0) (arg args 1))));
    (* o.hasOwnProperty(k), called safely *)
    ("hasOwn", fn "hasOwn" (fun ~this:_ args -> Bool (List.mem (to_string (arg args 1)) (own_keys (arg args 0)) || match arg args 0 with Object o -> get_own o (to_string (arg args 1)) <> None | _ -> false)));
  ]

let number_statics : (string * value) list =
  let finite v = match v with Number f -> not (Float.is_nan f || Float.abs f = Float.infinity) | _ -> false in
  [ ("isFinite", fn "isFinite" (fun ~this:_ args -> Bool (finite (arg args 0))));
    ("isNaN", fn "isNaN" (fun ~this:_ args -> Bool (match arg args 0 with Number f -> Float.is_nan f | _ -> false)));
    ("isInteger", fn "isInteger" (fun ~this:_ args -> Bool (match arg args 0 with Number f -> finite (Number f) && Float.is_integer f | _ -> false)));
    ("isSafeInteger", fn "isSafeInteger" (fun ~this:_ args -> Bool (match arg args 0 with Number f -> Float.is_integer f && Float.abs f <= 9007199254740991. | _ -> false)));
    ("MAX_SAFE_INTEGER", Number 9007199254740991.);
    ("MIN_SAFE_INTEGER", Number (-9007199254740991.));
    ("MAX_VALUE", Number Float.max_float);
    ("MIN_VALUE", Number 5e-324);
    ("EPSILON", Number Float.epsilon);
    ("POSITIVE_INFINITY", Number Float.infinity);
    ("NEGATIVE_INFINITY", Number Float.neg_infinity);
    ("NaN", Number Float.nan) ]

(*****************************************************************************)
(* Symbol *)
(*****************************************************************************)

(* a symbol is a string no script would write: "@@" and its number or
 * its well-known name *)
let symbol () : value =
  let made = ref 0 and registry : (string, value) Hashtbl.t = Hashtbl.create 8 in
  let fresh description = incr made; Symbol (Printf.sprintf "@@%d:%s" !made description) in
  let description args = match arg args 0 with Undefined -> "" | v -> to_string v in
  let s = fn "Symbol" (fun ~this:_ args -> fresh (description args)) in
  (match s with
  | Object o ->
      List.iter (fun name -> set_own o name (Symbol ("@@" ^ name))) [ "iterator"; "asyncIterator"; "toStringTag"; "hasInstance"; "toPrimitive"; "species" ];
      (* Symbol.for: the same one for the same name *)
      set_own o "for"
        (fn "for" (fun ~this:_ args ->
             let key = description args in
             match Hashtbl.find_opt registry key with
             | Some v -> v
             | None -> let v = fresh key in Hashtbl.replace registry key v; v))
  | _ -> ());
  s

(*****************************************************************************)
(* Map, Set *)
(*****************************************************************************)

(* a Map's or a Set's constructor: each object made keeps its entries
 * (a Set's: its values, each its own key) in a list, the first first *)
let collection ~(call : value -> this:value -> value list -> value) (name : string) ~(map : bool) : value =
  let proto = new_object () in
  let make ~this args =
    let o = match this with Object o -> o | _ -> throw "TypeError" (Printf.sprintf "Constructor %s requires 'new'" name) in
    let entries : (value * value) list ref = ref [] in
    let has k = List.exists (fun (k', _) -> same_value k k') !entries in
    let put k v = if has k then entries := List.map (fun (k', v') -> if same_value k k' then (k', v) else (k', v')) !entries else entries := !entries @ [ (k, v) ] in
    let def m f = set_own o m (fn m (fun ~this:_ args -> f args)) in
    let pair (k, v) = array [ k; v ] in
    def "has" (fun args -> Bool (has (arg args 0)));
    def "delete" (fun args ->
        let there = has (arg args 0) in
        entries := List.filter (fun (k, _) -> not (same_value k (arg args 0))) !entries;
        Bool there);
    def "clear" (fun _ -> entries := []; Undefined);
    def "forEach" (fun args -> List.iter (fun (k, v) -> ignore (call (arg args 0) ~this:(arg args 1) [ v; k; this ])) !entries; Undefined);
    def "keys" (fun _ -> array (List.map fst !entries));
    def "values" (fun _ -> array (List.map snd !entries));
    def "entries" (fun _ -> array (List.map pair !entries));
    if map then (
      def "get" (fun args -> match List.find_opt (fun (k, _) -> same_value k (arg args 0)) !entries with Some (_, v) -> v | None -> Undefined);
      def "set" (fun args -> put (arg args 0) (arg args 1); this))
    else def "add" (fun args -> put (arg args 0) (arg args 0); this);
    (* what a for-of and a spread go through: a Map's pairs, a Set's values *)
    set_own o "@@iterator" (fn "[Symbol.iterator]" (fun ~this:_ _ -> array (if map then List.map pair !entries else List.map fst !entries)));
    set_own o "size" (Object { (new_object ()) with kind = Accessor (fn "size" (fun ~this:_ _ -> Number (float_of_int (List.length !entries))), Undefined) });
    (* new Map([[k, v], ...]), new Set([v, ...]) *)
    (match arg args 0 with
    | Object ({ kind = Array _; _ } as a) -> List.iter (fun item -> if map then put (own item "0") (own item "1") else put item item) (array_items a)
    | Object src -> (
        match get_own src "@@iterator" with
        | Some f -> (
            match call f ~this:(Object src) [] with
            | Object ({ kind = Array _; _ } as a) -> List.iter (fun item -> if map then put (own item "0") (own item "1") else put item item) (array_items a)
            | _ -> ())
        | None -> ())
    | _ -> ());
    Undefined
  in
  let c = fn name make in
  (match c with Object o -> set_own o "prototype" (Object proto); set_own proto "constructor" c | _ -> ());
  c

(*****************************************************************************)
(* Proxy, Reflect *)
(*****************************************************************************)

(* new Proxy(target, handler): the traps are the interpreter's (Js_eval) *)
let proxy : value =
  fn "Proxy" (fun ~this:_ args ->
      match (arg args 0, arg args 1) with
      | Object tg, Object h -> Object { (new_object ()) with kind = Proxy (tg, h) }
      | _ -> throw "TypeError" "Cannot create proxy with a non-object as target or handler")

(* Reflect: what a trap does when it only wants the usual -- each
 * operation on an object as a function *)
let reflect ~(call : value -> this:value -> value list -> value) ~(lookup : string -> value option) ~(get : value -> string -> value)
    ~(put : value -> string -> value -> unit) ~(has : value -> string -> bool) : value =
  let o = new_object () in
  let def m f = set_own o m (fn m (fun ~this:_ args -> f args)) in
  let of_object m args = match lookup "Object" with Some (Object c) -> ( match get_own c m with Some f -> call f ~this:Undefined args | None -> Undefined) | _ -> Undefined in
  def "get" (fun args -> get (arg args 0) (to_string (arg args 1)));
  def "set" (fun args -> put (arg args 0) (to_string (arg args 1)) (arg args 2); Bool true);
  def "has" (fun args -> Bool (has (arg args 0) (to_string (arg args 1))));
  def "deleteProperty" (fun args ->
      (match arg args 0 with Object o -> let o = target o in o.props <- List.filter (fun (k, _) -> k <> to_string (arg args 1)) o.props | _ -> ());
      Bool true);
  (* an array's: its indices and "length" too *)
  def "ownKeys" (fun args ->
      let v = arg args 0 in
      array (List.map (fun k -> String k) (own_keys v @ match v with Object o when (match (target o).kind with Array _ -> true | _ -> false) -> [ "length" ] | _ -> [])));
  def "getPrototypeOf" (of_object "getPrototypeOf");
  def "defineProperty" (fun args -> ignore (of_object "defineProperty" args); Bool true);
  def "getOwnPropertyDescriptor" (of_object "getOwnPropertyDescriptor");
  def "apply" (fun args -> call (arg args 0) ~this:(arg args 1) (match arg args 2 with Object a -> array_items a | _ -> []));
  Object o

(*****************************************************************************)
(* Entry point *)
(*****************************************************************************)

let install ~(call : value -> this:value -> value list -> value) ~(lookup : string -> value option) ~(get : value -> string -> value)
    ~(put : value -> string -> value -> unit) ~(has : value -> string -> bool) (define : string -> value -> unit) : unit =
  let add name statics = match lookup name with Some (Object o) -> List.iter (fun (k, v) -> set_own o k v) statics | _ -> () in
  add "Object" object_statics;
  (* and what every object has from Object.prototype *)
  (match lookup "Object" with
  | Some (Object c) -> (
      match get_own c "prototype" with
      | Some (Object proto) ->
          let def m f = set_own proto m (fn m f) in
          def "propertyIsEnumerable" (fun ~this args -> Bool (List.mem (to_string (arg args 0)) (own_keys this)));
          def "isPrototypeOf" (fun ~this args ->
              let rec up (o : obj) = match o.proto with Some p -> Object p == this || (match this with Object t -> t == p | _ -> false) || up p | None -> false in
              Bool (match arg args 0 with Object o -> up o | _ -> false));
          def "valueOf" (fun ~this _ -> this);
          def "toLocaleString" (fun ~this _ -> to_primitive this)
      | _ -> ())
  | _ -> ());
  add "Number" number_statics;
  add "Array" [ ("of", fn "of" (fun ~this:_ args -> array args)) ];
  define "isFinite" (fn "isFinite" (fun ~this:_ args -> let f = to_number (arg args 0) in Bool (not (Float.is_nan f || Float.abs f = Float.infinity))));
  (* typed arrays (ES2015) are arrays here: of zeros for a length, else
   * of the items given; no buffer under them, no wrapping of a number
   * too big for its type *)
  List.iter
    (fun name ->
      define name
        (fn name (fun ~this:_ args ->
             match arg args 0 with
             | Number n -> array (List.init (max 0 (int_of_float n)) (fun _ -> Number 0.))
             | Object ({ kind = Array _; _ } as a) -> array (array_items a)
             | _ -> array [])))
    [ "Uint8Array"; "Int8Array"; "Uint8ClampedArray"; "Uint16Array"; "Int16Array"; "Uint32Array"; "Int32Array"; "Float32Array"; "Float64Array" ];
  define "Proxy" proxy;
  define "Reflect" (reflect ~call ~lookup ~get ~put ~has);
  define "Symbol" (symbol ());
  define "Map" (collection ~call "Map" ~map:true);
  define "WeakMap" (collection ~call "WeakMap" ~map:true);
  define "Set" (collection ~call "Set" ~map:false);
  define "WeakSet" (collection ~call "WeakSet" ~map:false)
