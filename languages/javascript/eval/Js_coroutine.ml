(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Js_coroutine.mli *)

(* whose turn it is: the body's (its thread runs), or the one who
 * resumed it (the body's thread waits) *)
type turn = Body | Resumer

type t = { mutable turn : turn; mutable ended : bool; changed : Condition.t; body : unit -> unit; mutable started : bool }

(* one lock for all: it is held only to pass the turn *)
let lock = Mutex.create ()

(* the bodies running, the innermost first: a body can resume another
 * (an async function calling one) *)
let running_here = Per_domain.make (fun () : t list ref -> ref [])

(* the turn given to [next], and this thread asleep until it is given
 * back *)
let pass (co : t) (next : turn) : unit =
  Mutex.lock lock;
  co.turn <- next;
  Condition.broadcast co.changed;
  while co.turn = next do Condition.wait co.changed lock done;
  Mutex.unlock lock

let create (body : unit -> unit) : t = { turn = Resumer; ended = false; changed = Condition.create (); body; started = false }

let start (co : t) : unit =
  co.started <- true;
  let run () =
    Mutex.lock lock;
    while co.turn <> Body do Condition.wait co.changed lock done;
    Mutex.unlock lock;
    (try co.body () with _ -> ());
    Mutex.lock lock;
    co.ended <- true;
    co.turn <- Resumer;
    Condition.broadcast co.changed;
    Mutex.unlock lock
  in
  ignore (Thread.create run ())

let resume (co : t) : unit =
  if not co.ended then (
    if not co.started then start co;
    let outer = !(running_here ()) in
    running_here () := co :: outer;
    pass co Body;
    running_here () := outer)

let current () : t option = match !(running_here ()) with co :: _ -> Some co | [] -> None

let suspend () : unit =
  match !(running_here ()) with
  | co :: _ -> pass co Resumer
  | [] -> invalid_arg "Js_coroutine.suspend: no coroutine is running"
