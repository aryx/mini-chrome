(* Omnibox: the one box at the top -- an address shown, an address or
 * a search typed.
 *
 * At rest it shows the page's address, the part that says whose page
 * it is (the scheme and the host) dark and the rest grey:
 *
 *   https://en.wikipedia.org/wiki/OCaml
 *   ^^^^^^^^^^^^^^^^^^^^^^^^ dark      ^^^^^^^^^^^ grey
 *
 * Clicked, it is a line of text (libs/gui's Gui_field) with the
 * address all selected, so that what is typed replaces it; Return
 * goes to what was typed ([destination]): an address if it looks like
 * one -- a scheme, or a host with a dot and no space -- else words to
 * search,
 *
 *   about:tube              about:tube
 *   news.ycombinator.com    https://news.ycombinator.com
 *   ocaml                   https://en.wikipedia.org/w/index.php?search=ocaml
 *
 * and Escape gives the keys back to the page. The rest is the usual of
 * a text field ([key], [clicked], [dragged]): the arrows, Home and
 * End, with Shift to select; a click for the caret, a drag for a
 * selection, a double click for the whole line; Ctrl+A, and Ctrl+C,
 * X and V with the clipboard (Gui_clipboard).
 *
 * A piece of chrome as libs/gui's (a value built from the model:
 * shapes for the view, hit tests and outcomes for update, no state of
 * its own), kept here because it is a browser's: it knows what an
 * address is, and where a search goes.
 *
 * cs-history: the first browsers had two boxes or none. Mosaic showed
 * the URL in a field one could type in; Netscape's "Location" was the
 * same; a search was a page one went to. Firefox 1.0 (2004) put a
 * second, small box for searches beside the address. Chrome (2008)
 * made them one again and gave it a name, the Omnibox: whatever is
 * typed is an address if it can be, else a search -- and, in the real
 * one, suggestions from the history and from the search engine as one
 * types, which is where its 2008 comic said the name came from: one
 * box for everything. Every browser has since followed.
 *
 * modern: the real Omnibox hides the scheme and "www.", shows a lock
 * (or said "Not secure"), completes what is typed inline, and sends
 * each keystroke to the search engine for suggestions unless told not
 * to -- the part of it that made people ask what a browser tells its
 * maker. None of that here. *)

(* where it is (its left edge, the line it is around, its width), how
 * many characters it has room for, the page's address, and its text
 * while it is typed into (None: it shows the address) *)
type t = { x : float; y : float; w : float; room : int; address : string; field : Gui_field.t option }

(* whether a point is in it *)
val at : t -> float * float -> bool

(* its field after a click at [px] (across): taken, the address all
 * selected, if it was at rest; else the caret put there, or with
 * [double] all selected again *)
val clicked : t -> double:bool -> float -> Gui_field.t

(* the pointer at [px] with the button held since a click in it: the
 * selection extended (None at rest) *)
val dragged : t -> float -> Gui_field.t option

(* what a key makes of the field: an edit, a page to go to (the text
 * as typed, for [destination]), the keys given back, or nothing *)
type outcome = Edit of Gui_field.t | Go of string | Leave | Nothing

val key : ctrl:bool -> shift:bool -> string -> Gui_field.t -> outcome

(* characters typed; with Ctrl held they are a command's, not text *)
val typed : ctrl:bool -> string -> Gui_field.t -> Gui_field.t

(* [search_url engine words]: where words are searched, by the engine's
 * name ("duckduckgo"; anything else is Wikipedia) *)
val search_url : string -> string -> string

(* [destination engine typed]: the address typed, or its search *)
val destination : string -> string -> string

(* the box, and its text: the address, or the field with its selection and caret *)
val shapes : t -> Playground.shape list
