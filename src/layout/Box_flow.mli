(* Box_flow: a block being laid out (Box_types.ctx) -- how wide it is
   and where (the horizontal equation), the margin above it (collapsed
   with its first child's), and its content as it is read: words
   gathered from its text, then set on lines in an anonymous box when a
   block interrupts them (CSS 2.1 sections 8.3.1, 9.2.1.1 and 10.3.3;
   Box_layout.mli's "The box" and "Vertical margins collapse").

   The horizontal equation, margin-left + border + padding + width +
   padding + border + margin-right = the containing block's width, the
   autos its unknowns:

     containing block 976, width 400, padding 10, border 1, margins auto
       horizontal: (277, 400, 277) -- the box at x 277, 422 wide
     width auto, margins 0:  (0, 954, 0)

   And two margins that touch are one, the larger:

     collapse 8. 21.4 = 21.4      collapse 10. (-4.) = 6.

   Box_layout does the recursion: these are the steps it composes. *)

open Box_types

(* {1 Sizes and margins} *)

(* a size in pixels, a percentage of [base]; auto None *)
val size : Computed.size -> float -> float option

(* a box that lays out its own content apart (a block formatting
 * context): its floats its own, its margins not collapsed with its
 * children's *)
val own_context : Computed.t -> bool

(* the larger margin, a negative one subtracted *)
val collapse : float -> float -> float

(* the margin above an element: its own collapsed with its first
 * child's, through no border and no padding *)
val top_margin : env -> Dom.element -> Computed.t -> cb_width:float -> float

(* [horizontal style ~cb_width ?content ()]: margin-left, the content's
 * width, margin-right; [content] a width already decided (shrink-to-fit,
 * a table's cell). min-width and max-width clamp it, box-sizing counts
 * padding and border in *)
val horizontal : Computed.t -> cb_width:float -> ?content:float -> unit -> float * float * float

(* {1 A block's content} *)

(* a space, in HTML's sense *)
val is_space : char -> bool

(* a word (or a picture, a control, an inline-block: [boxed]) added to
 * the block's inline content, [width] wide; [glue] no break before it *)
val add_word : ?boxed:boxed -> ?owner:Dom.element -> ?edge:edge -> ctx -> word_style -> glue:bool -> string -> float -> unit

(* a text's words added, cut and kept as its white-space says *)
val add_text : ctx -> Computed.t -> word_style -> string -> unit

(* the block's inline content so far set on lines, in an anonymous box
 * added to its children *)
val flush_inline : ctx -> unit
