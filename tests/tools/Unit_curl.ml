(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_curl.mli *)

(* the program run: its status, its output, its messages (the lines) *)
let curl caps (args : string list) : int * string * string list =
  let out = Buffer.create 256 and said = ref [] in
  let status = Curl.run caps ~print:(Buffer.add_string out) ~complain:(fun l -> said := l :: !said) args in
  (status, Buffer.contents out, List.rev !said)

let tests caps =
  let with_site f () = Testutil_httpd.with_server caps Testutil_httpd.site f in
  let index = List.assoc "index.html" Testutil_httpd.site in
  let lines (s : string) = List.filter (( <> ) "") (List.map String.trim (String.split_on_char '\n' s)) in
  Testo.categorize "Curl"
    [
      Testo.create "a URL's body; -i: its head first"
        (with_site (fun base ->
             Alcotest.(check (triple int string (list string))) "the body, nothing said" (0, index, []) (curl caps [ base ^ "/" ]);
             let _, out, _ = curl caps [ "-i"; base ^ "/notes/a.txt" ] in
             Alcotest.(check (list string)) "the status line, the headers, an empty line, the body"
               [ "HTTP/1.1 200 OK"; "Content-Type: text/plain; charset=utf-8"; "Content-Length: 7"; "Connection: close"; "a note" ]
               (lines out)));
      Testo.create "the worked example: a redirection, shown or followed"
        (with_site (fun base ->
             let _, out, _ = curl caps [ "-i"; base ^ "/notes" ] in
             Alcotest.(check (list string)) "not followed: the 301 and where it sends" [ "HTTP/1.1 301 Moved Permanently"; "Location: /notes/" ]
               (List.filteri (fun i _ -> i < 2) (lines out));
             let status, out, said = curl caps [ "-L"; "-v"; base ^ "/notes" ] in
             let heads = List.filter (fun l -> String.starts_with ~prefix:"> GET" l || String.starts_with ~prefix:"< HTTP" l) said in
             Alcotest.(check (list string)) "-L -v: each request and each answer"
               [ "> GET /notes HTTP/1.1"; "< HTTP/1.1 301 Moved Permanently"; "> GET /notes/ HTTP/1.1"; "< HTTP/1.1 200 OK" ] heads;
             Alcotest.(check bool) "the request's headers said too" true (List.mem "> Accept-Encoding: gzip, br, zstd" said);
             Alcotest.(check (pair int bool)) "and the listing printed" (0, true) (status, String.length out > 0 && String.sub out 0 15 = "<!doctype html>")));
      Testo.create "-f, -o, -d"
        (with_site (fun base ->
             let status, out, said = curl caps [ "-f"; base ^ "/nope" ] in
             Alcotest.(check (triple int string (list string))) "-f: a 404 is a failure, its page not printed" (22, "", [ "mini-curl: the server answered 404" ]) (status, out, said);
             let status, out, _ = curl caps [ base ^ "/nope" ] in
             Alcotest.(check (pair int bool)) "without it: the server's page, and 0" (0, true) (status, out <> "");
             let file = Filename.temp_file "mini-curl" ".html" in
             let status, out, _ = curl caps [ "-o"; file; base ^ "/" ] in
             Alcotest.(check (triple int string string)) "-o: the body in the file, nothing printed" (0, "", index) (status, out, In_channel.with_open_bin file In_channel.input_all);
             let _, _, said = curl caps [ "-v"; "-A"; "Lynx/2.8"; base ^ "/" ] in
             Alcotest.(check (pair bool bool)) "-A: the name it says" (true, false) (List.mem "> User-Agent: Lynx/2.8" said, List.mem "> User-Agent: elm_playground" said);
             let _, out, said = curl caps [ "-v"; "-d"; "a=1&b=2"; base ^ "/" ] in
             Alcotest.(check (pair bool bool)) "-d: a POST (which this server refuses)" (true, true)
               (List.mem "> POST / HTTP/1.1" said && List.mem "> Content-Length: 7" said, List.mem "< HTTP/1.1 405 Method Not Allowed" said && out <> "")));
      Testo.create "mistakes" (fun () ->
          let status, _, said = curl caps [] in
          Alcotest.(check (pair int int)) "no URL: the usage" (1, 1) (status, List.length said);
          let status, _, said = curl caps [ "-z"; "http://localhost/" ] in
          Alcotest.(check (pair int bool)) "a flag not known" (1, String.starts_with ~prefix:"mini-curl: -z: not a flag of mine" (List.hd said)) (status, true);
          let status, out, _ = curl caps [ "http://127.0.0.1:1/" ] in
          Alcotest.(check (pair int string)) "nobody listening" (1, "") (status, out));
    ]
