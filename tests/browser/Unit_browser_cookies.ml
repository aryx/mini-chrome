(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_browser_cookies.mli *)

let url (s : string) : Url.t = match Url.parse s with Ok u -> u | Error e -> Alcotest.fail e
let now = 1623147494.

(* a jar: a language kept a day, a session, a signed-in one kept an hour *)
let jar : Cookie.jar =
  [] |> Cookie.store ~now (url "https://www.example.com/") "lang=en-US; Path=/; Domain=example.com; Max-Age=86400"
  |> Cookie.store ~now (url "https://www.example.com/") "seen=1"
  |> Cookie.store ~now (url "https://www.example.com/account/") "SID=31d4d96e407aad42; Secure; HttpOnly; Max-Age=3600"

let text = {|[
  {
    "name": "SID",
    "value": "31d4d96e407aad42",
    "domain": "www.example.com",
    "host_only": true,
    "path": "/account",
    "expires": 1623151094,
    "secure": true,
    "http_only": true,
    "created": 1623147494
  },
  {
    "name": "lang",
    "value": "en-US",
    "domain": "example.com",
    "host_only": false,
    "path": "/",
    "expires": 1623233894,
    "secure": false,
    "http_only": false,
    "created": 1623147494
  }
]
|}

let names (j : Cookie.jar) = List.map (fun (c : Cookie.cookie) -> c.name) j

let tests (caps : < Cap.open_in ; Cap.open_out ; .. >) =
  Testo.categorize "Browser_cookies"
    [
      Testo.create "the worked example: the file's text, and back; a session's cookie is not written" (fun () ->
          Alcotest.(check string) "written" text (Browser_cookies.to_string jar);
          match Browser_cookies.of_string text with
          | Ok read ->
              Alcotest.(check (list string)) "the two with a date" [ "SID"; "lang" ] (names read);
              Alcotest.(check bool) "as they were" true (read = List.filter (fun (c : Cookie.cookie) -> c.expires <> None) jar)
          | Error e -> Alcotest.fail e);
      Testo.create "not a list of cookies: said; a cookie without a name: left out" (fun () ->
          Alcotest.(check bool) "an object" true (Result.is_error (Browser_cookies.of_string "{}"));
          Alcotest.(check bool) "not JSON" true (Result.is_error (Browser_cookies.of_string "cookies"));
          Alcotest.(check (result (list string) string)) "one of two" (Ok [ "a" ])
            (Result.map names (Browser_cookies.of_string {|[ {"name": "a", "value": "1", "domain": "x.org", "path": "/", "expires": 99}, {"value": "2"} ]|})));
      Testo.create "the file: none yet, written, read; what is past its date left out" (fun () ->
          let dir = Filename.concat (Filename.get_temp_dir_name ()) (Printf.sprintf "mini-chrome-cookies-%d" (Unix.getpid ())) in
          Fun.protect
            ~finally:(fun () -> List.iter (fun f -> try Sys.remove (Filename.concat dir f) with Sys_error _ -> ()) [ "Cookies"; "Cookies.tmp" ]; try Sys.rmdir dir with Sys_error _ -> ())
            (fun () ->
              Alcotest.(check (result (list string) string)) "no file yet: none" (Ok []) (Result.map names (Browser_cookies.load caps ~now ~dir));
              Alcotest.(check (result unit string)) "written, its directory made" (Ok ()) (Browser_cookies.save caps ~dir jar);
              Alcotest.(check int) "its owner's alone" 0o600 ((Unix.stat (Filename.concat dir "Cookies")).st_perm);
              Alcotest.(check (result (list string) string)) "read" (Ok [ "SID"; "lang" ]) (Result.map names (Browser_cookies.load caps ~now ~dir));
              Alcotest.(check (result (list string) string)) "two hours later: the hour's one is gone" (Ok [ "lang" ])
                (Result.map names (Browser_cookies.load caps ~now:(now +. 7200.) ~dir))));
      Testo.create "about:cookies: the jar as a page" (fun () ->
          let page = Browser_cookies.page ~now jar in
          let has s = Alcotest.(check bool) s true (let n = String.length s in let rec at i = i + n <= String.length page && (String.sub page i n = s || at (i + 1)) in at 0) in
          has "<h2>3 kept</h2>";
          has "<code>lang</code>";
          has "example.com <small>and under it</small>";
          has "the session";
          has "Secure, HttpOnly";
          Alcotest.(check bool) "an empty jar says so" true (String.length (Browser_cookies.page ~now []) < String.length page));
      Testo.create "document.cookie: the page's script reads the jar, and sets a cookie in it" (fun () ->
          let box = Cookie_jar.create () and page = url "http://x.org/a/page.html" in
          Cookie_jar.received box page [ ("Set-Cookie", "sid=42; HttpOnly"); ("Set-Cookie", "lang=en") ];
          let cookies = ((fun () -> Cookie_jar.script_cookies box page), fun v -> Cookie_jar.set_from_script box page v) in
          let html = {|<p id=x></p><script>document.cookie = "theme=dark; Path=/"; document.getElementById("x").textContent = document.cookie</script>|} in
          let t = Browser_script.create ~base:"http://x.org/a/page.html" ~cookies (Html_tree.of_string html) in
          Browser_script.run_scripts t;
          let said = match Dom.find_all "p" (Browser_script.tree t) with p :: _ -> Dom.text_content p | [] -> "" in
          Alcotest.(check string) "what the script saw: not the HttpOnly one, and its own" "lang=en; theme=dark" said;
          Alcotest.(check (option string)) "what the server will be sent" (Some "sid=42; lang=en; theme=dark") (Cookie_jar.header box page);
          Alcotest.(check int) "written twice: the answer's two at once, the script's" 2 (Cookie_jar.changes box));
    ]
