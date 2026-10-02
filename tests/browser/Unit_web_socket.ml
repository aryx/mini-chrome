(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_web_socket.mli *)

(* a page at http://site.test/app/ whose script is [script] *)
let page (script : string) : Browser_script.t =
  let t = Browser_script.create ~base:"http://site.test/app/" (Html_tree.of_string ("<body><script>var seen = [];\n" ^ script ^ "</script></body>")) in
  Browser_script.run_scripts t;
  t

let value (t : Browser_script.t) (s : string) : string = match Browser_script.eval t s with Ok v -> Js_value.display v | Error e -> "error: " ^ e.message

(* what the page's sockets asked, as words *)
let asks (t : Browser_script.t) : string list =
  List.map
    (fun (a : Script_types.socket_ask) ->
      match a with
      | Socket_open (id, url, origin) -> Printf.sprintf "open %d %s from %s" id url origin
      | Socket_send (id, message) -> Printf.sprintf "send %d %s" id message
      | Socket_close (id, code, reason) -> Printf.sprintf "close %d %d %S" id code reason)
    (Browser_script.take_socket_asks t)

let strings = Alcotest.(list string)

let tests =
  Testo.categorize "WebSocket"
    [
      Testo.create "the worked example: opened, a message each way, closed" (fun () ->
          let t =
            page
              {|const s = new WebSocket("ws://127.0.0.1:8000/echo");
                s.onopen = () => { seen.push("open " + s.readyState); s.send("hello") };
                s.onmessage = e => { seen.push(e.data + " from " + e.origin); s.close() };
                s.onclose = e => seen.push("closed " + e.code + " " + e.wasClean + " " + s.readyState);
                seen.push("the script goes on, readyState " + s.readyState)|}
          in
          Alcotest.check strings "an ask for the browser, with the page's origin" [ "open 1 ws://127.0.0.1:8000/echo from http://site.test" ] (asks t);
          Alcotest.(check string) "nothing yet" {|["the script goes on, readyState 0"]|} (value t "seen");
          Alcotest.(check bool) "the connection opened: told" true (Browser_script.socket_event t 1 Opened);
          Alcotest.check strings "onopen sent" [ "send 1 hello" ] (asks t);
          ignore (Browser_script.socket_event t 1 (Message "hello"));
          Alcotest.check strings "onmessage closed" [ {|close 1 1000 ""|} ] (asks t);
          Alcotest.(check string) "closing" "2" (value t "s.readyState");
          ignore (Browser_script.socket_event t 1 (Closed { code = 1000; reason = ""; clean = true }));
          Alcotest.(check string) "the events in order"
            {|["the script goes on, readyState 0", "open 1", "hello from ws://127.0.0.1:8000", "closed 1000 true 3"]|} (value t "seen");
          Alcotest.(check bool) "closed: the page has no such socket any more" false (Browser_script.socket_event t 1 (Message "late"));
          Alcotest.(check string) "and nothing more is said" "4" (value t "seen.length"));
      Testo.create "addresses: ws, wss, a page's own kind; what is not one" (fun () ->
          let t =
            page
              {|new WebSocket("wss://chat.test/room?id=7"); new WebSocket("/live"); new WebSocket("https://other.test/x");
                try { new WebSocket("mailto:someone@site.test") } catch (e) { seen.push(e.name) }
                try { WebSocket("ws://site.test/") } catch (e) { seen.push(e.name) }
                seen.push([WebSocket.CONNECTING, WebSocket.OPEN, WebSocket.CLOSING, WebSocket.CLOSED].join())|}
          in
          Alcotest.check strings "http is ws, https wss, a path the page's server"
            [ "open 1 wss://chat.test/room?id=7 from http://site.test"; "open 2 ws://site.test/live from http://site.test"; "open 3 wss://other.test/x from http://site.test" ]
            (asks t);
          Alcotest.(check string) "refused, and the constants" {|["SyntaxError", "TypeError", "0,1,2,3"]|} (value t "seen"));
      Testo.create "send too early, an error, listeners, two sockets" (fun () ->
          let t =
            page
              {|const a = new WebSocket("ws://a.test/"), b = new WebSocket("ws://b.test/");
                try { a.send("too early") } catch (e) { seen.push(e.name) }
                const heard = e => seen.push("a heard " + e.data);
                a.addEventListener("message", heard); a.addEventListener("message", e => seen.push("and again " + (e.target === a)));
                b.onerror = e => seen.push("b " + e.type); b.onclose = e => seen.push("b closed " + e.code + " " + e.wasClean);
                function quiet() { a.removeEventListener("message", heard) }|}
          in
          ignore (asks t);
          ignore (Browser_script.socket_event t 2 (Failed "can't reach b.test"));
          ignore (Browser_script.socket_event t 2 (Closed { code = 1006; reason = ""; clean = false }));
          ignore (Browser_script.socket_event t 1 Opened);
          ignore (Browser_script.socket_event t 1 (Message "one"));
          ignore (Browser_script.eval t "quiet()");
          ignore (Browser_script.socket_event t 1 (Message "two"));
          Alcotest.(check string) "each socket its own events"
            {|["InvalidStateError", "b error", "b closed 1006 false", "a heard one", "and again true", "and again true"]|} (value t "seen");
          ignore (Browser_script.eval t "b.send('to nobody'); b.close(); a.close(4000, 'done')");
          Alcotest.check strings "a closed socket says and asks nothing; a close's code and reason" [ {|close 1 4000 "done"|} ] (asks t));
    ]
