(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Sound_stream.mli *)

type t = {
  samples : Signal.stereo; (* at our rate *)
  native : float array array; (* at the file's: one channel, or two *)
  rate : int;
  mutable filled : int; (* of native *)
  mutable ready : int; (* of samples *)
  mutable skip : int; (* decoded samples still to drop *)
  mutable next : (unit -> float array array option) option; (* None: the end was reached *)
}

let create ~(rate : int) ~(length : int) ~(skip : int) ~(next : unit -> float array array option) : t =
  let ours = if rate = Signal.rate then length else int_of_float (Float.of_int length *. Float.of_int Signal.rate /. Float.of_int rate) in
  {
    samples = { left = Array.make ours 0.; right = Array.make ours 0. };
    native = [| Array.make length 0.; Array.make length 0. |];
    rate;
    filled = 0;
    ready = 0;
    skip;
    next = Some next;
  }

let samples (t : t) : Signal.stereo = t.samples
let ready (t : t) : int = t.ready

(* our samples that the file's decoded ones now give: each read at its
 * place among them, when the four a cubic needs are there *)
let convert (t : t) ~(ended : bool) : unit =
  let total = Array.length t.samples.left in
  if t.rate = Signal.rate then (
    let upto = min total t.filled in
    Array.blit t.native.(0) t.ready t.samples.left t.ready (upto - t.ready);
    Array.blit t.native.(1) t.ready t.samples.right t.ready (upto - t.ready);
    t.ready <- upto)
  else (
    let step = Float.of_int t.rate /. Float.of_int Signal.rate in
    let n = ref t.ready in
    while !n < total && (ended || int_of_float (Float.of_int !n *. step) + 3 < t.filled) do
      let at = Float.of_int !n *. step in
      t.samples.left.(!n) <- Resample.read Cubic t.native.(0) at;
      t.samples.right.(!n) <- Resample.read Cubic t.native.(1) at;
      incr n
    done;
    t.ready <- !n);
  if ended then t.ready <- total

(* one more packet decoded, if there is one *)
let step (t : t) : bool =
  match t.next with
  | None -> false
  | Some next -> (
      match next () with
      | None ->
          t.next <- None;
          convert t ~ended:true;
          false
      | Some channels ->
          let n = if Array.length channels = 0 then 0 else Array.length channels.(0) in
          let dropped = min t.skip n in
          t.skip <- t.skip - dropped;
          let kept = max 0 (min (n - dropped) (Array.length t.native.(0) - t.filled)) in
          if kept > 0 then (
            Array.blit channels.(0) dropped t.native.(0) t.filled kept;
            (* one channel: the same in both ears *)
            Array.blit channels.(if Array.length channels > 1 then 1 else 0) dropped t.native.(1) t.filled kept;
            t.filled <- t.filled + kept;
            convert t ~ended:false);
          true)

let ahead (t : t) (upto : int) : unit =
  let upto = min upto (Array.length t.samples.left) in
  while t.ready < upto && step t do
    ()
  done
