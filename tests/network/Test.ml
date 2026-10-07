(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

let () =
  Testo.interpret_argv ~project_name:"network" (fun _env ->
      Unit_url.tests @ Unit_urlencoded.tests @ Unit_http.tests @ Unit_http_cache.tests @ Unit_cookie.tests @ Unit_x509.tests @ Unit_tls13.tests @ Unit_tls12.tests @ Unit_websocket.tests)
