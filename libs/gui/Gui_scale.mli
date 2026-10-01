(* Gui_scale: how much bigger than its own units a window should draw,
 * to be the size the desktop's other programs are -- a browser's
 * "device scale factor": 2 on a screen of twice the dots, where a
 * letter drawn 6 dots wide can barely be read.
 *
 * On X11 the desktop says it in a resource, Xft.dpi, which GNOME sets
 * from its own scaling and GTK, Qt and Chrome follow; SDL does not, so
 * a Playground window is drawn dot for dot. 96 is no scaling:
 *
 *   $ xrdb -query
 *   Xft.dpi:        192          ->  2.
 *   Xft.antialias:  1
 *
 *   Xft.dpi: 144 -> 1.5      Xft.dpi: 96 -> 1.      no Xft.dpi -> none
 *
 * The program draws in its units and scales the whole picture by this
 * (its window is then that many times fewer units wide); a person's
 * own choice, if the program offers one, goes over it.
 *
 * Asking runs a program, an authority the caller hands down
 * (Cap.forkew: fork, exec and wait), with Cap.env for the display's
 * name. *)

(* the scale `xrdb -query`'s text says, if it has an Xft.dpi (between
 * 0.5 and 5) *)
val of_xrdb : string -> float option

(* the desktop's scale: Xft.dpi's, asked of the xrdb program; 1. when
 * there is none to ask (no X display, SDL's dummy driver: a frame
 * dumped is the same on every machine), no xrdb, or no Xft.dpi *)
val desktop : < Cap.forkew ; Cap.env ; .. > -> float
