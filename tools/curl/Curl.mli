(* Curl: a URL fetched and printed -- the browser's network stack with
   no browser around it.

   What the address bar does before anything is shown, on its own: the
   URL read (Url), the host's name resolved and a connection made
   (Tcp), for https:// the TLS 1.3 handshake of our own (Tls13,
   Tls_client) and the server's certificate checked (X509), the request
   written and the answer read (Http: the status line, the headers, a
   chunked body joined, a gzip one decompressed), the cookies kept from
   one request to the next (Cookie_jar). Here each step can be looked
   at: -v prints what is sent and what comes back, a redirection at a
   time.

     mini-curl https://example.com          the body
     mini-curl -i URL                       the status line and the headers first
     mini-curl -L URL                       a redirection (301, 302...) followed
     mini-curl -v URL                       the request (>) and the answer's head (<), on the standard error
     mini-curl -d "a=1&b=2" URL             a POST, the body a form's fields
     mini-curl -o file URL                  the body to a file
     mini-curl -f URL                       a status of 400 or more is a failure (exit 22), nothing printed
     mini-curl -A "Lynx/2.8" URL            the name said in User-Agent: what a server sends may
                                            depend on it (Browser_agent.mli)

   Worked example (tests/tools/Unit_curl.ml), a server whose /old
   answers "301, Location: new":

     mini-curl -i /old       HTTP/1.1 301 Moved Permanently
                             Location: new
     mini-curl -L -v /old    > GET /old HTTP/1.1  ...  < HTTP/1.1 301 ...
                             > GET /new HTTP/1.1  ...  < HTTP/1.1 200 OK
                             and /new's body

   A cookie set by an answer is sent with the requests that follow (a
   sign-in that answers "302, Set-Cookie" works with -L), and forgotten
   when the program ends. Less than curl's hundred flags: no HEAD, no
   headers of one's own, no upload, HTTP/1.1 only.

   Reference: curl(1), whose flags' letters these are. *)

(* [run caps args]: the program, its arguments those after its name;
 * its exit status: 0, 1 for a mistake (said by [complain]), 22 for -f's
 * failure. [print] gets the output, the standard output by default;
 * [complain] the messages and -v's lines, the standard error *)
val run :
  < Cap.network ; Cap.open_out ; Cap.stdout ; Cap.stderr ; .. > -> ?print:(string -> unit) -> ?complain:(string -> unit) -> string list -> int
