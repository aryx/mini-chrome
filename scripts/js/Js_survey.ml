(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Js_survey.mli *)

let read (file : string) : string = In_channel.with_open_bin file In_channel.input_all

(* the source's line [n] (from 1), cut to a screen's width *)
let line_of (source : string) (n : int) : string =
  match List.nth_opt (String.split_on_char '\n' source) (n - 1) with
  | Some l -> if String.length l > 110 then String.sub l 0 110 ^ " ..." else l
  | None -> ""

(* a message without what is the script's own in it (a name, a
 * number), so that the same mistake of two scripts counts as one *)
let kind (message : string) : string =
  let b = Buffer.create 64 in
  let quoted = ref false in
  String.iter
    (fun c ->
      if c = '"' || c = '\'' then (
        if not !quoted then Buffer.add_string b "\"..\"";
        quoted := not !quoted)
      else if not !quoted then Buffer.add_char b c)
    message;
  Buffer.contents b

let () =
  let files = List.tl (Array.to_list Sys.argv) in
  let counts : (string, int) Hashtbl.t = Hashtbl.create 16 in
  let count k = Hashtbl.replace counts k (1 + Option.value (Hashtbl.find_opt counts k) ~default:0) in
  List.iter
    (fun file ->
      let source = read file in
      Printf.printf "%-24s %9d bytes  " (Filename.basename file) (String.length source);
      match Js_parse.parse source with
      | Error (e : Js_parse.error) ->
          Printf.printf "PARSE line %d: %s\n      | %s\n" e.line e.message (String.trim (line_of source e.line));
          count ("parse: " ^ kind e.message)
      | Ok _ -> (
          let page = Html_tree.of_string "<!doctype html><html><head><title>survey</title></head><body></body></html>" in
          let t = Browser_script.create ~base:"http://survey.test/" page in
          match Browser_script.eval t source with
          | Ok _ -> (
              (* what it said on the console, its errors (uncaught in a callback) *)
              match List.filter (fun l -> String.length l > 5 && (String.sub l 0 5 = "Uncau" || String.sub l 0 4 = "Type" || String.sub l 0 4 = "Refe")) (Browser_script.console t) with
              | [] -> Printf.printf "ok\n"; count "ok"
              | errors -> Printf.printf "RUN  (on the console) %s\n" (List.hd (List.rev errors)); count ("run: " ^ kind (List.hd (List.rev errors))))
          | Error (e : Js_eval.error) ->
              Printf.printf "RUN  line %d: %s\n      | %s\n" e.line e.message (String.trim (line_of source e.line));
              count ("run: " ^ kind e.message)))
    files;
  print_newline ();
  List.iter (fun (k, n) -> Printf.printf "%3d  %s\n" n k) (List.sort (fun (_, a) (_, b) -> compare b a) (Hashtbl.fold (fun k n l -> (k, n) :: l) counts []))
