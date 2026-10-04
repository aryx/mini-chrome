(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_css_logical.mli *)

(* a declaration's physical ones, as "name: value" *)
let physical (name : string) (value : string) : string list option =
  match Css_syntax.parse_declarations (name ^ ": " ^ value) with
  | [ d ] -> Option.map (List.map (fun (n, v) -> n ^ ": " ^ String.trim (Css_syntax.to_string v))) (Css_logical.physical (d.name, d.value))
  | _ -> Alcotest.fail "one declaration"

let check what name value expected = Alcotest.(check (option (list string))) what expected (physical name value)

let tests =
  Testo.categorize "Css_logical"
    [
      Testo.create "the worked examples: a side, a line's length, a corner" (fun () ->
          check "before the block" "margin-block-start" "8px" (Some [ "margin-top: 8px" ]);
          check "after a line's last word" "padding-inline-end" "1em" (Some [ "padding-right: 1em" ]);
          check "a line's length" "inline-size" "50%" (Some [ "width: 50%" ]);
          check "the most a block is high" "max-block-size" "10px" (Some [ "max-height: 10px" ]);
          check "block start, inline end" "border-start-end-radius" "6px" (Some [ "border-top-right-radius: 6px" ]);
          check "a positioned box's side" "inset-inline-start" "0" (Some [ "left: 0" ]));
      Testo.create "a pair: one value for both, or one each" (fun () ->
          check "both" "margin-inline" "auto" (Some [ "margin-left: auto"; "margin-right: auto" ]);
          check "each" "padding-block" "4px 8px" (Some [ "padding-top: 4px"; "padding-bottom: 8px" ]);
          check "a positioned box's" "inset-block" "0 10px" (Some [ "top: 0"; "bottom: 10px" ]));
      Testo.create "a border: its shorthand, and its parts" (fun () ->
          check "a side's shorthand" "border-block-end" "1px solid red" (Some [ "border-bottom: 1px solid red" ]);
          check "a pair's shorthand: the same on both" "border-inline" "1px solid red" (Some [ "border-left: 1px solid red"; "border-right: 1px solid red" ]);
          check "a side's width" "border-inline-start-width" "2px" (Some [ "border-left-width: 2px" ]);
          check "a pair's colour" "border-block-color" "red blue" (Some [ "border-top-color: red"; "border-bottom-color: blue" ]));
      Testo.create "a custom property's name is as written; any other, in lower case" (fun () ->
          let names text = List.map (fun (d : Css_syntax.declaration) -> d.name) (Css_syntax.parse_declarations text) in
          Alcotest.(check (list string)) "--bgColor is not --bgcolor" [ "--bgColor-default"; "--bgcolor-default"; "color"; "margin-top" ]
            (names "--bgColor-default: #fff; --bgcolor-default: #000; COLOR: red; Margin-Top: 0");
          (* and var(--bgColor-default) finds the first: GitHub's top bar is black, not what follows it *)
          let style text = Computed.compute { width = 800.; height = 600. } ~root_font_size:16. ~parent:Computed.initial (List.map (fun (d : Css_syntax.declaration) -> (d.name, d.value)) (Css_syntax.parse_declarations text)) in
          let c = (style "--bgColor-default: #000; --bgcolor-default: #fff; background-color: var(--bgColor-default)").background in
          Alcotest.(check (list int)) "black" [ 0; 0; 0 ] [ c.r; c.g; c.b ]);
      Testo.create "what is not logical is left" (fun () ->
          check "a physical side" "margin-top" "1px" None;
          check "all the corners" "border-radius" "6px" None;
          check "a physical corner" "border-top-left-radius" "6px" None;
          check "a shorthand" "border" "1px solid" None;
          check "another property" "display" "block" None);
    ]
