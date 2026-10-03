(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See AudioContext.mli *)
open Js_value
open Script_host

type output = { now : unit -> float; play : at:float -> rate:int -> float array -> float array -> unit }

let output : output ref = ref { now = (fun () -> 0.); play = (fun ~at:_ ~rate:_ _ _ -> ()) }

(* a script's array of numbers (a Float32Array is one here) *)
let samples (v : value) : float array =
  match v with
  | Object { kind = Array a; _ } -> Array.init a.length (fun i -> match a.elements.(i) with Number f -> f | v -> to_number v)
  | _ -> [||]

let install (define : string -> value -> unit) : unit =
  let fn name f = host_function name (fun ~this:_ args -> f args) in
  let o = new_object () in
  set_own o "now" (fn "now" (fun _ -> Number (!output.now ())));
  set_own o "play"
    (fn "play" (fun args ->
         let rate = match arg args 2 with Number r when r >= 1. -> int_of_float r | _ -> 44100 in
         let at = match arg args 3 with Number t -> t | _ -> 0. in
         !output.play ~at ~rate (samples (arg args 0)) (samples (arg args 1));
         Undefined));
  define "__audio" (Object o)
