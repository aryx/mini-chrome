(* Browser_draw: the parts of a laid-out page (Html_layout) as the
 * playground's shapes -- a word's letters by Hershey's pen, a picture
 * by its pixels, the lines under links, the form controls in Motif's
 * look (Mosaic's and Netscape's toolkit on X), and, for an inspector,
 * the boxes outlined. A whole page is put together from these by its
 * engine: CSS's boxes by Browser_boxes, Mosaic's by tools/mosaic's
 * Mosaic_draw.
 *
 * The page's coordinates are the layout's, x right and y down from the
 * page's top; the shapes here are the same turned over (y up, a line
 * below the top negative), so that a browser moves the whole page into
 * its window and scrolls it with one move. Each thing drawn comes with
 * its top and bottom on the page ([drawn]), so that a frame shows only
 * what is in the window (culling, [between]) -- and so that a line's
 * shapes are built only if it is ever shown ([later]).
 *
 * What the drawing needs to know that the layout does not, the browser
 * gives: which links were visited (purple), which pictures have come,
 * each control's value (the browser's, never the page's tree), and
 * which field has the keys (its caret). *)

(* things drawn, each with its top and bottom on the page; a thing's
 * shape may not be built yet *)
type drawn = (float * float * Playground.shape Lazy.t) list

(* things whose shapes are built already *)
val ready : (float * float * Playground.shape) list -> drawn

(* opti: [later f] is a shape built by [f] the first time it is
 * asked for, and kept; with opti=off (Mini_opti.enabled false) it is
 * built at once, the simple way, as it was. For a line of text.
 *
 * The problem. A letter is not one shape but its pen's strokes
 * (Stroke_text.glyph): a rectangle for each segment, turned by an
 * atan2 and as long as a sqrt, and a dot at each point -- ten to twenty
 * shapes a letter. Drawing a page was building them for every letter
 * of every line, at each relayout, and a page is laid out again each
 * time one of its pictures or style sheets arrives. The view then
 * kept the lines in the window and dropped the others:
 *
 *     the page, 16,000 high          drawn, an entry a line
 *    +---------------------+
 *    | Lorem ipsum dolor   |   (    0,    22, shape)  \
 *    | sit amet, consectet |   (   22,    44, shape)   | the window, 713
 *    |    ...              |      ...                  | high: 32 lines,
 *    | sed do eiusmod temp |   (  691,   713, shape)  /  kept by the view
 *    +- - - - - - - - - - -+
 *    | incididunt ut labor |   (  713,   735, shape)  \
 *    |    ...              |      ...                  | 700 lines built,
 *    | est laborum.        |   (15978, 16000, shape)  /  then dropped
 *    +---------------------+
 *
 * On Wikipedia's article on OCaml (docs/plans/plan_performance.md): 450 ms
 * of shapes for a layout of 22 ms, 24 times while the page loads, for
 * the 4% of the lines that show.
 *
 * Why this works. An entry's top and bottom come from the layout, for
 * nothing; only its shape costs. And the culling was there already:
 * the view asks [between] the window's top and its bottom. So the
 * order is turned round -- cull first, build after -- by making the
 * shape a promise:
 *
 *    (    0,    22, built)    <- asked for by a frame: built, kept
 *    (   22,    44, built)
 *       ...
 *    (  713,   735, not yet)  <- never shown, never built;
 *       ...                      scrolled to: built then, once
 *    (15978, 16000, not yet)
 *
 * A shape once built is kept (Lazy), so the next frame costs what it
 * did; a line scrolled away and back is still there; a relayout makes
 * a new list and the old shapes go with the old one. It is the same
 * shape either way: what builds it reads only the line's fragments and
 * what the browser knew at the layout (the links visited, the pictures
 * come), none of which change under it (the test "a line's shapes are
 * built when it is shown", and a frame dumped with and without).
 *
 * Measured, the same page (scripts/perf/Page_bench.exe, and opti=off):
 *
 *                                  opti=off      now
 *    a relayout, styles kept        450 ms      28 ms
 *    the page read, no sheet yet    796 ms     239 ms
 *    the first window's shapes        -          6 ms, once
 *    the load, to its last answer  14.8 s      6.2 s
 *
 * What it does not buy: a page that fits its window is built whole
 * (example.com); and the whole page's shapes are still 500 ms for
 * someone who scrolls through all of it, but spread, a window at a
 * time. Only the lines' shapes are promises: a box's background, a
 * marker, a rule are a few shapes, built at once ([ready]). *)
val later : (unit -> Playground.shape) -> Playground.shape Lazy.t

(* the shapes of what is, even in part, between [top] and [bottom] of
 * the page (the window's, for a frame): built now if they were not
 * ([later]), the others left as they are *)
val between : top:float -> bottom:float -> drawn -> Playground.shape list

(* a rectangle's outline, [t] (1) thick, its top-left at (x, y) of the
 * page, [w] by [h] *)
val frame : ?t:float -> Playground.color -> float -> float -> float -> float -> Playground.shape

(* Motif's two bevels, at (x, top), w by h: a raised thing (a button)
 * lit from the top left, a sunken one (a field) the other way *)
val raised : float -> float -> float -> float -> Playground.shape list

val sunken : float -> float -> float -> float -> Playground.shape list

(* a fragment's shapes: a word's letters (a link's in blue, purple if
 * [visited]), a picture ([picture_of] its src: arrived, the room kept,
 * the broken image; a link's framed in its colour); a control's are
 * [control_shapes]' *)
val glyphs :
  ?visited:(string -> bool) ->
  ?picture_of:(string -> Browser_picture.t option) ->
  ?decorated:bool ->
  Html_layout.fragment ->
  Playground.shape list
(* with [decorated] (true), its underline and its strike too,
 * its own; false for a line's fragments, whose lines are drawn a run
 * at a time: *)

(* the lines under and through a line's words ([fragments], left
 * to right): one for each run of neighbours of the same link, colour,
 * size and baseline, from the first's left to the last's right -- a
 * link of several words is underlined whole, the spaces between its
 * words too, as browsers draw it (a letter's own piece of line left
 * the spaces bare) *)
val decorations : ?visited:(string -> bool) -> Html_layout.fragment list -> Playground.shape list

(* a control with its [value], its caret if [focused] *)
val control_shapes :
  value:(Dom.element -> Forms.value) -> focused:bool -> Html_layout.fragment -> Html_layout.control -> Playground.shape list

(* every control of the page, drawn with its value (every frame: they
 * change as one types, where the rest is drawn once a layout) *)
val controls_drawn : value:(Dom.element -> Forms.value) -> focus:Dom.element option -> Html_layout.box -> drawn

(* the layout's boxes outlined, as a browser's inspector does: blocks
 * blue, the anonymous boxes of inline content green, their lines grey *)
val outlines : Html_layout.box -> drawn
