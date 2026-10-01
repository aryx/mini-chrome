(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Gui_toolbar.mli *)
open Playground

type icon = Back | Forward | Reload | Stop
type t = { left : float; y : float; buttons : (icon * bool) list }

let button_x (t : t) (i : int) : float = t.left +. (38. *. float_of_int i)

let at (t : t) (point : float * float) : icon option =
  List.mapi (fun i b -> (i, b)) t.buttons
  |> List.find_map (fun (i, (icon, active)) -> if active && Gui_kit.near (button_x t i -. 16.) t.y 32. 32. point then Some icon else None)

let picture (icon : icon) (active : bool) (x : number) (y : number) : shape list =
  let c = if active then rgb 70 90 120 else Gui_kit.disabled in
  let hole = Gui_kit.surface in
  List.map (move x y)
    (match icon with
    | Back -> [ polygon c [ (-9., 0.); (1., 9.); (1., -9.) ]; rectangle c 8. 5. |> move 4. 0. ]
    | Forward -> [ polygon c [ (9., 0.); (-1., 9.); (-1., -9.) ]; rectangle c 8. 5. |> move (-4.) 0. ]
    | Reload -> [ circle c 9.; circle hole 5.; rectangle hole 6. 6. |> move 5. 5.; polygon c [ (2., 3.); (10., 3.); (6., 10.) ] ]
    | Stop -> [ rectangle c 16. 3. |> rotate 45.; rectangle c 16. 3. |> rotate (-45.) ])

let shapes (t : t) : shape list = List.concat (List.mapi (fun i (icon, active) -> picture icon active (button_x t i) t.y) t.buttons)
