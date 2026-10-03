(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* MINI_OPTI=off: the engine's simple code paths (Mini_opti), which
 * dune runs these same tests on a second time: the two agree *)
let simple = Sys.getenv_opt "MINI_OPTI" = Some "off"
let () = if simple then Mini_opti.enabled := false

(* a name of its own: the two runs keep their results apart *)
let () = Testo.interpret_argv ~project_name:(if simple then "javascript-simple" else "javascript") (fun _env -> Unit_js_lexer.tests @ Unit_js_parse.tests @ Unit_js_eval.tests @ Unit_js_scope.tests @ Unit_js_es5.tests @ Unit_js_classic.tests @ Unit_js_modern.tests @ Unit_js_promise.tests @ Unit_js_module.tests @ Unit_js_globals.tests @ Unit_json.tests)
