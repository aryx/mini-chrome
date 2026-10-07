(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Json.mli *)

type t = Null | Bool of bool | Number of float | String of string | Array of t list | Object of (string * t) list

exception Bad of int * string

(* value := object | array | string | number | - number | true | false | null
 * object := { (string : value ,)* }   array := [ (value ,)* ] *)
let parse (text : string) : (t, string) result =
  match Js_lexer.tokenize text with
  | exception Js_lexer.Error (line, msg) -> Error (Printf.sprintf "line %d: %s" line msg)
  | tokens -> (
      let toks = ref tokens in
      let peek () : Js_lexer.token = match !toks with t :: _ -> t | [] -> { kind = Eof; line = 0; newline_before = false; at = 0 } in
      let next () = let t = peek () in (toks := match !toks with _ :: r -> r | [] -> []); t in
      (* the end said in words (a brace lost in a file fixed by hand) *)
      let fail (t : Js_lexer.token) = raise (Bad (t.line, "unexpected " ^ if t.kind = Eof then "end of the text" else Js_lexer.to_string t.kind)) in
      let expect p = let t = next () in if t.kind <> Punct p then fail t in
      (* the items up to [close], a comma after each but maybe the last *)
      let items close item =
        let out = ref [] in
        while (peek ()).kind <> Punct close do
          out := item () :: !out;
          if (peek ()).kind <> Punct close then expect ","
        done;
        ignore (next ());
        List.rev !out
      in
      let rec value () : t =
        let t = next () in
        match t.kind with
        | Punct "{" ->
            Object
              (items "}" (fun () ->
                   let k = next () in
                   match k.kind with
                   | String s -> expect ":"; (s, value ())
                   | _ -> fail k))
        | Punct "[" -> Array (items "]" value)
        | Punct "-" -> ( match (next ()).kind with Number n -> Number (-.n) | _ -> fail t)
        | String s -> String s
        | Number n -> Number n
        | Keyword "true" -> Bool true
        | Keyword "false" -> Bool false
        | Keyword "null" -> Null
        | _ -> fail t
      in
      match
        let v = value () in
        let t = next () in
        if t.kind <> Eof then fail t;
        v
      with
      | v -> Ok v
      | exception Bad (line, msg) -> Error (Printf.sprintf "line %d: %s" line msg))

let member (k : string) (v : t) : t option = match v with Object fields -> List.assoc_opt k fields | _ -> None

(*****************************************************************************)
(* Writing *)
(*****************************************************************************)

(* not in elm-playground's Json, which only reads *)
let quote (s : string) : string =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"';
  String.iter
    (fun c ->
      match c with
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | '\n' -> Buffer.add_string b "\\n"
      | c when Char.code c < 0x20 -> Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
      | c -> Buffer.add_char b c)
    s;
  Buffer.add_char b '"';
  Buffer.contents b

let number (n : float) : string =
  if Float.is_nan n || Float.abs n = Float.infinity then "null"
  else if Float.is_integer n && Float.abs n < 1e15 then Printf.sprintf "%.0f" n
  else
    let short = Printf.sprintf "%.15g" n in
    if float_of_string short = n then short else Printf.sprintf "%.17g" n

let to_string (v : t) : string =
  let rec print (indent : string) (v : t) : string =
    let inner = indent ^ "  " in
    let block (opening : string) (closing : string) (items : string list) : string =
      if items = [] then opening ^ closing
      else opening ^ "\n" ^ String.concat ",\n" (List.map (fun i -> inner ^ i) items) ^ "\n" ^ indent ^ closing
    in
    match v with
    | Null -> "null"
    | Bool b -> string_of_bool b
    | Number n -> number n
    | String s -> quote s
    | Array items -> block "[" "]" (List.map (print inner) items)
    | Object fields -> block "{" "}" (List.map (fun (k, v) -> quote k ^ ": " ^ print inner v) fields)
  in
  print "" v
