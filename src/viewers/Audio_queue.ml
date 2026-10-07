(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Audio_queue.mli *)

type scheduled = { start : int; left : Signal.t; right : Signal.t }

(* in samples of the output *)
let clock = ref 0
let queue : scheduled list ref = ref []

let now () : float = float_of_int !clock /. float_of_int Signal.rate

(* a script's sound comes from its tab's domain, the mixing is the window's *)
let lock = Mutex.create ()
let locked (f : unit -> 'a) : 'a = Mutex.lock lock; Fun.protect ~finally:(fun () -> Mutex.unlock lock) f

let play ~(at : float) ~(rate : int) (left : float array) (right : float array) : unit =
  locked @@ fun () ->
  let ours x = if rate = Signal.rate then x else Resample.to_rate Cubic rate x in
  let start = max !clock (int_of_float (Float.round (at *. float_of_int Signal.rate))) in
  (* with no sound card (a dump), the clock does not move and nothing
   * is ever over: a second of them kept at most *)
  let waiting = List.filter (fun s -> s.start + Array.length s.left > !clock && s.start < !clock + Signal.rate) !queue in
  queue := waiting @ [ { start; left = ours left; right = ours right } ]

let mix (out : Signal.stereo) : unit =
  locked @@ fun () ->
  let n = Array.length out.left and from = !clock in
  List.iter
    (fun s ->
      (* the part of s inside [from, from + n) *)
      let a = max from s.start and b = min (from + n) (s.start + Array.length s.left) in
      for i = a to b - 1 do
        out.left.(i - from) <- out.left.(i - from) +. s.left.(i - s.start);
        out.right.(i - from) <- out.right.(i - from) +. s.right.(i - s.start)
      done)
    !queue;
  clock := from + n;
  queue := List.filter (fun s -> s.start + Array.length s.left > !clock) !queue
