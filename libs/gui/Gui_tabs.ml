(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Gui_tabs.mli *)
open Playground

type 'a tab = { value : 'a; title : string; busy : bool }
type 'a t = { left : float; y : float; room : float; tabs : 'a tab list; current : 'a }
type 'a hit = Close of 'a | Show of 'a | New

let tab_width (s : 'a t) : float = Float.min 220. (s.room /. float_of_int (max 1 (List.length s.tabs)))
let tab_x (s : 'a t) (i : int) : float = s.left +. (float_of_int i *. (tab_width s +. 2.))

let at (s : 'a t) (point : float * float) : 'a hit option =
  let w = tab_width s in
  let on_tab =
    List.mapi (fun i t -> (i, t)) s.tabs
    |> List.find_map (fun (i, (t : 'a tab)) ->
           let x = tab_x s i in
           if Gui_kit.near (x +. w -. 26.) s.y 18. 20. point then Some (Close t.value) else if Gui_kit.near x s.y w 28. point then Some (Show t.value) else None)
  in
  match on_tab with Some _ -> on_tab | None -> if Gui_kit.near (tab_x s (List.length s.tabs)) s.y 26. 26. point then Some New else None

let dim = rgb 168 192 228

let shapes (s : 'a t) ~(time : float) : shape list =
  let w = tab_width s in
  let chars = int_of_float ((w -. 60.) /. Gui_text.cell) in
  List.concat
    (List.mapi
       (fun i (t : 'a tab) ->
         let x = tab_x s i in
         let back = if t.value = s.current then Gui_kit.surface else dim in
         let angle = if t.busy then time *. 360. else 0. in
         [ polygon back [ (x, s.y -. 15.); (x +. 12., s.y +. 13.); (x +. w -. 12., s.y +. 13.); (x +. w, s.y -. 15.) ];
           group [ circle Gui_kit.accent 7.; rectangle back 3. 8. |> move 0. 4. ] |> rotate angle |> move (x +. 26.) s.y ]
         @ Gui_text.monospace (x +. 38.) s.y Gui_kit.ink (Gui_text.tail chars t.title)
         @ [ rectangle Gui_kit.muted 9. 2. |> rotate 45. |> move (x +. w -. 17.) s.y; rectangle Gui_kit.muted 9. 2. |> rotate (-45.) |> move (x +. w -. 17.) s.y ])
       s.tabs)
  @
  let x = tab_x s (List.length s.tabs) in
  [ rectangle (rgb 120 155 210) 22. 18. |> move (x +. 13.) (s.y -. 2.); rectangle Gui_kit.white 10. 2. |> move (x +. 13.) (s.y -. 2.);
    rectangle Gui_kit.white 2. 10. |> move (x +. 13.) (s.y -. 2.) ]
