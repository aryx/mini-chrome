(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Keep_alive.mli *)

type resting = { host : string; port : int; connection : Tls_client.t; since : float }

let patience = 10.

(* no more than these at rest: the oldest closed *)
let most = 12
let pool : resting list ref = ref []
let lock = Mutex.create ()
let count = ref 0
let reused () = !count

let locked (f : unit -> 'a) : 'a =
  Mutex.lock lock;
  Fun.protect ~finally:(fun () -> Mutex.unlock lock) f

(* the most recent connection at rest for that host, still young; the
 * old ones closed on the way *)
let take ~(host : string) ~(port : int) : Tls_client.t option =
  let now = Unix.gettimeofday () in
  locked (fun () ->
      let young, old = List.partition (fun r -> now -. r.since < patience && not (Tls_client.ended r.connection)) !pool in
      List.iter (fun r -> Tls_client.close r.connection) old;
      match List.partition (fun r -> r.host = host && r.port = port) young with
      | r :: others, rest ->
          pool := others @ rest;
          Some r.connection
      | [], _ ->
          pool := young;
          None)

let give ~(host : string) ~(port : int) (connection : Tls_client.t) : unit =
  locked (fun () ->
      let all = { host; port; connection; since = Unix.gettimeofday () } :: !pool in
      List.iteri (fun i r -> if i >= most then Tls_client.close r.connection) all;
      pool := List.filteri (fun i _ -> i < most) all)

let clear () : unit =
  locked (fun () ->
      List.iter (fun r -> Tls_client.close r.connection) !pool;
      pool := [])

(* what came of a request on a connection: the answer whole (and
 * whether the connection may be kept), the bytes up to the
 * connection's end, or an error after [got] bytes *)
type outcome = Whole of string * bool | Ended of string | Failed of string * int

let ask ~(timeout : float) (c : Tls_client.t) ~(host : string) (request : string) : outcome =
  Tls_client.send c request;
  let answer = Buffer.create 65536 in
  let extent = ref None in
  let rec wait (silent : float) : outcome =
    let got = Tls_client.receive c in
    Buffer.add_string answer got;
    let so_far = Buffer.contents answer in
    if got <> "" && !extent = None then extent := Http.extent so_far;
    match (!extent, Tls_client.state c) with
    | Some (e, keep), _ when got <> "" && Http.whole so_far e -> Whole (so_far, keep)
    | _, Failed why -> if Buffer.length answer = 0 then Failed (why, 0) else Failed (why, Buffer.length answer)
    | _, Closed -> Ended so_far
    | _ when Tls_client.ended c -> Ended (so_far ^ Tls_client.receive c)
    | _ when silent > timeout -> Failed (Printf.sprintf "%s: no answer in %.0f s" host timeout, Buffer.length answer)
    | _ ->
        if got = "" then (
          Tls_client.wait c 0.05;
          wait (silent +. 0.05))
        else wait 0.
  in
  wait 0.

let exchange ?(timeout = 30.) (caps : < Cap.network ; .. >) ~(host : string) ~(port : int) (request : string) : (string, string) result =
  let finish (c : Tls_client.t) (o : outcome) : (string, string) result =
    match o with
    | Whole (answer, true) ->
        give ~host ~port c;
        Ok answer
    | Whole (answer, false) | Ended answer ->
        Tls_client.close c;
        Ok answer
    | Failed (why, _) ->
        Tls_client.close c;
        Error why
  in
  let fresh () = match Tls_client.connect caps ~host ~port () with Error e -> Error e | Ok c -> finish c (ask ~timeout c ~host request) in
  match take ~host ~port with
  | None -> fresh ()
  | Some c -> (
      match ask ~timeout c ~host request with
      (* a connection the server had closed: nothing came back, and
       * nothing says the request was read -- again, on a new one *)
      | Ended "" | Failed (_, 0) ->
          Tls_client.close c;
          fresh ()
      | o ->
          incr count;
          finish c o)
