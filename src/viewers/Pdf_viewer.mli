(* Pdf_viewer: a PDF file shown in a tab -- as a page of ours, each of
 * its pages a picture.
 *
 * The browser has a layout engine and scrolling already, so the
 * viewer is small: the document is turned into HTML,
 *
 *   <body style="background: grey">
 *     <div><img src="pdf-page:1" width=816 height=1056></div>
 *     <div><img src="pdf-page:2" ...></div>
 *
 * one <img> a page, at the page's size (a PDF's point is 1/72 inch, a
 * CSS pixel 1/96), white until its picture comes. The tab
 * (Browser_tab) draws the pages that are in view, and a little
 * before and after, as it is scrolled, and lets go of the others: a
 * page's picture is megabytes, a book a thousand pages. Zooming,
 * scrolling, the scroll bar, going back: all the browser's own.
 *
 * The drawing itself is libs/pdf's (Pdf_render); [options] says how
 * much of it is done (the flag pdf=: pdf=strokes for our letters,
 * pdf=plain for the simplest rendering).
 *
 * modern: Chrome's viewer is a plug-in process of its own around
 * PDFium; Firefox's is a web page -- PDF.js, HTML and JavaScript
 * drawing on <canvas> elements, one a page, made as they scroll into
 * view. This is the second kind, with the drawing done in OCaml. *)

type t

(* how much of a page's drawing is done: all of it unless set *)
val options : Pdf_render.options ref

(* dots of a page's picture for each CSS pixel *)
val density : float

val sniff : string -> bool

(* a file's bytes; why not, if it cannot be shown *)
val open_ : string -> (t, string) result

(* the document as HTML, titled by its file's name *)
val html : t -> name:string -> string

(* a page's address in that HTML ("pdf-page:3"), and back *)
val src : int -> string

val page_of_src : string -> int option

(* a page drawn, from 1 *)
val picture : t -> int -> Rgba_image.t
