(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* claude: Node_host's tests read and write files (a temporary
 * directory): the capability from here *)
let () =
  Cap.main (fun caps ->
      Testo.interpret_argv ~project_name:"javascript" (fun _env ->
          Unit_js_lexer.tests @ Unit_js_parse.tests @ Unit_js_eval.tests @ Unit_js_es5.tests @ Unit_js_classic.tests @ Unit_js_modern.tests @ Unit_js_promise.tests
          @ Unit_js_globals.tests @ Unit_json.tests @ Unit_node_host.tests caps))
