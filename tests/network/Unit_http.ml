(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_http.mli *)

let ok = function Ok x -> x | Error e -> Alcotest.fail e

(* the response's body, parsed from the status line, the headers and
 * what follows the empty line *)
let body_of (head : string list) (rest : string) : string =
  (ok (Http.parse_response (String.concat "\r\n" head ^ "\r\n\r\n" ^ rest))).body

(* Gzip.mli's worked example: "hi" in one stored block *)
let hi_gz = "\x1F\x8B\x08\x00\x00\x00\x00\x00\x00\xFF\x01\x02\x00\xFD\xFF\x68\x69\xAC\x2A\x93\xD8\x02\x00\x00\x00"

let wikipedia = "4\r\nWiki\r\n5\r\npedia\r\nE\r\n in\r\n\r\nchunks.\r\n0\r\n\r\n"

let tests =
  Testo.categorize "Http"
    [
      Testo.create "the request of the diagram" (fun () ->
          Alcotest.(check string) "bytes"
            "GET /images/turtle.gif HTTP/1.1\r\nHost: elm-lang.org\r\nUser-Agent: elm_playground\r\nAccept-Encoding: gzip, br, zstd\r\nConnection: close\r\n\r\n"
            (Http.request_to_string (Http.get ~host:"elm-lang.org" "/images/turtle.gif"));
          Alcotest.(check (option string)) "another name said, when one is given" (Some "Lynx/2.8")
            (Http.header "User-Agent" (Http.get ~agent:"Lynx/2.8" ~host:"a" "/").headers));
      Testo.create "the status line" (fun () ->
          Alcotest.(check (triple string int string)) "200" ("HTTP/1.1", 200, "OK") (ok (Http.parse_status_line "HTTP/1.1 200 OK"));
          Alcotest.(check (triple string int string))
            "a reason with spaces" ("HTTP/1.0", 404, "Not Found")
            (ok (Http.parse_status_line "HTTP/1.0 404 Not Found"));
          Alcotest.(check (triple string int string)) "no reason" ("HTTP/1.1", 204, "") (ok (Http.parse_status_line "HTTP/1.1 204"));
          Alcotest.(check bool) "not HTTP" true (Result.is_error (Http.parse_status_line "SSH-2.0-OpenSSH"));
          Alcotest.(check bool) "a 4-digit status" true (Result.is_error (Http.parse_status_line "HTTP/1.1 2000 OK")));
      Testo.create "the worked example: Wikipedia's chunked body" (fun () ->
          Alcotest.(check string) "joined" "Wikipedia in\r\n\r\nchunks." (ok (Http.dechunk wikipedia)));
      Testo.create "chunk extensions and trailers ignored" (fun () ->
          Alcotest.(check string) "joined" "Wikipedia"
            (ok (Http.dechunk "4;name=value\r\nWiki\r\n5\r\npedia\r\n0\r\nExpires: never\r\n\r\n")));
      Testo.create "a chunked body cut short" (fun () ->
          Alcotest.(check bool) "inside a chunk" true (Result.is_error (Http.dechunk "a\r\nWiki"));
          Alcotest.(check bool) "before the last chunk" true (Result.is_error (Http.dechunk "4\r\nWiki\r\n")));
      Testo.create "the four ways a body ends" (fun () ->
          Alcotest.(check string) "1. a 304 has none" "" (body_of [ "HTTP/1.1 304 Not Modified"; "Content-Length: 5" ] "hello");
          Alcotest.(check string) "2. chunked, before Content-Length" "Wikipedia in\r\n\r\nchunks."
            (body_of [ "HTTP/1.1 200 OK"; "Content-Length: 3"; "transfer-encoding: Chunked" ] wikipedia);
          Alcotest.(check string) "3. Content-Length" "hello" (body_of [ "HTTP/1.1 200 OK"; "content-length: 5" ] "hello, and more");
          Alcotest.(check string) "4. until closed" "hello, and more" (body_of [ "HTTP/1.1 200 OK" ] "hello, and more"));
      Testo.create "a body shorter than its Content-Length" (fun () ->
          Alcotest.(check bool) "truncated" true
            (Result.is_error (Http.parse_response "HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\nhello")));
      Testo.create "headers: case-insensitive, trimmed, lone LFs" (fun () ->
          let r = ok (Http.parse_response "HTTP/1.1 301 Moved\nLOCATION:   /new  \n\n") in
          Alcotest.(check (option string)) "Location" (Some "/new") (Http.header "Location" r.headers);
          Alcotest.(check bool) "a redirect" true (Http.is_redirect r.status));
      Testo.create "Content-Encoding: gzip, the worked example" (fun () ->
          Alcotest.(check string) "Content-Length, the compressed bytes'" "hi" (body_of [ "HTTP/1.1 200 OK"; "Content-Encoding: gzip"; "Content-Length: 25" ] (hi_gz ^ "more"));
          Alcotest.(check string) "until the connection closes; x-gzip" "hi" (body_of [ "HTTP/1.1 200 OK"; "content-encoding: X-GZIP" ] hi_gz);
          let chunked = Printf.sprintf "a\r\n%s\r\nf\r\n%s\r\n0\r\n\r\n" (String.sub hi_gz 0 10) (String.sub hi_gz 10 15) in
          Alcotest.(check string) "under the chunks" "hi" (body_of [ "HTTP/1.1 200 OK"; "Content-Encoding: gzip"; "Transfer-Encoding: chunked" ] chunked);
          Alcotest.(check string) "identity" "hi" (body_of [ "HTTP/1.1 200 OK"; "Content-Encoding: identity" ] "hi");
          Alcotest.(check string) "a 304 has no body to decompress" "" (body_of [ "HTTP/1.1 304 Not Modified"; "Content-Encoding: gzip" ] "");
          let r = ok (Http.parse_response ("HTTP/1.1 200 OK\r\nContent-Encoding: gzip\r\nContent-Length: 25\r\n\r\n" ^ hi_gz)) in
          Alcotest.(check (option string)) "the headers are the server's" (Some "25") (Http.header "Content-Length" r.headers));
      Testo.create "Content-Encoding: br, zstd" (fun () ->
          let of_hex h = String.init (String.length h / 2) (fun i -> Char.chr (int_of_string ("0x" ^ String.sub h (2 * i) 2))) in
          (* the same three lines, by "brotli" and by "zstd" *)
          let text = String.concat "" (List.init 3 (fun _ -> "<p>Hello, compressed web. The quick brown fox jumps over the lazy dog, and the dog does not mind.</p>\n")) in
          let br = of_hex "1b3101288c94ee3ea2648424b3aa1b6ab3cca809739e801407a1415ce6f2eae480f9bf5dc2a02581e612b8170da71c71ab2489aebfbce8f0b3d576ec41b56f5a64ce88d4cc293c8e3904c7d27f81ce0b41870e6ec5fa0d28" in
          let zstd = of_hex "28b52ffd04580503001206151a80491d803d21bb914c721730232862df19d02ad66d1b0e3a17180024038771e8ac3ec736ffcafc0e9326e657c5225175f39419f1b65c50a189138ad19952c3e24087ba19d4501cf5dc9a59ae2f4d57ca02248f02009369a056aa9d666e806a95" in
          Alcotest.(check string) "Brotli, with its dictionary's words" text (body_of [ "HTTP/1.1 200 OK"; "Content-Encoding: br" ] br);
          Alcotest.(check string) "Zstandard" text (body_of [ "HTTP/1.1 200 OK"; "Content-Encoding: zstd"; Printf.sprintf "Content-Length: %d" (String.length zstd) ] zstd);
          Alcotest.(check bool) "a stream cut short is an error, not an exception" true
            (Result.is_error (Http.parse_response ("HTTP/1.1 200 OK\r\nContent-Encoding: br\r\n\r\n" ^ String.sub br 0 20))));
      Testo.create "refused: folded headers, another coding, a corrupt gzip" (fun () ->
          Alcotest.(check bool) "folded" true
            (Result.is_error (Http.parse_response "HTTP/1.1 200 OK\r\nX-A: 1\r\n  2\r\n\r\n"));
          Alcotest.(check bool) "space before the colon" true
            (Result.is_error (Http.parse_response "HTTP/1.1 200 OK\r\nX-A : 1\r\n\r\n"));
          Alcotest.(check bool) "a coding we do not ask for" true
            (Result.is_error (Http.parse_response "HTTP/1.1 200 OK\r\nContent-Encoding: compress\r\n\r\n..."));
          Alcotest.(check bool) "not a gzip stream" true
            (Result.is_error (Http.parse_response "HTTP/1.1 200 OK\r\nContent-Encoding: gzip\r\n\r\n..."));
          Alcotest.(check bool) "a gzip stream cut short" true
            (Result.is_error (Http.parse_response ("HTTP/1.1 200 OK\r\nContent-Encoding: gzip\r\n\r\n" ^ String.sub hi_gz 0 14))));
      Testo.create "the server's side: a request, whole or not yet" (fun () ->
          let show (p : Http.parsed_request) =
            match p with
            | Incomplete -> "incomplete"
            | Bad _ -> "bad"
            | Request (r, body, used) -> Printf.sprintf "%s %s body=%S used=%d" r.meth r.target body used
          in
          let check what s expected = Alcotest.(check string) what expected (show (Http.parse_request s)) in
          check "no empty line yet" "GET / HTTP/1.1\r\nHost: a\r\n" "incomplete";
          check "whole" "GET / HTTP/1.1\r\nHost: a\r\n\r\n" "GET / body=\"\" used=27";
          check "a body to come" "POST /f HTTP/1.1\r\nContent-Length: 3\r\n\r\nab" "incomplete";
          check "the body come, and more" "POST /f HTTP/1.1\r\nContent-Length: 3\r\n\r\nabcGET" "POST /f body=\"abc\" used=42";
          check "not a request line" "HELLO\r\n\r\n" "bad";
          check "a bad length" "POST / HTTP/1.1\r\nContent-Length: x\r\n\r\n" "bad");
      Testo.create "the server's side: a response, read back" (fun () ->
          let bytes = Http.response_to_string (Http.response 404 ~content_type:"text/html" "<p>no") in
          Alcotest.(check string)
            "the bytes"
            "HTTP/1.1 404 Not Found\r\nContent-Type: text/html\r\nContent-Length: 5\r\nConnection: close\r\n\r\n<p>no"
            bytes;
          let r = ok (Http.parse_response bytes) in
          Alcotest.(check (pair int string)) "parsed back" (404, "<p>no") (r.status, r.body));
    ]
