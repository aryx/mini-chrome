(* Gui_scrollbar: the bar at the right of what is longer than its
 * window -- a thumb as tall as the part that shows, as far down its
 * track as that part is down the whole; dragged, or its track clicked
 * above or below it.
 *
 * It lies over the right edge of what it scrolls and takes no room
 * from it (Chrome's "overlay" scrollbars: a page is not laid out again
 * because its bar appears); what fits whole has no bar. A track from
 * [top], [height] long; the content's length, the part [shown] and
 * the [offset] it is scrolled by, in any unit they share (lines,
 * here):
 *
 *   a track of 600 from y = 250; 300 lines, 60 shown, scrolled by 120
 *
 *   thumb    120 long (600 * 60 / 300), its top 240 under the track's
 *            (120 of the 240 lines it can be scrolled by: half of the
 *            480 it can travel): from y = 10 to y = -110
 *   a press  at y = 0, on the thumb: grabbed 10 under its top. The
 *            pointer dragged to y = -120: the thumb's top to -110,
 *            scrolled by 180 (360 / 480 of 240)
 *            at y = 100, above the thumb: a page up; at y = -200: down
 *
 * A thumb is never shorter than 24, however long the content. A piece
 * in Gui_kit's style: the program keeps what a drag needs (the grab)
 * in its model. *)

type t = {
  right : float; (* the track's right edge *)
  top : float;
  height : float;
  total : float; (* the content's length *)
  shown : float; (* the part that shows *)
  offset : float; (* how far it is scrolled *)
}

val width : float

(* the thumb's top and its length; None when all the content shows *)
val thumb : t -> (float * float) option

(* what a point is on: the thumb, with how far under the thumb's top
 * (the grab a drag keeps); the track before it or after it *)
type hit = Thumb of float | Before | After

val at : t -> float * float -> hit option

(* [dragged bar ~grab y]: the offset that puts the thumb's top [grab]
 * above the pointer at [y], within what can be scrolled *)
val dragged : t -> grab:float -> float -> float

(* the bar drawn, darker when [lit] (the pointer on it, or dragging);
 * nothing when all the content shows *)
val shapes : t -> lit:bool -> Playground.shape list
