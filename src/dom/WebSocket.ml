(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See WebSocket.mli *)

open Js_value
open Script_types
open Script_host

let fn (name : string) (f : value list -> value) : value = host_function name (fun ~this:_ args -> f args)

(* a page's address made a socket's: http is ws, https wss *)
let address (t : t) (url : string) : string option =
  let url = Browser_url.resolve t.base url in
  let after (prefix : string) = String.sub url (String.length prefix) (String.length url - String.length prefix) in
  if Browser_url.starts_with "ws://" url || Browser_url.starts_with "wss://" url then Some url
  else if Browser_url.starts_with "http://" url then Some ("ws://" ^ after "http://")
  else if Browser_url.starts_with "https://" url then Some ("wss://" ^ after "https://")
  else None

(* new WebSocket(url): [o], the object new made, given its state and
 * its methods; the browser asked for the connection *)
let make (t : t) (o : obj) (url : string) : unit =
  let url = match address t url with Some u -> u | None -> throw "SyntaxError" (Printf.sprintf "Failed to construct 'WebSocket': The URL '%s' is invalid." url) in
  t.next_request <- t.next_request + 1;
  let id = t.next_request in
  let listeners : (string * value) list ref = ref [] in
  let set k v = set_own o k v in
  let state () = match get_own o "readyState" with Some (Number n) -> int_of_float n | _ -> 3 in
  let ask (a : socket_ask) = t.socket_asks <- a :: t.socket_asks in
  (* an event: the on... property's function, then the listeners' *)
  let fire (typ : string) (fields : (string * value) list) : unit =
    let ev = Script_events.make typ ([ ("target", Object o); ("currentTarget", Object o) ] @ fields) in
    Script_fetch.call t (Option.value (get_own o ("on" ^ typ)) ~default:Undefined) ~this:(Object o) [ ev ];
    List.iter (fun (ty, f) -> if ty = typ then Script_fetch.call t f ~this:(Object o) [ ev ]) !listeners
  in
  set "url" (String url);
  set "readyState" (Number 0.);
  set "protocol" (String "");
  set "extensions" (String "");
  set "bufferedAmount" (Number 0.);
  set "binaryType" (String "blob");
  set "send" (fn "send" (fun args ->
      (match state () with
      | 0 -> throw "InvalidStateError" "Failed to execute 'send' on 'WebSocket': Still in CONNECTING state."
      | 1 -> ask (Socket_send (id, str (arg args 0)))
      (* closing or closed: said to nobody, as browsers do *)
      | _ -> ());
      Undefined));
  set "close" (fn "close" (fun args ->
      if state () < 2 then (
        set "readyState" (Number 2.);
        ask (Socket_close (id, (match arg args 0 with Number n -> int_of_float n | _ -> 1000), match arg args 1 with Undefined -> "" | r -> str r)));
      Undefined));
  set "addEventListener" (fn "addEventListener" (fun args -> listeners := !listeners @ [ (str (arg args 0), arg args 1) ]; Undefined));
  set "removeEventListener" (fn "removeEventListener" (fun args ->
      listeners := List.filter (fun (ty, f) -> not (ty = str (arg args 0) && strict_equal f (arg args 1))) !listeners;
      Undefined));
  (* what the connection says, as the socket's events *)
  let told (e : Websocket_client.event) : unit =
    match e with
    | Opened ->
        set "readyState" (Number 1.);
        fire "open" []
    | Message data -> fire "message" [ ("data", String data); ("origin", String (Script_fetch.origin url)) ]
    | Failed _ -> fire "error" []
    | Closed { code; reason; clean } ->
        set "readyState" (Number 3.);
        t.sockets <- List.remove_assoc id t.sockets;
        fire "close" [ ("code", Number (float_of_int code)); ("reason", String reason); ("wasClean", Bool clean) ]
  in
  t.sockets <- (id, told) :: t.sockets;
  ask (Socket_open (id, url, Script_fetch.origin t.base))

let install (t : t) (define : string -> value -> unit) : unit =
  let c =
    host_function "WebSocket" (fun ~this args ->
        let o = match this with Object o -> o | _ -> throw "TypeError" "Failed to construct 'WebSocket': Please use the 'new' operator" in
        make t o (str (arg args 0));
        Undefined)
  in
  (match c with
  | Object c -> List.iter (fun (k, n) -> set_own c k (Number n)) [ ("CONNECTING", 0.); ("OPEN", 1.); ("CLOSING", 2.); ("CLOSED", 3.) ]
  | _ -> ());
  define "WebSocket" c

let tell (t : t) (id : int) (e : Websocket_client.event) : bool =
  match List.assoc_opt id t.sockets with
  | Some told -> told e; true
  | None -> false
