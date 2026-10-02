(* WebSocket: a page's script and its server talking both ways, for as
   long as the page is there -- the object a script is given.

   XMLHttpRequest and fetch (their .mlis) ask and are answered, once.
   A WebSocket is opened and stays: either side says something when
   it has something to say.

     const s = new WebSocket("ws://127.0.0.1:8000/echo")
     s.onopen = () => s.send("hello")
     s.onmessage = e => { show(e.data); s.close() }
     s.onclose = e => show("closed " + e.code)

   Like a request, it is an event's affair: new WebSocket returns at
   once with a socket that is not yet one (readyState 0, CONNECTING),
   and the script goes on. What happens then comes as tasks, each
   after the script that was running is done:

     readyState   event      when
     0 CONNECTING            from new, until the server agrees
     1 OPEN       open       the handshake answered: send may be called
                  message    a message came: its text in the event's data
     2 CLOSING               close() was called, the server's close
                             awaited
     3 CLOSED     close      the end: the event's code, reason and
                             wasClean (error before it if it was not)

   send before OPEN throws (InvalidStateError); after CLOSING it is
   dropped without a word.

   As with a request, the script touches no socket. [make] leaves an
   ask for the browser (Script_types.socket_ask: open, send, close),
   which Browser_script hands over ([take_socket_asks]); the tab
   gives them to the program, whose Web_sockets keeps the real
   connections (Websocket_client: the handshake, the frames) and
   steps them each frame; what they say comes back by the socket's
   number ([tell]) and becomes the events above.

     script          Browser_script        tab, window        Web_sockets
     new WebSocket -> an ask kept
                      take_socket_asks --> Socket msg ------> connect (a thread)
                                                              step, each frame
     onopen <-------- tell <-------------- Got_socket <------ Opened
     send ----------> an ask ...                              a frame out
     onmessage <----- tell <-------------- Got_socket <------ Message

   The address: ws:// or wss://, or a page's own kind (http://,
   https://, a relative one), taken as those. Its origin need not be
   the page's: no same-origin rule here, and no CORS (Websocket.mli's
   design note says why and what stands in for it: the Origin header
   that the browser adds, for the server to judge).

   modern:
   What a real browser adds: ArrayBuffer and Blob messages
   (binaryType), bufferedAmount that counts what send has queued,
   subprotocols (the second argument of new), the page's cookies in
   the handshake, a refusal to open ws:// from an https:// page
   (mixed content), sockets closed with 1001 when the page is left.
   Here a message is a string, and the socket of a page that is gone
   is closed when it next says something.

   The name: this module is the script's object, as JavaScript spells
   it; the protocol is Websocket (libs/network), as the RFC's.

   References: WHATWG, WebSockets Standard (the API; it was in HTML5
   at first); RFC 6455 for what goes on the wire. *)

(* [make t o url]: [o], made by new, as a socket to [url]: its
 * members, and an ask to open it. Throws a SyntaxError for an address
 * that cannot be a socket's. *)
val make : Script_types.t -> Js_value.obj -> string -> unit

(* the constructor defined, with its four constants *)
val install : Script_types.t -> (string -> Js_value.value -> unit) -> unit

(* [tell t id event]: what the connection of that number said, given
 * to its socket as events; false if the page has no such socket *)
val tell : Script_types.t -> int -> Websocket_client.event -> bool
