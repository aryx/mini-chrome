(* Gui_field: a line of text being typed into -- a browser's omnibox, a
 * search box -- as a value: what it holds, where its caret is, what is
 * selected, and what a key or a click makes of it.
 *
 * The caret is between two characters, counted from 0; the selection
 * is what lies between the caret and the *anchor*, where the caret was
 * when the selecting began (the two together when nothing is
 * selected). That one pair is the whole of it:
 *
 *   focused "about:chrome"   [about:chrome]|   a field just clicked:
 *                                              all of it selected
 *   typed "h"                h|                what is typed replaces
 *                                              the selection
 *   typed "n"                hn|
 *   backspace                h|
 *   moved Left               |h
 *   moved ~select Right      [h]|              Shift held: the anchor stays
 *   backspace                |                 the selection gone
 *
 * ([..] the selection, | the caret.) Typing, Backspace and Delete all
 * replace the selection if there is one; the arrows move the caret,
 * and with Shift leave the anchor behind; a click puts the caret, a
 * drag moves it with the anchor left where the click was; Ctrl+A is
 * [select_all], and a copy takes [selected].
 *
 * A character is a character, not a byte ("caf\xc3\xa9" is four).
 * The letters are of one width, so a point is a character by a
 * division ([index_at]), and a text too long for its box is shown
 * from the character that keeps both its end and the caret in view
 * ([shown]). Return and Escape are the program's to give a meaning
 * to. A piece in Gui_kit's style: the program keeps the field in its
 * model while it has the keys ([None] otherwise).
 *
 * cs-history: selecting by dragging and typing over the selection is
 * Xerox PARC's (Bravo and Gypsy, 1974-75), against the editors of the
 * time where one said "delete word" before saying which: first the
 * object, then the verb. *)

type t = { text : string; caret : int; (* 0 to its length, in characters *) anchor : int (* the selection's other end *) }

(* a field just clicked, holding [text], all of it selected *)
val focused : string -> t

(* how many characters *)
val length : t -> int

(* the selection: from a character to before another; equal for none *)
val selection : t -> int * int

val selected : t -> string
val select_all : t -> t

(* the characters typed (or pasted) put in the selection's place, the caret after them *)
val typed : string -> t -> t

(* the selection gone; with none, the character before the caret
 * (Backspace) or after it (Delete) *)
val backspace : t -> t

val delete : t -> t

type move = Left | Right | Home | End

(* the caret moved; with [select] (Shift) the anchor stays, else the
 * selection ends, and Left and Right first go to its nearer end *)
val moved : ?select:bool -> move -> t -> t

(* the caret put before a character (a click); with [select], the anchor left where it was (a drag) *)
val caret_at : ?select:bool -> int -> t -> t

(* the text shown in room for [room] characters *)
val shown : t -> room:int -> string

(* the box of a field starting at [x], [w] wide, 28 high around the
 * line [y]: white, edged; its text is the program's to put in it *)
val box : x:float -> y:float -> w:float -> Playground.shape list

(* the selection's band and the caret's bar, for text set from [x] in
 * characters [cell] wide, around the line [y]: to draw under the text *)
val marks : t -> room:int -> x:float -> y:float -> cell:float -> Playground.shape list

(* the character before which a point at [px] falls, for [caret_at] *)
val index_at : t -> room:int -> x:float -> cell:float -> float -> int
