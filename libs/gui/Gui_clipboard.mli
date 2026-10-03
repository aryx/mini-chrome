(* Gui_clipboard: the text last copied, to be pasted -- the system's
 * clipboard when the program is given one, else a string of its own.
 *
 * Copy and paste are an effect on something outside the program: the
 * one buffer every program of the desktop shares. A piece of chrome
 * (Gui_field, through the program's update) only needs [get] and
 * [set]; what is behind them is the main's to say, by setting [read]
 * and [write] to the platform's functions. Until it does -- and in
 * the tests -- the clipboard is the program's alone: what is copied
 * in the omnibox can be pasted in it, and nowhere else.
 *
 * cs-history: cut, copy and paste, and the buffer between them, are
 * Larry Tesler's, at Xerox PARC in the 1970s (the Gypsy editor, with
 * Tim Mott): editing without modes. The Lisa and the Macintosh gave
 * them their keys -- X, C and V, next to each other under the left
 * hand -- and the name clipboard. *)

val get : unit -> string
val set : string -> unit

(* the system's, for the main to set *)
val read : (unit -> string) ref

val write : (string -> unit) ref
