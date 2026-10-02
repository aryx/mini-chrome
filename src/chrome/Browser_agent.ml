(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Browser_agent.mli *)

let table : (string * string * string) list = []

let for_host (host : string) : string =
  let host = String.lowercase_ascii host in
  match List.find_opt (fun (site, _, _) -> host = site || String.ends_with ~suffix:("." ^ site) host) table with
  | Some (_, agent, _) -> agent
  | None -> Http.default_agent
