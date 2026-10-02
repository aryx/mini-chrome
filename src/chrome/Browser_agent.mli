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
   everybody, and has a table, [table], of the sites it would give
   another name to, each with the reason. The table is empty, and here
   is the one that was in it:

     google.com   a search, asked by a browser Google does not know, is
                  answered by a program to run (a challenge:
                  docs/sites.md) and no result. To the Opera Mini of
                  old phones, which ran no such program, it sent the
                  results as plain HTML. Said to be that one, a search
                  worked -- when the consent page before it was
                  refused; accepted, the search answered 403. A false
                  name that works by one path and not by another, for
                  a site that does not want to be read by what it does
                  not know: taken out the day it went in. The omnibox
                  searches elsewhere (Window_tabs.search_url).

   road-not-taken:
   The lesson is the user agent's own. A name borrowed gets the page
   made for that name, with what its owner did not need and without
   what the borrower does; and a site that sorts its readers by name
   will sort them again tomorrow by something else. A line goes in
   the table only where a plain page exists, the name alone keeps it
   away, and it works by every path -- and never to get past a
   refusal that is meant (a paywall, a robots rule).

   What a page's script reads, navigator.userAgent, is another matter
   (Script_window) and says the browser's own.

   Reference: RFC 9110, section 10.1.5 (User-Agent); Aaron Andersen,
   "History of the browser user-agent string" (2008). *)

(* the hosts the browser gives another name to: a host (it and those
 * under it), the name, and why *)
val table : (string * string * string) list

(* what the browser says it is to that host *)
val for_host : string -> string
