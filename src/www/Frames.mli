(* Frames: a document shown inside another -- <iframe>, and before it
   <frameset>.

   An <iframe> is a box of the page, 300 by 150 unless its style says
   (data/css/ua.css), in which another document is laid out as in a
   small window of that size: its own style sheets, its own tree. The
   document is the text of its srcdoc attribute, else what its src
   address gives.

     <p>before</p>
     <iframe srcdoc="<h1>inside</h1>" width=400 height=100></iframe>

     page's boxes                      the frame's document, laid out at
       body                            400 by 100, its boxes put under
         p "before"                    the iframe's box at its content's
         iframe 400x100                corner ([graft]): drawn with the
           html > body > h1 "inside"   page, clipped by the iframe's box,
                                       and a link in it found by a click

   So a frame costs the browser no second window: once its boxes are
   among the page's, what draws, scrolls and hit-tests a page does the
   same for what its frames hold. Three frames deep at most.

   A frame's scripts run in a world of their own (Browser_script.adopt,
   made by the tab for a document that has scripts): its own globals
   and its own document, on the page's clock, and what they leave of
   the document is what is laid out (the settings' [framed]). The two
   worlds share no object. They talk as two documents of different
   sites may in any browser, by messages alone:

     the page:   iframe.contentWindow.postMessage(data)
     the frame:  window.addEventListener("message", e => ... e.data ...
                   e.source.postMessage(answer))        // or parent.postMessage

   which is how a deck of slides in a frame is turned by its page, an
   embedded player told to pause. A key pressed is told to the frame
   too.

   Not yet: one document reaching into the other's (contentDocument,
   parent.document: same-site frames may, here none), a frame's
   scripts of a file not fetched for the page, a frame scrolled by
   itself (what is past its box is cut), a document's own address for
   its relative links when it came by src (they are taken as the
   page's), and <frameset>, which no page written since 2000 uses.

   cs-history:
   Frames were Netscape 2's (March 1996): <frameset> cut the window in
   panes, each a document with its own address -- a menu that stayed
   while the page beside it changed, at a time when a site's every
   page was a file written by hand and a menu repeated in each. They
   were everywhere by 1997 and resented soon after: the address bar
   showed the frameset's address whatever was read, so a page could be
   neither bookmarked nor linked to, Back went one pane at a time, and
   a search engine brought readers to a pane alone, without its menu.
   HTML 4 (1997) put them in a "Frameset" DTD of their own, beside the
   strict one; HTML5 removed them.

   The <iframe> -- a frame in the flow of a page, like a picture -- is
   Internet Explorer 3's (August 1996), and it had the other career.
   It is how a page of one site holds a piece of another's: an
   advertisement, a video's player, a map, a payment form whose card
   number the shop never sees. Before XMLHttpRequest, a hidden one was
   how a page asked its server for more without reloading (the page
   loaded in it called back its parent); Gmail's first chat was a
   request left open in one. And since a frame is another document
   with its own origin, it is where the web's rules of who may read
   whom are tested hardest: clickjacking (a page shown invisible under
   the pointer) brought X-Frame-Options, 2009; the sandbox attribute,
   srcdoc and postMessage -- the one door between two frames of
   different sites -- came with HTML5.

   modern:
   Chrome puts a frame of another site in another process (site
   isolation, 2018, hastened by Spectre: a page must not share an
   address space with what it may not read), each with its renderer,
   their pictures put together by the compositor; a frame is then the
   unit of the browser's architecture, as a tab was in 2008.

   References: the HTML Standard, 4.8.5 "The iframe element" and 7
   "Loading web pages" (navigables, the nested ones); Netscape's
   "Frames: an Introduction" (1996). *)

(* what an iframe shows: its srcdoc's text, or its src's address (as
   written: to resolve) *)
type source = Inline of string | Address of string

val source : Dom.element -> source option

(* the addresses of a tree's iframes that have no srcdoc: to fetch *)
val addresses : Dom.element -> string list

(* a document's text read to a tree; the same tree for the same text
   (what is computed from it is kept by its identity) *)
val tree_of : string -> Dom.element

(* how deep frames are followed: a frame's frame's frame, no further *)
val depth : int

(* [graft frame box]: each iframe's box of the tree given its document's
   boxes, moved to its content's corner. [frame e ~width ~height] lays
   that document out at its origin, None when it has not come *)
val graft : (Dom.element -> width:float -> height:float -> Box_types.box option) -> Box_types.box -> Box_types.box
