(* Box_inline: a block's inline content set on lines -- words, pictures,
   controls and inline-blocks side by side on a shared baseline, each
   line as wide as the floats beside it leave (CSS 2.1 sections 9.4.2,
   9.5 and 10.8; Box_layout.mli's "Inline content", "An inline
   element's box" and "Floats").

   The items come in the page's order (Box_types.item: a word, a break,
   an anchor, a float, a clear). They are cut into units (the words
   with no space between), and lines are filled greedily:

     float: left, width 40, height 30; then "aa bb cc", a page 200
     with a margin of 8, a character 10 wide

     the float      at x 8..48, from the line's top: placed
     room           beside it 144 from x 48; under it (30 lower) 184
                    from x 8
     the line       "aa" at 48, "bb" at 78, "cc" at 108

   A line is as tall as its words need above and below the baseline
   (their own line-height, split as half-leading around the font's 0.8
   and 0.2 em), at least the block's own (the strut). An inline
   element with a background or a border gets a box per line it is on
   (the backdrops). *)

open Box_types

(* the look a fragment of text in this style is drawn with (Browser_draw
 * draws looks): its size, weight, slant, face, colour, decoration;
 * [link] the href around it *)
val look_of : Computed.t -> link:string option -> Looks.t

(* a function over the four sides: top, right, bottom, left *)
val four : ('a -> 'b) -> 'a * 'a * 'a * 'a -> 'b * 'b * 'b * 'b

(* a style's words: their look, their room above and below the
 * baseline, the baseline moved (sub, super) *)
val word_style : Computed.t -> link:string option -> word_style

(* the room for a line from [top], [height] high, beside the floats: its
 * left edge and its width *)
val room : placed list -> x:float -> width:float -> top:float -> height:float -> float * float

(* [top], or lower: below the floats of the sides *)
val cleared : placed list -> side list -> float -> float

(* a float put at [top] against its edge of the room there (below the
 * floats beside it if it does not fit), its box moved there and added
 * to the boxes *)
val place : placed list ref -> x:float -> width:float -> top:float -> box list ref -> item -> unit

(* [set_lines floats strut align ~pre ~x ~width ~top items]: the items
 * set on lines from [top] in a column at [x], [width] wide; [strut] the
 * block's own words' style, [pre] the lines kept as written. The lines,
 * the boxes set in them (inline-blocks, floats), the inline elements'
 * boxes (the backdrops), and the bottom *)
val set_lines :
  placed list ref -> word_style -> Looks.align -> pre:bool -> x:float -> width:float -> top:float -> item list ->
  Html_layout.line list * box list * box list * float
