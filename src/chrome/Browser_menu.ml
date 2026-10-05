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

type action = Open_in_new_tab of string | Open_with of string list | Back | Forward | Reload | Inspect

let items ?(helper : (string * string list) option) ~(link : string option) ~(back : bool) ~(forward : bool) () : action Gui_menu.item list =
  let with_helper what = match helper with Some (program, command) -> [ { Gui_menu.label = what ^ " with " ^ program; value = Open_with command; enabled = true } ] | None -> [] in
  (match link with
  | Some url -> [ { Gui_menu.label = "Open link in new tab"; value = Open_in_new_tab url; enabled = true } ] @ with_helper "Open link"
  | None ->
      with_helper "Open"
      @
      [ { Gui_menu.label = "Back"; value = Back; enabled = back }; { label = "Forward"; value = Forward; enabled = forward };
        { label = "Reload"; value = Reload; enabled = true } ])
  @ [ { label = "Inspect"; value = Inspect; enabled = true } ]
