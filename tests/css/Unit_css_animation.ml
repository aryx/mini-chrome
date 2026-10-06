(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_css_animation.mli *)

let sheet =
  "@keyframes fade-in { from { opacity: 0 } to { opacity: 1 } }\n\
   @keyframes a-s { 100% { opacity: 1; top: 0 } }\n\
   @media (min-width: 100000px) { @keyframes fade-in { to { opacity: .5 } } }\n\
   @keyframes spin { from { opacity: .2 } 50% { opacity: .7 } }"

let ends = lazy (Css_animation.ends ~media:(fun _ -> false) [ Css_syntax.parse_stylesheet sheet ])

(* an element's declarations after its animation, as "name: value" *)
let ended (style : string) : string list =
  Css_syntax.parse_declarations style
  |> List.map (fun (d : Css_syntax.declaration) -> (d.name, d.value))
  |> Css_animation.ended ends
  |> List.map (fun (n, v) -> n ^ ": " ^ String.trim (Css_syntax.to_string v))

let check what style expected = Alcotest.(check (list string)) what expected (ended style)

let tests =
  Testo.categorize "Css_animation"
    [
      Testo.create "the worked example: forwards is the last step, kept" (fun () ->
          check "the logo is there" "opacity: 0; animation: fade-in .25s 1.25s 1 forwards" [ "animation: fade-in 0.25s 1.25s 1 forwards"; "opacity: 1" ];
          check "never ended: its own values" "opacity: 0; animation: fade-in 1s infinite" [ "opacity: 0"; "animation: fade-in 1s infinite" ];
          check "ended, and back to its own" "opacity: 0; animation: fade-in 1s" [ "opacity: 0"; "animation: fade-in 1s" ]);
      Testo.create "the long names, 100%, both, and a name nobody defined" (fun () ->
          check "Gmail's loading screen" "color: red; opacity: 0; animation-name: a-s; animation-fill-mode: both"
            [ "color: red"; "animation-name: a-s"; "animation-fill-mode: both"; "opacity: 1"; "top: 0" ];
          check "no such keyframes" "opacity: 0; animation: nowhere 1s forwards" [ "opacity: 0"; "animation: nowhere 1s forwards" ];
          check "keyframes with no last step" "opacity: 0; animation: spin 1s forwards" [ "opacity: 0"; "animation: spin 1s forwards" ];
          check "no animation at all" "opacity: 0" [ "opacity: 0" ]);
      Testo.create "through the cascade: the element's style is the last step's" (fun () ->
          let tree = Html_tree.of_string "<style>@keyframes in { to { opacity: 1 } } p { opacity: 0; animation: in 1s forwards }</style><p id=a>x</p><p id=b style=\"animation: none\">y</p>" in
          let sheets : Cascade.sheet list = [ { origin = Author; rules = Css_syntax.parse_stylesheet "@keyframes in { to { opacity: 1 } } p { opacity: 0; animation: in 1s forwards }" } ] in
          let declared = Cascade.cascade { width = 1000.; height = 800. } sheets tree in
          let opacity id =
            let rec find (e : Dom.element) = if List.assoc_opt "id" e.attributes = Some id then Some e else List.find_map (fun (n : Dom.node) -> match n with Element c -> find c | Text _ -> None) e.children in
            match find tree with
            | Some e -> Option.map (fun v -> String.trim (Css_syntax.to_string v)) (List.assoc_opt "opacity" (declared e))
            | None -> Alcotest.fail "no such element"
          in
          Alcotest.(check (option string)) "shown" (Some "1") (opacity "a");
          Alcotest.(check (option string)) "its animation turned off: as written" (Some "0") (opacity "b"));
    ]
