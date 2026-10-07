(* Box_tree: a box read -- what is asked of the boxes Box_layout makes,
   by the layout itself (a float or an inline-block is laid out at an
   origin, then moved to its place; shrink-to-fit asks how far right a
   box's content reaches) and by what comes after it: Hit and the form
   controls work on Html_layout's boxes, the drawing on the fragments.

     a box at (10, 20) holding a line with "ab" at x 12
     moved 5. 100.:  the box at (15, 120), "ab" at x 17, its baseline
                     100 lower -- and so every box and line inside it

   Box_layout.mli tells the whole of the layout. *)

open Box_types

(* every fragment of the page: each box's lines, then its children's
 * (an inline-block's words after its line's) *)
val fragments : box -> Html_layout.fragment list

(* a box and all it holds moved by (dx, dy) *)
val moved : float -> float -> box -> box

(* [scaled kx ky (ox, oy) b]: a box and all it holds drawn that many
 * times its size around a point (transform: scale) *)
val scaled : float -> float -> float * float -> box -> box

(* how far right a box's content reaches, for shrink-to-fit: its lines'
 * words, its children's content (a block of width auto is as wide as
 * its container, which is not what it needs) *)
val inner_right : box -> float

(* the baseline of a box's last line, its own or its last child's that
 * has one: where an inline-block sits on its line *)
val last_baseline : box -> float option

(* the same page as Html_layout's boxes (their borders and styles
 * dropped): for Hit, the form controls, the anchors *)
val as_html_layout : box -> Html_layout.box

(* a picture's address: its src=, or else the first of its srcset=
 * (the pages that give only srcset=, the sizes chosen by the browser) *)
val picture_src : Dom.element -> string option
