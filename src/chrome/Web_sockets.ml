(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Web_sockets.mli *)

type connection =
  (* the name being resolved and the connection made, on a thread *)
  | Connecting of (Websocket_client.t, string) result Worker.job
  | Live of Websocket_client.t
  | Dead of string (* no connection to be had: told at the next step *)

type 'msg socket = {
  url : string;
  mutable connection : connection;
  k : Websocket_client.event -> 'msg;
  (* what was asked while it was connecting, to do once it is: the
   * messages (the newest first), a close *)
  mutable unsent : string list;
  mutable closing : (int * string) option;
}

type 'msg t = { pool : Worker.t option; mutable sockets : ((int * int) * 'msg socket) list }

let create ?pool () : 'msg t = { pool; sockets = [] }

let open_ (t : 'msg t) (caps : < Cap.network ; .. >) ~(key : int * int) ~(origin : string) (url : string) (k : Websocket_client.event -> 'msg) : unit =
  let caps = (caps :> Cap.network) in
  let connect () = Websocket_client.connect ~origin caps url in
  let connection =
    match t.pool with
    | Some pool -> Connecting (Worker.submit pool connect)
    (* no threads: at once, the frame waiting *)
    | None -> ( match connect () with Ok c -> Live c | Error why -> Dead why)
  in
  t.sockets <- t.sockets @ [ (key, { url; connection; k; unsent = []; closing = None }) ]

let send (t : 'msg t) (key : int * int) (message : string) : unit =
  match List.assoc_opt key t.sockets with
  | Some { connection = Live c; _ } -> Websocket_client.send c message
  | Some ({ connection = Connecting _; _ } as s) -> s.unsent <- message :: s.unsent
  | Some { connection = Dead _; _ } -> ()
  | None -> ()

let close (t : 'msg t) (key : int * int) ~(code : int) ~(reason : string) : unit =
  match List.assoc_opt key t.sockets with
  | Some { connection = Live c; _ } -> Websocket_client.close ~code ~reason c
  | Some ({ connection = Connecting _; _ } as s) -> s.closing <- Some (code, reason)
  | Some { connection = Dead _; _ } -> ()
  | None -> ()

(* a tab closed: its sockets with it (1001, going away) *)
let close_tab (t : 'msg t) (tab : int) : unit =
  List.iter (fun ((id, _) as key, _) -> if id = tab then close t key ~code:1001 ~reason:"") t.sockets

let lost : Websocket_client.event = Closed { code = 1006; reason = ""; clean = false }

let step (t : 'msg t) : 'msg list =
  let events (s : 'msg socket) : Websocket_client.event list =
    match s.connection with
    | Live c -> Websocket_client.step c
    | Dead why -> [ Failed why; lost ]
    | Connecting job -> (
        match Worker.poll job with
        | None -> []
        | Some (Ok (Ok c)) ->
            s.connection <- Live c;
            List.iter (Websocket_client.send c) (List.rev s.unsent);
            Option.iter (fun (code, reason) -> Websocket_client.close ~code ~reason c) s.closing;
            Websocket_client.step c
        | Some (Ok (Error why)) -> [ Failed why; lost ]
        | Some (Error e) -> [ Failed (Printexc.to_string e); lost ])
  in
  let said = List.map (fun (key, s) -> (key, s, events s)) t.sockets in
  (* what -v shows: a socket's life, not its messages *)
  List.iter
    (fun (_, s, es) ->
      List.iter
        (fun (e : Websocket_client.event) ->
          match e with
          | Opened -> Logs.info (fun m -> m "101 %s, a WebSocket open" s.url)
          | Failed why -> Logs.info (fun m -> m "failed %s: %s" s.url why)
          | Closed { code; _ } -> Logs.info (fun m -> m "closed %s (%d)" s.url code)
          | Message _ -> ())
        es)
    said;
  let ended (es : Websocket_client.event list) = List.exists (fun (e : Websocket_client.event) -> match e with Closed _ -> true | _ -> false) es in
  t.sockets <- List.filter_map (fun (key, s, es) -> if ended es then None else Some (key, s)) said;
  List.concat_map (fun (_, s, es) -> List.map s.k es) said
