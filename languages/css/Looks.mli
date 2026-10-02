(* Looks: a look -- how a run of text is to be drawn, once somebody
   has decided: its size, bold or not, its colour, the link it is in.

   Every word of a page laid out carries one (Html_layout.fragment),
   and the drawing reads nothing else. Who decides is the engine:

     CSS's, the browser's     the computed style of the word's element
                              (Computed), made a look when the word is
                              set on its line (Box_inline)
     Mosaic's, tools/mosaic   a table, element by element, the look
                              inherited down the tree (Mosaic_looks,
                              where the table and its history are)

   A look is what the two share, and all a pen of one font can show:
   CSS's font-family is here fixed width or not.

   Also here, what both read of old HTML: a colour as pages wrote them
   ([color_of_string]: bgcolor=, <font color=>), <font size=>'s scale
   ([font_scale]).

   Reference: CSS 2.1, section 6.2 (inheritance) and chapter 15
   (fonts); HTML 3.2 (the 16 colour names, <font>). *)

type color = int * int * int (* red, green, blue, 0-255 *)
type align = Left | Center | Right

type t = {
  size : float; (* an em, in the page's units *)
  bold : bool;
  italic : bool;
  underline : bool;
  strike : bool;
  monospace : bool;
  color : color;
  link : string option; (* the href of the link the text is in *)
  pre : bool; (* spaces and newlines kept, lines never broken *)
  align : align; (* where a block's lines go *)
  link_color : color; (* a link's, blue; body link= *)
  visited_color : color; (* a visited link's, purple; body vlink= *)
  base : float; (* the root's size: <font size=3> *)
  extensions : bool; (* Netscape's honoured (Mosaic_looks: Mosaic's engine reads it) *)
}

(* the root's look: black text of [size], all off; Netscape's extensions
 * honoured if [extensions] (false) *)
val root : ?extensions:bool -> size:float -> unit -> t

(* #rrggbb, or one of HTML 3.2's 16 colour names (Windows' VGA palette:
 * black, silver, gray, white, maroon, red, purple, fuchsia, green,
 * lime, olive, yellow, navy, blue, teal, aqua), any case *)
val color_of_string : string -> color option

(* <font size=>'s factor of the root's size: "1" to "7", or "+n", "-n"
 * from 3, kept within 1..7 *)
val font_scale : string -> float option

(* the height of a line, in ems: CSS's "normal", about what fonts ask *)
val leading : float
