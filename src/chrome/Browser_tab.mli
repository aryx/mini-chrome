(* Browser_tab: one page being browsed, and how it goes elsewhere --
   what a browser's window holds in each of its tabs.

   A browser is two things: its chrome (the title, the toolbar, the
   Location field: each browser's own) and what it shows, a **tab**: the
   page (loading, or shown and scrolled), the history behind and ahead,
   the pictures fetched and still to fetch, the form's field in focus,
   and -- when the browser runs scripts -- the page's script world
   (Browser_script), a JavaScript realm per page. TinyNetscape and
   TinyFirefox have one tab each; Firefox's tabs (2004, after Opera's
   and Mozilla's own) are a list of these, an exercise.

   cs-history:
   Tabs are older than they look. A window per page was the rule from
   Mosaic on; several pages in one window appeared in InternetWorks
   (BookLink, 1994), then NetCaptor (1997) and Opera, and reached most
   people through Mozilla (2001) and Firefox (2004); Internet Explorer
   took them in 2006. Chrome (2008) made two changes that stayed: the
   tabs above the address, which belongs to the page and not to the
   window, and each tab's page in a process of its own, so that one
   page's crash or busy script is that tab's alone (told as a comic,
   drawn by Scott McCloud, the day it shipped). Here a tab is a value,
   and all of them are one process: docs/architecture.md.

   Going somewhere:

     visit url     the page now kept in the history, then [load]
     load url      an about: page read at once (the built-in site); an
                   http:// or https:// one asked for (Cmd.Http_get), the
                   tab Loading until [got] answers
     got           the page read (Browser_page.read), its scripts run if
                   the browser has them, laid out again from the tree
                   they left; its pictures queued; a <meta
                   http-equiv=refresh content="0; url=..."> followed at
                   once, in its place (a second or less; one in a
                   <noscript> only if its scripts do not run) -- how
                   DuckDuckGo's links reach their result without a
                   script
     back, forward the history's two stacks (Browser_history): a page
                   kept is shown again at once, as it was scrolled

   The pictures come **four at a time** (Netscape's connections; Mosaic
   fetched one after the other): [fetch_more] keeps [connections] of them
   in flight, [got_picture] takes one in, decodes it, lays the page out
   again, and asks for the next. Stop forgets the rest.

   A page whose scripts run has its **scripts of their own file**
   (<script src>, Browser_script.script_sources) fetched the same way,
   before its pictures; its scripts run, in order, once the last has
   come (the page shown meanwhile as it came, where a browser waits);
   the GETs they queue (XMLHttpRequest, fetch) are sent after each
   task, their answers dropped.

   A page laid out by the box model (TinyChrome's) has its **style
   sheets** fetched the same way, ahead of its pictures: its <link
   rel=stylesheet>s, then the @imports of those that have come
   (Browser_page.sheets_wanted); [got_picture] takes a sheet in too
   (it is in [sheet_urls]), and the page is laid out again with it -- a
   page is shown at once, plain, and dressed as its sheets arrive,
   where Chrome waits for them (a few hundred milliseconds of a blank
   window, to avoid that flash).

   What varies between browsers is a [config]: their looks (the page's
   settings: Netscape's extensions, CSS), their messages (what a
   response is turned into), their built-in site, the page area's size,
   whether they run scripts. *)

type state = Loading of string | Shown of Browser_page.t

(* what was asked for, for a network panel (TinyChrome's): the page,
 * its style sheets, its pictures, each pending (no status) or answered
 * (0 if it could not be had), its size; the log starts again with each
 * page *)
type kind = Document | Sheet | Script | Picture | Media | Fetch (* Media: a <video>'s or an <audio>'s file; Fetch: a script's GET *)
type request = { url : string; kind : kind; status : int option; bytes : int }
type view = Page | Source

(* a page in the history: where, and itself if it was shown, kept
 * whole to come back to (Bfcache) *)
(* [within]: the script of the document this entry is a state of, when
 * the page made it (history.pushState): going back to it loads no
 * page, the script is told (popstate) *)
type entry = { at : string; kept : Bfcache.t option; within : Browser_script.t option }

type t = {
  state : state;
  view : view;
  scroll : int; (* the first line shown, of [config.line_height] *)
  history : entry Browser_history.t;
  visited : string list;
  fragment : string option; (* a #name to scroll to once shown *)
  pictures : (string * Browser_picture.t) list; (* by URL, every page's: a cache *)
  pdf : Pdf_viewer.t option; (* the page shown is a PDF file's: its pages are pictures, drawn as they come into view *)
  sheets : (string * string) list; (* the style sheets' texts by URL, "" for one that could not be had: a cache *)
  sheet_urls : string list; (* the URLs asked for as style sheets *)
  queue : string list; (* the page's pictures still to fetch *)
  in_flight : string list; (* on their way *)
  total : int; (* the page's pictures to fetch, for the progress *)
  images : bool; (* Auto Load Images *)
  focus : Dom.element option; (* a form's field typed into *)
  script : Browser_script.t option; (* the page's scripts, if the browser runs them *)
  requests : request list; (* the page's, the newest first *)
  sources : (string * string) list; (* the texts of the pages' <script src>s, by URL: a cache *)
  pending_scripts : string list; (* the page's <script src>s still to come: its scripts run when none is *)
  media : (string * string) list; (* the bytes of <video>s' and <audio>s' files, by URL, "" if they could not be had: a cache *)
  media_urls : string list; (* the URLs asked for as media *)
}

(* the files of a page's <video>s and <audio>s, resolved: their src=,
 * else their first <source src=> -- fetched last, for the browser's
 * player (TinyChrome's Browser_media) *)
val media_sources : Browser_page.t -> string list

type 'msg config = {
  settings : t -> Browser_page.settings; (* the page's looks: the browser's, the tab's visited links and pictures *)
  about : string -> (string * string) option; (* the built-in site: about:NAME's bytes and type *)
  got : string -> (Fetch.response, Fetch.error) result -> 'msg;
  got_picture : string -> (Fetch.response, Fetch.error) result -> 'msg;
  got_answer : int -> string -> (Fetch.response, Fetch.error) result -> 'msg; (* a script's request's, by its number *)
  (* what a script's WebSocket asks (opened, a message sent, closed),
   * for the program to do (Web_sockets); what the socket says comes
   * back by [got_socket] *)
  socket : Script_types.socket_ask -> 'msg;
  (* a request for the program to carry out (Fetch): the tab asks for
   * what it needs by a message, never touching a socket *)
  fetch : 'msg Fetch.request -> 'msg;
  connections : int; (* pictures at a time *)
  visible : int; (* the page area's lines *)
  line_height : float;
  scripts : string -> bool; (* whether a page's <script>s run (Browser_script), by its URL *)
  cookies : Cookie_jar.t; (* the browser's cookies: what a page's document.cookie reads and sets *)
  seed : int; (* Math.random's *)
  epoch : float; (* the time when asked, in ms since 1970: where a page's Date starts *)
}

(* nothing shown yet; pictures loaded or not *)
val empty : images:bool -> t
val current_url : t -> string

(* the lines the tab's page (or its source) is long, of
 * [cfg.line_height]: what a scrollbar shows the part of *)
val line_count : 'msg config -> t -> int

(* the scroll moved by [by] lines, kept within the page *)
val scrolled : 'msg config -> int -> t -> t

(* laid out again: the same tree, the browser's looks changed (CSS off) *)
val relaid : 'msg config -> t -> t

val load : ?post:string * string -> 'msg config -> < Cap.network ; .. > -> string -> t -> t * 'msg Cmd.t
val visit : ?post:string * string -> 'msg config -> < Cap.network ; .. > -> string -> t -> t * 'msg Cmd.t
val back : 'msg config -> < Cap.network ; .. > -> t -> t * 'msg Cmd.t
val forward : 'msg config -> < Cap.network ; .. > -> t -> t * 'msg Cmd.t

(* not waiting any more: a page loading shown as stopped, the pictures
 * on their way forgotten *)
val stop : 'msg config -> t -> t

(* the pictures loaded now (Netscape's Images button) *)
val load_images : 'msg config -> < Cap.network ; .. > -> t -> t * 'msg Cmd.t

(* a page's answer: read and shown, or the page saying why not *)
val got : 'msg config -> < Cap.network ; .. > -> string -> (Fetch.response, Fetch.error) result -> t -> t * 'msg Cmd.t

(* a picture's answer: decoded (or broken), the page laid out again, the
 * next one asked for *)
(* the answer to a request a page's script made (XMLHttpRequest,
 * fetch), of that number and URL: given to the script, the page laid
 * out again if the script changed it *)
val got_answer : 'msg config -> < Cap.network ; .. > -> int -> string -> (Fetch.response, Fetch.error) result -> t -> t * 'msg Cmd.t

(* [got_socket cfg network id event]: what the connection of the
 * script's WebSocket of that number said, given to the script -- a
 * task, as an answer. A socket the page does not know (a page left
 * for this one) is closed. *)
val got_socket : 'msg config -> < Cap.network ; .. > -> int -> Websocket_client.event -> t -> t * 'msg Cmd.t

(* [details cfg network clicked tab]: if the element clicked is in a
 * <details>'s <summary>, the tab with it opened or closed
 * (Browser_details), laid out again; None if it is not *)
val details : 'msg config -> < Cap.network ; .. > -> Dom.element -> t -> (t * 'msg Cmd.t) option

val got_picture : 'msg config -> < Cap.network ; .. > -> string -> (Fetch.response, Fetch.error) result -> t -> t * 'msg Cmd.t

(* what a form's click or key did (Browser_forms): the focus moved, the
 * page's values changed (its script told, if it has one), or the form
 * sent *)
val form_effect : 'msg config -> < Cap.network ; .. > -> keep_focus:bool -> Browser_forms.outcome -> t -> t * 'msg Cmd.t

(* after a script's task (a click, a key, a timer): if the tree changed,
 * the page laid out again from it, the field in focus found again in
 * it, new pictures asked for *)
val after_task : 'msg config -> < Cap.network ; .. > -> t -> t * 'msg Cmd.t
