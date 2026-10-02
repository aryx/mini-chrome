(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Httpd.mli *)

let content_type (name : string) : string =
  match String.lowercase_ascii (Filename.extension name) with
  | ".html" | ".htm" -> "text/html; charset=utf-8"
  | ".css" -> "text/css"
  | ".js" | ".mjs" -> "text/javascript"
  | ".json" -> "application/json"
  | ".txt" | ".md" | ".ml" | ".mli" -> "text/plain; charset=utf-8"
  | ".svg" -> "image/svg+xml"
  | ".png" -> "image/png"
  | ".jpg" | ".jpeg" -> "image/jpeg"
  | ".gif" -> "image/gif"
  | ".ico" -> "image/x-icon"
  | ".wav" -> "audio/wav"
  | ".pdf" -> "application/pdf"
  | _ -> "application/octet-stream"

let escape (s : string) : string =
  String.concat "" (List.map (fun c -> match c with '&' -> "&amp;" | '<' -> "&lt;" | '>' -> "&gt;" | '"' -> "&quot;" | c -> String.make 1 c) (List.init (String.length s) (String.get s)))

(* %20 as a space; a + stays a + (a path, not a form's field) *)
let unescape (s : string) : string =
  let b = Buffer.create (String.length s) in
  let rec go i =
    if i < String.length s then
      match (s.[i], if i + 2 < String.length s then int_of_string_opt ("0x" ^ String.sub s (i + 1) 2) else None) with
      | '%', Some code -> Buffer.add_char b (Char.chr code); go (i + 3)
      | c, _ -> Buffer.add_char b c; go (i + 1)
  in
  go 0;
  Buffer.contents b

(* a name as a link's address: what a URL cannot hold as it is, as %XX *)
let quote (s : string) : string =
  String.concat "" (List.map (fun c -> match c with ' ' | '%' | '?' | '#' | '"' -> Printf.sprintf "%%%02X" (Char.code c) | c -> String.make 1 c) (List.init (String.length s) (String.get s)))

let page (status : int) (text : string) : Network.Http.response =
  Network.Http.response status ~content_type:"text/html; charset=utf-8"
    (Printf.sprintf "<!doctype html><title>%d %s</title><h1>%d %s</h1><p>%s</p>\n" status (Network.Http.reason status) status (Network.Http.reason status) (escape text))

(* a directory's page: what is in it, each a link, the directories
 * first *)
let listing (path : string) (dir : string) : Network.Http.response =
  let names = List.sort compare (Array.to_list (Sys.readdir dir)) in
  let is_dir n = Sys.is_directory (Filename.concat dir n) in
  let item n = let n = if is_dir n then n ^ "/" else n in Printf.sprintf "<li><a href=\"%s\">%s</a>\n" (escape (quote n)) (escape n) in
  let dirs, files = List.partition is_dir names in
  Network.Http.response 200 ~content_type:"text/html; charset=utf-8"
    (Printf.sprintf "<!doctype html><title>%s</title><h1>%s</h1>\n<ul>\n%s</ul>\n" (escape path) (escape path) (String.concat "" (List.map item (dirs @ files))))

let answer (caps : < Cap.open_in ; .. >) ~(root : string) (request : Network.Http.request) : Network.Http.response =
  let read file =
    let (_ : Cap.FS_.open_in) = caps#open_in file in
    In_channel.with_open_bin file In_channel.input_all
  in
  let target = match String.index_opt request.target '?' with Some i -> String.sub request.target 0 i | None -> request.target in
  let raw = unescape target in
  (* a/../b is b; more ".." than directories before them would go
   * above the root *)
  let above =
    let rec go depth parts = match parts with [] -> false | ".." :: rest -> depth = 0 || go (depth - 1) rest | ("" | ".") :: rest -> go depth rest | _ :: rest -> go (depth + 1) rest in
    go 0 (String.split_on_char '/' raw)
  in
  let path = Network.Url.remove_dot_segments raw in
  let file = root ^ path in
  if request.meth <> "GET" then page 405 (request.meth ^ " is not allowed here: only GET.")
  else if above || String.contains path '\000' || not (String.starts_with ~prefix:"/" path) then page 403 "Nothing above the directory served."
  else
    match (Sys.file_exists file, Sys.file_exists file && Sys.is_directory file) with
    | false, _ -> page 404 (path ^ " is not here.")
    | true, false -> ( try Network.Http.response 200 ~content_type:(content_type file) (read file) with Sys_error why -> page 403 why)
    | true, true ->
        if not (String.ends_with ~suffix:"/" path) then
          { (page 301 (path ^ "/")) with headers = [ ("Location", path ^ "/"); ("Content-Type", "text/html; charset=utf-8") ] }
        else
          let index = Filename.concat file "index.html" in
          if Sys.file_exists index then Network.Http.response 200 ~content_type:(content_type index) (read index) else listing path file

let listen (caps : < Cap.network ; .. >) ~(port : int) : Unix.file_descr * int =
  let (_ : Cap.Network.t) = caps#network "127.0.0.1" in
  let sock = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt sock Unix.SO_REUSEADDR true;
  Unix.bind sock (Unix.ADDR_INET (Unix.inet_addr_loopback, port));
  Unix.listen sock 16;
  (sock, match Unix.getsockname sock with Unix.ADDR_INET (_, p) -> p | _ -> port)

(* a request read from a connection, piece by piece, until it is whole
 * (or the client is gone, or it is too long to be one) *)
let read_request (fd : Unix.file_descr) : Network.Http.parsed_request =
  let buffer = Bytes.create 4096 and so_far = Buffer.create 1024 in
  let rec go () =
    match Network.Http.parse_request (Buffer.contents so_far) with
    | Incomplete when Buffer.length so_far < 1_000_000 -> (
        match Unix.read fd buffer 0 4096 with
        | 0 -> Network.Http.Bad "the connection closed before the request's end"
        | n -> Buffer.add_subbytes so_far buffer 0 n; go ())
    | Incomplete -> Bad "the request is too long"
    | r -> r
  in
  go ()

(* the key of a request that asks to become a WebSocket *)
let websocket_key (r : Network.Http.request) : string option =
  match Network.Http.header "Upgrade" r.headers with
  | Some u when String.lowercase_ascii u = "websocket" -> Network.Http.header "Sec-WebSocket-Key" r.headers
  | _ -> None

(* a WebSocket's server, the simplest: the handshake answered, then
 * each message sent back as it came, until the client closes (or
 * says nothing for a minute); how many it echoed *)
let echo (fd : Unix.file_descr) (key : string) : int =
  let send (s : string) = ignore (Unix.write_substring fd s 0 (String.length s)) in
  send (Network.Websocket.response ~key);
  Unix.setsockopt_float fd Unix.SO_RCVTIMEO 60.;
  let buffer = Bytes.create 4096 in
  let rec go (inbox : string) (count : int) : int =
    match Network.Websocket.decode inbox with
    | Frame (f, used) -> (
        let rest = String.sub inbox used (String.length inbox - used) in
        (* what the client masked comes back unmasked: a server's frames are *)
        match f.opcode with
        | Text | Binary -> send (Network.Websocket.encode f); go rest (count + 1)
        | Ping -> send (Network.Websocket.encode { f with opcode = Pong }); go rest count
        | Close -> send (Network.Websocket.encode f); count
        | Pong | Continuation -> go rest count)
    | Bad _ -> count
    | Incomplete -> (
        match Unix.read fd buffer 0 4096 with
        | 0 -> count
        | n -> go (inbox ^ Bytes.sub_string buffer 0 n) count)
  in
  go "" 0

let serve (caps : < Cap.open_in ; .. >) ~(root : string) ?(log = fun _ -> ()) (sock : Unix.file_descr) : 'a =
  (* a client that left before its answer: an error of the write, not
   * a signal that ends the program *)
  Sys.set_signal Sys.sigpipe Sys.Signal_ignore;
  let rec loop () =
    let fd, _ = Unix.accept sock in
    (* a client that says nothing does not hold the others for ever *)
    Unix.setsockopt_float fd Unix.SO_RCVTIMEO 5.;
    (try
       let request = read_request fd in
       match request with
       | Request (r, _, _) when websocket_key r <> None ->
           log (Printf.sprintf "%s %s 101, a WebSocket" r.meth r.target);
           let echoed = echo fd (Option.get (websocket_key r)) in
           log (Printf.sprintf "%s: closed, %d messages echoed" r.target echoed)
       | _ ->
           let said, (response : Network.Http.response) =
             match request with
             | Request (r, _, _) -> (r.meth ^ " " ^ r.target, answer caps ~root r)
             | Bad why -> ("?", page 400 why)
             | Incomplete -> ("?", page 400 "not a whole request")
           in
           let bytes = Network.Http.response_to_string response in
           ignore (Unix.write_substring fd bytes 0 (String.length bytes));
           log (Printf.sprintf "%s %d %d" said response.status (String.length response.body))
     with Unix.Unix_error _ | Sys_error _ -> ());
    (try Unix.close fd with Unix.Unix_error _ -> ());
    loop ()
  in
  loop ()
