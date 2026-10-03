(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Js_compile.mli *)
open Js_value
module A = Js_ast
module E = Js_eval

(* an expression compiled: given a scope and a this, its value; a
 * statement: how it ended *)
type code = scope -> value -> value
type outcome = E.outcome = Normal | Return of value | Break of string option | Continue of string option
type run = scope -> value -> outcome

(*****************************************************************************)
(* Operators *)
(*****************************************************************************)

(* a 32-bit integer already (NaN is not) *)
let small (x : float) : bool = x >= -2147483648. && x <= 2147483647. && Float.of_int (Float.to_int x) = x

(* an operator found once, by its name: a function of two values, two
 * numbers first and anything else Js_operators'. None: one the
 * evaluator does itself (instanceof, in) *)
let binary (op : string) : (value -> value -> value) option =
  let slow = Js_operators.arithmetic_simple op in
  let numbers (f : float -> float -> value) : (value -> value -> value) option =
    Some (fun a b -> match (a, b) with Number x, Number y -> f x y | _ -> slow a b)
  in
  let bits (f : int -> int -> int) : (value -> value -> value) option =
    Some (fun a b -> match (a, b) with Number x, Number y when small x && small y -> Number (Float.of_int (f (Float.to_int x) (Float.to_int y))) | _ -> slow a b)
  in
  match op with
  | "instanceof" | "in" -> None
  | "+" -> numbers (fun x y -> Number (x +. y))
  | "-" -> numbers (fun x y -> Number (x -. y))
  | "*" -> numbers (fun x y -> Number (x *. y))
  | "/" -> numbers (fun x y -> Number (x /. y))
  | "<" -> numbers (fun x y -> Bool (x < y))
  | ">" -> numbers (fun x y -> Bool (x > y))
  | "<=" -> numbers (fun x y -> Bool (x <= y))
  | ">=" -> numbers (fun x y -> Bool (x >= y))
  | "===" | "==" -> numbers (fun x y -> Bool (x = y))
  | "!==" | "!=" -> numbers (fun x y -> Bool (x <> y))
  | "|" -> bits ( lor )
  | "&" -> bits ( land )
  | "^" -> bits ( lxor )
  | ">>" -> bits (fun x y -> x asr (y land 31))
  | _ -> Some slow

let callable (fn : value) : bool = match fn with Object { kind = Closure _ | Host_function _ | Proxy _; _ } -> true | _ -> false
let spread (es : A.expr list) : bool = List.exists (fun (e : A.expr) -> match e with Spread _ -> true | _ -> false) es

