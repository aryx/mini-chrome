(* Cookie: what a server asks a browser to remember, and to say back.

   HTTP forgets: each request is answered on its own, and the server
   cannot tell that two of them came from the same person. Lou
   Montulli's cookies (Netscape, 1994: for a shopping cart) are the
   memory, kept by the browser: a response says "Set-Cookie: name=
   value", and every later request to that site says "Cookie: name=
   value" back. It is how a site knows who is signed in -- the value is
   a number that names the session, which only the server understands.

     GET /login HTTP/1.1                 (the form posted)
                                HTTP/1.1 302 Found
                                Location: /inbox
                                Set-Cookie: SID=31d4d96e407aad42; Path=/; Secure; HttpOnly
                                Set-Cookie: lang=en-US; Path=/; Domain=example.com
     GET /inbox HTTP/1.1
     Cookie: SID=31d4d96e407aad42; lang=en-US

   (RFC 6265's own example, section 3.1.) After the name and the value
   come the **attributes**, which say where the cookie goes back, and
   until when:

     Domain=example.com  to that host and those under it
                         (www.example.com); without it, to the one host
                         that set it and no other (a "host-only" cookie)
     Path=/docs          to the paths under it (/docs, /docs/web, not
                         /docsweb); without it, the directory of the
                         page that set it
     Expires=Wed, 09 Jun 2021 10:18:14 GMT
     Max-Age=3600        until then, or for so many seconds (Max-Age
                         wins); without either, until the browser is
                         closed, a session's cookie. A date in the past
                         is how a server deletes one.
     Secure              over https:// only
     HttpOnly            not shown to the page's scripts
                         (document.cookie): a stolen script cannot take
                         the session with it

   A browser keeps them in a **jar** ([jar], a value: the list). A new
   cookie replaces the one of the same name, domain and path. For a
   request, those whose domain and path match its URL are sent, the
   longest paths first.

   What a server may not do is set a cookie for someone else: a Domain
   that the host answering is not under is refused, and so is one with
   no dot ("com"), which every site would share. (A browser has the
   Public Suffix List for that, "co.uk" and thousands more: not here.)

   Not done: the Public Suffix List; SameSite (a cookie is sent with
   every request to its site, whoever asks: a picture on another site's
   page too); the __Host- and __Secure- prefixes; partitioning.

   Reference: Adam Barth, RFC 6265, "HTTP State Management Mechanism"
   (2011), sections 4.1 (Set-Cookie), 5.1 (dates, domains, paths), 5.3
   (storing), 5.4 (the Cookie header); Netscape's "Persistent Client
   State: HTTP Cookies" (1994). *)

type cookie = {
  name : string;
  value : string;
  domain : string; (* lowercase, no dot before it *)
  host_only : bool; (* no Domain said: that host alone *)
  path : string;
  expires : float option; (* seconds since 1970; None: the session's *)
  secure : bool;
  http_only : bool;
  created : float;
}

(* the cookies kept, the newest first *)
type jar = cookie list

(* an Expires' date, as seconds since 1970: "Wed, 09 Jun 2021 10:18:14
 * GMT", and what servers write instead (RFC 6265 section 5.1.1: a
 * time, a day, a month's name, a year, in any order) *)
val date : string -> float option

(* [parse ~now url value]: the cookie a "Set-Cookie: [value]" in the
 * answer to [url] asks for; None if it is refused (no name, a Domain
 * that is not [url]'s host's, Secure over http://) *)
val parse : now:float -> Url.t -> string -> cookie option

(* the jar after that Set-Cookie: the cookie kept, in the place of the
 * one of its name, domain and path; that one only removed, if the new
 * one is already past its date. [script] (false): set by the page's
 * script, which may neither set an HttpOnly cookie nor replace one *)
val store : now:float -> ?script:bool -> Url.t -> string -> jar -> jar

(* the cookies a request to [url] sends: its domain's, its path's, not
 * past their date, Secure ones over https:// only; without the
 * HttpOnly ones for [script] (false). The longest paths first, then
 * the oldest *)
val for_url : now:float -> ?script:bool -> Url.t -> jar -> cookie list

(* the Cookie header's value for [url]: "SID=31d4d96e407aad42;
 * lang=en-US"; None if there is none to send *)
val header : now:float -> ?script:bool -> Url.t -> jar -> string option

(* the jar without what is past its date *)
val alive : now:float -> jar -> jar
