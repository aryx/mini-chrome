(* Json: JSON read and written, for the browser's own files (the
   profile's Preferences).

   JSON is JavaScript's literals alone -- objects, arrays, strings,
   numbers, true, false, null -- so its text is cut by JavaScript's
   lexer (Js_lexer: the strings' escapes decoded, the numbers read), and
   only the grammar is here, a recursive descent of five rules. Being
   JavaScript's lexer, it also takes comments (// and /* */) and a comma
   before a closing bracket: a file fixed by hand may have them. What is
   written has neither, and any JSON reader takes it.

   Worked example (the tests'):

     { "colors": { "kernel": "#e08030" }, "depth": 2, "x": [true, null] }

     Object [ ("colors", Object [ ("kernel", String "#e08030") ]);
              ("depth", Number 2.); ("x", Array [ Bool true; Null ]) ]

   and written, a field or an item a line, two spaces deeper each level:

     {
       "colors": {
         "kernel": "#e08030"
       },
       "depth": 2,
       "x": [
         true,
         null
       ]
     }

   https://www.rfc-editor.org/rfc/rfc8259 *)

type t =
  | Null
  | Bool of bool
  | Number of float
  | String of string
  | Array of t list
  | Object of (string * t) list (* in the text's order *)

(* the value of a text, or what is wrong with it and on which line *)
val parse : string -> (t, string) result

(* a field of an object, if it is one and has it *)
val member : string -> t -> t option

(* a value's text, as above: [parse (to_string v)] is [Ok v]. A number
 * is written with the fewest digits that read back the same (0.9, not
 * 0.90000000000000002), a whole one without a point; one that JSON
 * cannot say (infinity, not a number) as null *)
val to_string : t -> string
