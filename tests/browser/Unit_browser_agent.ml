(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_browser_agent.mli *)

let tests =
  Testo.categorize "Browser agent"
    [
      Testo.create "its own name to everybody, but for the sites of the table" (fun () ->
          let own h = Browser_agent.for_host h = Http.default_agent in
          Alcotest.(check (list bool)) "example.com, a site whose name ends the same, a host under Google, Google, whatever the case"
            [ true; true; false; false; false ]
            (List.map own [ "example.com"; "notgoogle.com"; "www.google.com"; "google.com"; "WWW.Google.COM" ]);
          Alcotest.(check bool) "each line says why it is there" true (List.for_all (fun (_, agent, why) -> agent <> "" && String.length why > 20) Browser_agent.table));
    ]
