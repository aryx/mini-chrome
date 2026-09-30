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
   cookies, compression, connections kept alive. *)

type response = { url : string; (* after the redirections *) status : int; headers : (string * string) list; body : string }

type error =
  | Bad_url of string
  | Timeout
  | Network_error of string

(* "bad URL: ...", "timeout", "network error: ..." *)
val error_to_string : error -> string

(* a request, and the message its answer becomes *)
type 'msg request

val get : < Cap.network ; .. > -> string -> ((response, error) result -> 'msg) -> 'msg request

val post :
  < Cap.network ; .. > -> string -> content_type:string -> body:string -> ((response, error) result -> 'msg) -> 'msg request

(* the requests in flight *)
type 'msg t

(* [threads]: https:// fetched (and names resolved) on a pool of four
 * threads, Netscape's four connections; without, the frame waits *)
val create : ?threads:bool -> unit -> 'msg t

(* the request started *)
val perform : 'msg t -> 'msg request -> unit

(* each request advanced without waiting; the messages of those
 * answered since *)
val step : 'msg t -> 'msg list
