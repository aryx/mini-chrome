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
      Testo.create "its own name to everybody; the table is empty" (fun () ->
          Alcotest.(check (list bool)) "example.com, Google, a host under it"
            [ true; true; true ]
            (List.map (fun h -> Browser_agent.for_host h = Http.default_agent) [ "example.com"; "google.com"; "www.google.com" ]);
          Alcotest.(check int) "no site is given another name" 0 (List.length Browser_agent.table));
    ]
