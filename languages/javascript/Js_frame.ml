(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Js_frame.mli *)
open Js_value
module A = Js_ast

type params = scope -> value -> (A.pattern * A.expr option) list -> A.pattern option -> value list -> unit

let rec pattern_names (pt : A.pattern) : string list =
  match pt with
  | Bind x -> [ x ]
  | Object_pattern (parts, rest) -> List.concat_map (fun (_, pt, _) -> pattern_names pt) parts @ (match rest with Some r -> pattern_names r | None -> [])
  | Array_pattern (parts, rest) ->
      List.concat_map (fun part -> match part with Some (pt, _) -> pattern_names pt | None -> []) parts @ (match rest with Some r -> pattern_names r | None -> [])

(* var's names, declared (undefined) at the top of their function: a
 * var in a block or a loop is the function's -- hoisting, ES5's, what
 * let (block-scoped) came to fix *)
let hoisted (body : A.stmt list) : string list =
  let rec names (st : A.stmt) : string list =
    match st.stmt with
    | Let (Var_kind, decls) -> List.concat_map (fun (pt, _) -> pattern_names pt) decls
    | Var_set decls -> List.map (fun (x, _, _) -> x) decls
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
    | Export (Export_decl st) -> names st
    | _ -> []
  in
  List.concat_map names body

let hoist (s : scope) (body : A.stmt list) : unit =
  List.iter (fun x -> if Js_scope.own s x = None then Js_scope.declare s x ~constant:false Undefined) (hoisted body)

(* a call's frame, the simple way: a scope under the function's, and
 * in it arguments, the var's hoisted, then the parameters *)
let simple ~(params : params) (c : closure) (fn : value) (this : value) (args : value list) ~(strict : bool) : scope =
  let frame = if strict then Js_scope.strict c.scope else Js_scope.nested c.scope in
  if not c.func.arrow then Js_scope.declare frame "arguments" ~constant:false (Object (new_array args));
  (* a function expression's own name, in its body (var f =
   * function again(n) { ... again(n - 1) }), unless the name is
   * already somebody's *)
  (match c.func.name with Some n when Js_scope.lookup c.scope n = None -> Js_scope.declare frame n ~constant:false fn | _ -> ());
  hoist frame c.func.body;
  params frame this c.func.params c.func.rest args;
  frame

(* opti: what every call of a function declares, found once in its
 * text: arguments, the var's (each once), the parameters when they
 * are plain names; and each parameter's slot *)
let layout (f : A.func) : A.frame =
  let plain = List.for_all (fun (pt, default) -> match ((pt : A.pattern), default) with Bind _, None -> true | _ -> false) f.params in
  let slots = A.Names.create 16 and names = ref [] in
  let slot (x : string) : int =
    match A.Names.find_opt slots x with
    | Some i -> i
    | None ->
        let i = A.Names.length slots in
        A.Names.replace slots x i;
        names := x :: !names;
        i
  in
  if not f.arrow then ignore (slot "arguments");
  List.iter (fun x -> ignore (slot x)) (hoisted f.body);
  let params = if plain then List.map (fun ((pt : A.pattern), _) -> match pt with Bind x -> slot x | _ -> -1) f.params else [] in
  let names = Array.of_list (List.rev !names) in
  { names; index = (if Array.length names > 16 then Some slots else None); slots = Array.of_list params; plain; own = A.place () }

(* opti: a call's frame made at once from the function's layout, an
 * array of bindings beside the function's array of names (shared by
 * its every call), the parameters set by their slots -- where [simple]
 * declares each name in a table, one after the other. 1M calls of a
 * function of two arguments: 3,700 ms to 670, with Js_scope's places *)
let opti ~(params : params) (l : A.frame) (c : closure) (fn : value) (this : value) (args : value list) ~(strict : bool) : scope =
  let f = c.func in
  let cells = Array.make (Array.length l.names) Js_scope.nothing in
  for i = 0 to Array.length cells - 1 do
    cells.(i) <- { value = Undefined; constant = false }
  done;
  let frame = Js_scope.frame c.scope ~names:l.names ~index:l.index ~cells ~strict in
  if not f.arrow then cells.(0).value <- Object (new_array args);
  (* its own name: looked for outside once, by the place it was found
   * (-2 hops: nowhere, and it is then the function's own for good) *)
  (match f.name with
  | Some n when l.own.hops = -2 || (match Js_scope.find c.scope n l.own with None -> l.own.hops <- -2; true | Some _ -> false) ->
      Js_scope.declare frame n ~constant:false fn
  | _ -> ());
  if l.plain then (
    (* each by its slot; those the call did not give, undefined *)
    let rec set (i : int) (args : value list) : value list =
      if i >= Array.length l.slots then args
      else
        match args with
        | v :: left -> cells.(l.slots.(i)).value <- v; set (i + 1) left
        | [] -> cells.(l.slots.(i)).value <- Undefined; set (i + 1) []
    in
    params frame this [] f.rest (set 0 args))
  else params frame this f.params f.rest args;
  frame

let make ~(params : params) (c : closure) (fn : value) (this : value) (args : value list) ~(strict : bool) : scope =
  match c.func.frame with
  | Some l when Js_scope.slotted c.scope -> opti ~params l c fn this args ~strict
  | _ -> simple ~params c fn this args ~strict
