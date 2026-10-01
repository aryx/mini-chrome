(* Gui_text: a line of text in cells of one width, a character a cell
 * -- the chrome's text (a tab's title, the address, a menu's items,
 * the developer tools' lines), where a column must stay a column
 * whatever the letters.
 *
 *   monospace 100. 0. ink "a b"
 *
 *   'a' centred at (103, 0), 'b' at (115, 0): cells of 6, the first
 *   starting at x = 100; the space is a cell left empty
 *
 * A character is a code point (UTF-8), not a byte: "café" is 4 cells. *)

(* a cell's width *)
val cell : float

(* the width of a text: [cell] times its characters *)
val width : string -> float

(* [monospace ?max x y color s]: [s] from [x], its characters' middles
 * at [y]; no more than [max] characters (160) *)
val monospace : ?max:int -> Playground.number -> Playground.number -> Playground.color -> string -> Playground.shape list

(* the last [n] characters of a text, or all of it: what shows of a
 * title or an address too long for its place *)
val tail : int -> string -> string

(* [bubble ~left ~y s]: [s] (its last 100 characters) on a small card
 * starting at [left], its middle at [y] -- Chrome's status bubble, at
 * the bottom of the window: a link's address, what is loading *)
val bubble : left:float -> y:float -> string -> Playground.shape list
