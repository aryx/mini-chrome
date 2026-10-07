(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Tab_jobs.mli *)
open Window_model

type work = msg Browser_tab.config -> Browser_tab.t -> Browser_tab.t * msg Cmd.t
type job = { run : (Browser_tab.t * msg Cmd.t) Worker.job; mutable waiting : work list; mutable owed : float }

(* the window's domain's alone: the tabs' domains, the jobs given, the messages kept *)
let pools : Worker.t array ref = ref [||]
let jobs : (int, job) Hashtbl.t = Hashtbl.create 8
let kept : msg list ref = ref []

let start (n : int) : unit =
  if n > 0 && not Per_domain.parallel then Logs.warn (fun m -> m "tabs=domains needs OCaml 5: this program has one domain, and its tabs stay in it")
  else if n > 0 then (
    Logs.info (fun m -> m "tabs: %d domains for their work" n);
    (* each a pool of one: a tab stays on its domain *)
    pools := Array.init n (fun i -> Worker.create ~name:(fun _ -> Printf.sprintf "tab domain %d" i) 1))

let stop () : unit =
  pools := [||];
  Hashtbl.reset jobs;
  kept := []

let enabled () : bool = Array.length !pools > 0
let domains () : int = Array.length !pools
let away (id : int) : bool = Hashtbl.mem jobs id

let send (id : int) (cfg : msg Browser_tab.config) (tab : Browser_tab.t) (f : work) : unit =
  let pool = !pools.(id mod Array.length !pools) in
  Hashtbl.replace jobs id { run = Worker.submit pool (fun () -> f cfg tab); waiting = []; owed = 0. }

(* [f], on the tab's domain, waited for: a script's task whose answer
 * the window needs before it goes on (did the page prevent the click?)
 * -- run where the page's other tasks run, not in the window's
 * domain: an async function of the page stopped at an await is a
 * thread of the tab's domain, and woken from another it found no
 * coroutine running (a click in Gmail asked for its message and the
 * answer was never shown) *)
let wait (id : int) (f : unit -> 'a) : 'a =
  if not (Array.length !pools > 0) then f ()
  else
    let job = Worker.submit !pools.(id mod Array.length !pools) f in
    let rec poll () = match Worker.poll job with Some (Ok v) -> v | Some (Error e) -> raise e | None -> Unix.sleepf 0.0002; poll () in
    poll ()

let later (id : int) (f : work) : unit = match Hashtbl.find_opt jobs id with Some j -> j.waiting <- j.waiting @ [ f ] | None -> ()
let owe (id : int) (ms : float) : unit = match Hashtbl.find_opt jobs id with Some j -> j.owed <- Float.min 5000. (j.owed +. ms) | None -> ()
let hold (msg : msg) : unit = kept := !kept @ [ msg ]

let back () : (int * (Browser_tab.t * msg Cmd.t) option * work list * float) list =
  let done_ =
    Hashtbl.fold
      (fun id (j : job) acc ->
        match Worker.poll j.run with
        | None -> acc
        | Some (Ok result) -> (id, Some result, j.waiting, j.owed) :: acc
        | Some (Error e) ->
            Logs.warn (fun m -> m "tab %d: its work ended on %s" id (Printexc.to_string e));
            (id, None, j.waiting, j.owed) :: acc)
      jobs []
  in
  List.iter (fun (id, _, _, _) -> Hashtbl.remove jobs id) done_;
  List.sort (fun (a, _, _, _) (b, _, _, _) -> compare (a : int) b) done_

let holding () : bool = !kept <> []

let held () : msg list =
  let msgs = !kept in
  kept := [];
  msgs
