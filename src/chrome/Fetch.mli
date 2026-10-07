(* Fetch: the browser's requests in flight, over its own networking
   (libs/network) rather than the Playground's Http.get.

   A tab asks for a page, a picture, a style sheet: a [request], a GET
   or a POST and what to make of the answer, carried to the program as
   a message ([Browser_tab.config]'s fetch) so that the tab never
   touches a socket. The program keeps the requests in a [t], and steps
   them once a frame ([step], on its Tick), getting back the messages of
   those answered:

     http://    Http_request, a GET that never blocks: a state a
                step advances as far as it can without waiting
     https://   Http_client over our TLS 1.3, blocking, so on a
                thread of Worker's pool (threads, the default), or
                at once, the frame waiting (threads=off)

   The same as elm-playground's native platforms do for a program's
   Cmd.Http_get (their Commands.ml), here where the browser can grow it:
   cookies, compression, connections kept alive.

   modern:
   What a real browser has here is its largest part after the engine:
   a cache on disk, which answers most requests without the network
   (and the rules of when it may: Cache-Control, ETag, 304); a pool of
   connections kept open, six to a host at most for HTTP/1.1 (Netscape
   allowed four at once, the number of Worker's pool); one connection
   carrying every request at once for HTTP/2 and 3; a priority for
   each (the style sheet before the pictures); and the rule of who may
   ask what (Script_fetch.mli). The Fetch Standard is where all of it
   is written as one algorithm. None of that is here: every request
   opens its connection, asks once, and closes. *)

type response = { url : string; (* after the redirections *) status : int; headers : (string * string) list; body : string }

type error =
  | Bad_url of string
  | Timeout
  | Network_error of string

(* "bad URL: ...", "timeout", "network error: ..." *)
val error_to_string : error -> string

(* a request, and the message its answer becomes *)
type 'msg request

(* [said]: headers of the asker's own in the request (a script's
 * Accept; Origin, its page's, when it asks another site). [ready]:
 * called with the answer where it was fetched, on a thread of the
 * pool when there is one (https://), before the answer is given -- to
 * make there what its reader will need (a picture decoded) *)
val get : ?said:(string * string) list -> ?ready:(response -> unit) -> ?reload:bool -> < Cap.network ; .. > -> string -> ((response, error) result -> 'msg) -> 'msg request

val post :
  ?said:(string * string) list -> < Cap.network ; .. > -> string -> content_type:string -> body:string -> ((response, error) result -> 'msg) -> 'msg request

(* the requests in flight *)
type 'msg t

(* [threads]: https:// fetched (and names resolved) on a pool of four
 * threads, Netscape's four connections; without, the frame waits *)
(* [replay]: each request answered by it, 404 for None, and the network
   never asked (Browser_replay.answers) *)
val create : ?threads:bool -> ?jar:Cookie_jar.t -> ?agent:(string -> string) -> ?cache:Http_cache.store -> ?replay:(string -> string option) -> unit -> 'msg t

(* [cache]: the answers kept, which an https:// GET goes through
 * (Http_cache; none if not given), read and written on the pool's
 * threads; a request made with [reload] asks about a fresh copy too *)
val cache : 'msg t -> Http_cache.store option

(* how many workers the pool is asked of, and whether there is one *)
val workers : int
val threads : 'msg t -> bool
(* [jar], the cookies the requests say and keep (an empty one
 * if none is given): one for the whole browser *)
(* [agent]: what the browser says it is to a host, the User-Agent of
 * each request (Browser_agent) *)

val jar : 'msg t -> Cookie_jar.t

(* the pages' WebSockets (Web_sockets), which [step] steps too: what
 * they say comes among the answers *)
val sockets : 'msg t -> 'msg Web_sockets.t

(* the request started *)
val perform : 'msg t -> 'msg request -> unit

(* each request advanced without waiting; the messages of those
 * answered since *)
val step : 'msg t -> 'msg list
