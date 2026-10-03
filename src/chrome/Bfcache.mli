(* Bfcache: the back/forward cache -- a page left is kept whole, so
 * that Back shows it at once and as it was.
 *
 * Going back could be done by asking for the page again: its address
 * is in the history. But that is a second of network, the scripts run
 * again from nothing, and the page comes back at its top with its
 * form empty and its list collapsed. So a browser keeps the page it
 * leaves -- not its bytes (that is the HTTP cache's), the page itself,
 * alive but frozen:
 *
 *   page       the document as it was, tree and layout: what the
 *              scripts had added is there, what was typed too
 *   script     its scripts' world -- every variable, every listener,
 *              the timers waiting; none runs while the page is away
 *   document   a PDF file's (Pdf_viewer), for a page that was one
 *   scroll     how far down it was
 *
 * and Back or Forward puts that back in the tab (Browser_tab.restore)
 * instead of loading. An entry of the history (Browser_history) is an
 * address and, if the page got as far as being shown, one of these.
 *
 * wib: every page is kept, for as long as its tab: no limit on how
 * many, none on memory, and no page is refused. A page's sockets and
 * requests in flight are not frozen with it (a WebSocket of a page
 * left stays open until its next message).
 *
 * cs-history: the name is Firefox's: "bfcache", in Firefox 1.5
 * (2005), with two events made for it -- pagehide and pageshow, since
 * a page restored is not loaded and gets no "load" a second time.
 * Safari has one too, its "page cache". Chrome did without for long
 * (it relied on its HTTP cache and fast loads) and added one in 2020
 * on Android and 2021 on the desktop.
 *
 * modern: a real one refuses pages it cannot freeze safely -- for
 * years, any page with an "unload" handler (written for a world where
 * leaving meant dying), a page holding a connection open, one served
 * with Cache-Control: no-store -- keeps a few pages only, and drops
 * them after a time. Much of making sites "bfcache-friendly" is
 * removing what gets them refused.
 *
 * Reference: the HTML Standard, on session history and "fully
 * active" documents; web.dev, "Back/forward cache" (Philip
 * Walton, Barry Pollard). *)

(* a page kept: itself, its scripts' world, its PDF document if it is
 * one, and how far down it was scrolled (in lines) *)
type t = { page : Browser_page.t; script : Browser_script.t option; document : Pdf_viewer.t option; scroll : int }
