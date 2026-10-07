(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Browser_cpu.mli *)

type reading = (int * int) list
type task = { name : string; percent : int }

let ticks (stat : string) : int option =
  (* "48213 (mini chrome) S 1 ...": the name may have spaces, so from
   * its closing parenthesis; then the state, and the time in the
   * program and in the kernel are the 12th and 13th after it *)
  match String.rindex_opt stat ')' with
  | Some i when i + 2 < String.length stat -> (
      let fields = String.split_on_char ' ' (String.sub stat (i + 2) (String.length stat - i - 2)) in
      match (List.nth_opt fields 11, List.nth_opt fields 12) with
      | Some u, Some s -> ( match (int_of_string_opt u, int_of_string_opt s) with Some u, Some s -> Some (u + s) | _ -> None)
      | _ -> None)
  | _ -> None

let read (caps : < Cap.open_in ; .. >) : reading =
  let dir = "/proc/self/task" in
  match Sys.readdir dir with
  | exception Sys_error _ -> []
  | tasks ->
      List.filter_map
        (fun task ->
          let file = Filename.concat (Filename.concat dir task) "stat" in
          let (_ : Cap.FS_.open_in) = caps#open_in file in
          (* a thread may end between the list and the read *)
          match ticks (In_channel.with_open_bin file In_channel.input_all) with
          | Some n -> Option.map (fun id -> (id, n)) (int_of_string_opt task)
          | None | (exception Sys_error _) -> None)
        (Array.to_list tasks)

let busy ~(before : reading) ~(after : reading) ~(seconds : float) : task list =
  List.filter_map
    (fun (id, n) ->
      (* a tick is a hundredth of a second: ticks a second are percents of a core *)
      Option.map
        (fun was -> { name = Option.value (Task_names.of_task id) ~default:"(the runtime's)"; percent = int_of_float (float_of_int (n - was) /. Float.max 0.01 seconds) })
        (List.assoc_opt id before))
    after
  |> List.stable_sort (fun a b -> compare b.percent a.percent)

let total (tasks : task list) : int = List.fold_left (fun n t -> n + t.percent) 0 tasks

let card (tasks : task list) : string =
  if tasks = [] then ""
  else
    let row (t : task) = Printf.sprintf "<tr><td>%s</td><td>%d%%</td><td><div style=\"background: #8ab4f8; height: 8px; width: %dpx\"></div></td></tr>\n" (Browser_text.escape_html t.name) t.percent (min 100 t.percent * 2) in
    Printf.sprintf
      "<div class=\"card\"><h2>The processor</h2>\n<table><tr><th>Thread</th><th>Busy</th><th></th></tr>\n%s</table>\n<p>%d%% in all, of %d threads, over the last two seconds: 100%% is one core kept busy. A tab's work is on a domain of its own with <code>tabs=domains</code>, else on the window's.</p></div>\n"
      (String.concat "" (List.map row tasks)) (total tasks) (List.length tasks)
