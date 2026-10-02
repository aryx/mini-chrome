(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See MiniHttpd.mli *)
let usage = "usage: mini-httpd [-p port] [directory]"

let () =
  Cap.main (fun caps ->
      let rec options port root args =
        match args with
        | [] -> Ok (port, root)
        | "-p" :: p :: rest -> ( match int_of_string_opt p with Some p -> options p root rest | None -> Error usage)
        | flag :: _ when String.length flag > 1 && flag.[0] = '-' -> Error usage
        | dir :: rest -> options port dir rest
      in
      match options 8000 "." (List.tl (Array.to_list (CapSys.argv caps))) with
      | Error usage -> prerr_endline usage; CapStdlib.exit caps 2
      | Ok (_, root) when not (Sys.file_exists root && Sys.is_directory root) -> prerr_endline (root ^ ": not a directory"); CapStdlib.exit caps 1
      | Ok (port, root) -> (
          match Httpd.listen caps ~port with
          | exception Unix.Unix_error (e, _, _) -> prerr_endline (Printf.sprintf "port %d: %s" port (Unix.error_message e)); CapStdlib.exit caps 1
          | sock, port ->
              Printf.printf "serving %s on http://127.0.0.1:%d/\n%!" root port;
              Httpd.serve caps ~root ~log:(fun l -> print_endline l) sock))
