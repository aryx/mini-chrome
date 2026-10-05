(* The HTTP cache: an answer kept, to be given again without asking, or
   after asking only whether it changed.

   Most of what a page asks for it asked for yesterday: the site's
   style sheet, its scripts, its logo. The server says how long each
   answer may be used again, and a browser that listens does the second
   visit to a site with a tenth of the requests of the first.

     the first time                    later
     -------------------------------   -------------------------------
     GET /app-3f9a.js                  (fresh: nothing sent, the copy)
     200, Cache-Control: max-age=
       31536000, immutable
     GET /                             GET /
     200, ETag: "a79",                   If-None-Match: "a79"
       Cache-Control: max-age=0        304 Not Modified  (the copy)

   Three questions, which are this module:

   **May it be kept?** ([storable]) A GET answered 200, that does not
   say no-store. "private" is no obstacle: this cache is one person's,
   and that word is for the caches between (a proxy, a CDN). An
   answer that depends on the request's headers (Vary) other than
   Accept-Encoding is not kept: one address, one copy. And an answer
   with neither a lifetime nor a validator would be asked for again
   whole each time: not kept either.

   **Is the copy fresh?** ([fresh]) Its lifetime is Cache-Control's
   max-age, less the Age it had when it came (the time it had spent in
   a cache on the way); else Expires less Date. no-cache is a lifetime
   of nothing: kept, and asked about each time.

       max-age=600, Age: 100, stored at t  ->  fresh until t + 500

   **If it is not, has it changed?** ([validators], [revalidated])
   The request says what the copy is: If-None-Match with its ETag,
   If-Modified-Since with its Last-Modified. A 304 has no body: the
   copy is the answer, with the headers the 304 brought (a new date, a
   new lifetime). Anything else is the new answer.

   Not done: the heuristic lifetime of an answer that gives none (a
   tenth of the time since Last-Modified, RFC 9111 section 4.2.2: such
   a copy is asked about each time here); Vary on other headers; an
   answer in parts (206); stale-while-revalidate.

   The copy as a file ([to_string], [of_string]) is its address, when
   it was kept, and the answer, in the shape of an HTTP message: lines
   of headers, an empty line, the body -- which is the body decoded
   (no gzip, no chunks: Http.parse_response did that). Where the files
   are and how many is the browser's business (Browser_cache); this
   module opens none.

   cs-history:
   HTTP/1.0 (RFC 1945, 1996) had Expires, a date, and
   If-Modified-Since: both ask two clocks to agree. HTTP/1.1 (RFC
   2068, 1997) added Cache-Control's max-age, a duration, and the
   ETag, a name the server gives a version of a file, which needs no
   clock at all. "immutable" came later (RFC 8246, 2017), for the
   files whose name is a hash of their content: a browser reloading
   the page was asking about each of them, to be told 304 each time.

   modern:
   Chrome's cache is on disk too, and since 2020 it is keyed by the
   site of the page asking as well as by the address (so that a site
   cannot learn, by timing a fetch, what another site made the
   browser load). Beside it Chrome keeps what it made of the bytes --
   V8's compiled code for a script -- which this cache does not: a
   cache of bytes, not of work.

   References: RFC 9111 (HTTP Caching, 2022; before it RFC 7234);
   RFC 9110, section 13 (conditional requests) and 8.8 (validators);
   RFC 8246 (immutable). *)

type entry = {
  url : string;
  stored : float; (* when the answer came, seconds since 1970 *)
  response : Http.response;
}

(* where copies are kept: given by who has the files. [entries]: what
 * is kept, to be shown -- each copy's address, its body's size, when
 * it was kept, whether it is fresh; [place]: where, said to people *)
type store = { find : string -> entry option; keep : entry -> unit; entries : now:float -> (string * int * float * bool) list; place : string }

(* the three questions *)
val storable : Http.response -> bool

(* how long the answer may be used again, in seconds, from when it came *)
val lifetime : stored:float -> Http.header list -> float
val fresh : now:float -> entry -> bool

(* the request's headers that ask whether the copy changed; none: it
 * can only be asked for whole *)
val validators : entry -> Http.header list

(* the copy after a 304: its body, the 304's headers over its own *)
val revalidated : now:float -> entry -> Http.response -> entry

(* the copy as a file's text, and back (None: not one of ours) *)
val to_string : entry -> string
val of_string : string -> entry option
