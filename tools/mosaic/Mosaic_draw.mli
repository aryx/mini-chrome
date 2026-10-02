(* Mosaic_draw: a page laid out by Mosaic_layout, drawn -- every line,
 * float, rule and list marker, as the playground's shapes.
 *
 * The words and pictures are Browser_draw's (the browser draws them
 * the same); what is here is what Mosaic's pages had around them and
 * CSS's boxes draw another way: a rule as Motif's inset line, a list's
 * bullet or number in its indent, and, with Netscape's extensions, a
 * <table border>'s bevelled frames -- the table raised, its cells
 * sunken -- and <hr noshade>'s flat bar. A style sheet's
 * background-color goes under its box.
 *
 * The coordinates and the culling are Browser_draw's: each thing with
 * its top and bottom on the page. *)

(* the whole page but its controls: every line, float, rule and marker;
 * with [extensions] (false), Netscape's <hr noshade> a flat bar and a
 * <table border>'s bevelled frames, the table raised, its cells
 * sunken *)
val draw :
  ?extensions:bool -> visited:(string -> bool) -> picture_of:(string -> Browser_picture.t option) -> Html_layout.box -> Browser_draw.drawn