(* each one's value, in order *)
let rec values (cs : code list) (s : scope) (this : value) : value list =
  match cs with [] -> [] | c :: rest -> let v = c s this in v :: values rest s this

(*****************************************************************************)
(* Expressions *)
(*****************************************************************************)

let rec expr (t : E.t) (e : A.expr) : code =
  (* what is not compiled: the evaluator's, on the tree *)
  let walk : code = fun s this -> E.eval_expr t s this e in
  match e with
  | Number f -> let v = Number f in fun _ _ -> v
  | String x -> let v = String x in fun _ _ -> v
  | Bool b -> let v = Bool b in fun _ _ -> v
  | Null -> fun _ _ -> Null
  | This -> fun _ this -> this
  | Local (x, p) ->
      fun s this ->
        if s.in_with then walk s this
        else
          let b = Js_scope.at s x p in
          if b == Js_scope.nothing then throw "ReferenceError" (x ^ " is not defined") else b.value
  | Unary ("!", a) -> let a = expr t a in fun s this -> Bool (not (truthy (a s this)))
  | Unary ("-", a) -> let a = expr t a in fun s this -> Number (-.to_number (a s this))
  | Unary ("void", a) -> let a = expr t a in fun s this -> ignore (a s this); Undefined
  | Unary ("typeof", a) when (match a with Name _ | Local _ -> false | _ -> true) -> let a = expr t a in fun s this -> String (typeof (a s this))
  | Binary (op, a, b) -> (
      match binary op with
      | Some f -> let a = expr t a and b = expr t b in fun s this -> let x = a s this in f x (b s this)
      | None -> walk)
  | Logical ("&&", a, b) -> let a = expr t a and b = expr t b in fun s this -> let v = a s this in if truthy v then b s this else v
  | Logical ("??", a, b) -> let a = expr t a and b = expr t b in fun s this -> ( match a s this with Undefined | Null -> b s this | v -> v)
  | Logical (_, a, b) -> let a = expr t a and b = expr t b in fun s this -> let v = a s this in if truthy v then v else b s this
  | Conditional (c, a, b) -> let c = expr t c and a = expr t a and b = expr t b in fun s this -> if truthy (c s this) then a s this else b s this
  | Comma (a, b) -> let a = expr t a and b = expr t b in fun s this -> ignore (a s this); b s this
  | Member (o, k) -> let o = expr t o in fun s this -> E.get t (o s this) k
  | Index (o, k) -> let o = expr t o and k = expr t k in fun s this -> let o = o s this in E.item t o (k s this)
  (* x = v: the binding set; one that is not there, or a constant, is
   * the evaluator's to say *)
  | Assign ("=", (Local (x, p) as target), v) ->
      let v = expr t v in
      fun s this ->
        if s.in_with then walk s this
        else
          let v = v s this in
          let b = Js_scope.at s x p in
          if b == Js_scope.nothing || b.constant then E.assign t s this target v else b.value <- v;
          v
  | Assign ("=", Member (o, k), v) -> let o = expr t o and v = expr t v in fun s this -> let o = o s this in let v = v s this in E.put t o k v; v
  | Assign ("=", Index (o, k), v) ->
      let o = expr t o and k = expr t k and v = expr t v in
      fun s this -> let o = o s this in let k = k s this in let v = v s this in E.put_item t o k v; v
  (* x += v, x++ *)
  | Assign (op, Local (x, p), v) when (match op with "=" | "&&=" | "||=" | "??=" -> false | _ -> true) -> (
      match binary (String.sub op 0 (String.length op - 1)) with
      | Some f ->
          let v = expr t v in
          fun s this ->
            let b = if s.in_with then Js_scope.nothing else Js_scope.at s x p in
            if b == Js_scope.nothing || b.constant then walk s this
            else (
              let old = b.value in
              let v = f old (v s this) in
              b.value <- v;
              v)
      | None -> walk)
  | Update (op, prefix, Local (x, p)) ->
      let by = if op = "++" then 1. else -1. in
      fun s this ->
        let b = if s.in_with then Js_scope.nothing else Js_scope.at s x p in
        if b == Js_scope.nothing || b.constant then walk s this
        else (
          let old = to_number b.value in
          b.value <- Number (old +. by);
          Number (if prefix then old +. by else old))
  (* f(a), o.m(a), o[k](a): the function and its this, the arguments,
   * then the call *)
  | Call (f, args) when not (spread args) -> (
      let args = List.map (expr t) args in
      let call (fn : value) (self : value) (s : scope) (this : value) : value =
        let args = values args s this in
        if not (callable fn) then throw "TypeError" (E.describe f ^ " is not a function");
        E.call_in_run t fn ~this:self args
      in
      match f with
      | Member (o, k) -> let o = expr t o in fun s this -> let o = o s this in call (E.get t o k) o s this
      | Index (o, k) -> let o = expr t o and k = expr t k in fun s this -> let o = o s this in call (E.item t o (k s this)) o s this
      | Opt _ | Super_member _ -> walk
      | f -> let f = expr t f in fun s this -> call (f s this) Undefined s this)
  | Function f -> fun s this -> E.closure s this f
  | Array es when not (spread es) -> let es = List.map (expr t) es in fun s this -> Object (new_array (values es s this))
  | _ -> walk

(*****************************************************************************)
(* Statements *)
(*****************************************************************************)

(* a loop's body ran: whether the loop goes on (None), or how it ends
 * (a loop with a label is the evaluator's) *)
and after (o : E.outcome) : E.outcome option = match o with Normal | Continue None -> None | Break None -> Some Normal | leave -> Some leave

and stmt (t : E.t) (st : A.stmt) : run =
  let line = st.line in
  let walk : run = fun s this -> E.exec t s this st in
  let plain decls = List.for_all (fun ((pt : A.pattern), _) -> match pt with Bind _ -> true | _ -> false) decls in
  match st.stmt with
  | Expr e -> let e = expr t e in fun s this -> E.step t line; ignore (e s this); Normal
  | Var_set decls ->
      let decls = List.map (fun (x, p, init) -> (x, p, Option.map (expr t) init)) decls in
      fun s this ->
        E.step t line;
        List.iter
          (fun (x, p, init) ->
            match init with
            | None -> if Js_scope.find s x p = None then Js_scope.declare s x ~constant:false Undefined
            | Some e -> (
                let v = e s this in
                match Js_scope.find s x p with Some b -> b.value <- v | None -> Js_scope.declare s x ~constant:false v))
          decls;
        Normal
  | Let (((Let_kind | Const_kind) as kind), decls) when plain decls ->
      let decls = List.concat_map (fun ((pt : A.pattern), init) -> match pt with Bind x -> [ (x, Option.map (expr t) init) ] | _ -> []) decls in
      let constant = kind = Const_kind in
      fun s this ->
        E.step t line;
        List.iter (fun (x, init) -> Js_scope.declare s x ~constant (match init with Some e -> e s this | None -> Undefined)) decls;
        Normal
  | Return None -> fun _ _ -> E.step t line; Return Undefined
  | Return (Some e) -> let e = expr t e in fun s this -> E.step t line; Return (e s this)
  | If (c, a, b) -> (
      let c = expr t c and a = inside t a in
      match b with
      | Some b -> let b = inside t b in fun s this -> E.step t line; if truthy (c s this) then a s this else b s this
      | None -> fun s this -> E.step t line; if truthy (c s this) then a s this else Normal)
  | While (c, body) ->
      let c = expr t c and body = inside t body in
      fun s this ->
        E.step t line;
        let rec loop () = if truthy (c s this) then match after (body s this) with None -> loop () | Some o -> o else Normal in
        loop ()
  | Do_while (body, c) ->
      let c = expr t c and body = inside t body in
      fun s this ->
        E.step t line;
        let rec loop () = match after (body s this) with None -> if truthy (c s this) then loop () else Normal | Some o -> o in
        loop ()
  (* for (let i ...): a scope for i, each turn in a copy of the last *)
  | For (init, test, update, body) ->
      let own = match init with Some { stmt = Let ((Let_kind | Const_kind), _); _ } -> true | _ -> false in
      let init = Option.map (stmt t) init and test = Option.map (expr t) test and update = Option.map (expr t) update and body = inside t body in
      fun s this ->
        E.step t line;
        let first = if own then Js_scope.nested s else s in
        Option.iter (fun i -> ignore (i first this)) init;
        let rec loop (it : scope) =
          let ok = match test with Some c -> truthy (c it this) | None -> true in
          if not ok then E.Normal
          else
            match after (body it this) with
            | Some o -> o
            | None ->
                let next = if own then Js_scope.copy it else it in
                Option.iter (fun u -> ignore (u next this)) update;
                loop next
        in
        loop first
  | Block body -> let b = block t ~scoped:true body in fun s this -> E.step t line; b s this
  (* the first case that is === the value, and from there every
   * statement to a break *)
  | Switch (e, cases) when not (List.exists (fun (_, body) -> functions body) cases) ->
      let e = expr t e in
      let tests = Array.of_list (List.map (fun (test, _) -> Option.map (expr t) test) cases) in
      let bodies = Array.of_list (List.map (fun (_, body) -> Array.of_list (List.map (stmt t) body)) cases) in
      let n = Array.length tests in
      let default = let rec go i = if i >= n then -1 else match tests.(i) with None -> i | Some _ -> go (i + 1) in go 0 in
      fun s this ->
        E.step t line;
        let v = e s this in
        let sc = Js_scope.nested s in
        let rec from i = if i >= n then default else match tests.(i) with Some test when strict_equal v (test sc this) -> i | _ -> from (i + 1) in
        let rec go i j : E.outcome =
          if i >= n then Normal
          else if j >= Array.length bodies.(i) then go (i + 1) 0
          else match bodies.(i).(j) sc this with Normal -> go i (j + 1) | Break None -> Normal | o -> o
        in
        let start = from 0 in
        if start < 0 then Normal else go start 0
  | Throw e -> let e = expr t e in fun s this -> E.step t line; raise (Throw (e s this))
  (* finally runs however the rest ended, and its own ending wins if
   * it is not the normal one *)
  | Try (body, handler, finally) ->
      let body = block t ~scoped:false body in
      let handler = Option.map (fun (x, h) -> (x, block t ~scoped:false h)) handler in
      let finally = Option.map (block t ~scoped:false) finally in
      fun s this ->
        E.step t line;
        let finish (ended : unit -> E.outcome) : E.outcome =
          match finally with
          | None -> ended ()
          | Some f -> (
              let run () = f (Js_scope.nested s) this in
              match ended () with
              | o -> ( match run () with Normal -> o | leave -> leave)
              | exception e -> ( match run () with Normal -> raise e | leave -> leave))
        in
        finish (fun () ->
            match body (Js_scope.nested s) this with
            | outcome -> outcome
            | exception Throw v when handler <> None ->
                let x, h = Option.get handler in
                let scope = Js_scope.nested s in
                Option.iter (fun x -> Js_scope.declare scope x ~constant:false v) x;
                h scope this)
  | Function_decl _ | Empty -> fun _ _ -> E.step t line; Normal
  | Break l -> fun _ _ -> E.step t line; Break l
  | Continue l -> fun _ _ -> E.step t line; Continue l
  | _ -> walk

(* whether statements declare functions: made first, in their block *)
and functions (body : A.stmt list) : bool = List.exists (fun (st : A.stmt) -> match st.stmt with Function_decl _ | Export _ -> true | _ -> false) body

(* a branch's or a loop's body, in a scope of its own: a block makes its own *)
and inside (t : E.t) (st : A.stmt) : run =
  match st.stmt with
  | Block _ -> stmt t st
  | _ -> let r = stmt t st in fun s this -> r (Js_scope.nested s) this

(* statements one after the other, their functions first; [scoped]: in
 * a scope of their own if they declare a name (a block's; a
 * function's body and a try's are given theirs) *)
and block (t : E.t) ~(scoped : bool) (body : A.stmt list) : run =
  let fresh = scoped && E.declares body and functions = functions body in
  let codes = Array.of_list (List.map (stmt t) body) in
  let n = Array.length codes in
  fun s this ->
    let s = if fresh then Js_scope.nested s else s in
    if functions then E.declare_functions s this body;
    let rec go i : E.outcome = if i >= n then Normal else match (Array.unsafe_get codes i) s this with Normal -> go (i + 1) | leave -> leave in
    go 0

(*****************************************************************************)
(* Entry point *)
(*****************************************************************************)

let body (t : E.t) (f : A.func) : scope -> value -> value =
  let b = block t ~scoped:false f.body in
  fun frame this -> match b frame this with Return v -> v | _ -> Undefined

let () = E.compiler := Some body
