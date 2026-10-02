(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Websocket_client.mli *)

type event = Opened | Message of string | Closed of { code : int; reason : string; clean : bool } | Failed of string

type transport = Plain of Unix.file_descr | Secure of Tls_client.t
type state = Handshaking | Open | Closing | Done

type t = {
  transport : transport;
  key : string;
  mutable state : state;
  mutable inbox : string; (* the bytes read that are not yet a whole handshake or frame *)
  mutable queued : string list; (* the messages sent before it was open, the newest first *)
  mutable partial : string; (* a message whose last frame has not come *)
  mutable eof : bool;
  mutable pending : event list; (* what happened outside [step], for it to say *)
}

(*****************************************************************************)
(* The bytes *)
(*****************************************************************************)

let write (t : t) (bytes : string) : unit =
  match t.transport with
  | Secure tls -> Tls_client.send tls bytes
  | Plain fd ->
      (* the socket does not block: a write it cannot take now waits for it *)
      let rec go pos =
        if pos < String.length bytes then
          match Unix.write_substring fd bytes pos (String.length bytes - pos) with
          | n -> go (pos + n)
          | exception Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK), _, _) ->
              ignore (Unix.select [] [ fd ] [] 1.);
              go pos
          | exception Unix.Unix_error _ -> t.eof <- true
      in
      go 0

(* what has arrived, without waiting *)
let read (t : t) : string =
  match t.transport with
  | Secure tls ->
      let data = Tls_client.receive tls in
      (match Tls_client.state tls with Failed _ | Closed -> t.eof <- true | _ -> if Tls_client.ended tls then t.eof <- true);
      data
  | Plain fd ->
      let buf = Bytes.create 65536 in
      let rec go acc =
        match Unix.read fd buf 0 (Bytes.length buf) with
        | 0 -> t.eof <- true; acc
        | n -> go (acc ^ Bytes.sub_string buf 0 n)
        | exception Unix.Unix_error ((Unix.EAGAIN | Unix.EWOULDBLOCK), _, _) -> acc
        | exception Unix.Unix_error _ -> t.eof <- true; acc
      in
      go ""

let frame (t : t) (opcode : Websocket.opcode) (payload : string) : unit =
  write t (Websocket.encode ~mask:(Tls_client.random 4) { fin = true; opcode; payload })

let finish (t : t) : unit =
  if t.state <> Done then begin
    t.state <- Done;
    match t.transport with Secure tls -> Tls_client.close tls | Plain fd -> ( try Unix.close fd with Unix.Unix_error _ -> ())
  end

(*****************************************************************************)
(* Entry points *)
(*****************************************************************************)

let connect ?(origin : string option) (caps : < Cap.network ; .. >) (url : string) : (t, string) result =
  match Url.parse url with
  | Error why -> Error why
  | Ok u -> (
      let secure = match u.scheme with Some ("wss" | "https") -> Some true | Some ("ws" | "http") -> Some false | _ -> None in
      match (secure, u.authority) with
      | None, _ | _, None -> Error (url ^ ": not a ws:// or wss:// address")
      | Some secure, Some a -> (
          let port = Option.value a.port ~default:(if secure then 443 else 80) in
          let key = Base64.encode (Tls_client.random 16) in
          let host = if a.port = None then a.host else Printf.sprintf "%s:%d" a.host port in
          let path = match Url.request_target u with "" -> "/" | p -> p in
          let request = Websocket.request ?origin ~host ~path ~key () in
          let made transport = { transport; key; state = Handshaking; inbox = ""; queued = []; partial = ""; eof = false; pending = [] } in
          Logs.info (fun m -> m "WebSocket %s" url);
          if secure then
            match Tls_client.connect caps ~host:a.host ~port () with
            | Error why -> Error why
            | Ok tls ->
                Tls_client.send tls request;
                Ok (made (Secure tls))
          else
            match Tcp.connect caps ~host:a.host ~port () with
            | exception Unix.Unix_error (e, _, _) -> Error (Printf.sprintf "can't reach %s:%d: %s" a.host port (Unix.error_message e))
            | exception Failure why -> Error why
            | fd ->
                Tcp.send_all fd request;
                Unix.set_nonblock fd;
                Ok (made (Plain fd))))

let send (t : t) (message : string) : unit =
  match t.state with
  | Handshaking -> t.queued <- message :: t.queued
  | Open -> frame t Text message
  | Closing | Done -> ()

(* a close frame's payload: the code in two bytes, then the reason *)
let close_payload (code : int) (reason : string) : string = Printf.sprintf "%c%c%s" (Char.chr (code lsr 8)) (Char.chr (code land 255)) reason

let close ?(code = 1000) ?(reason = "") (t : t) : unit =
  match t.state with
  | Open ->
      frame t Close (close_payload code reason);
      t.state <- Closing
  | Handshaking ->
      finish t;
      t.pending <- [ Closed { code = 1006; reason = ""; clean = false } ]
  | Closing | Done -> ()

let failed (t : t) (why : string) : event list =
  finish t;
  [ Failed why; Closed { code = 1006; reason = ""; clean = false } ]

let step (t : t) : event list =
  let before = t.pending in
  t.pending <- [];
  if t.state = Done then before
  else begin
    t.inbox <- t.inbox ^ read t;
    let opened =
      if t.state <> Handshaking then []
      else
        match Websocket.handshake t.inbox with
        | None -> []
        | Some (headers, rest) ->
            let status = Option.value (List.assoc_opt "" headers) ~default:"" in
            (* the server agreed, and it is one that read the key *)
            if String.starts_with ~prefix:"HTTP/1.1 101" status && List.assoc_opt "sec-websocket-accept" headers = Some (Websocket.accept t.key) then begin
              t.inbox <- String.sub t.inbox rest (String.length t.inbox - rest);
              t.state <- Open;
              List.iter (frame t Text) (List.rev t.queued);
              t.queued <- [];
              [ Opened ]
            end
            else failed t (if status = "" then "not a WebSocket server" else "the server answered " ^ status)
    in
    (* the frames that are whole *)
    let rec frames (acc : event list) : event list =
      if t.state <> Open && t.state <> Closing then acc
      else
        match Websocket.decode t.inbox with
        | Incomplete -> acc
        | Bad why -> acc @ failed t why
        | Frame (f, used) -> (
            t.inbox <- String.sub t.inbox used (String.length t.inbox - used);
            match f.opcode with
            | Text | Binary | Continuation ->
                t.partial <- t.partial ^ f.payload;
                if f.fin then (
                  let message = t.partial in
                  t.partial <- "";
                  frames (acc @ [ Message message ]))
                else frames acc
            | Ping ->
                frame t Pong f.payload;
                frames acc
            | Pong -> frames acc
            | Close ->
                let n = String.length f.payload in
                let code = if n >= 2 then (Char.code f.payload.[0] lsl 8) lor Char.code f.payload.[1] else 1005 in
                let reason = if n > 2 then String.sub f.payload 2 (n - 2) else "" in
                (* the server's close answered, unless it answers ours *)
                if t.state = Open then frame t Close (if n >= 2 then String.sub f.payload 0 2 else "");
                finish t;
                acc @ [ Closed { code; reason; clean = true } ])
    in
    let events = before @ opened @ frames [] in
    if t.eof && t.state <> Done then begin
      let was = t.state in
      finish t;
      events @ if was = Handshaking then [ Failed "the connection closed during the handshake"; Closed { code = 1006; reason = ""; clean = false } ] else [ Closed { code = 1006; reason = ""; clean = false } ]
    end
    else events
  end
