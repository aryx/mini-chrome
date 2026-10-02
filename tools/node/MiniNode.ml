(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See MiniNode.mli *)

(* a line read, run, shown, until the input ends *)
let console (caps : < Cap.stdin ; .. >) (t : Node_host.t) : unit =
  let (_ : Cap.Console_.stdin) = caps#stdin in
  let prompt = Unix.isatty Unix.stdin in
  let rec go () =
    if prompt then (print_string "> "; flush stdout);
    match In_channel.input_line stdin with
    | None -> if prompt then print_newline ()
    | Some l ->
        (match Node_host.line t l with
        | Ok (Some shown) -> print_endline shown
        | Ok None -> if prompt then print_endline "undefined"
        | Error message -> print_endline ("Uncaught " ^ message));
        go ()
  in
  go ()

let () =
  Cap.main (fun caps ->
      match List.tl (Array.to_list (CapSys.argv caps)) with
      | ("-h" | "-help" | "--help") :: _ ->
          print_endline "usage: mini-node [file.js [arguments] | -e text]";
          CapStdlib.exit caps 0
      | "-e" :: text :: rest ->
          let t = Node_host.create caps ~argv:rest () in
          CapStdlib.exit caps (if Node_host.run_text t text then 0 else 1)
      | [] -> console caps (Node_host.create caps ~argv:[] ())
      | file :: _ as argv ->
          let t = Node_host.create caps ~argv () in
          CapStdlib.exit caps (if Node_host.run_file t file then 0 else 1))
