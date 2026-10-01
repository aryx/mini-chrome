(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_json.mli *)

let example : Json.t =
  Object [ ("colors", Object [ ("kernel", String "#e08030") ]); ("depth", Number 2.); ("x", Array [ Bool true; Null ]) ]

let written = {|{
  "colors": {
    "kernel": "#e08030"
  },
  "depth": 2,
  "x": [
    true,
    null
  ]
}|}

let json = Alcotest.testable (fun f v -> Format.pp_print_string f (Json.to_string v)) ( = )
let parsed = Alcotest.(result json string)

let tests =
  Testo.categorize "Json"
    [
      Testo.create "the worked example: read, written" (fun () ->
          Alcotest.(check parsed) "read" (Ok example) (Json.parse {|{ "colors": { "kernel": "#e08030" }, "depth": 2, "x": [true, null] }|});
          Alcotest.(check string) "written" written (Json.to_string example);
          Alcotest.(check parsed) "and read again" (Ok example) (Json.parse written);
          Alcotest.(check (option json)) "a field" (Some (Number 2.)) (Json.member "depth" example);
          Alcotest.(check (option json)) "not an object's" None (Json.member "depth" (Array [])));
      Testo.create "a file fixed by hand: comments, a last comma" (fun () ->
          Alcotest.(check parsed) "read" (Ok (Object [ ("a", Array [ Number 1.; Number (-2.) ]) ]))
            (Json.parse "{ // why\n \"a\": [1, -2,], /* and */ }"));
      Testo.create "strings and numbers read back the same" (fun () ->
          let v : Json.t =
            Array [ String "a \"quote\", a \\, a line\nand a tab\t, caf\xc3\xa9"; Number 0.9; Number 1.1; Number (-3.); Number 1e21; Number (1. /. 3.); Object []; Array [] ]
          in
          Alcotest.(check parsed) "the same" (Ok v) (Json.parse (Json.to_string v));
          Alcotest.(check string) "the fewest digits" "0.9" (Json.to_string (Number 0.9));
          Alcotest.(check string) "a whole number" "150" (Json.to_string (Number 150.));
          Alcotest.(check string) "not a number: null" "null" (Json.to_string (Number Float.nan));
          Alcotest.(check string) "an empty object" "{}" (Json.to_string (Object [])));
      Testo.create "the mistakes, with their line" (fun () ->
          Alcotest.(check parsed) "a brace lost" (Error "line 2: unexpected end of the text") (Json.parse "{ \"a\": {\n");
          Alcotest.(check bool) "a field not a string" true (Result.is_error (Json.parse "{ a: 1 }"));
          Alcotest.(check bool) "two values" true (Result.is_error (Json.parse "1 2")));
    ]
