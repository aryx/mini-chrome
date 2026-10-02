(* Web_sockets: the WebSockets the pages' scripts have open -- the
   browser's side of new WebSocket.

   A page's script touches no socket (WebSocket.mli): it asks, and the
   program does. This is where the connections live, each under the
   number of its tab and the number its page gave it, for as long as
   it is open; Fetch, which holds the requests in flight, holds one
   of these and steps it with them, every frame:

     open_   the connection started. Its first part waits (a name
             resolved, a TCP connection, a TLS hello), so it is done
             on a thread of Fetch's pool; what the script sends or
             closes meanwhile is kept and done when it is there.
     step    each connection asked what happened (Websocket_client.
             step, which never waits) and its events turned into the
             program's messages, by the function given at [open_]; a
             socket that closed is forgotten.

   A request ends with its answer; a socket ends when either side
   says so, or the tab is closed ([close_tab]). A page left for
   another has no such moment here: its sockets stay until they next
   speak, when the tab, finding no script for them, closes them
   (Browser_tab.got_socket).

   modern:
   Chrome keeps a page's sockets in its network process, not in the
   page's renderer, as its requests: the sandboxed process that runs
   the page's script cannot open a connection at all, and asks, by a
   message, for each one. The shape is this one, with a process's
   wall where here there is a module's. *)

type 'msg t

(* [pool]: the threads a connection is made on; without, made at once,
 * the frame waiting *)
val create : ?pool:Worker.t -> unit -> 'msg t

(* [open_ t caps ~key ~origin url k]: a socket to [url], said to come
 * from the page of that origin, under [key] (a tab, a number); what
 * it says is given to [k] by [step] *)
val open_ : 'msg t -> < Cap.network ; .. > -> key:int * int -> origin:string -> string -> (Websocket_client.event -> 'msg) -> unit

val send : 'msg t -> int * int -> string -> unit
val close : 'msg t -> int * int -> code:int -> reason:string -> unit

(* the sockets of a tab that is closed, closed (1001) *)
val close_tab : 'msg t -> int -> unit

(* what the sockets said since the last call, as messages *)
val step : 'msg t -> 'msg list
