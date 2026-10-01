(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Browser_menu.mli *)

type action = Open_in_new_tab of string | Back | Forward | Reload | Inspect

let items ~(link : string option) ~(back : bool) ~(forward : bool) : action Gui_menu.item list =
  (match link with
  | Some url -> [ { Gui_menu.label = "Open link in new tab"; value = Open_in_new_tab url; enabled = true } ]
  | None ->
      [ { Gui_menu.label = "Back"; value = Back; enabled = back }; { label = "Forward"; value = Forward; enabled = forward };
        { label = "Reload"; value = Reload; enabled = true } ])
  @ [ { label = "Inspect"; value = Inspect; enabled = true } ]
