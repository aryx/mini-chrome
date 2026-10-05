(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Stopwatch.mli *)

let enabled = ref false

type span = { mutable times : int; mutable own : float; mutable whole : float }

let table : (string, span) Hashtbl.t = Hashtbl.create 16

(* the spans open, the innermost first: each the time its children took *)
let stack : float ref list ref = ref []

let time (name : string) (f : unit -> 'a) : 'a =
  if not !enabled then f ()
  else (
    let children = ref 0. and start = Unix.gettimeofday () in
    stack := children :: !stack;
    Fun.protect f ~finally:(fun () ->
        let whole = Unix.gettimeofday () -. start in
        let s = match Hashtbl.find_opt table name with Some s -> s | None -> let s = { times = 0; own = 0.; whole = 0. } in Hashtbl.replace table name s; s in
        s.times <- s.times + 1;
        s.own <- s.own +. whole -. !children;
        s.whole <- s.whole +. whole;
        (* closed: its whole time is the parent's to take off *)
        stack := (match !stack with _ :: rest -> rest | [] -> []);
        match !stack with parent :: _ -> parent := !parent +. whole | [] -> ()))

let spans () : (string * int * float * float) list =
  List.sort (fun (_, _, a, _) (_, _, b, _) -> compare b a) (Hashtbl.fold (fun name s acc -> (name, s.times, s.own, s.whole) :: acc) table [])

let report ~(since : float) : string list =
  let all = spans () and gc = Gc.quick_stat () in
  let measured = List.fold_left (fun sum (_, _, own, _) -> sum +. own) 0. all in
  (Printf.sprintf "timings: %.1f s of %.1f measured" measured (Unix.gettimeofday () -. since)
   :: List.map (fun (name, times, own, whole) -> Printf.sprintf "  %-10s %6d times %7.1f s   (%.1f with what it calls)" name times own whole) all)
  @ [ Printf.sprintf "  the collector: %d major collections, a heap of %d MB at most" gc.major_collections (gc.top_heap_words * (Sys.word_size / 8) / 1_000_000) ]
