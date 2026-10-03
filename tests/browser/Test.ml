(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* the profile's tests read and write files (a temporary directory):
 * the capability from here *)
let () =
  Cap.main (fun caps ->
      Testo.interpret_argv ~project_name:"browser" (fun _env ->
          List.concat [ Unit_browser.tests; Unit_browser_script.tests; Unit_page_program.tests; Unit_script_dom.tests; Unit_xhr.tests @ Unit_cors.tests @ Unit_web_socket.tests @ Unit_script_modules.tests; Unit_browser_zoom.tests; Unit_browser_menu.tests; Unit_browser_agent.tests; Unit_media.tests; Unit_browser_details.tests; Unit_gui.tests; Unit_glyph_picture.tests; Unit_glyph_unicode.tests; Unit_window.tests caps; Unit_browser_profile.tests caps; Unit_browser_cookies.tests caps ]))
