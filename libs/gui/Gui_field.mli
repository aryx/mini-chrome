(* Gui_field: a line of text being typed into -- a browser's omnibox, a
 * search box -- as a value: what it holds, what typing and Backspace
 * make of it, the box it is drawn in.
 *
 * A field just clicked is **fresh**: it shows the text it was given
 * (the page's address), and the first thing typed replaces it rather
 * than adding to it -- what selecting it all would do, in a field
 * without a selection.
 *
 *   focused "about:chrome"        about:chrome_     fresh
 *   typed "h"                     h_                the address replaced
 *   typed "n"                     hn_
 *   backspace                     h_
 *   focused "x", then backspace   _                 a fresh field emptied
 *
 * The caret is always at the end: no arrows, no selection yet. Return
 * and Escape are the program's to give a meaning to. A piece in
 * Gui_kit's style: the program keeps the field in its model while it
 * has the keys ([None] otherwise). *)

type t = { text : string; fresh : bool (* just clicked: typing replaces the text *) }

(* a field just clicked, holding [text] *)
val focused : string -> t

(* the characters typed (one, or a key repeating) added, or replacing a
 * fresh field's text *)
val typed : string -> t -> t

(* the last character gone (a character, not a byte); a fresh field
 * emptied *)
val backspace : t -> t

(* its text as shown, the caret after it *)
val shown : t -> string

(* the box of a field starting at [x], [w] wide, 28 high around the
 * line [y]: white, edged; its text is the program's to put in it *)
val box : x:float -> y:float -> w:float -> Playground.shape list
