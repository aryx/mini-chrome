(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_http_cache.mli *)

let response ?(status = 200) (headers : Http.header list) : Http.response = { version = "HTTP/1.1"; status; reason = "OK"; headers; body = "body" }
let near = Alcotest.float 1e-6

let tests =
  Testo.categorize "Http_cache"
    [
      Testo.create "may it be kept" (fun () ->
          let kept ?status headers = Http_cache.storable (response ?status headers) in
          Alcotest.(check bool) "a lifetime" true (kept [ ("Cache-Control", "public, max-age=31536000, immutable") ]);
          Alcotest.(check bool) "private: this cache is one person's" true (kept [ ("Cache-Control", "private, max-age=60") ]);
          Alcotest.(check bool) "no lifetime but a validator: kept, to ask about" true (kept [ ("Cache-Control", "max-age=0, must-revalidate"); ("ETag", {|W/"a79"|}) ]);
          Alcotest.(check bool) "no-store" false (kept [ ("Cache-Control", "no-cache, no-store"); ("ETag", {|"x"|}) ]);
          Alcotest.(check bool) "neither a lifetime nor a validator" false (kept [ ("Content-Type", "text/html") ]);
          Alcotest.(check bool) "Vary: Accept-Encoding" true (kept [ ("Cache-Control", "max-age=60"); ("Vary", "Accept-Encoding") ]);
          Alcotest.(check bool) "Vary on another header" false (kept [ ("Cache-Control", "max-age=60"); ("Vary", "Accept-Encoding, Cookie") ]);
          Alcotest.(check bool) "a 404" false (kept ~status:404 [ ("Cache-Control", "max-age=60") ]));
      Testo.create "the lifetime, and fresh" (fun () ->
          let life headers = Http_cache.lifetime ~stored:1000. headers in
          Alcotest.check near "the worked example: max-age less the Age it came with" 500. (life [ ("Cache-Control", "max-age=600"); ("Age", "100") ]);
          Alcotest.check near "Expires less Date" 3600.
            (life [ ("Date", "Wed, 09 Jun 2021 10:18:14 GMT"); ("Expires", "Wed, 09 Jun 2021 11:18:14 GMT") ]);
          Alcotest.check near "max-age over Expires" 60. (life [ ("Expires", "Wed, 09 Jun 2021 11:18:14 GMT"); ("cache-control", "Max-Age=60") ]);
          Alcotest.check near "no-cache: none" 0. (life [ ("Cache-Control", "no-cache, max-age=600") ]);
          Alcotest.check near "nothing said: none" 0. (life [ ("ETag", {|"x"|}) ]);
          let copy : Http_cache.entry = { url = "https://x.org/a.js"; stored = 1000.; response = response [ ("Cache-Control", "max-age=600"); ("Age", "100") ] } in
          Alcotest.(check (pair bool bool)) "fresh until 1500" (true, false) (Http_cache.fresh ~now:1499. copy, Http_cache.fresh ~now:1500. copy));
      Testo.create "asked about: the validators, and the copy after a 304" (fun () ->
          let copy : Http_cache.entry =
            { url = "https://x.org/"; stored = 1000.; response = response [ ("ETag", {|"a79"|}); ("Last-Modified", "Thu, 01 Oct 2026 13:01:19 GMT"); ("Cache-Control", "max-age=0"); ("Age", "7"); ("Content-Type", "text/html") ] }
          in
          Alcotest.(check (list (pair string string))) "If-None-Match, If-Modified-Since"
            [ ("If-None-Match", {|"a79"|}); ("If-Modified-Since", "Thu, 01 Oct 2026 13:01:19 GMT") ] (Http_cache.validators copy);
          let after = Http_cache.revalidated ~now:2000. copy { (response ~status:304 [ ("cache-control", "max-age=60"); ("ETag", {|"a79"|}) ]) with body = "" } in
          Alcotest.(check (list (pair string string))) "the 304's headers over the copy's; its Age gone"
            [ ("cache-control", "max-age=60"); ("ETag", {|"a79"|}); ("Last-Modified", "Thu, 01 Oct 2026 13:01:19 GMT"); ("Content-Type", "text/html") ] after.response.headers;
          Alcotest.(check (pair int string)) "the copy's status and body" (200, "body") (after.response.status, after.response.body);
          Alcotest.(check bool) "fresh again, from now" true (Http_cache.fresh ~now:2059. after && not (Http_cache.fresh ~now:2060. after)));
      Testo.create "a copy as a file's text, and back" (fun () ->
          let copy : Http_cache.entry =
            { url = "https://x.org/a?b=1"; stored = 1623233894.; response = { (response [ ("Content-Type", "text/css"); ("ETag", {|"x:y"|}) ]) with body = "a { }\n\n\x00b { }\n" } }
          in
          let text = Http_cache.to_string copy in
          Alcotest.(check string) "its head" "mini-chrome cache 1\nhttps://x.org/a?b=1\n1623233894\n200\nContent-Type: text/css\nETag: \"x:y\"\n\n" (String.sub text 0 (String.length text - 14));
          (match Http_cache.of_string text with
          | Some back -> Alcotest.(check bool) "the same copy" true (back.url = copy.url && back.stored = copy.stored && back.response.headers = copy.response.headers && back.response.body = copy.response.body)
          | None -> Alcotest.fail "not read back");
          Alcotest.(check bool) "another file is not a copy" true (Http_cache.of_string "hello\n\nworld" = None));
    ]
