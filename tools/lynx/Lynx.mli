(* Lynx: the web in a terminal -- a page as lines of text, its links
   numbered, a number typed to follow one.

   The first browser most people could run was not the one with a
   window: CERN's Line Mode Browser (1991) worked on any terminal, and
   Lynx (University of Kansas, 1992) is still used. They are a browser
   with the hard parts left out -- no fonts, no boxes, no pictures --
   and so the shortest path through one:

       an address --Http_client--> bytes --Charset--> text
                  --Html_tree--> the tree --Line_mode--> lines, links
                  a number typed --Browser_url.resolve--> an address

   A page shown ([show]): its title, its lines, and the addresses of
   its links by their numbers, each resolved against the page's own:

     Menu  (http://localhost/menu.html)

                                     Menu

     Soup of the day. See the recipes[1] or go back home[2].

     [1] http://localhost/recipes.html
     [2] http://localhost/

   What is typed after a page ([step]): a link's number to go there,
   an address to go to it, "b" to come back, "q" to leave, nothing to
   see the page again.

   An address without "http://" is a file when there is one of that
   name, else a host. Styles and scripts are not read; a form cannot be
   filled.

   Worked example (tests/tools/Unit_lynx.ml): the page above served by
   mini-httpd's Httpd, opened, its link 1 followed, then "b".

   Reference: the Line Mode Browser (libwww, 1991); lynx(1). *)

(* a page read: its address (after the redirections), its title, its
 * lines and its links' addresses *)
type page = { url : string; title : string; lines : string list; links : string list }

(* [open_ caps address]: fetched (http://, https://) or read (a file's
 * name), decoded, laid out in [width] columns (80) *)
val open_ : < Cap.network ; Cap.open_in ; .. > -> ?width:int -> string -> (page, string) result

(* the page as text: the title and address, the lines, the links *)
val show : page -> string

(* a session: the page shown and those before it *)
type t = page list

(* what a line typed asks of the session *)
type step =
  | Go of t (* another page shown: a link followed, an address opened, back *)
  | Stay of string (* the same page; what to say ("no link 9") *)
  | Quit

val step : < Cap.network ; Cap.open_in ; .. > -> ?width:int -> t -> string -> step
