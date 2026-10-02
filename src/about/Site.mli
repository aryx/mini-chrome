(* Site: the browser's built-in site, the about: pages -- data/about's
 * files, embedded by dune (Site_pages, Site_pictures), so that the
 * browser has something to show with no network, and a dumped frame
 * something that never changes.
 *
 * It is the browser's demonstration, and a short history of the web
 * in pages: each written as its time wrote them, and all read by the
 * one engine. They came with the teaching browsers this one was forked
 * from (elm-playground's TinyMosaic, TinyNetscape, TinyFirefox,
 * TinyChrome: docs/history.md), each of which had one as its home;
 * here they are pages of 1993, of 1995, of 1996, and today's. *)

(* about:NAME: its bytes and their Content-Type -- chrome (the home
 * page: a card for each thing the engine does, in today's CSS; its
 * sheets chrome.css and chrome-colours.css), history (the browsers, in
 * order), mosaic (or home, its first name: the web of 1993, HTML 2.0
 * alone, as Mosaic read it),
 * form (or form.html: a fill-out form, Mosaic 2.0's, answered by
 * about:echo), netscape (1995: Netscape's extensions to HTML), css
 * (1996: style sheets), firefox (pages that are programs) and its
 * four, counter, todo, timer and tictactoe, threads (comments folded
 * by threads.js, ES5 as Hacker News writes it), and picture.gif,
 * .png, .jpg *)
val about : string -> (string * string) option
