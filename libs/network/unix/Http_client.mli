(* Http_client: getting a URL, the three layers put together.

     "http://elm-lang.org/images/turtle.gif"
        | Url.parse
        v
     scheme http, host elm-lang.org, port 80, target /images/turtle.gif
        | Http.get, Http.request_to_string
        v
     "GET /images/turtle.gif HTTP/1.1\r\nHost: elm-lang.org\r\n..."
        | Tcp.exchange (DNS, connect, send, read until closed)
        v
     "HTTP/1.1 301 Moved Permanently\r\nLocation: https://...\r\n..."
        | Http.parse_response
        v
     status 301: again, with Url.resolve of the Location, at most
     [max_redirects] times (5 by default; Firefox and Chrome stop at 20)

   https:// is the same request inside TLS, our own TLS 1.3
   (Tls_client.mli, Tls13.mli): the server's certificate checked with
   the system's roots, then the same bytes, encrypted. A URL of
   another scheme is refused.
   This one blocks: the program waits, doing nothing else, until the
   answer is in -- the simple version, fine for a file loaded once
   (Download.mli). Http_request.mli is the same request that doesn't
   block, for a program that must go on drawing its frames.

   cs-history:
   What this stands in for is curl, which elm-playground ran as a
   program for its https:// until it had a TLS of its own. Daniel
   Stenberg began it in 1996 to fetch currency rates for an IRC bot
   (httpget, then urlget; "curl" in 1998); its library is now in
   nearly every phone, car and television, the most widely installed
   HTTP client there is, and what "getting a URL" means when a program
   that is not a browser does it. tools/curl is a small one made of
   this module. *)

(* the final response (whatever its status, 404 included: the caller
 * decides), or why there is none: a URL we can't get, a network error,
 * a response that doesn't parse, too many redirections *)
val get : ?jar:Cookie_jar.t -> ?agent:(string -> string) -> ?max_redirects:int -> ?timeout:float -> < Cap.network ; .. > -> string -> (Http.response, string) result
(* with a [jar], each request says the cookies kept for its
 * URL, and each answer's Set-Cookie is kept: a redirection's before
 * the next request is made *)

(* [agent]: what each request says it is (its User-Agent), given the
 * host it goes to; Http.default_agent without *)

(* the same, and the URL the redirections led to; with [post] (its
 * content type and body), the first request a POST *)
val fetch :
  ?post:string * string -> ?jar:Cookie_jar.t -> ?agent:(string -> string) -> ?max_redirects:int -> ?timeout:float -> < Cap.network ; .. > -> string -> (string * Http.response, string) result

(* one request and its answer, a redirection given as it is
 * (a 301 and its Location), not followed: what [fetch] does at each
 * step (tools/curl shows them one by one) *)
val once : ?post:string * string -> ?jar:Cookie_jar.t -> ?agent:(string -> string) -> ?timeout:float -> < Cap.network ; .. > -> Url.t -> (Http.response, string) result

(* what to connect to and what to send for [url]: the host for the
 * resolver, the port, the request's bytes (a GET; a POST of [post], its
 * content type and body); Error for a URL that isn't http:// or
 * https:// (the message says why) *)
val prepare : ?post:string * string -> ?jar:Cookie_jar.t -> ?agent:(string -> string) -> Url.t -> (string * int * string, string) result
