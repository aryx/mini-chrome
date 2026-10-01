(* Gui_tabs: a strip of tabs, Chrome's -- trapezoids side by side, each
 * with a round icon (turning while its page loads), a title and a
 * close box, the one shown lit; then a + for a new one.
 *
 *    ___________   ___________
 *   / o Title  x\ / o Title  x\ [+]
 *
 * The tabs share the room: 220 wide each while they fit, narrower
 * together when they do not, their titles cut to what shows (the end
 * kept). Worked example:
 *
 *   two tabs, from x = -490 on the line y = 331, in a room of 900
 *
 *   width    220 each (900 / 2 would be 450), 2 between
 *   a click  at (-400, 331): on the first tab            Show
 *            at (-290, 331): on its close box (the 18
 *                            from 194 of its 220)        Close
 *            at (-250, 331): on the second tab           Show
 *            at (-40, 331):  on the +, after the tabs    New
 *            at (100, 331):  on none
 *
 * A piece in Gui_kit's style: a value built from the program's model,
 * asked what is under a point, and drawn. *)

type 'a tab = { value : 'a; (* what the program knows it by *) title : string; busy : bool (* its icon turns *) }

type 'a t = {
  left : float; (* where the first tab starts *)
  y : float; (* the line the tabs are centred on *)
  room : float; (* the width they share *)
  tabs : 'a tab list;
  current : 'a; (* the tab shown *)
}

type 'a hit = Close of 'a | Show of 'a | New

val tab_width : 'a t -> float

(* what a point is on: a tab's close box, a tab, the + *)
val at : 'a t -> float * float -> 'a hit option

(* the strip drawn; [time], in seconds, turns the busy tabs' icons *)
val shapes : 'a t -> time:float -> Playground.shape list
