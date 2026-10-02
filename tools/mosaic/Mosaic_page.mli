(* Mosaic_page: Mosaic's engine as the browser's page pipeline takes
 * one -- the looks, the layout and the drawing put together.
 *
 * Browser_page reads a page (the bytes decoded, the tokens, the tree:
 * the same for every browser here) and then lays it out and draws it
 * by CSS's box model, unless its settings give another engine. This
 * is the other: the one the web started with.
 *
 *   tree -Mosaic_looks-> a look for each element (and, with ~css, the
 *                        page's style sheets over it: Css.cascade)
 *        -Mosaic_layout-> boxes and lines
 *        -Mosaic_draw->   shapes
 *
 * Three browsers are its settings:
 *
 *   mini-mosaic     engine ()                          HTML 2.0, 1993
 *   mini-netscape   engine ~extensions:true ~css ()    1994 to 1997
 *   mini-firefox    the same, and the page's scripts   2004
 *
 * The page's colour is Netscape's <body bgcolor> (with ~extensions),
 * or its style sheets' background for <body> or <html> (with ~css). *)

(* Knuth and Plass's lines (Linebreak.optimal), ragged right as a
 * browser's are -- the spaces may stretch (a line may end short), not
 * shrink (it may not end past the edge) -- with the paragraph's first
 * real space for all (Linebreak's model has one): CSS's text-wrap:
 * pretty *)
val pretty : Html_layout.breaker

(* [engine ?extensions ?css ?breaker ()]: the engine; Netscape's
 * extensions to HTML honoured (false), the page's <style> and style=
 * honoured, CSS1's (false), its lines broken by [breaker] (greedy) *)
val engine : ?extensions:bool -> ?css:bool -> ?breaker:Html_layout.breaker -> unit -> Browser_page.engine
