(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_httpd.mli *)

let tests caps =
  let root = lazy (Testutil_httpd.directory (Testutil_httpd.site @ [ ("notes/b c.txt", "spaced"); ("pic.png", "\137PNG") ])) in
  (* a GET's status, its Content-Type or Location, and its body *)
  let get ?(meth = "GET") (target : string) : int * string * string =
    let r = Httpd.answer caps ~root:(Lazy.force root) { (Http.get ~host:"localhost" target) with meth } in
    let said = match Http.header "Location" r.headers with Some l -> l | None -> Option.value (Http.header "Content-Type" r.headers) ~default:"" in
    (r.status, said, r.body)
  in
  let check what target expected = Alcotest.(check (triple int string string)) what expected (get target) in
  let status what ?meth target expected = let s, _, _ = get ?meth target in Alcotest.(check int) what expected s in
  let contains what target (part : string) =
    let _, _, body = get target in
    let rec at i = i + String.length part <= String.length body && (String.sub body i (String.length part) = part || at (i + 1)) in
    Alcotest.(check bool) what true (at 0)
  in
  Testo.categorize "Httpd"
    [
      Testo.create "the worked example: a file, a directory" (fun () ->
          check "/: its index.html" "/" (200, "text/html; charset=utf-8", List.assoc "index.html" Testutil_httpd.site);
          check "a file, its type from its extension" "/notes/a.txt" (200, "text/plain; charset=utf-8", "a note\n");
          contains "a directory with no index: its files, each a link" "/notes/" "<li><a href=\"a.txt\">a.txt</a>";
          contains "a name with a space, as an address" "/notes/" "<a href=\"b%20c.txt\">b c.txt</a>";
          let s, location, _ = get "/notes" in
          Alcotest.(check (pair int string)) "a directory without its /: sent to it" (301, "/notes/") (s, location));
      Testo.create "the target read: a query, %20, dots" (fun () ->
          check "a query dropped" "/notes/a.txt?v=2" (200, "text/plain; charset=utf-8", "a note\n");
          check "%20 is a space" "/notes/b%20c.txt" (200, "text/plain; charset=utf-8", "spaced");
          check "a/../b is b" "/notes/../notes/./a.txt" (200, "text/plain; charset=utf-8", "a note\n");
          status "nothing above the root" "/../etc/passwd" 403;
          status "however it is written" "/notes/../../etc/passwd" 403;
          status "%2e%2e too" "/%2e%2e/etc/passwd" 403);
      Testo.create "what is not there, what is not allowed" (fun () ->
          status "no such file" "/nope.html" 404;
          contains "said in a page" "/nope.html" "404 Not Found";
          status "only GET" ~meth:"POST" "/" 405;
          status "and DELETE" ~meth:"DELETE" "/notes/a.txt" 405);
      Testo.create "a WebSocket: the echo, by Websocket_client" (fun () ->
          Testutil_httpd.with_server caps Testutil_httpd.site (fun base ->
              let url = "ws" ^ String.sub base 4 (String.length base - 4) ^ "/echo" in
              match Websocket_client.connect ~origin:base caps url with
              | Error why -> Alcotest.fail why
              | Ok socket ->
                  (* said before it is open: kept, and sent then *)
                  Websocket_client.send socket "hello";
                  let rec until (wanted : Websocket_client.event -> bool) (seen : Websocket_client.event list) (tries : int) =
                    if List.exists wanted seen || tries = 0 then seen
                    else (
                      Unix.sleepf 0.01;
                      until wanted (seen @ Websocket_client.step socket) (tries - 1))
                  in
                  let seen = until (fun e -> e = Message "hello") [] 300 in
                  Alcotest.(check bool) "opened, then our message back" true (seen = [ Opened; Message "hello" ]);
                  let big = String.make 70000 'x' in
                  Websocket_client.send socket big;
                  Alcotest.(check bool) "a message of 70,000 bytes, its length in 8 bytes" true (until (fun e -> e = Message big) [] 300 = [ Message big ]);
                  Websocket_client.close ~code:1000 ~reason:"done" socket;
                  Alcotest.(check bool) "closed by both: clean, our code and reason back" true
                    (until (fun e -> match e with Closed _ -> true | _ -> false) [] 300 = [ Closed { code = 1000; reason = "done"; clean = true } ]);
                  Alcotest.(check bool) "nothing after" true (Websocket_client.step socket = []));
          Testutil_httpd.with_server caps Testutil_httpd.site (fun base ->
              match Websocket_client.connect caps ("ws://127.0.0.1:1/") with
              | Ok _ -> Alcotest.fail "connected to nothing"
              | Error _ -> ignore base));
      Testo.create "content types" (fun () ->
          Alcotest.(check (list string)) "by the extension, whatever its case; unknown: bytes"
            [ "text/html; charset=utf-8"; "text/css"; "text/javascript"; "image/png"; "image/jpeg"; "application/octet-stream" ]
            (List.map Httpd.content_type [ "a.html"; "s.CSS"; "x/app.js"; "p.png"; "photo.JPG"; "Makefile" ]);
          let _, typ, body = get "/pic.png" in
          Alcotest.(check (pair string int)) "bytes as they are" ("image/png", 4) (typ, String.length body));
    ]
