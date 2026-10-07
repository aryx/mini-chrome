(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Task_names.mli *)

(* added to by any thread as it starts, read by the window's: no lock, a list swapped whole *)
let names : (int * string) list Atomic.t = Atomic.make []

let here (name : string) : unit =
  (* a link to PID/task/TID, the thread that reads it *)
  match int_of_string_opt (Filename.basename (Unix.readlink "/proc/thread-self")) with
  | Some task ->
      let rec add () = let old = Atomic.get names in if not (Atomic.compare_and_set names old ((task, name) :: old)) then add () in
      add ()
  | None | (exception Unix.Unix_error _) -> ()

let of_task (task : int) : string option = List.assoc_opt task (Atomic.get names)
