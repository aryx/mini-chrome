(* Browser_devtools: what a browser's developer tools show, as lines
 * of text -- TinyChrome's panel (plan_tiny_chrome.md C7), after
 * Chrome's (2008, WebKit's Web Inspector) and Firebug's before it
 * (TinyFirefox's panel).
 *
 * Three views, each a list of lines the browser draws in its panel:
 *
 * cs-history:
 * The first tool was View Source: a page's HTML shown as it came, in
 * every browser since the first, and how a generation learned to
 * write pages -- by reading other people's. Scripts and styles made
 * the source not enough: what matters is the tree as it now is and
 * which rule won. Mozilla had a DOM Inspector and a JavaScript
 * debugger (Venkman, 2001); Joe Hewitt's Firebug (January 2006), an
 * extension for Firefox, put the tree, the styles, the console and
 * the network's requests in one panel under the page, edited live,
 * and writing for the web became a different trade. WebKit's Web
 * Inspector (2006) and Chrome's tools (2008) are its descendants; the
 * protocol they speak to the page is also how a program drives a
 * browser with no window (Puppeteer, 2017).
 *
 *   the element    its place in the tree (html > body > div.card > p),
 *                  its tag, its box on the page (Box_layout's: x, y,
 *                  width, height), its children;
 *   its styles     the declarations that won the cascade, each with
 *                  where it came from -- a rule's selector and its
 *                  sheet, an attribute, style= (Browser_page.explain,
 *                  over Cascade.explain): why a heading is blue, which
 *                  of the page's forty sheets said so;
 *   the network    each request of the page (Browser_tab's log): its
 *                  status, kind, size, and time -- the browser's clock,
 *                  the start and the end it saw -- and a summary. *)

type color = int * int * int
type line = string * color

(* the element's view: [e] a page's element *)
val element : Browser_page.t -> Dom.element -> line list

(* its styles, winning declarations and their sources *)
val styles : Browser_page.settings -> Browser_page.t -> Dom.element -> line list

(* the network's view; [times url] the request's start and end (if
 * done), in seconds of the browser's clock *)
val network : Browser_tab.request list -> times:(string -> (float * float option) option) -> line list

(* where an element is on the page, if it is laid out: its block's
 * box, or its words' (x, y, width, height, y down) -- for the
 * inspector's outline *)
val box_of : Browser_page.t -> Dom.element -> (float * float * float * float) option
