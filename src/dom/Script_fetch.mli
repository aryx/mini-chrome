(* Script_fetch: a script asking the network -- the request that leaves
   a page and the answer that comes back to it; and fetch.

   A page's script cannot wait: it runs to its end before the page
   moves again (Js_eval), and an answer takes a second. So asking is
   two tasks, and the browser between them:

       the script                 the browser                the server
       ----------                 -----------                ----------
       fetch("/items")
         a request queued  ---->  take_requests: sent  --->
         a promise, pending       (Browser_tab, Fetch)
       ... runs to its end
                                  the answer arrives   <---  200, a body
       then(...) called    <----  Browser_script.answer:
       the page changed           a task; then laid out again

   [ask] queues a request with what to do with its answer; [answer] is
   that answer coming back, by the request's number. XMLHttpRequest
   (its own module) and fetch are two faces of these two.

   **fetch(url, { method, headers, body })** gives a promise of a
   response: ok, status, statusText, url, headers.get(name), and its
   body as promises too, text() and json():

     const r = await fetch("/items.json")
     if (r.ok) show(await r.json())

   A status of 404 is an answer (ok is false); the promise is rejected
   (a TypeError, as browsers say it) only when there is no answer: no
   network, or one the page may not read.

   **Who may read what.** A request carries the user's cookies
   (Cookie_jar). Were any page's script free to read any answer, a
   page could ask the reader's bank for their account and send it
   home. Netscape saw it the year scripts arrived (Navigator 2, 1995):
   a script reads only what comes from its own *origin* -- the same
   scheme, host and port as its page -- the same-origin policy, the
   one rule the web's security stands on.

   It was too strict for pages that had a good reason to ask another
   site (a map, a font, an API), and for ten years they went around it:
   a <script> element may come from anywhere, so a server wrapped its
   data in a call to a function of the page ("JSONP", Bob Ippolito,
   2005), giving that server the run of the page. The remedy lets the
   *other* site decide: CORS, Cross-Origin Resource Sharing (a W3C
   draft from 2006, in browsers from 2009, a Recommendation in 2014).
   An answer of another origin is the script's to read only if it
   carries "Access-Control-Allow-Origin: *" or the page's own origin.
   Else the script is told the request failed, and nothing of the
   answer -- the request was sent all the same: CORS protects what is
   read, not what is asked.

   Here that one check is all of CORS: no "preflight" (the OPTIONS
   request a browser sends first, to ask whether a POST of JSON or a
   DELETE may be sent at all), no distinction of requests with
   credentials (for which "*" is not enough).

   GET and POST only (what the browser's Fetch sends); a script's own
   request headers are not sent, but a POST's Content-Type.

   fetch itself is of 2015 (Chrome 42, Firefox 39; the Fetch Standard,
   Anne van Kesteren, WHATWG): the same request as XMLHttpRequest's,
   as a promise, and the standard where what a browser's every request
   does -- a page's, a picture's, a script's -- was at last written in
   one place.

   Reference: the Fetch Standard (fetch.spec.whatwg.org), sections 3.2
   (CORS), 5 (the fetch method). RFC 6454, "The Web Origin Concept"
   (Barth, 2011). Michal Zalewski, "The Tangled Web" (2011), chapter 9,
   on the same-origin policy and its holes. *)

open Js_value
open Script_types

(* [ask t ~meth ~url ~post k]: a request queued for the browser, [url]
 * resolved against the page's; [k] called with its answer, or with why
 * there is none. The request's number *)
val ask : t -> meth:string -> url:string -> post:(string * string) option -> ((answer, string) result -> unit) -> int

(* the request of that number will not be answered to (abort) *)
val forget : t -> int -> unit

(* [answer t rid result]: the answer of request [rid], given to who
 * asked, if the page may read it. To be called in a task of the
 * engine's (Browser_script.answer) *)
val answer : t -> int -> (answer, string) result -> unit

(* a URL's origin: "https://example.com", "http://localhost:8000" *)
val origin : string -> string

(* a header's value, whatever its name's case *)
val header : answer -> string -> string option

(* a script's function called from a host function, its error said on
 * the console *)
val call : t -> value -> this:value -> value list -> unit

(* a text as JSON, by the engine's JSON.parse (a SyntaxError thrown) *)
val parse_json : t -> string -> value

(* fetch defined *)
val install : t -> (string -> value -> unit) -> unit
