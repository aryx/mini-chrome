(* Browser_page: a page, read and laid out -- the whole pipeline of
 * the web engine (languages/html, languages/css, src/layout) in one
 * place, from the bytes a server sent to the shapes a browser shows:
 *
 *   bytes -Charset-> text -Html_lexer-> tokens -Html_tree-> tree
 *         -Cascade, Computed-> styles -Box_layout-> boxes
 *         -Browser_boxes-> shapes
 *
 * (the last line is CSS's; the older browsers of tools/ put their own
 * there, Mosaic's looks and layout: [engine])
 *
 * keeping every stage (a browser's views show each), and what the
 * person did to it: its form controls' values, the browser's, not the
 * tree's.
 *
 * What the layout and the drawing need that the page does not say is
 * the browser's, given as [settings]: the page's width (and the height
 * of the window showing it, for CSS's vh), how lines are
 * broken, which URLs were visited (a link purple), which pictures have
 * come -- a page is laid out again when any of them changes (a reflow).
 *
 * And the pages a browser writes itself, laid out like any: what is not
 * HTML made one (text in <pre>, as Mosaic showed it), an error, a
 * form's echo (what a server would read). *)

type t = {
  url : string; (* where it came from, after the redirections *)
  status : int; (* 200; 0 for a page that could not be had *)
  charset : Charset.t;
  bytes : int;
  lines : string list; (* the text, UTF-8, tabs expanded: its source *)
  tokens : Html_lexer.token list;
  tree : Dom.element;
  line_mode : Line_mode.t;
  title : string; (* the text of its <title>, or "" *)
  layout : Html_layout.box;
  drawn : Browser_draw.drawn; (* all but its controls, drawn once a layout *)
  background : Looks.color option; (* <body bgcolor=>, Netscape's; or its style sheets' *)
  forms : Forms.form list;
  values : (Dom.element * Forms.value) list; (* the controls changed, by element (==) *)
  quirks : bool; (* no DOCTYPE: quirks mode (Computed.styles), by the box model *)
  backgrounds : string list; (* by the box model: the pictures of its boxes' background-image, absolute URLs *)
  frames : (string * Dom.element) list; (* the documents its <iframe>s show (Frames), each with the address its links are of: their boxes are in [layout] *)
}

(* another way to lay a page out and draw it than CSS's box model: the
 * older browsers' (tools/mosaic's Mosaic_page.engine: Mosaic's fixed
 * looks, Netscape's extensions). Given the links visited and the
 * pictures come (the page's own addresses, as it wrote them), the
 * page's width and its tree; gives the boxes and lines every layout
 * here gives, their shapes, and the page's colour if it has one *)
type engine =
  visited:(string -> bool) -> picture:(string -> Browser_picture.t option) -> width:float -> Dom.element -> Html_layout.box * Browser_draw.drawn * Looks.color option

type settings = {
  css : bool; (* the page's style sheets honoured: <style>, style=, <link> *)
  engine : engine option; (* None: CSS 2.1's box model (Cascade, Computed, Box_layout, Browser_boxes), the browser's *)
  width : float;
  height : float; (* the window's part that shows the page: 100vh, a media query's height *)
  visited : string -> bool; (* an absolute URL, no #fragment *)
  picture : string -> Browser_picture.t option; (* an absolute URL *)
  sheet : string -> string option; (* a style sheet's text, once it has come (an absolute URL) *)
}

(* [read settings url status content_type bytes]: the page, through the
 * whole pipeline *)
val read : settings -> string -> int -> string option -> string -> t

(* the same tree laid out and drawn again: a reflow *)
val laid_out : settings -> t -> t

(* the page with another tree, laid out and drawn (its title, forms and
 * line mode too; its source stays): what a script left
 * (Browser_script.tree) *)
val with_tree : settings -> t -> Dom.element -> t

(* where each element of a laid out page is: its block's box, or the
 * box around its words (x, y, width, height, from the page's top) *)
val where : t -> Dom.element -> (float * float * float * float) option

(* by the box model, with its style sheets: the addresses of the
 * sheets the page asks for and does not have yet ([settings.sheet]) --
 * its <link rel=stylesheet>s whose media= holds, and the @imports of
 * those it has, to fetch; the page laid out again as each comes *)
val sheets_wanted : settings -> t -> string list

(* by the box model: an element's winning declarations (Cascade.explain)
 * as (property, value, where it came from: a rule's selector and its
 * sheet's name -- its address, <style> n, the browser's -- an
 * attribute, style=), a developer tools' Styles pane *)
val explain : settings -> t -> Dom.element -> (string * string * string) list

(* a control's value now: as typed and clicked, else as the page gave
 * it *)
val value_of : t -> Dom.element -> Forms.value

val with_value : t -> Dom.element -> Forms.value -> t

(* a response's media type: "text/html; charset=utf-8" is "text/html" *)
val media_type : string option -> string

(* a page that could not be had, laid out like any: its URL, why *)
val error_html : string -> string -> string

(* a form's fields, as a server would read them: the method ("GET",
 * "POST") and what was sent, encoded (the query or the body), decoded
 * too *)
val echo_html : string -> string -> string
