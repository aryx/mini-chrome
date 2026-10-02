(* Httpd: a directory's files served over HTTP -- the other end of the
   browser's conversation.

   A browser writes a request and reads an answer (Http_client). A
   server does the reverse, with the same two messages (Http): it
   waits for a connection, reads until the request is whole
   (Http.parse_request), finds what the request's target names, and
   writes the answer (Http.response_to_string).

   cs-history:
   The first web server was the program on Tim Berners-Lee's NeXT at
   CERN (1990; the machine kept a label, "This machine is a server. DO
   NOT POWER IT DOWN!!"): a URL's path was a file's path, as here.
   NCSA's HTTPd (Rob McCool, 1993) was the one sites ran, and added
   programs behind a URL (CGI). When McCool left for Netscape its users
   went on exchanging their patches by mail, and released them together
   in 1995 -- "a patchy server", as the story goes: Apache, the most used web server for
   the twenty years after, and with Linux the proof that software so
   made could run the Internet. nginx (Igor Sysoev, 2004) took its
   place by serving ten thousand connections from one loop
   (Http_request.mli) instead of a process for each. This one serves
   one at a time.

       the browser                          mini-httpd
       -----------                          ----------
       connect ---------------------------> accept
       "GET /notes/a.html HTTP/1.1" ------> root/notes/a.html read
            <------------------------------ "HTTP/1.1 200 OK", its type,
                                            its length, its bytes
            <------------------------------ close

   What a target names, under the directory served ([answer]):

     /notes/a.html     that file: 200, its Content-Type from its
                       extension (.html, .css, .js, .png, ...)
     /notes/           the directory's index.html if it has one; else
                       a page listing what is in it, each a link
     /notes            301, Location: /notes/ (so that the listing's
                       relative links resolve)
     /nope             404
     /../secret        403: ".." is resolved first (Url.remove_dot_segments),
                       and nothing above the directory is ever named
     POST /x           405: only GET

   And one thing that is not a file: a request that asks to become a
   WebSocket (Upgrade: websocket, at any path) is agreed to
   (Websocket.response: 101, and the proof that the key was read) and
   the connection kept: each message is sent back as it came, until
   the client closes -- an echo, the hello world of sockets, and the
   server side of Websocket.mli in thirty lines. While it lasts
   nobody else is served: one connection at a time.

   A query (?v=2) is dropped, %20 decoded. One connection at a time,
   closed after its answer; it listens on 127.0.0.1 alone: a server for
   the pages on one's own machine, not for the Internet.

   Worked example (tests/tools/Unit_httpd.ml), a directory with
   index.html and notes/a.txt:

     GET /             200 text/html, index.html's bytes
     GET /notes/       200, a listing with <a href="a.txt">a.txt</a>
     GET /notes/a.txt  200 text/plain
     GET /notes        301 Location: /notes/

   Reference: RFC 9110 (HTTP semantics): sections 9.3.1 (GET), 15
   (status codes); "python3 -m http.server", which this stands in for. *)

(* a file's Content-Type, by its name's extension; application/octet-stream
 * for one not known *)
val content_type : string -> string

(* the answer to a request, for the directory [root] *)
val answer : < Cap.open_in ; .. > -> root:string -> Network.Http.request -> Network.Http.response

(* a socket listening on 127.0.0.1's [port] (0: any free one), and the
 * port it got *)
val listen : < Cap.network ; .. > -> port:int -> Unix.file_descr * int

(* connections accepted for ever, one at a time, each request answered
 * for [root]; [log] is told each: "GET /x 200 1234" *)
(* [echo fd key]: the WebSocket handshake answered on a connection
 * whose request had that Sec-WebSocket-Key, then each message
 * echoed until the close; how many were *)
val echo : Unix.file_descr -> string -> int

val serve : < Cap.open_in ; .. > -> root:string -> ?log:(string -> unit) -> Unix.file_descr -> 'a
