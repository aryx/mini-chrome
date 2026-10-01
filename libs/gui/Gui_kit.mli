(* Gui_kit: what the pieces of libs/gui share -- their colours, Chrome
 * 1.0's on Windows (the blue frame, the light toolbar), and the one
 * hit test they all do.
 *
 * The pieces are in the Model-View-Update style, the program's own
 * (the Playground's run_app; elm-playground's notes_gui.md, section 4,
 * compares it with callbacks, MVC and immediate mode), in its plainest
 * form: a piece is a value built from the model when needed -- no
 * state of its own, no callback, no message type --
 *
 *   in view     Gui_tabs.shapes strip        the value, drawn
 *   in update   Gui_tabs.at strip m.mouse    on a click: what is there?
 *
 * and the program's update decides what a hit means. What a piece
 * would have to remember (a menu open, a tab shown) is a field of the
 * program's model. *)

val frame : Playground.color (* the window's blue *)
val surface : Playground.color (* the toolbar, the tab shown *)
val edge : Playground.color
val white : Playground.color
val ink : Playground.color
val muted : Playground.color (* a second line of text, a close box *)
val disabled : Playground.color
val accent : Playground.color (* Chrome's blue: the spinner, what is on *)
val lit : Playground.color (* the item under the pointer *)

(* [near x y w h point]: [point] is in the box starting at [x], [w]
 * wide, [h] high around the line [y] *)
val near : float -> float -> float -> float -> float * float -> bool
