(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Testutil_httpd.mli *)

let directory (files : (string * string) list) : string =
  let dir = Filename.temp_file "mini-tools" "" in
  Sys.remove dir;
  Sys.mkdir dir 0o700;
  List.iter
    (fun (name, text) ->
      let path = Filename.concat dir name in
      if not (Sys.file_exists (Filename.dirname path)) then Sys.mkdir (Filename.dirname path) 0o700;
      Out_channel.with_open_bin path (fun ch -> output_string ch text))
    files;
  dir

let site =
  [ ("index.html", "<title>Menu</title><h1>Menu</h1>\n<p>Soup of the day. See the <a href=\"recipes.html\">recipes</a>\nor go back <a href=\"/\">home</a>.");
    ("recipes.html", "<title>Recipes</title><p>Leek and potato.");
    ("notes/a.txt", "a note\n") ]

let with_server (caps : < Cap.network ; Cap.open_in ; .. >) (files : (string * string) list) (f : string -> unit) : unit =
  let root = directory files in
  let sock, port = Httpd.listen caps ~port:0 in
  match Unix.fork () with
  | 0 ->
      (* the child: serve until killed; never back into the test runner *)
      (try Httpd.serve caps ~root sock with _ -> ());
      Unix._exit 0
  | child ->
      Unix.close sock;
      Fun.protect
        ~finally:(fun () ->
          Unix.kill child Sys.sigkill;
          ignore (Unix.waitpid [] child))
        (fun () -> f (Printf.sprintf "http://127.0.0.1:%d" port))
