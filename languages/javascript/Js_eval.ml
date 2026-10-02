(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Js_eval.mli *)
open Js_value
module A = Js_ast

type t = {
  globals : scope;
  mutable protos : Js_builtins.protos option; (* set once the built-ins are *)
  mutable line : int; (* of the statement running: an error's *)
  mutable steps : int; (* left in this run's budget *)
  mutable budget : int;
  mutable depth : int; (* of the calls *)
}

type error = { line : int; message : string }

(* how a statement ended *)
type outcome = Normal | Return of value | Break of string option | Continue of string option

let max_depth = 2_000

(*****************************************************************************)
(* Scopes *)
(*****************************************************************************)

let new_scope (parent : scope) : scope = { vars = Hashtbl.create 8; parent = Some parent }

let rec lookup (s : scope) (x : string) : binding option =
  match Hashtbl.find_opt s.vars x with Some b -> Some b | None -> Option.bind s.parent (fun p -> lookup p x)

let declare (s : scope) (x : string) ~(constant : bool) (v : value) : unit = Hashtbl.replace s.vars x { value = v; constant }

(* a for's next iteration: the same names, in new bindings holding the
 * same values (Hashtbl.copy would share the bindings, and every
 * iteration's closures would see the last i) *)
let copy_scope (s : scope) : scope =
  let vars = Hashtbl.create 8 in
  Hashtbl.iter (fun x (b : binding) -> Hashtbl.replace vars x { b with value = b.value }) s.vars;
  { s with vars }

(*****************************************************************************)
(* Properties *)
(*****************************************************************************)

let protos (t : t) : Js_builtins.protos = Option.get t.protos

(* the array index a key names, if it is one: "3", not "03" nor "-1" *)
let index_of_key (k : string) : int option =
  match int_of_string_opt k with Some i when i >= 0 && string_of_int i = k -> Some i | _ -> None

let key_of (v : value) : string = match v with Number f when Float.is_integer f && f >= 0. -> Printf.sprintf "%.0f" f | v -> to_string v

(* an object's prototype: its own, else its kind's (an array's
 * Array.prototype...), Object.prototype last, and nothing after it *)
let proto_of (t : t) (o : obj) : obj option =
  match o.proto with
  | Some p -> Some p
  | None -> (
      let p = protos t in
      if o == p.objects then None
      else
        match o.kind with
        | Array _ -> Some p.arrays
        | Closure _ | Host_function _ -> Some p.functions
        | Regexp _ -> Some p.regexps
        | Host_object _ -> None
        | Plain -> Some p.objects)

(* a property: the object's own, else up its prototypes' chain; a
 * function's prototype made when first asked for, {constructor: f} *)
let rec from_chain (t : t) (o : obj) (k : string) : value =
  match get_own o k with
  | Some v -> v
  | None -> (
      match (o.kind, k) with
      | Closure _, "prototype" ->
          let p = new_object () in
          set_own p "constructor" (Object o);
          set_own o "prototype" (Object p);
          Object p
      | Host_object h, _ -> h.get k
      | _ -> ( match proto_of t o with Some p -> from_chain t p k | None -> Undefined))

let get (t : t) (target : value) (k : string) : value =
  match target with
  | Undefined | Null -> throw "TypeError" (Printf.sprintf "Cannot read properties of %s (reading '%s')" (to_string target) k)
  | String s -> (
      match (k, index_of_key k) with
      | "length", _ -> Number (float_of_int (String.length s))
      | _, Some i -> if i < String.length s then String (String.make 1 s.[i]) else Undefined
      | _ -> from_chain t (protos t).strings k)
  | Object ({ kind = Array a; _ } as o) -> (
      match (k, index_of_key k) with
      | "length", _ -> Number (float_of_int a.length)
      | _, Some i -> if i < a.length then a.elements.(i) else Undefined
      | _ -> from_chain t o k)
  | Object { kind = Host_object h; _ } -> h.get k
  | Object o -> from_chain t o k
  | Number _ -> from_chain t (protos t).numbers k
  | Bool _ -> Undefined

(* whether an object has a property, its own or its prototypes': k in o *)
let rec has (t : t) (o : obj) (k : string) : bool =
  get_own o k <> None
  ||
  match o.kind with
  | Array a -> k = "length" || (match index_of_key k with Some i -> i < a.length | None -> false) || inherited t o k
  | Host_object h -> h.get k <> Undefined
  | _ -> inherited t o k

and inherited (t : t) (o : obj) (k : string) : bool = match proto_of t o with Some p -> has t p k | None -> false

(* the keys for (k in v) goes through: an array's indices, a string's;
 * an object's own, in the order they were set, then those of the
 * prototypes it was given (not the built-in ones', whose methods do
 * not show; nor a prototype's "constructor") *)
let enumerable_keys (v : value) : string list =
  let rec chain (o : obj) (seen : string list) : string list =
    let own = List.filter (fun k -> not (List.mem k seen)) (keys o) in
    own @ match o.proto with Some p -> List.filter (( <> ) "constructor") (chain p (seen @ own)) | None -> []
  in
  match v with
  | Object ({ kind = Array a; _ } as o) -> List.init a.length string_of_int @ chain o []
  | Object { kind = Host_object _; _ } -> []
  | Object o -> chain o []
  | String s -> List.init (String.length s) string_of_int
  | _ -> []

(* whether F's prototype is in v's chain: v instanceof F *)
let instance_of (t : t) (v : value) (f : value) : bool =
  match (v, get t f "prototype") with
  | Object o, Object p ->
      let rec up (x : obj) = match proto_of t x with Some q -> q == p || up q | None -> false in
      up o
  | _ -> false

(* ==: the same as === for the same kinds; null and undefined equal
 * each other only; else numbers compared, a string or a boolean made
 * one, an object its primitive (ECMA-262 5.1, 11.9.3) *)
let rec loose_equal (a : value) (b : value) : bool =
  match (a, b) with
  | (Undefined | Null), (Undefined | Null) -> true
  | (Undefined | Null), _ | _, (Undefined | Null) -> false
  | Number _, Number _ | String _, String _ | Bool _, Bool _ | Object _, Object _ -> strict_equal a b
  | Number x, String _ -> x = to_number b
  | String _, Number y -> to_number a = y
  | Bool _, _ -> loose_equal (Number (to_number a)) b
  | _, Bool _ -> loose_equal a (Number (to_number b))
  | Object _, _ -> loose_equal (to_primitive a) b
  | _, Object _ -> loose_equal a (to_primitive b)

let set (target : value) (k : string) (v : value) : unit =
  match target with
  | Undefined | Null -> throw "TypeError" (Printf.sprintf "Cannot set properties of %s (setting '%s')" (to_string target) k)
  | Object ({ kind = Array a; _ } as o) -> (
      let grow n =
        if n > Array.length a.elements then (
          let bigger = Array.make (max n (2 * Array.length a.elements)) Undefined in
          Array.blit a.elements 0 bigger 0 a.length;
          a.elements <- bigger)
      in
      match (k, index_of_key k) with
      | "length", _ ->
          let n = int_of_float (to_number v) in
          grow n;
          for i = a.length to n - 1 do a.elements.(i) <- Undefined done;
          a.length <- n
      | _, Some i ->
          grow (i + 1);
          for j = a.length to i - 1 do a.elements.(j) <- Undefined done;
          a.elements.(i) <- v;
          a.length <- max a.length (i + 1)
      | _ -> set_own o k v)
  | Object { kind = Host_object h; _ } -> h.set k v
  | Object o -> set_own o k v
  (* a property of a primitive: lost, as JavaScript loses it *)
  | Bool _ | Number _ | String _ -> ()

(*****************************************************************************)
(* Operators *)
(*****************************************************************************)

(* a number as the 32 bits the bitwise operators work on: its integer
 * part, modulo 2^32 (NaN and the infinities: 0) *)
let to_int32 (v : value) : int32 =
  let f = to_number v in
  if Float.is_nan f || Float.abs f = Float.infinity then 0l
  else Int64.to_int32 (Int64.of_float (Float.rem (Float.trunc f) 4294967296.))

let of_int32 (i : int32) : value = Number (Int32.to_float i)

let arithmetic (op : string) (a : value) (b : value) : value =
  match op with
  | "+" -> (
      match (to_primitive a, to_primitive b) with
      | (String _ as x), y | x, (String _ as y) -> String (to_string x ^ to_string y)
      | x, y -> Number (to_number x +. to_number y))
  | "-" -> Number (to_number a -. to_number b)
  | "*" -> Number (to_number a *. to_number b)
  | "/" -> Number (to_number a /. to_number b)
  | "%" -> Number (Float.rem (to_number a) (to_number b))
  | "**" -> Number (Float.pow (to_number a) (to_number b))
  (* the bits: both sides made 32-bit integers, the answer one too; a
   * shift's count is its low five bits; >>> fills with zeros, so its
   * answer is not negative *)
  | "&" -> of_int32 (Int32.logand (to_int32 a) (to_int32 b))
  | "|" -> of_int32 (Int32.logor (to_int32 a) (to_int32 b))
  | "^" -> of_int32 (Int32.logxor (to_int32 a) (to_int32 b))
  | "<<" -> of_int32 (Int32.shift_left (to_int32 a) (Int32.to_int (to_int32 b) land 31))
  | ">>" -> of_int32 (Int32.shift_right (to_int32 a) (Int32.to_int (to_int32 b) land 31))
  | ">>>" ->
      Number (Int64.to_float (Int64.logand (Int64.of_int32 (Int32.shift_right_logical (to_int32 a) (Int32.to_int (to_int32 b) land 31))) 0xFFFFFFFFL))
  | "<" | ">" | "<=" | ">=" -> (
      let cmp =
        match (to_primitive a, to_primitive b) with
        | String x, String y -> Some (compare x y)
        | x, y ->
            let x = to_number x and y = to_number y in
            if Float.is_nan x || Float.is_nan y then None else Some (compare x y)
      in
      match cmp with
      | None -> Bool false
      | Some c -> Bool (match op with "<" -> c < 0 | ">" -> c > 0 | "<=" -> c <= 0 | _ -> c >= 0))
  | "===" -> Bool (strict_equal a b)
  | "!==" -> Bool (not (strict_equal a b))
  | "==" -> Bool (loose_equal a b)
  | "!=" -> Bool (not (loose_equal a b))
  | _ -> throw "SyntaxError" ("unknown operator " ^ op)

(* "x", "o.m": what a TypeError names *)
let rec describe (e : A.expr) : string =
  match e with
  | Name x -> x
  | This -> "this"
  | Member (o, x) -> describe o ^ "." ^ x
  | Index (o, _) -> describe o ^ "[...]"
  | Call (f, _) -> describe f ^ "(...)"
  | _ -> "expression"

(*****************************************************************************)
(* Expressions *)
(*****************************************************************************)

let tick (t : t) : unit =
  t.steps <- t.steps - 1;
  if t.steps < 0 then throw "RangeError" "the script ran too long (a loop that never ends?)"

let rec eval_expr (t : t) (s : scope) (this : value) (e : A.expr) : value =
  match e with
  | Number f -> Number f
  | String x -> String x
  | Bool b -> Bool b
  | Null -> Null
  | This -> this
  | Name x -> (
      match lookup s x with Some b -> b.value | None -> throw "ReferenceError" (x ^ " is not defined"))
  | Array es -> Object (new_array (List.map (eval_expr t s this) es))
  | Object kvs ->
      let o = new_object () in
      List.iter (fun (k, v) -> set_own o k (eval_expr t s this v)) kvs;
      Object o
  | Function f -> closure s this f
  | Unary (op, x) -> (
      match op with
      (* typeof of an undeclared name is "undefined", not an error *)
      | "typeof" -> (
          match x with
          | Name n when lookup s n = None -> String "undefined"
          | _ -> String (typeof (eval_expr t s this x)))
      | "!" -> Bool (not (truthy (eval_expr t s this x)))
      | "-" -> Number (-.to_number (eval_expr t s this x))
      | "~" -> of_int32 (Int32.lognot (to_int32 (eval_expr t s this x)))
      | "void" -> ignore (eval_expr t s this x); Undefined
      (* delete o.k: the property gone from the object itself *)
      | "delete" -> (
          let remove o k = match o with Object o -> o.props <- List.filter (fun (k', _) -> k' <> k) o.props | _ -> () in
          match x with
          | Member (o, k) -> remove (eval_expr t s this o) k; Bool true
          | Index (o, k) -> let o = eval_expr t s this o in remove o (key_of (eval_expr t s this k)); Bool true
          | _ -> Bool true)
      | _ -> Number (to_number (eval_expr t s this x)))
  | Update (op, prefix, target) ->
      let old = to_number (eval_expr t s this target) in
      let now = if op = "++" then old +. 1. else old -. 1. in
      assign t s this target (Number now);
      Number (if prefix then now else old)
  | Binary ("instanceof", a, f) ->
      let a = eval_expr t s this a in
      Bool (instance_of t a (eval_expr t s this f))
  | Binary ("in", k, o) -> (
      let k = key_of (eval_expr t s this k) in
      match eval_expr t s this o with
      | Object o -> Bool (has t o k)
      | v -> throw "TypeError" (Printf.sprintf "Cannot use 'in' operator to search for '%s' in %s" k (display v)))
  | Comma (a, b) -> ignore (eval_expr t s this a); eval_expr t s this b
  | Binary (op, a, b) ->
      let a = eval_expr t s this a in
      arithmetic op a (eval_expr t s this b)
  | Regex (source, flags) -> (
      match Js_regexp.compile source flags with
      | Ok re -> Js_builtins.regexp_value (protos t).regexps re
      | Error why -> throw "SyntaxError" ("Invalid regular expression: /" ^ source ^ "/: " ^ why))
  (* new F(a): an object whose prototype is F.prototype, F called with it
   * as this; what F returns instead if it is an object (a host
   * constructor's: Date, URL) *)
  | New (f, args) ->
      let fn = eval_expr t s this f in
      let args = List.map (eval_expr t s this) args in
      (match fn with Object { kind = Closure _ | Host_function _; _ } -> () | _ -> throw "TypeError" (describe f ^ " is not a constructor"));
      let o = new_object () in
      (match get t fn "prototype" with Object p -> o.proto <- Some p | _ -> ());
      (match call_value t fn ~this:(Object o) args with Object _ as r -> r | _ -> Object o)
  | Logical ("&&", a, b) -> let v = eval_expr t s this a in if truthy v then eval_expr t s this b else v
  | Logical ("??", a, b) -> ( match eval_expr t s this a with Undefined | Null -> eval_expr t s this b | v -> v)
  | Logical (_, a, b) -> let v = eval_expr t s this a in if truthy v then v else eval_expr t s this b
  | Assign ("=", target, v) ->
      let v = eval_expr t s this v in
      assign t s this target v;
      v
  | Assign (op, target, v) ->
      let old = eval_expr t s this target in
      (* "+=" is "+", ">>>=" is ">>>" *)
      let v = arithmetic (String.sub op 0 (String.length op - 1)) old (eval_expr t s this v) in
      assign t s this target v;
      v
  | Conditional (c, a, b) -> if truthy (eval_expr t s this c) then eval_expr t s this a else eval_expr t s this b
  | Member (o, k) -> get t (eval_expr t s this o) k
  | Index (o, k) ->
      let o = eval_expr t s this o in
      get t o (key_of (eval_expr t s this k))
  | Call (f, args) ->
      (* a method call: this is the object the function was read from *)
      let fn, self =
        match f with
        | Member (o, k) -> let o = eval_expr t s this o in (get t o k, o)
        | Index (o, k) -> let o = eval_expr t s this o in (get t o (key_of (eval_expr t s this k)), o)
        | _ -> (eval_expr t s this f, Undefined)
      in
      let args = List.map (eval_expr t s this) args in
      (match fn with Object { kind = Closure _ | Host_function _; _ } -> () | _ -> throw "TypeError" (describe f ^ " is not a function"));
      call_value t fn ~this:self args

and closure (s : scope) (this : value) (f : A.func) : value =
  let c = { func = f; scope = s; this = (if f.arrow then Some this else None) } in
  Object { (new_object ()) with kind = Closure c }

and assign (t : t) (s : scope) (this : value) (target : A.expr) (v : value) : unit =
  match target with
  | Name x -> (
      match lookup s x with
      | Some { constant = true; _ } -> throw "TypeError" "Assignment to constant variable."
      | Some b -> b.value <- v
      | None -> throw "ReferenceError" (x ^ " is not defined"))
  | Member (o, k) -> set (eval_expr t s this o) k v
  | Index (o, k) ->
      let o = eval_expr t s this o in
      set o (key_of (eval_expr t s this k)) v
  | _ -> throw "SyntaxError" "Invalid assignment target"

and call_value (t : t) (fn : value) ~(this : value) (args : value list) : value =
  match fn with
  | Object { kind = Host_function (_, f); _ } -> f ~this args
  | Object { kind = Closure c; _ } ->
      if t.depth >= max_depth then throw "RangeError" "Maximum call stack size exceeded";
      t.depth <- t.depth + 1;
      let frame = new_scope c.scope in
      (* arguments, the var's hoisted, then the parameters *)
      if not c.func.arrow then declare frame "arguments" ~constant:false (Object (new_array args));
      hoist frame c.func.body;
      List.iteri (fun i x -> declare frame x ~constant:false (Option.value (List.nth_opt args i) ~default:Undefined)) c.func.params;
      let this = match c.this with Some captured -> captured | None -> this in
      let line = t.line in
      (* the caller's line back when the call returns; not when it
       * throws, so that the error keeps the line it was thrown on *)
      (match exec_block t frame this c.func.body with
      | result ->
          t.depth <- t.depth - 1;
          t.line <- line;
          (match result with Return v -> v | _ -> Undefined)
      | exception e ->
          t.depth <- t.depth - 1;
          raise e)
  | _ -> throw "TypeError" (display fn ^ " is not a function")

(*****************************************************************************)
(* Statements *)
(*****************************************************************************)

(* var's names, declared (undefined) at the top of their function: a
 * var in a block or a loop is the function's -- hoisting, ES5's, what
 * let (block-scoped) came to fix *)
and hoist (s : scope) (body : A.stmt list) : unit =
  let rec names (st : A.stmt) : string list =
    match st.stmt with
    | Let (Var_kind, decls) -> List.map fst decls
    | If (_, a, b) -> names a @ (match b with Some b -> names b | None -> [])
    | While (_, b) -> names b
    | For (init, _, _, b) -> (match init with Some i -> names i | None -> []) @ names b
    | For_of (Var_kind, x, _, b) | For_in (Declared (Var_kind, x), _, b) -> x :: names b
    | For_of (_, _, _, b) | For_in (_, _, b) | Do_while (b, _) | Labeled (_, b) -> names b
    | Switch (_, cases) -> List.concat_map (fun (_, body) -> List.concat_map names body) cases
    | Try (a, handler, finally) ->
        List.concat_map names a
        @ (match handler with Some (_, h) -> List.concat_map names h | None -> [])
        @ (match finally with Some f -> List.concat_map names f | None -> [])
    | Block b -> List.concat_map names b
    | _ -> []
  in
  List.iter (fun x -> if not (Hashtbl.mem s.vars x) then declare s x ~constant:false Undefined) (List.concat_map names body)

(* a block's statements in [s]: its function declarations first *)
and exec_block (t : t) (s : scope) (this : value) (body : A.stmt list) : outcome =
  List.iter
    (fun (st : A.stmt) -> match st.stmt with Function_decl f -> declare s (Option.get f.name) ~constant:false (closure s this f) | _ -> ())
    body;
  let rec go (body : A.stmt list) =
    match body with
    | [] -> Normal
    | st :: rest -> ( match exec t s this st with Normal -> go rest | leave -> leave)
  in
  go body

(* [labels]: those of the statement, if it is a loop: "continue l" with
 * one of them goes on with it *)
and exec ?(labels = []) (t : t) (s : scope) (this : value) (st : A.stmt) : outcome =
  t.line <- st.line;
  tick t;
  let eval = eval_expr t s this in
  (* a loop's body ran: whether the loop goes on (None), or how it ends *)
  let after (o : outcome) : outcome option =
    match o with
    | Normal | Continue None -> None
    | Continue (Some l) when List.mem l labels -> None
    | Break None -> Some Normal
    | leave -> Some leave
  in
  match st.stmt with
  | Expr e -> ignore (eval e); Normal
  | Let (Var_kind, decls) ->
      (* the function's binding, hoisted: set, not declared again *)
      List.iter
        (fun (x, init) ->
          match (lookup s x, init) with
          | Some b, Some e -> b.value <- eval e
          | Some _, None -> ()
          | None, init -> declare s x ~constant:false (match init with Some e -> eval e | None -> Undefined))
        decls;
      Normal
  | Let (kind, decls) ->
      List.iter (fun (x, init) -> declare s x ~constant:(kind = Const_kind) (match init with Some e -> eval e | None -> Undefined)) decls;
      Normal
  | Function_decl _ -> Normal (* defined by its block, first *)
  | Return e -> Return (match e with Some e -> eval e | None -> Undefined)
  | If (c, a, b) -> (
      if truthy (eval c) then exec t (new_scope s) this a
      else match b with Some b -> exec t (new_scope s) this b | None -> Normal)
  | While (c, body) ->
      let rec loop () =
        if truthy (eval c) then match after (exec t (new_scope s) this body) with None -> loop () | Some o -> o else Normal
      in
      loop ()
  | Do_while (body, c) ->
      let rec loop () =
        match after (exec t (new_scope s) this body) with None -> if truthy (eval c) then loop () else Normal | Some o -> o
      in
      loop ()
  | For (init, test, update, body) ->
      let first = new_scope s in
      Option.iter (fun i -> ignore (exec t first this i)) init;
      (* each iteration in a copy of the last: its own i *)
      let rec loop (it : scope) =
        let ok = match test with Some c -> truthy (eval_expr t it this c) | None -> true in
        if not ok then Normal
        else
          match after (exec t (new_scope it) this body) with
          | Some o -> o
          | None ->
              let next = copy_scope it in
              Option.iter (fun u -> ignore (eval_expr t next this u)) update;
              loop next
      in
      loop first
  | For_of (kind, x, xs, body) ->
      let items =
        match eval xs with
        | Object ({ kind = Array _; _ } as o) -> array_items o
        | String str -> List.init (String.length str) (fun i -> String (String.make 1 str.[i]))
        | v -> throw "TypeError" (display v ^ " is not iterable")
      in
      let rec loop items =
        match items with
        | [] -> Normal
        | v :: rest -> (
            let it = new_scope s in
            declare it x ~constant:(kind = Const_kind) v;
            match after (exec t it this body) with None -> loop rest | Some o -> o)
      in
      loop items
  (* for (k in o): each key, a string; a var's, or a name's or a
   * property's, set before each turn *)
  | For_in (target, o, body) ->
      let rec loop keys =
        match keys with
        | [] -> Normal
        | k :: rest -> (
            let it = new_scope s in
            (match target with
            | Declared (Var_kind, x) -> ( match lookup s x with Some b -> b.value <- String k | None -> declare s x ~constant:false (String k))
            | Declared (kind, x) -> declare it x ~constant:(kind = Const_kind) (String k)
            | Target e -> assign t s this e (String k));
            match after (exec t it this body) with None -> loop rest | Some o -> o)
      in
      loop (enumerable_keys (eval o))
  (* the first case that is === the value, and from there every
   * statement to a break, the next cases' too; no case: the default *)
  | Switch (e, cases) -> (
      let v = eval e in
      let sc = new_scope s in
      let rec from (cases : (A.expr option * A.stmt list) list) =
        match cases with
        | [] -> None
        | (Some test, _) :: rest when not (strict_equal v (eval_expr t sc this test)) -> from rest
        | (None, _) :: rest -> from rest
        | found -> Some found
      in
      let rec default (cases : (A.expr option * A.stmt list) list) =
        match cases with [] -> [] | (None, _) :: _ as found -> found | _ :: rest -> default rest
      in
      let run = match from cases with Some found -> found | None -> default cases in
      match exec_block t sc this (List.concat_map snd run) with Break None -> Normal | o -> o)
  | Labeled (l, body) -> ( match exec ~labels:(l :: labels) t s this body with Break (Some l') when l' = l -> Normal | o -> o)
  | Break l -> Break l
  | Continue l -> Continue l
  | Throw e -> raise (Throw (eval e))
  (* finally runs however the rest ended, and its own ending wins if
   * it is not the normal one *)
  | Try (body, handler, finally) ->
      let finish (ended : unit -> outcome) : outcome =
        match finally with
        | None -> ended ()
        | Some f -> (
            let run () = exec_block t (new_scope s) this f in
            match ended () with
            | o -> ( match run () with Normal -> o | leave -> leave)
            | exception e -> ( match run () with Normal -> raise e | leave -> leave))
      in
      finish (fun () ->
          match exec_block t (new_scope s) this body with
          | outcome -> outcome
          | exception Throw v when handler <> None ->
              let x, h = Option.get handler in
              let scope = new_scope s in
              Option.iter (fun x -> declare scope x ~constant:false v) x;
              exec_block t scope this h)
  | Block body -> exec_block t (new_scope s) this body
  | Empty -> Normal

(*****************************************************************************)
(* Entry points *)
(*****************************************************************************)

let default_budget = 10_000_000

let create ?(log = fun _ -> ()) ?(seed = 1) ?now () : t =
  let globals = { vars = Hashtbl.create 64; parent = None } in
  let t = { globals; protos = None; line = 0; steps = default_budget; budget = default_budget; depth = 0 } in
  let call f ~this args = call_value t f ~this args in
  t.protos <- Some (Js_builtins.install ~call ~log ~seed ?now (fun x v -> declare globals x ~constant:false v));
  t

(* the error a console shows: an error object as "Name: message", any
 * other value thrown as "Uncaught " and it *)
let error_of (t : t) (v : value) : error =
  let message =
    match v with
    | Object o -> (
        match (get_own o "name", get_own o "message") with
        | Some (String n), Some (String m) -> n ^ ": " ^ m
        | _ -> "Uncaught " ^ display v)
    | v -> "Uncaught " ^ display v
  in
  { line = t.line; message }

(* a run or a call, its budget renewed, its throws caught *)
let guarded (t : t) (f : unit -> value) : (value, error) result =
  t.steps <- t.budget;
  t.depth <- 0;
  match f () with
  | v -> Ok v
  | exception Throw v -> Error (error_of t v)
  | exception Stack_overflow -> Error { line = t.line; message = "RangeError: Maximum call stack size exceeded" }

let run (t : t) (program : A.program) : (value, error) result =
  guarded t (fun () ->
      (* the value of the last expression statement: a console's echo *)
      let last = ref Undefined in
      hoist t.globals program;
      List.iter
        (fun (st : A.stmt) -> match st.stmt with Function_decl f -> declare t.globals (Option.get f.name) ~constant:false (closure t.globals Undefined f) | _ -> ())
        program;
      List.iter
        (fun (st : A.stmt) ->
          match st.stmt with
          | Expr e ->
              t.line <- st.line;
              tick t;
              last := eval_expr t t.globals Undefined e
          | _ -> (
              match exec t t.globals Undefined st with
              | Normal -> ()
              | Return _ -> throw "SyntaxError" "Illegal return statement"
              | Break _ | Continue _ -> throw "SyntaxError" "Illegal break or continue statement"))
        program;
      !last)

let eval (t : t) (text : string) : (value, error) result =
  match Js_parse.parse text with
  | Ok program -> run t program
  | Error e -> Error { line = e.line; message = "SyntaxError: " ^ e.message }

let call (t : t) (f : value) ~(this : value) (args : value list) : (value, error) result =
  guarded t (fun () -> call_value t f ~this args)

let global (t : t) (x : string) : value option = Option.map (fun b -> b.value) (Hashtbl.find_opt t.globals.vars x)
let define (t : t) (x : string) (v : value) : unit = declare t.globals x ~constant:false v
let set_budget (t : t) (steps : int) : unit = t.budget <- steps
