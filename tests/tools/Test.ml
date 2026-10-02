(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* the tests read and write files (temporary directories) and reach
 * the network (localhost): the capabilities from here *)
let () =
  Cap.main (fun caps ->
      Testo.interpret_argv ~project_name:"tools" (fun _env ->
          Unit_httpd.tests caps @ Unit_curl.tests caps @ Unit_lynx.tests caps @ Unit_node_host.tests caps))
