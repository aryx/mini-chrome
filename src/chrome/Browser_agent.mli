(* Browser_agent: what the browser says it is -- the User-Agent of its
   requests, and why it is not the same for every site.

   cs-history:
   A request says who is asking: "User-Agent: NCSA_Mosaic/2.0 (Windows
   3.1)". It was meant for statistics and for working round a
   browser's bugs. Servers used it at once to choose what to send:
   frames to Netscape ("Mozilla/2.0"), plain pages to the rest. So
   Internet Explorer called itself "Mozilla/2.0 (compatible; MSIE
   3.02...)", and every browser since has had to carry the names of
   those before it to be sent the good page (Script_window.mli tells
   the whole chain; Chrome's string still says Mozilla, AppleWebKit,
   KHTML, Gecko and Safari). The header says less and less about the
   browser, and more about which gates it has had to pass.

   A new browser meets the same gate from the other side: a site sends
   its page to the names it knows, and something else, or nothing, to
   a name it does not. Ours is one it does not.

   So the browser says its own name, [Http.default_agent], to
   everybody, but for the sites listed in [table], to which it says a
   name they send a page it can show:

     www.google.com   a search, asked by a browser it does not know,
                      is answered by a program to run (a challenge:
                      docs/sites.md) and no result. To the Opera Mini
                      of old phones, which ran no such program, it
                      still sends the results as plain HTML. We say
                      that name to Google, and only to Google.

   It is a false name, said knowingly: the same thing every browser's
   User-Agent has been since 1996, with less history behind it. The
   page that comes is the one made for a small browser with no
   scripts, which is what this one is to Google. The list is short on
   purpose and each line says why it is there; a site is not added to
   get round a refusal that is meant (a paywall, a robots rule), only
   where the plain page exists and the name alone keeps it away.

   What a page's script reads, navigator.userAgent, is another matter
   (Script_window) and says the browser's own.

   Reference: RFC 9110, section 10.1.5 (User-Agent); Aaron Andersen,
   "History of the browser user-agent string" (2008). *)

(* the hosts the browser gives another name to: a host (it and those
 * under it), the name, and why *)
val table : (string * string * string) list

(* what the browser says it is to that host *)
val for_host : string -> string
