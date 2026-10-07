(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Js_slice.mli *)

let length = ref 0.25
let enabled = ref true

(* whose turn it is: nobody's, the run's, the window's (a slice is
 * over), or the window's for good (the run ended) *)
type turn = Idle | Running | Paused | Finished

let turn = ref Idle
let lock = Mutex.create ()
let changed = Condition.create ()
let started = ref 0.
let calls = ref 0

(* the run to make, for the thread that makes them; what it raised *)
let job : (unit -> unit) option ref = ref None
let raised : exn option ref = ref None
let worker : Thread.t option ref = ref None

(* one thread for every run: it waits for a job, makes it, says so *)
let rec work () : unit =
  Mutex.lock lock;
  while !job = None do Condition.wait changed lock done;
  let f = Option.get !job in
  job := None;
  Mutex.unlock lock;
  (try f () with e -> raised := Some e);
  Mutex.lock lock;
  turn := Finished;
  Condition.broadcast changed;
  Mutex.unlock lock;
  work ()

(* the window waits for its turn: whether the run is done *)
let wait () : bool =
  while !turn = Running do Condition.wait changed lock done;
  let finished = !turn = Finished in
  if finished then turn := Idle;
  Mutex.unlock lock;
  (match !raised with
  | Some e when finished ->
      raised := None;
      raise e
  | _ -> ());
  finished

let run (f : unit -> unit) : bool =
  if not !enabled then (f (); true)
  else (
    if !worker = None then worker := Some (Thread.create work ());
    Mutex.lock lock;
    job := Some f;
    turn := Running;
    started := Unix.gettimeofday ();
    Condition.broadcast changed;
    wait ())

let continue () : bool =
  Mutex.lock lock;
  (* only a run that is paused goes on: one that ended meanwhile is
   * said ended, not waited for (it would be for ever) *)
  if !turn = Paused then (
    turn := Running;
    started := Unix.gettimeofday ();
    Condition.broadcast changed);
  wait ()

(* the slice ended if its time is up, the clock looked at now *)
(* (a run on a domain of its own is not the window's to cut: a tab's
 * work, which the window does not wait for) *)
let rec breath_now () : unit =
  if !turn = Running && Per_domain.main () && Unix.gettimeofday () -. !started > !length then pause ()

and breath () : unit =
  if !turn = Running && Per_domain.main () then (
    incr calls;
    if !calls land 1023 = 0 && Unix.gettimeofday () -. !started > !length then pause ())

(* the turn given to the window, and waited for back *)
and pause () : unit =
  Mutex.lock lock;
  turn := Paused;
  Condition.broadcast changed;
  while !turn = Paused do Condition.wait changed lock done;
  Mutex.unlock lock
