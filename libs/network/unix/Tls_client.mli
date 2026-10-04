(* Tls_client: TLS 1.3 over a real socket -- our own (Tls13.mli), with
   the system's trusted roots.

   Tls13 is a pure machine, bytes in and bytes out; this is the rest:
   the TCP connection (Tcp.mli), 96 bytes of randomness from
   /dev/urandom (the hello's random, the session id, the X25519 key --
   a pure machine rolls no dice), the roots read once from the system's
   bundle (/etc/ssl/certs/ca-certificates.crt, or where the other
   systems keep it), the chain checked with them at the time of day
   (X509.verify), and the loop that carries the bytes between the socket
   and the machine, never waiting.

   Reading the system's roots and the kernel's randomness is part of
   what reaching a host over TLS means, so it is done under the same
   authority, Cap.network -- as curl, which this replaces, did.

   [exchange], one request and its whole answer, is what HTTPS
   (Http_client) uses. (elm-playground's has a second face, the
   connection as lines for POP3 and SMTP, which a browser does not need.)

   Worked examples (checked by the tests): a handshake with a local
   `openssl s_server` over each of our two ciphers, its self-signed
   certificate the one root trusted, a page asked and received; the same
   refused when the root is not trusted, or the host is another. By
   hand: the web servers the browser visits. *)

type t

(* the system's roots, read once *)
val system_roots : < Cap.network ; .. > -> X509.t list

(* [connect caps ~host ~port ()]: the TCP connection made (waiting for
 * it) and the ClientHello sent; the handshake goes on in [step].
 * [trust]: the roots, the system's unless given *)
val connect : < Cap.network ; .. > -> ?trust:X509.t list -> host:string -> port:int -> unit -> (t, string) result

(* what can be done without waiting: bytes read and given to the
 * machine, its answers written *)
val step : t -> unit

val state : t -> Tls13.state

(* the machine, to ask it what it saw (the chain, the cipher) *)
val machine : t -> Tls13.t

(* application data: sent once the handshake is done (queued before) *)
val send : t -> string -> unit

(* the application data arrived since the last call *)
val receive : t -> string

val close : t -> unit

(* [wait t s]: until bytes come, [s] seconds at most *)
val wait : t -> float -> unit

(* whether the other side is gone: the connection closed, by it or by
 * [close] (a lasting connection asks; [exchange] reads until then) *)
val ended : t -> bool

(* [random n]: n bytes of the kernel's randomness (/dev/urandom) *)
val random : int -> string

(* [exchange caps ~host ~port request]: connect, send [request], read
 * until the server closes (or [timeout] seconds of silence) *)
val exchange : ?trust:X509.t list -> ?timeout:float -> < Cap.network ; .. > -> host:string -> port:int -> string -> (string, string) result
