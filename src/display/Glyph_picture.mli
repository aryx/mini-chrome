(* A letter drawn as one small picture, made once and kept, instead of
   the ten to twenty shapes of its pen's strokes.

   The way a page's letters are drawn (docs/plans/plan_performance.md, step
   4b, "a letter a picture"). Stroke_text.glyph chooses
   (Mini_opti.letters); the simple way, its own glyph_segments, is what
   one reads first, and what letters=segments or opti=off on the
   command line give back.

   The problem. Stroke_text draws a letter as its pen went: a rectangle
   for each segment of each stroke, a dot at each point. The platform
   draws shapes one by one (a save, a colour, a transform, a path, a
   fill, a restore), so a window of 1,400 letters is 20,000 shapes and
   70 ms a frame: a scroll at 14 frames a second.

       'A', the pen's way                    'A', a picture
       3 strokes, 8 points:                  made once, 9 by 14 pixels:
         5 rectangles + 8 dots                 . . . # # . . .
         = 13 shapes, at each frame            . . # . . # . .
                                               . # # # # # # .
                                               # . . . . . . #
                                             1 shape, at each frame

   Why it can work. A page says the same few letters again and again:
   an 'e' in the text's size and colour is the same picture wherever it
   is. So the letter is rasterized once, into an Rgba_image, kept by
   what makes it (the character, the look's size, weight and slant, the
   colour, the scale), and drawn as a [Playground.bitmap], one shape.

   How it is rasterized: the round pen is the set of points nearer to
   the strokes than half its width. So a pixel's opacity is read off
   its distance to the nearest segment,

       alpha = clamp (pen / 2 - distance, in pixels, + 0.5)

   one pixel of soft edge: an antialiased "capsule" round each segment,
   their union the letter. No rasterizer is needed for that, and none
   is here that a platform has: the picture is the same under Cairo and
   under our own.

   What it costs. A picture is pixels, made for one size on the screen:
   [density], the screen's dots for one unit of the page (the window's
   scale times the page's zoom, times the dots a Retina screen has for
   a point), set by the view before any letter of
   the page is built (Window_view.page_shapes: a line's letters, a list
   item's number, a control's text are all built there, when shown --
   not at the layout, which knows no screen). At another density the letters are other pictures
   (the cache keeps them apart). And a picture lands on whole pixels
   where a shape could start between two: a letter is moved by up to
   half a pixel to be sharp, so the spaces between letters are not
   quite the pen's. The frame is no longer the simple way's pixel for
   pixel: close to it, not equal. *)

(* the screen's dots for one unit of the page: 1 unless the view says *)
val density : float ref

(* [shape ~key ~pen ~strokes ~x ~baseline]: the letter whose pen, [pen]
 * wide, goes along [strokes ()] (the page's units, from the letter's
 * left edge on its baseline, y up), its left edge at [x] and its
 * baseline at [baseline]. [key] is all that the strokes and the pen
 * depend on, with the colour: the picture is made the first time, and
 * [strokes] not asked again. None for a letter without ink. *)
val shape :
  key:string * Style.t * (int * int * int) ->
  pen:float ->
  strokes:(unit -> (float * float) list list) ->
  x:float ->
  baseline:float ->
  Playground.shape option

(* how many pictures are kept (the tests, the bench) *)
val kept : unit -> int
