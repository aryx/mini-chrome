(* Text drawn from Hershey's own strokes, in a look -- how the two word
 * processors here get bold, italic, underline and strike out of a
 * playground whose [words] knows only a colour and a string.
 *
 * A Hershey glyph (graphics/font, 1967) is a few pen strokes, so
 * drawing one ourselves is drawing its strokes -- each segment a thin
 * rectangle, each point a dot as wide (a round pen: no corner sticks
 * out of a joint, however zoomed) -- and a look is then a change to
 * the *pen*, not a second font:
 *
 *   bold       a thicker pen (Hershey's own duplex and triplex faces
 *              are the same letters drawn with more strokes: the
 *              plotter's way to be bold)
 *   italic     the strokes' points sheared right as they go up, a
 *              fifth of their height -- a slant, which is what an
 *              oblique face is (a true italic is drawn differently)
 *   underline  a rule below the baseline, and strike one through the
 *              middle, as a typewriter's backspace-and-overstrike did
 *
 * and because the same glyph data gives the widths ([metrics]) and the
 * strokes, what is laid out is exactly what is drawn: the caret goes
 * between two letters where they really meet, which is what the rest
 * of the toolkit, measuring with an average width, could not promise.
 *
 * Next to the Playground's own [words] (Playground.mli), which also
 * draws text:
 *
 *                 Playground.words            Stroke_text.glyph
 *   takes         a colour and a string       a colour, a look, one
 *                                             character
 *   gives         one shape, the platform's   the letter's strokes as
 *                 to draw                     shapes: rectangles, dots
 *   the letters   the platform's: Cairo's     Hershey's on every
 *                 sans-serif, or Hershey's    platform: a page is laid
 *                 in the software one         out the same on both
 *   looks         none; [scale] for a size    bold, italic, underline,
 *                                             strike, any size
 *   placed        centred on a point          left edge and baseline
 *   width         not known to the program    [metrics], exact
 *
 * A word wrapped at the right place needs the last three, so a page's
 * text is drawn here. The chrome's own text (a tab's title, the
 * address: Gui_text) is [words], a character a cell: a column needs no
 * width, and Cairo's letters are smoother than a pen's.
 *
 * Shared by the office apps (TinyBravo and TinyWord first) and
 * TinyMosaic. *)

(* the width of a character in a look: Hershey's, scaled to its size *)
val metrics : Page.metrics

(* [glyph color look ch ~x ~baseline]: [ch] drawn in [look], its left
 * edge at [x] and its baseline at [baseline], in the playground's
 * coordinates (y up) *)
val glyph :
  Playground.color -> Style.t -> string -> x:float -> baseline:float -> Playground.shape list
