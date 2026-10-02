(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Node_host.mli *)
open Js_value

type timer = { id : int; mutable due : float; every : float option; fn : value; args : value list }

type t = {
  engine : Js_eval.t;
  mutable timers : timer list;
  mutable next_id : int;
  modules : (string, obj) Hashtbl.t; (* a file's path to its module object *)
  complain : string -> unit;
  now : unit -> float;
  sleep : float -> unit;
  mutable file : string; (* what is run: the program's file *)
  mutable failed : string option; (* the module that failed to load, the innermost: where the error is *)
  read : string -> string option; (* a file's text *)
}

let arg (args : value list) (i : int) : value = Option.value (List.nth_opt args i) ~default:Undefined
let fn (name : string) (f : value list -> value) : value = host_function name (fun ~this:_ args -> f args)

let object_of (fields : (string * value) list) : value =
  let o = new_object () in
  List.iter (fun (k, v) -> set_own o k v) fields;
  Object o

(*****************************************************************************)
(* Timers, and the loop *)
(*****************************************************************************)

let add_timer (t : t) ~(repeat : bool) (args : value list) : value =
  let ms = Float.max 1. (match arg args 1 with Undefined -> 0. | v -> to_number v) in
  t.next_id <- t.next_id + 1;
  let rest = match args with _ :: _ :: rest -> rest | _ -> [] in
  t.timers <- t.timers @ [ { id = t.next_id; due = t.now () +. ms; every = (if repeat then Some ms else None); fn = arg args 0; args = rest } ];
  Number (float_of_int t.next_id)

let clear_timer (t : t) (args : value list) : value =
  let id = int_of_float (to_number (arg args 0)) in
  t.timers <- List.filter (fun tm -> tm.id <> id) t.timers;
  Undefined

let report (t : t) (e : Js_eval.error) : unit =
  t.complain (Printf.sprintf "%s:%d: %s" (Option.value t.failed ~default:t.file) e.line e.message);
  t.failed <- None

(* as long as a timer is set: sleep until the earliest is due, call it
 * (its jobs run after it: Js_eval.call); whether none failed *)
let loop (t : t) : bool =
  let ok = ref true in
  let rec go () =
    match List.sort (fun a b -> compare (a.due, a.id) (b.due, b.id)) t.timers with
    | [] -> ()
    | tm :: _ ->
        let wait = tm.due -. t.now () in
        if wait > 0. then t.sleep wait;
        (match tm.every with
        | Some every -> tm.due <- tm.due +. every
        | None -> t.timers <- List.filter (fun x -> x.id <> tm.id) t.timers);
        (match Js_eval.call t.engine tm.fn ~this:Undefined tm.args with Ok _ -> () | Error e -> ok := false; report t e);
        go ()
  in
  go ();
  !ok

(*****************************************************************************)
(* Modules *)
(*****************************************************************************)

(* "./lib" asked by /a/main.js: /a/lib, or /a/lib.js *)
let resolve (t : t) ~(from : string) (name : string) : string =
  let path = if Filename.is_relative name then Filename.concat (Filename.dirname from) name else name in
  (* a/./b, a/x/../b: as written but for those *)
  let parts =
    List.fold_left
      (fun acc part -> match (part, acc) with ".", _ -> acc | "..", p :: rest when p <> ".." && p <> "" -> rest | _ -> part :: acc)
      [] (String.split_on_char '/' path)
  in
  let path = String.concat "/" (List.rev parts) in
  if t.read path = None && t.read (path ^ ".js") <> None then path ^ ".js" else path

(* a file's module: run once, inside the function that gives it
 * exports, require and module; what its module.exports is then *)
let rec load (t : t) ~(fs : value) (path : string) : value =
  match Hashtbl.find_opt t.modules path with
  | Some m -> Option.value (get_own m "exports") ~default:Undefined
  | None -> (
      let source = match t.read path with Some s -> s | None -> throw "Error" (Printf.sprintf "Cannot find module '%s'" path) in
      (* #!/usr/bin/env mini-node, a script's first line: a comment *)
      let source = if String.starts_with ~prefix:"#!" source then "//" ^ source else source in
      let m = new_object () in
      let exports = Object (new_object ()) in
      set_own m "exports" exports;
      set_own m "filename" (String path);
      (* noted before it is run: a module that requires it meanwhile
       * gets its exports so far, and the two end *)
      Hashtbl.replace t.modules path m;
      let require = fn "require" (fun args -> require t ~fs ~from:path (to_string (arg args 0))) in
      (* on the file's first line, so that its lines keep their numbers *)
      let wrapped = "(function (exports, require, module, __filename, __dirname) {" ^ source ^ "\n})" in
      match
        let f = Js_eval.eval_in_run t.engine wrapped in
        Js_eval.call_in_run t.engine f ~this:exports [ exports; require; Object m; String path; String (Filename.dirname path) ]
      with
      | _ -> Option.value (get_own m "exports") ~default:Undefined
      | exception e ->
          Hashtbl.remove t.modules path;
          if t.failed = None then t.failed <- Some path;
          raise e)

and require (t : t) ~(fs : value) ~(from : string) (name : string) : value =
  match name with
  | "fs" | "node:fs" -> fs
  | _ when String.length name > 0 && (name.[0] = '.' || name.[0] = '/') -> load t ~fs (resolve t ~from name)
  | _ -> throw "Error" (Printf.sprintf "Cannot find module '%s'" name)

(*****************************************************************************)
(* Entry points *)
(*****************************************************************************)

let create (caps : < Cap.stdout ; Cap.stderr ; Cap.open_in ; Cap.open_out ; Cap.env ; Cap.exit ; .. >) ?print ?complain
    ?(now = fun () -> Unix.gettimeofday () *. 1000.) ?(sleep = fun ms -> Unix.sleepf (ms /. 1000.)) ~(argv : string list) () : t =
  let print = match print with Some p -> p | None -> let (_ : Cap.Console_.stdout) = caps#stdout in fun s -> print_string s; flush stdout in
  let complain = match complain with Some c -> c | None -> let (_ : Cap.Console_.stderr) = caps#stderr in fun s -> prerr_endline s in
  let read path =
    if Sys.file_exists path && not (Sys.is_directory path) then (
      let (_ : Cap.FS_.open_in) = caps#open_in path in
      Some (In_channel.with_open_bin path In_channel.input_all))
    else None
  in
  let engine = Js_eval.create ~log:(fun l -> print (l ^ "\n")) ~now () in
  let t = { engine; timers = []; next_id = 0; modules = Hashtbl.create 8; complain; now; sleep; file = "mini-node"; failed = None; read } in
  let define name f = Js_eval.define engine name (fn name f) in
  define "setTimeout" (add_timer t ~repeat:false);
  define "setInterval" (add_timer t ~repeat:true);
  define "setImmediate" (fun args -> add_timer t ~repeat:false (arg args 0 :: Number 0. :: (match args with _ :: rest -> rest | [] -> [])));
  define "clearTimeout" (clear_timer t);
  define "clearInterval" (clear_timer t);
  let fs =
    object_of
      [ ("readFileSync", fn "readFileSync" (fun args ->
             let path = to_string (arg args 0) in
             match read path with Some s -> String s | None -> throw "Error" (Printf.sprintf "ENOENT: no such file or directory, open '%s'" path)));
        ("writeFileSync", fn "writeFileSync" (fun args ->
             let path = to_string (arg args 0) in
             let (_ : Cap.FS_.open_out) = caps#open_out path in
             (try Out_channel.with_open_bin path (fun ch -> output_string ch (to_string (arg args 1)))
              with Sys_error why -> throw "Error" why);
             Undefined));
        ("existsSync", fn "existsSync" (fun args -> Bool (Sys.file_exists (to_string (arg args 0))))) ]
  in
  let env = host_object { class_name = "env"; get = (fun k -> try String (CapSys.getenv caps k) with Not_found -> Undefined); set = (fun _ _ -> ()); show = (fun () -> "[object env]") } in
  Js_eval.define engine "process"
    (object_of
       [ ("argv", Object (new_array (List.map (fun a -> String a) ("mini-node" :: argv))));
         ("env", env);
         ("exit", fn "exit" (fun args -> CapStdlib.exit caps (match arg args 0 with Undefined -> 0 | v -> int_of_float (to_number v))));
         ("stdout", object_of [ ("write", fn "write" (fun args -> print (to_string (arg args 0)); Bool true)) ]);
         ("nextTick", Option.value (Js_eval.global engine "queueMicrotask") ~default:Undefined) ]);
  (* a console's require, and a text's (-e): from where the program was run *)
  define "require" (fun args -> require t ~fs ~from:"./console" (to_string (arg args 0)));
  Js_eval.define engine "%load" (fn "load" (fun args -> load t ~fs (to_string (arg args 0))));
  t

(* a run, then the loop *)
let finish (t : t) (r : (value, Js_eval.error) result) : bool =
  let ok = match r with Ok _ -> true | Error e -> report t e; false in
  loop t && ok

let run_file (t : t) (path : string) : bool =
  t.file <- path;
  let path = resolve t ~from:"./program" (if Filename.is_implicit path then "./" ^ path else path) in
  finish t (Js_eval.call t.engine (Option.get (Js_eval.global t.engine "%load")) ~this:Undefined [ String path ])

let run_text (t : t) (text : string) : bool =
  t.file <- "[eval]";
  finish t (Js_eval.eval t.engine text)

let line (t : t) (text : string) : (string option, string) result =
  t.file <- "console";
  let r = Js_eval.eval t.engine text in
  ignore (loop t);
  match r with
  | Ok Undefined -> Ok None
  | Ok (String s) -> Ok (Some (Printf.sprintf "'%s'" s))
  | Ok v -> Ok (Some (display v))
  | Error e -> t.failed <- None; Error e.message
