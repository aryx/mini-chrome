(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See MiniCurl.mli *)
let () =
  Cap.main (fun caps ->
      let status = Curl.run caps (List.tl (Array.to_list (CapSys.argv caps))) in
      flush stdout;
      CapStdlib.exit caps status)
