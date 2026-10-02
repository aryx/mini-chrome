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
  mutable promises : Js_promise.t option; (* the same: the jobs waiting *)
  mutable line : int; (* of the statement running: an error's *)
  mutable steps : int; (* left in this run's budget *)
  mutable budget : int;
  mutable depth : int; (* of the calls *)
  mutable generators : generating list; (* those whose body is running, the innermost first *)
}

(* a generator between its body and who calls next(): what the body
 * gave last, what it is given back *)
and generating = { mutable out : out; mutable sent : sent }
and out = Yielded of value | Ended of value | Failed of value
and sent = Sent of value | Thrown of value | Returned of value

type error = { line : int; message : string }

(* how a statement ended *)
type outcome = Normal | Return of value | Break of string option | Continue of string option

let max_depth = 2_000

(* generator.return(v): the body left from its yield, its finally
 * blocks run on the way *)
exception Generator_return of value

(* a?.b with a null or undefined: the chain it is in ends, undefined *)
exception Short_circuit

(* get k() and set k(v) of the same k are one property of [o]: the
 * getter or the setter given, the other kept *)
let define_accessor (o : obj) (k : string) ~(getter : value option) ~(setter : value option) : unit =
  let g, st = match get_own o k with Some (Object { kind = Accessor (g, st); _ }) -> (g, st) | _ -> (Undefined, Undefined) in
  set_own o k (Object { (new_object ()) with kind = Accessor (Option.value getter ~default:g, Option.value setter ~default:st) })

(*****************************************************************************)
(* Scopes *)
(*****************************************************************************)

let new_scope (parent : scope) : scope = { vars = Hashtbl.create 8; parent = Some parent; subject = None; in_with = parent.in_with }

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

(* an object's properties and the operators are Js_props' and
 * Js_operators'; here with the interpreter's prototypes *)
let has (t : t) = Js_props.has (protos t)
let instance_of (t : t) = Js_props.instance_of (protos t)
let key_of = Js_props.key_of
let enumerable_keys = Js_props.enumerable_keys

open Js_operators

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
      match if s.in_with then with_subject t s x else None with
      | Some o -> get t o x
      | None -> ( match lookup s x with Some b -> b.value | None -> throw "ReferenceError" (x ^ " is not defined")))
  | Array es -> Object (new_array (eval_list t s this es))
  | Spread _ -> throw "SyntaxError" "... is for an array's items or a call's arguments"
  | Object props ->
      let o = new_object () in
      let key (k : A.key) = match k with Key k -> k | Computed e -> key_of (eval_expr t s this e) in
      let accessor = define_accessor o in
      List.iter
        (fun (pr : A.property) ->
          match pr with
          | Prop (k, v) -> set_own o (key k) (eval_expr t s this v)
          | Getter (k, f) -> accessor (key k) ~getter:(Some (closure s this f)) ~setter:None
          | Setter (k, f) -> accessor (key k) ~getter:None ~setter:(Some (closure s this f))
          (* ...o: its own properties, copied *)
          | Spread_prop e -> (
              match eval_expr t s this e with
              | Object ({ kind = Array a; _ } as src) ->
                  Array.iteri (fun i v -> if i < a.length then set_own o (string_of_int i) v) a.elements;
                  List.iter (fun k -> set_own o k (get t (Object src) k)) (keys src)
              | Object src -> List.iter (fun k -> set_own o k (get t (Object src) k)) (keys src)
              | String str -> String.iteri (fun i c -> set_own o (string_of_int i) (String (String.make 1 c))) str
              | _ -> ()))
        props;
      Object o
  | Function f -> closure s this f
  | Class c -> make_class t s this c
  (* super(a): the parent's constructor, on this object; then this
   * class's fields. A host constructor (Error) gives an object of its
   * own: what it holds is this object's *)
  | Super_call args ->
      let hidden x = match lookup s x with Some b -> b.value | None -> Undefined in
      (match (call_value t (hidden "%super") ~this (eval_list t s this args), this) with
      | Object made, Object self when made != self -> List.iter (fun k -> set_own self k (Option.get (get_own made k))) (keys made)
      | _ -> ());
      ignore (call_value t (hidden "%init") ~this []);
      Undefined
  | Super_member k -> (
      match lookup s "%home" with
      | Some { value = Object { proto = Some parent; _ }; _ } -> get t (Object parent) k
      | _ -> Undefined)
  | Opt e -> ( match eval_expr t s this e with Undefined | Null -> raise Short_circuit | v -> v)
  | Optional e -> ( try eval_expr t s this e with Short_circuit -> Undefined)
  | Await e -> Js_promise.await (Option.get t.promises) (eval_expr t s this e)
  (* tag`a${x}b`: tag(["a", "b"], x), the strings' array with itself
   * as its raw (the escapes are read already: an approximation) *)
  | Tagged (tag, strings, es) ->
      let fn, self = match tag with Member (o, k) -> let o = eval_expr t s this o in (get t o k, o) | tag -> (eval_expr t s this tag, Undefined) in
      let parts = new_array (List.map (fun x -> String x) strings) in
      set_own parts "raw" (Object parts);
      call_value t fn ~this:self (Object parts :: List.map (eval_expr t s this) es)
  | Yield (false, e) -> yield t (match e with Some e -> eval_expr t s this e | None -> Undefined)
  (* yield* xs: each of xs yielded *)
  | Yield (true, e) ->
      iterate t (match e with Some e -> eval_expr t s this e | None -> Undefined) (fun v -> ignore (yield t v); true);
      Undefined
  (* a ||= b: assigned only if a is falsy; &&=, ??= the same of && and ?? *)
  | Assign ((("&&=" | "||=" | "??=") as op), target, v) ->
      let old = eval_expr t s this target in
      let wanted = match op with "&&=" -> truthy old | "||=" -> not (truthy old) | _ -> old = Undefined || old = Null in
      if wanted then (let v = eval_expr t s this v in assign t s this target v; v) else old
  | Unary (op, x) -> (
      match op with
      (* typeof of an undeclared name is "undefined", not an error *)
      | "typeof" -> (
          match x with
          | Name n when lookup s n = None && not (s.in_with && with_subject t s n <> None) -> String "undefined"
          | _ -> String (typeof (eval_expr t s this x)))
      | "!" -> Bool (not (truthy (eval_expr t s this x)))
      | "-" -> Number (-.to_number (eval_expr t s this x))
      | "~" -> of_int32 (Int32.lognot (to_int32 (eval_expr t s this x)))
      | "void" -> ignore (eval_expr t s this x); Undefined
      (* delete o.k: the property gone from the object itself *)
      | "delete" -> (
          let rec remove o k =
            match o with
            | Object { kind = Proxy (tg, h); _ } -> (
                match trap t h "deleteProperty" with Some f -> ignore (call_value t f ~this:(Object h) [ Object tg; String k ]) | None -> remove (Object tg) k)
            | Object o -> o.props <- List.filter (fun (k', _) -> k' <> k) o.props
            | _ -> ()
          in
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
      | Object _ as o -> Bool (has_property t o k)
      | v -> throw "TypeError" (Printf.sprintf "Cannot use 'in' operator to search for '%s' in %s" k (display v)))
  | Comma (a, b) -> ignore (eval_expr t s this a); eval_expr t s this b
  (* `a${x}b`: the strings and the values, as strings, one after the other *)
  | Template (strings, es) ->
      let values = List.map (fun e -> to_string (eval_expr t s this e)) es in
      let rec weave strings values = match (strings, values) with str :: rest, v :: vs -> str :: v :: weave rest vs | strings, _ -> strings in
      String (String.concat "" (weave strings values))
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
      let args = eval_list t s this args in
      (match fn with Object { kind = Closure _ | Host_function _ | Proxy _; _ } -> () | _ -> throw "TypeError" (describe f ^ " is not a constructor"));
      let o = new_object () in
      (match get t fn "prototype" with Object p -> o.proto <- Some p | _ -> ());
      (match call_value t fn ~this:(Object o) args with Object _ as r -> r | _ -> Object o)
  | Logical ("&&", a, b) -> let v = eval_expr t s this a in if truthy v then eval_expr t s this b else v
  | Logical ("??", a, b) -> ( match eval_expr t s this a with Undefined | Null -> eval_expr t s this b | v -> v)
  | Logical (_, a, b) -> let v = eval_expr t s this a in if truthy v then v else eval_expr t s this b
  (* o.k = v, o[k] = v: o (and k) first, then v, as written --
   * "(b = {...}).x = b.y", in a minified jQuery, needs b made before
   * b.y is read *)
  | Assign ("=", Member (o, k), v) ->
      let o = eval_expr t s this o in
      let v = eval_expr t s this v in
      put t o k v;
      v
  | Assign ("=", Index (o, k), v) ->
      let o = eval_expr t s this o in
      let k = key_of (eval_expr t s this k) in
      let v = eval_expr t s this v in
      put t o k v;
      v
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
        (* o.m?.(): the method, if there is one, still on o *)
        | Opt (Member (o, k)) -> (
            let o = eval_expr t s this o in
            match get t o k with Undefined | Null -> raise Short_circuit | fn -> (fn, o))
        (* super.m(): the parent's m, on this *)
        | Super_member _ -> (eval_expr t s this f, this)
        | _ -> (eval_expr t s this f, Undefined)
      in
      let args = eval_list t s this args in
      (match fn with Object { kind = Closure _ | Host_function _ | Proxy _; _ } -> () | _ -> throw "TypeError" (describe f ^ " is not a function"));
      call_value t fn ~this:self args

(* class A extends B { ... }: a constructor function whose prototype
 * has the methods, and B's prototype behind it; the class's static
 * members on the function itself, B behind it. Its constructor and
 * methods are made in a scope that knows the parent (%super), the
 * prototype (%home: super.m is looked for behind it) and how to set
 * the fields of a new object (%init) *)
and make_class (t : t) (s : scope) (this : value) (c : A.class_) : value =
  let cs = new_scope s in
  let proto = new_object () in
  let parent = Option.map (eval_expr t s this) c.parent in
  (match parent with
  | None | Some Null -> ()
  | Some (Object { kind = Closure _ | Host_function _; _ } as pv) -> ( match get t pv "prototype" with Object pp -> proto.proto <- Some pp | _ -> ())
  | Some v -> throw "TypeError" (Printf.sprintf "Class extends value %s is not a constructor or null" (display v)));
  let key (k : A.key) = match k with Key k -> k | Computed e -> key_of (eval_expr t cs this e) in
  let fields = List.filter_map (fun (m : A.member) -> match m.what with Field e when not m.static -> Some (key m.key, e) | _ -> None) c.members in
  let init =
    host_function "fields" (fun ~this _ ->
        List.iter (fun (k, e) -> put t this k (match e with Some e -> eval_expr t cs this e | None -> Undefined)) fields;
        Undefined)
  in
  declare cs "%super" ~constant:true (Option.value parent ~default:Undefined);
  declare cs "%home" ~constant:true (Object proto);
  declare cs "%init" ~constant:true init;
  let stmt e : A.stmt = { line = t.line; stmt = Expr e } in
  (* its fields first (a class of its own), or by super() (one that
   * extends); with no constructor written: the parent's, called with
   * what it was given *)
  let ctor : A.func =
    match (c.ctor, c.parent) with
    | Some f, Some _ -> f
    | Some f, None -> { f with body = stmt (Call (Member (Name "%init", "call"), [ This ])) :: f.body }
    | None, None -> { name = c.class_name; params = []; rest = None; body = [ stmt (Call (Member (Name "%init", "call"), [ This ])) ]; arrow = false; generator = false; async = false }
    | None, Some _ -> { name = c.class_name; params = []; rest = Some (Bind "args"); body = [ stmt (Super_call [ Spread (Name "args") ]) ]; arrow = false; generator = false; async = false }
  in
  let made = closure cs this { ctor with name = c.class_name } in
  let f = match made with Object f -> f | _ -> assert false in
  set_own f "prototype" (Object proto);
  set_own proto "constructor" made;
  (match parent with Some (Object pc) -> f.proto <- Some pc | _ -> ());
  Option.iter (fun name -> declare cs name ~constant:true made) c.class_name;
  List.iter
    (fun (m : A.member) ->
      let target = if m.static then f else proto in
      match m.what with
      | Method fn -> set_own target (key m.key) (closure cs this fn)
      | Get fn -> define_accessor target (key m.key) ~getter:(Some (closure cs this fn)) ~setter:None
      | Set fn -> define_accessor target (key m.key) ~getter:None ~setter:(Some (closure cs this fn))
      | Field e when m.static -> set_own f (key m.key) (match e with Some e -> eval_expr t cs made e | None -> Undefined)
      | Field _ -> ()
      | Static_block body -> ignore (exec_block t (new_scope cs) made body))
    c.members;
  made

(* an array's items or a call's arguments: each one's value, a ...xs
 * each of xs' *)
and eval_list (t : t) (s : scope) (this : value) (es : A.expr list) : value list =
  List.concat_map (fun (e : A.expr) -> match e with Spread x -> items_of t (eval_expr t s this x) | e -> [ eval_expr t s this e ]) es

(* what a for-of, a ...spread or an array pattern goes through, one
 * item at a time, [f] saying whether to go on: an array's items, a
 * string's characters; else the iteration protocol (ES2015) -- the
 * object's [Symbol.iterator]() gives an iterator, whose next() gives
 * { value, done } each time; stopped early, its return() is called *)
and iterate (t : t) (v : value) (f : value -> bool) : unit =
  let rec each (l : value list) = match l with x :: rest -> if f x then each rest | [] -> () in
  match v with
  | Object ({ kind = Array _ | Proxy _; _ } as o) when (match (Js_value.target o).kind with Array _ -> true | _ -> false) -> each (array_items o)
  | String str -> each (List.init (String.length str) (fun i -> String (String.make 1 str.[i])))
  | Object _ -> (
      match get t v "@@iterator" with
      | Object { kind = Closure _ | Host_function _; _ } as make -> (
          match call_value t make ~this:v [] with
          (* an array given at once (a Map's entries here) *)
          | Object { kind = Array _; _ } as items -> iterate t items f
          | it ->
              let next = get t it "next" in
              let rec go () =
                let r = call_value t next ~this:it [] in
                if not (truthy (get t r "done")) then
                  if f (get t r "value") then go ()
                  else match get t it "return" with Object { kind = Closure _ | Host_function _; _ } as stop -> ignore (call_value t stop ~this:it []) | _ -> ()
              in
              go ())
      | _ -> throw "TypeError" (display v ^ " is not iterable"))
  | v -> throw "TypeError" (display v ^ " is not iterable")

and items_of (t : t) (v : value) : value list =
  let items = ref [] in
  iterate t v (fun x -> items := x :: !items; true);
  List.rev !items

(* yield v, in a generator's body: v given to who called next(), the
 * body stopped until the next one; what that next() was given *)
and yield (t : t) (v : value) : value =
  match t.generators with
  | [] -> throw "SyntaxError" "yield is only valid in generator functions"
  | g :: _ -> (
      g.out <- Yielded v;
      Js_coroutine.suspend ();
      match g.sent with
      | Sent v -> v
      | Thrown e -> raise (Throw e)
      | Returned v -> raise (Generator_return v))

(* a generator's call: its body a coroutine not started yet, and the
 * iterator that runs it a yield at a time -- next(v), return(v),
 * throw(e), and itself as its own [Symbol.iterator]() *)
and generator (t : t) (body : unit -> value) : value =
  let g = { out = Yielded Undefined; sent = Sent Undefined } in
  let ended = ref false and started = ref false in
  let run () =
    g.out <-
      (match body () with
      | v -> Ended v
      | exception Generator_return v -> Ended v
      | exception Throw e -> Failed e
      | exception Stack_overflow -> Failed (error "RangeError" "Maximum call stack size exceeded"));
    ended := true
  in
  let co = Js_coroutine.create run in
  let result v finished =
    let o = new_object () in
    set_own o "value" v;
    set_own o "done" (Bool finished);
    Object o
  in
  let resume (what : sent) : value =
    if !ended then (match what with Thrown e -> raise (Throw e) | Returned v -> result v true | Sent _ -> result Undefined true)
    else if (not !started) && (match what with Sent _ -> false | _ -> true) then (
      (* stopped before it began: nothing of its body runs *)
      ended := true;
      match what with Thrown e -> raise (Throw e) | Returned v -> result v true | Sent _ -> result Undefined true)
    else (
      started := true;
      g.sent <- what;
      t.generators <- g :: t.generators;
      Js_coroutine.resume co;
      t.generators <- List.tl t.generators;
      match g.out with Yielded v -> result v false | Ended v -> result v true | Failed e -> raise (Throw e))
  in
  let o = new_object () in
  let self = Object o in
  let arg args = match args with v :: _ -> v | [] -> Undefined in
  set_own o "next" (host_function "next" (fun ~this:_ args -> resume (Sent (arg args))));
  set_own o "return" (host_function "return" (fun ~this:_ args -> resume (Returned (arg args))));
  set_own o "throw" (host_function "throw" (fun ~this:_ args -> resume (Thrown (arg args))));
  set_own o "@@iterator" (host_function "[Symbol.iterator]" (fun ~this:_ _ -> self));
  self

(* o.k: the property, or what its getter gives *)
and get (t : t) (target : value) (k : string) : value =
  match target with
  (* a proxy: its handler's get(target, key, receiver), else the target's *)
  | Object { kind = Proxy (tg, h); _ } -> (
      match trap t h "get" with Some f -> call_value t f ~this:(Object h) [ Object tg; String k; target ] | None -> get t (Object tg) k)
  | _ -> (
      match Js_props.get (protos t) target k with
      | Object { kind = Accessor (getter, _); _ } -> if getter = Undefined then Undefined else call_value t getter ~this:target []
      | v -> v)

(* a handler's trap, if it has that one *)
and trap (t : t) (handler : obj) (name : string) : value option =
  match Js_props.get (protos t) (Object handler) name with Object { kind = Closure _ | Host_function _; _ } as f -> Some f | _ -> None

(* k in o: its own or its prototypes'; a proxy's has(target, key) *)
and has_property (t : t) (o : value) (k : string) : bool =
  match o with
  | Object { kind = Proxy (tg, h); _ } -> (
      match trap t h "has" with Some f -> truthy (call_value t f ~this:(Object h) [ Object tg; String k ]) | None -> has_property t (Object tg) k)
  | Object o -> has t o k
  | _ -> false

(* the object of the nearest with (o) { } around [s] that has [x], if
 * no frame nearer declares x *)
and with_subject (t : t) (s : scope) (x : string) : value option =
  if Hashtbl.mem s.vars x then None
  else
    match (s.subject, s.parent) with
    | Some o, _ when has_property t o x -> Some o
    | _, Some p when p.in_with -> with_subject t p x
    | _ -> None

(* o.k = v: the property set, or its setter called (an object's own, or
 * its prototypes': looked for only where there can be one) *)
and put (t : t) (target : value) (k : string) (v : value) : unit =
  match target with
  | Object { kind = Proxy (tg, h); _ } -> (
      match trap t h "set" with Some f -> ignore (call_value t f ~this:(Object h) [ Object tg; String k; v; target ]) | None -> put t (Object tg) k v)
  | Object { kind = Plain | Closure _; _ } -> (
      match Js_props.get (protos t) target k with
      | Object { kind = Accessor (_, setter); _ } -> if setter <> Undefined then ignore (call_value t setter ~this:target [ v ])
      | _ -> Js_props.set target k v)
  | _ -> Js_props.set target k v

(* a pattern's names bound to the parts of a value, each by [bind]: a
 * name to the value; { } to its properties, by key, and what is left;
 * [ ] to its items, in order, and those left. A part that is
 * undefined takes its default *)
and destructure (t : t) (s : scope) (this : value) (pt : A.pattern) (v : value) (bind : string -> value -> unit) : unit =
  let or_default (v : value) (default : A.expr option) = match (v, default) with Undefined, Some d -> eval_expr t s this d | v, _ -> v in
  match pt with
  | Bind x -> bind x v
  | Object_pattern (parts, rest) ->
      (match v with Undefined | Null -> throw "TypeError" (Printf.sprintf "Cannot destructure '%s' as it is %s." (display v) (to_string v)) | _ -> ());
      let taken =
        List.map
          (fun ((k : A.key), part, default) ->
            let k = match k with Key k -> k | Computed e -> key_of (eval_expr t s this e) in
            destructure t s this part (or_default (get t v k) default) bind;
            k)
          parts
      in
      Option.iter
        (fun r ->
          let o = new_object () in
          (match v with Object src -> List.iter (fun k -> if not (List.mem k taken) then set_own o k (get t v k)) (keys src) | _ -> ());
          destructure t s this r (Object o) bind)
        rest
  | Array_pattern (parts, rest) ->
      let rec go parts items =
        match parts with
        | [] -> Option.iter (fun r -> destructure t s this r (Object (new_array items)) bind) rest
        | part :: more ->
            let v, left = match items with v :: left -> (v, left) | [] -> (Undefined, []) in
            Option.iter (fun (pt, default) -> destructure t s this pt (or_default v default) bind) part;
            go more left
      in
      go parts (items_of t v)

and closure (s : scope) (this : value) (f : A.func) : value =
  let c = { func = f; scope = s; this = (if f.arrow then Some this else None) } in
  let proto = if f.async then match lookup s "%async" with Some { value = Object p; _ } -> Some p | _ -> None else None in
  Object { (new_object ()) with kind = Closure c; proto }

and assign (t : t) (s : scope) (this : value) (target : A.expr) (v : value) : unit =
  match target with
  | Name x when s.in_with && with_subject t s x <> None -> put t (Option.get (with_subject t s x)) x v
  | Name x -> (
      match lookup s x with
      | Some { constant = true; _ } -> throw "TypeError" "Assignment to constant variable."
      | Some b -> b.value <- v
      (* a name nobody declared, assigned to: a global made, as scripts
       * not in strict mode have always relied on (Wikipedia's "RLQ = ...").
       * Before: ReferenceError, strict mode's answer *)
      | None -> declare t.globals x ~constant:false v)
  | Member (o, k) -> put t (eval_expr t s this o) k v
  | Index (o, k) ->
      let o = eval_expr t s this o in
      put t o (key_of (eval_expr t s this k)) v
  (* [a, b] = v, ({ a, b: o.x } = v): the literal read as a pattern, each
   * part assigned to; "= d" after a part, its default *)
  | Array es ->
      let part (e : A.expr) (v : value) =
        match e with
        | Assign ("=", target, d) -> assign t s this target (if v = Undefined then eval_expr t s this d else v)
        | e -> assign t s this e v
      in
      let rec go es items =
        match (es, items) with
        | [], _ -> ()
        | [ A.Spread rest ], items -> assign t s this rest (Object (new_array items))
        | e :: more, v :: left -> part e v; go more left
        | e :: more, [] -> part e Undefined; go more []
      in
      go es (items_of t v)
  | Object props ->
      List.iter
        (fun (pr : A.property) ->
          match pr with
          | Prop (k, target) -> (
              let k = match k with Key k -> k | Computed e -> key_of (eval_expr t s this e) in
              match (target, get t v k) with
              | Assign ("=", target, d), Undefined -> assign t s this target (eval_expr t s this d)
              | Assign ("=", target, _), pv | target, pv -> assign t s this target pv)
          | _ -> throw "SyntaxError" "Invalid assignment target")
        props
  | _ -> throw "SyntaxError" "Invalid assignment target"

and call_value (t : t) (fn : value) ~(this : value) (args : value list) : value =
  match fn with
  | Object { kind = Host_function (_, f); _ } -> f ~this args
  (* a proxy of a function: its handler's apply(target, this, arguments) *)
  | Object { kind = Proxy (tg, h); _ } -> (
      match trap t h "apply" with Some f -> call_value t f ~this:(Object h) [ Object tg; this; Object (new_array args) ] | None -> call_value t (Object tg) ~this args)
  | Object { kind = Closure c; _ } ->
      if t.depth >= max_depth then throw "RangeError" "Maximum call stack size exceeded";
      t.depth <- t.depth + 1;
      let frame = new_scope c.scope in
      (* arguments, the var's hoisted, then the parameters *)
      if not c.func.arrow then declare frame "arguments" ~constant:false (Object (new_array args));
      (* a function expression's own name, in its body (var f =
       * function again(n) { ... again(n - 1) }), unless the name is
       * already somebody's *)
      (match c.func.name with Some n when lookup c.scope n = None -> declare frame n ~constant:false fn | _ -> ());
      hoist frame c.func.body;
      let bind x v = declare frame x ~constant:false v in
      let rec params (ps : (A.pattern * A.expr option) list) (args : value list) =
        match ps with
        | [] -> Option.iter (fun r -> destructure t frame this r (Object (new_array args)) bind) c.func.rest
        | (pt, default) :: more ->
            let v, left = match args with v :: left -> (v, left) | [] -> (Undefined, []) in
            (* a default is read in the call's frame: it sees the parameters before it *)
            let v = match (v, default) with Undefined, Some d -> eval_expr t frame this d | v, _ -> v in
            destructure t frame this pt v bind;
            params more left
      in
      params c.func.params args;
      let this = match c.this with Some captured -> captured | None -> this in
      let line = t.line in
      (* the caller's line back when the call returns; not when it
       * throws, so that the error keeps the line it was thrown on *)
      let body () = match exec_block t frame this c.func.body with Return v -> v | _ -> Undefined in
      (* an async function: its body a coroutine, run to its first
       * await; the call gives its promise *)
      (match if c.func.generator then generator t body else if c.func.async then Js_promise.async (Option.get t.promises) body else body () with
      | result ->
          t.depth <- t.depth - 1;
          t.line <- line;
          result
      | exception e ->
          t.depth <- t.depth - 1;
          raise e)
  | _ -> throw "TypeError" (display fn ^ " is not a function")

(*****************************************************************************)
(* Statements *)
(*****************************************************************************)

(* the names a pattern binds *)
and pattern_names (pt : A.pattern) : string list =
  match pt with
  | Bind x -> [ x ]
  | Object_pattern (parts, rest) -> List.concat_map (fun (_, pt, _) -> pattern_names pt) parts @ (match rest with Some r -> pattern_names r | None -> [])
  | Array_pattern (parts, rest) ->
      List.concat_map (fun part -> match part with Some (pt, _) -> pattern_names pt | None -> []) parts @ (match rest with Some r -> pattern_names r | None -> [])

(* var's names, declared (undefined) at the top of their function: a
 * var in a block or a loop is the function's -- hoisting, ES5's, what
 * let (block-scoped) came to fix *)
and hoist (s : scope) (body : A.stmt list) : unit =
  let rec names (st : A.stmt) : string list =
    match st.stmt with
    | Let (Var_kind, decls) -> List.concat_map (fun (pt, _) -> pattern_names pt) decls
    | If (_, a, b) -> names a @ (match b with Some b -> names b | None -> [])
    | While (_, b) | With (_, b) -> names b
    | For (init, _, _, b) -> (match init with Some i -> names i | None -> []) @ names b
    | For_of (Var_kind, x, _, b) | For_await (Var_kind, x, _, b) -> pattern_names x @ names b
    | For_in (Declared (Var_kind, x), _, b) -> x :: names b
    | For_of (_, _, _, b) | For_await (_, _, _, b) | For_in (_, _, b) | Do_while (b, _) | Labeled (_, b) -> names b
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
      let bind x v = match lookup s x with Some b -> b.value <- v | None -> declare s x ~constant:false v in
      List.iter
        (fun ((pt : A.pattern), init) ->
          match (pt, init) with
          (* var x; again: what it holds stays *)
          | Bind x, None -> if lookup s x = None then declare s x ~constant:false Undefined
          | pt, init -> destructure t s this pt (match init with Some e -> eval e | None -> Undefined) bind)
        decls;
      Normal
  | Let (kind, decls) ->
      List.iter
        (fun (pt, init) ->
          destructure t s this pt (match init with Some e -> eval e | None -> Undefined) (fun x v -> declare s x ~constant:(kind = Const_kind) v))
        decls;
      Normal
  | Function_decl _ -> Normal (* defined by its block, first *)
  | Class_decl c ->
      declare s (Option.get c.class_name) ~constant:false (make_class t s this c);
      Normal
  | Return e -> Return (match e with Some e -> eval e | None -> Undefined)
  | If (c, a, b) -> (
      if truthy (eval c) then exec t (new_scope s) this a
      else match b with Some b -> exec t (new_scope s) this b | None -> Normal)
  | While (c, body) ->
      let rec loop () =
        if truthy (eval c) then match after (exec t (new_scope s) this body) with None -> loop () | Some o -> o else Normal
      in
      loop ()
  | With (o, body) ->
      let o = eval o in
      (match o with Undefined | Null -> throw "TypeError" (Printf.sprintf "Cannot convert %s to object" (to_string o)) | _ -> ());
      exec t { vars = Hashtbl.create 1; parent = Some s; subject = Some o; in_with = true } this body
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
  | For_of (kind, x, xs, body) | For_await (kind, x, xs, body) ->
      (* one item at a time: what is gone through may never end (a
       * generator), and a break tells it to stop *)
      let ended = ref Normal in
      let turn (v : value) : bool =
        let it = new_scope s in
        (* a var's, or a name's already there: set; else this turn's own *)
        let bind x v = match (kind, lookup s x) with A.Var_kind, Some b -> b.value <- v | _ -> declare it x ~constant:(kind = Const_kind) v in
        destructure t it this x v bind;
        match after (exec t it this body) with None -> true | Some o -> ended := o; false
      in
      let xs = eval xs in
      (match st.stmt with
      | For_await _ -> (
          let await v = Js_promise.await (Option.get t.promises) v in
          match (match xs with Object _ -> get t xs "@@asyncIterator" | _ -> Undefined) with
          (* its own way of giving items late: next() is a promise of { value, done } *)
          | Object { kind = Closure _ | Host_function _; _ } as make ->
              let it = call_value t make ~this:xs [] in
              let next = get t it "next" in
              let rec go () =
                let r = await (call_value t next ~this:it []) in
                if (not (truthy (get t r "done"))) && turn (get t r "value") then go ()
              in
              go ()
          | _ -> iterate t xs (fun v -> turn (await v)))
      | _ -> iterate t xs turn);
      !ended
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
      loop
        (match eval o with
        | Object { kind = Proxy (tg, h); _ } as o -> (
            match trap t h "ownKeys" with Some f -> List.map to_string (items_of t (call_value t f ~this:(Object h) [ Object tg ])) | None -> enumerable_keys o)
        | o -> enumerable_keys o)
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

(* a program's statements, in the global scope *)
let run_in_run (t : t) (program : A.program) : value =
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
      !last

let eval_in_run (t : t) (text : string) : value =
  match Js_parse.parse text with
  | Ok program -> run_in_run t program
  | Error e -> t.line <- e.line; throw "SyntaxError" e.message

let default_budget = 10_000_000

let create ?(log = fun _ -> ()) ?(seed = 1) ?now () : t =
  let globals = { vars = Hashtbl.create 64; parent = None; subject = None; in_with = false } in
  let t = { globals; protos = None; promises = None; line = 0; steps = default_budget; budget = default_budget; depth = 0; generators = [] } in
  let call f ~this args = call_value t f ~this args in
  let define x v = declare globals x ~constant:false v in
  (* new Function(params, body); an async one's constructor makes async ones *)
  let compile ~async params body = eval_in_run t (Printf.sprintf "(%sfunction anonymous(%s\n) {\n%s\n})" (if async then "async " else "") params body) in
  t.protos <- Some (Js_builtins.install ~call ~get:(fun v k -> get t v k) ~put:(fun v k x -> put t v k x) ~items:(fun v -> items_of t v) ~compile ~log ~seed ?now define);
  (* the prototype of async functions: Object.getPrototypeOf(async
   * function () {}).constructor is how a library gets to make one
   * from a text (Alpine) *)
  let async_proto = { (new_object ()) with proto = Some (protos t).functions } in
  set_own async_proto "constructor"
    (host_function "AsyncFunction" (fun ~this:_ args ->
         match List.rev (List.map to_string args) with [] -> compile ~async:true "" "" | body :: params -> compile ~async:true (String.concat "," (List.rev params)) body));
  declare globals "%async" ~constant:true (Object async_proto);
  (* eval(text): the text run as a program, its last expression's
   * value; of anything else, the thing itself. In the global scope
   * always: the names of the function calling it are not seen (a
   * "direct" eval's are, in JavaScript) *)
  define "eval" (host_function "eval" (fun ~this:_ args -> match args with String text :: _ -> eval_in_run t text | v :: _ -> v | [] -> Undefined));
  (* the helpers libraries look for: Symbol, Map, Object.defineProperty... *)
  Js_globals.install ~call ~lookup:(fun x -> Option.map (fun (b : binding) -> b.value) (Hashtbl.find_opt globals.vars x))
    ~get:(fun v k -> get t v k) ~put:(fun v k x -> put t v k x) ~has:(has_property t) ~items:(fun v -> items_of t v) define;
  (* a rejection nobody handled, said as an error is *)
  let report v = log ("Uncaught (in promise) " ^ match v with Object o -> (match (get_own o "name", get_own o "message") with Some (String n), Some (String m) -> n ^ ": " ^ m | _ -> display v) | v -> display v) in
  t.promises <- Some (Js_promise.install ~call ~get:(get t) ~items:(fun v -> items_of t v) ~report define);
  (* the global object, by its standard name (a page's window is the browser's) *)
  define "globalThis" (host_object { class_name = "global"; get = (fun k -> match Hashtbl.find_opt globals.vars k with Some b -> b.value | None -> Undefined); set = define; show = (fun () -> "[object global]") });
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

(* a run or a call, its budget renewed, its throws caught; then the
 * jobs it left (the thens of the promises it settled) *)
let guarded (t : t) (f : unit -> value) : (value, error) result =
  t.steps <- t.budget;
  t.depth <- 0;
  Fun.protect ~finally:(fun () -> Js_promise.drain (Option.get t.promises)) @@ fun () ->
  match f () with
  | v -> Ok v
  | exception Throw v -> Error (error_of t v)
  | exception Stack_overflow -> Error { line = t.line; message = "RangeError: Maximum call stack size exceeded" }
  (* a mistake of the engine's own (an OCaml exception a
   * built-in let through): the script's error, never the browser's end *)
  | exception ((Invalid_argument _ | Failure _ | Not_found | Division_by_zero) as e) ->
      Error { line = t.line; message = "InternalError: " ^ Printexc.to_string e }

let run (t : t) (program : A.program) : (value, error) result = guarded t (fun () -> run_in_run t program)

let call_in_run = call_value

let eval (t : t) (text : string) : (value, error) result =
  match Js_parse.parse text with
  | Ok program -> run t program
  | Error e -> Error { line = e.line; message = "SyntaxError: " ^ e.message }

let call (t : t) (f : value) ~(this : value) (args : value list) : (value, error) result =
  guarded t (fun () -> call_value t f ~this args)

let promise (t : t) = Js_promise.make (Option.get t.promises)
let items = items_of

let global (t : t) (x : string) : value option = Option.map (fun b -> b.value) (Hashtbl.find_opt t.globals.vars x)
let define (t : t) (x : string) (v : value) : unit = declare t.globals x ~constant:false v
let set_budget (t : t) (steps : int) : unit = t.budget <- steps
