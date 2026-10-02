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

let opera_mini = "Opera/9.80 (J2ME/MIDP; Opera Mini/9.80 (S60; SymbOS; Opera Mobi/23.348; U; en) Presto/2.5.25 Version/10.54"

let table =
  [ ("google.com", opera_mini, "its search answers a browser it does not know with a script to run and no result; an old Opera Mini, with plain HTML") ]

let for_host (host : string) : string =
  let host = String.lowercase_ascii host in
  match List.find_opt (fun (site, _, _) -> host = site || String.ends_with ~suffix:("." ^ site) host) table with
  | Some (_, agent, _) -> agent
  | None -> Http.default_agent
