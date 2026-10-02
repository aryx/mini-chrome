(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See MiniLynx.mli *)
let usage = "usage: mini-lynx [-dump] [-w width] address"

let () =
  Cap.main (fun caps ->
      let rec options dump width address args =
        match args with
        | [] -> ( match address with Some a -> Ok (dump, width, a) | None -> Error usage)
        | "-dump" :: rest -> options true width address rest
        | "-w" :: w :: rest -> ( match int_of_string_opt w with Some w when w > 10 -> options dump w address rest | _ -> Error usage)
        | flag :: _ when String.length flag > 1 && flag.[0] = '-' -> Error usage
        | a :: rest -> options dump width (Some a) rest
      in
      match options false 80 None (List.tl (Array.to_list (CapSys.argv caps))) with
      | Error usage -> prerr_endline usage; CapStdlib.exit caps 2
      | Ok (dump, width, address) -> (
          match Lynx.open_ caps ~width address with
          | Error why -> prerr_endline ("mini-lynx: " ^ why); CapStdlib.exit caps 1
          | Ok page ->
              print_string (Lynx.show page);
              (* a prompt only for somebody: not when the output goes to a file *)
              if not (dump || not (Unix.isatty Unix.stdin)) then (
                let rec loop (session : Lynx.t) =
                  print_string "\nlink number, address, b (back), q (quit): ";
                  flush stdout;
                  match In_channel.input_line stdin with
                  | None -> ()
                  | Some typed -> (
                      match Lynx.step caps ~width session typed with
                      | Quit -> ()
                      | Stay why -> print_endline why; loop session
                      | Go session -> print_string (Lynx.show (List.hd session)); loop session)
                in
                loop [ page ])))
