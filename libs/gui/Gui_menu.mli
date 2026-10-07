(* Gui_menu: a menu opened at a point -- a right click's -- as a value:
 * where it is put, which of its items a point is on, and its shapes.
 * What its items stand for is the program's ['a]; so is when it opens
 * and closes (a field of its model).
 *
 * The menu's top left corner is the point, unless it would then leave
 * the window: it is moved in, as far as needed. In the window's units,
 * the origin at its centre and y up:
 *
 *   a window of 1000 by 700, a menu of two items opened at (480, -330),
 *   the longer "Open link in new tab"
 *
 *   size    148 wide (20 letters of 6, and 28), 52 high (2 items of 22,
 *           and 4 above and below)
 *   corner  (352, -298) rather than (480, -330): 148 from the right
 *           edge (500), 52 from the bottom (-350)
 *   a point at (400, -310): 12 under the top, the first item
 *           at (400, -335): the second; at (300, -310): none
 *
 * An item that cannot be chosen now is shown grey, and a click on it
 * chooses nothing. A piece in Gui_kit's style. *)

type 'a item = { label : string; value : 'a; enabled : bool }

type 'a t = {
  at : float * float; (* the point it was opened at *)
  left : float;
  top : float; (* its top left corner *)
  items : 'a item list;
}

(* [opened ~screen ~at items]: the menu opened at [at], kept inside a
 * window of [screen] (its width and height) *)
val opened : screen:float * float -> at:float * float -> 'a item list -> 'a t

val width : 'a t -> float
val height : 'a t -> float

(* the item a point is on, from 0; and what a click there chooses: its
 * value, if it is enabled *)
val index_at : 'a t -> float * float -> int option
(* the y of an item's middle *)
val row : 'a t -> int -> float

val chosen : 'a t -> float * float -> 'a option

(* the menu drawn: a white card and its shadow, the item under
 * [pointer] lit *)
val shapes : 'a t -> pointer:float * float -> Playground.shape list
