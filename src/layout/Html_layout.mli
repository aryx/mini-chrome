(* Html_layout: a page laid out, as every layout here gives it -- a
   tree of boxes, each with a place and a size, their words fragments
   on lines.

   Two layouts make this: CSS's box model, the browser's (Box_layout,
   which turns its own boxes into these: Box_tree.as_html_layout), and
   the one it replaced, Mosaic's (tools/mosaic's Mosaic_layout, where
   these types were born and where the lines, baselines and breaks are
   told at length). What comes after a layout works on these and does
   not ask which made them: the drawing of words and pictures
   (Browser_draw), what is under the pointer (Hit), a form's controls,
   the developer tools' outlines.

     box            a block: its place, its children, or its lines
      +- line       a top, a height, a baseline
          +- fragment   a word in its look (Looks.t), a picture, or a
                        form's control: its left edge, its width, the
                        baseline it sits on, the element it is in

   The coordinates are the typesetter's: x from the page's left, y
   **down** from its top; the app turns them over to draw. No font
   here: a word is as wide as the caller's [metrics] say.

   **A line is broken** where the next *unit* does not fit -- the words
   stuck together with no space between them, which a break must not
   separate ("home" in a link and the "." after it). How units are
   shared out between lines is a [breaker]'s choice; [greedy] is every
   browser's (fill a line, break before what does not fit).

   **A form's control** is a box in a line, its size from its kind
   ([control_size]): a text field size= characters wide (20), a
   checkbox or a radio button 0.9 em square, a button its label and
   some room, a select its widest option, a textarea cols= by rows=; a
   hidden one is nothing.

   Reference: W3C, CSS 2.1, 9.2 (block and inline boxes) and 10.8
   (line height); Mosaic_layout.mli for the worked examples. *)

(* the width of a string in a look: the caller's font *)
type metrics = Looks.t -> string -> float

(* an image in a line: its src (as the page wrote it), its size, and
 * whether its middle or its bottom is on the baseline (align=middle,
 * or bottom, Mosaic's default) *)
type picture = { src : string; height : float; middle : bool }

(* a form's control in a line (Forms): the page's element (the key of
 * its value, which the browser keeps), and its height; its bottom a
 * quarter of it below the baseline, where its own text's baseline
 * falls *)
type control = { element : Dom.element; control_height : float }

(* a word (or, in <pre>, a line's text; or an image or a control, [text]
 * ""), where it goes *)
type fragment = {
  text : string;
  look : Looks.t;
  x : float; (* its left edge *)
  width : float;
  baseline : float;
  picture : picture option;
  control : control option;
  element : Dom.element; (* the innermost element it is in: a click on it is on that *)
}

(* a line, and the names on it a #fragment can scroll to: <a name=x>,
 * an inline element's id=x (an anchor with no text before it, alone,
 * is a line of no height where it is) *)
type line = { top : float; height : float; baseline : float; fragments : fragment list; anchors : string list }

type kind =
  | Block of Dom.element
  | Anonymous (* the lines of a run of inline content *)
  | Rule of Dom.element (* hr *)

(* a list item's: a bullet (ul, dir, menu), or its number (ol) *)
type marker = Bullet | Number of int

type box = {
  kind : kind;
  x : float;
  y : float;
  width : float;
  height : float;
  children : box list; (* its blocks, in order *)
  lines : line list; (* an Anonymous box's *)
  floats : fragment list; (* an Anonymous box's floats (pictures), placed *)
  marker : marker option; (* a list item's *)
  background : Looks.color option; (* a style sheet's background-color *)
}

(* a unit to set: the space before it (in its first word's look) and
 * its width *)
type unit_ = { space : float; width : float }

(* [breaker ~measure units]: the lines, each the indexes of its first
 * and last unit, in order, together all the units *)
type breaker = measure:float -> unit_ array -> (int * int) list

(* fill each line, break before what does not fit *)
val greedy : breaker

(* a form's control's size (width, height) in the look it is in, by its
 * kind; None for a hidden one, or what is not a control *)
val control_size : metrics -> Looks.t -> Dom.element -> (float * float) option

(* the baseline of a box's first line, if it has one *)
val first_baseline : box -> float option

(* every fragment of the page, in document order (a box's floats after
 * its lines) *)
val fragments : box -> fragment list
