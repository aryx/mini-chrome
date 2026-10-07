(* Bookmarks: the pages a person chose to keep at hand.

   A star at the omnibox's end, yellow when the page shown is one of
   them: a click on it (or Ctrl+D) keeps the page, another lets it go.
   Those kept are in a bar under the toolbar, a name each, a click
   away; about:bookmarks lists them whole. They are the profile's (the
   "bookmarks" of Preferences, a list of { "url", "title" }): saved
   with it, and a person may put them in order there by hand.

     |  <-  ->  C   [ https://dynamicland.org/                  * JS ]  |
     |  Dynamicland front shelf   Hacker News   Wikipedia               |   <- the bar

   cs-history:
   Mosaic had a "hotlist" (1993), a menu of pages to come back to,
   kept in a file of the user's; Netscape called them bookmarks and
   wrote them as a page of HTML, bookmarks.html, which could itself be
   opened, sent to a friend, put on a site -- several early
   directories of the web, Yahoo among them, began as one person's
   list of links. Internet Explorer's were "favorites", a file each
   in a folder, and its request for a favorite's picture is the
   favicon (Ico.mli). The star in the address bar is Firefox 3's and
   Chrome's, both of 2008; before, keeping a page was a menu's item
   and a dialog to answer.

   modern:
   A browser's bookmarks are a tree of folders, with tags and
   keywords, kept in a database and synchronised between a person's
   machines; here a list, in the order they were kept. *)

type entry = { url : string; title : string }
type t = entry list

val has : t -> string -> bool

(* the page kept if it was not, let go if it was *)
val toggle : t -> url:string -> title:string -> t

(* the profile's "bookmarks", and back (what is not one is left out) *)
val to_json : t -> Json.t
val of_json : Json.t -> t

(* about:bookmarks *)
val page : t -> string

(* The bar: built from the model, as libs/gui's pieces are.
   [left], the x its first name starts at; [y], its line's middle *)
type bar = { left : float; y : float; room : float; entries : t }

val bar_height : float

(* the address of the name at a point *)
val at : bar -> float * float -> string option
val shapes : bar -> pointer:float * float -> Playground.shape list

(* the star, at a point: yellow if the page is kept, else an outline's grey *)
val star : kept:bool -> float -> float -> Playground.shape list
