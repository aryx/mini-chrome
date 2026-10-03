(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Gui_clipboard.mli *)

let kept : string ref = ref ""
let read : (unit -> string) ref = ref (fun () -> !kept)
let write : (string -> unit) ref = ref (fun s -> kept := s)
let get () : string = !read ()
let set (s : string) : unit = !write s
