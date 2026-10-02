(* Websocket_client: a WebSocket as its client keeps it -- connected,
   then stepped every frame, never waiting.

   Websocket.mli is the protocol, bytes in and bytes out; this is the
   connection: a socket (or a TLS connection over one, for wss://),
   the handshake sent and its answer awaited, then frames both ways
   for as long as it lasts. Unlike a request (Http_request), nothing
   says when it ends: it is asked each frame what happened since.

     connect   the name resolved, the TCP connection made (and for
               wss:// the TLS hello sent): this part waits, so a
               browser does it on a thread. The handshake's request
               is sent: GET, Upgrade: websocket, a key of 16 random
               bytes, the page's Origin.
     step      what can be read without waiting is read, and what it
               makes is told:

                 Opened            the server answered 101 with the
                                   key's proof (Websocket.accept):
                                   messages sent before now go
                 Message text      a whole message: its frames put
                                   together if it came in several
                 Closed            the end, with the code and reason
                                   of the server's close frame --
                                   clean -- or 1006 when the
                                   connection just went
                 Failed why        before a Closed that is not clean:
                                   no such server, not a WebSocket
                                   one, a frame that is not one

     send      a text message, in one masked frame (the mask: 4 bytes
               of the kernel's randomness, new for each)
     close     a close frame sent; the connection ends when the
               server's comes back (the closing handshake: each side
               says it has no more to say, so that no message is
               lost in the air), which [step] then tells

   A ping is answered by a pong with the same bytes, here and not by
   the caller: how each side knows the other is still there, and how
   the boxes between are kept from forgetting an idle connection.

   The codes of a close, some: 1000 normal, 1001 going away (the page
   left), 1005 none was given, 1006 no close frame at all (never
   sent, only told), 1009 a message too big, 1011 the server failed.

   Not done: binary messages apart from text (a Binary frame's bytes
   are given as a Message), subprotocols and extensions (the
   compression of messages, permessage-deflate), cookies in the
   handshake, a limit on how long a close waits for its answer.

   Reference: RFC 6455, sections 4 (the opening handshake), 5.4
   (fragments), 5.5 (close, ping, pong), 7 (closing), 7.4 (the
   codes). *)

type event = Opened | Message of string | Closed of { code : int; reason : string; clean : bool } | Failed of string

type t

(* [connect ?origin caps url]: the connection made to a ws:// or
 * wss:// address (http:// and https:// are taken as those) and the
 * handshake sent. Waits for the connection; an Error when there is
 * none to be had. *)
val connect : ?origin:string -> < Cap.network ; .. > -> string -> (t, string) result

(* what happened since the last call, in order; nothing after a Closed *)
val step : t -> event list

(* a text message; kept until the socket is open if it is not yet *)
val send : t -> string -> unit

(* the closing handshake started (code 1000 unless said); before the
 * socket is open, the connection dropped *)
val close : ?code:int -> ?reason:string -> t -> unit
