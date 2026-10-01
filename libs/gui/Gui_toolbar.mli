(* Gui_toolbar: a row of buttons that are pictures -- a browser's Back,
 * Forward, Reload and Stop, Chrome's flat arrows -- a button every 38,
 * each 32 by 32 around its middle; one that cannot be used now is
 * grey, and a click on it is no click.
 *
 *   [ (Back, true); (Forward, false); (Reload, true) ]
 *   from x = -476 on the line y = 288
 *
 *   their middles at -476, -438, -400
 *   a click at (-470, 290): Back; at (-440, 290): none (Forward is
 *   grey); at (-420, 290): none (between two)
 *
 * A piece in Gui_kit's style. *)

type icon = Back | Forward | Reload | Stop

type t = {
  left : float; (* the first button's middle *)
  y : float;
  buttons : (icon * bool) list; (* a button, and whether it can be used *)
}

(* the button a point is on, if it can be used *)
val at : t -> float * float -> icon option

val shapes : t -> Playground.shape list
