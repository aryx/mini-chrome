(* Browser_zoom: Chrome's page zoom -- Ctrl and + (or =), Ctrl and -,
 * Ctrl and 0 -- by its steps, each site keeping its own.
 *
 * It is the whole page that grows, not its fonts alone: the browser
 * lays the page out narrower, at the window's width divided by the
 * zoom (a site's @media rules for a small screen may then hold), and
 * draws it scaled. That part is the program's (MiniChrome); here are
 * the levels and what is remembered.
 *
 *   at 100%, Ctrl +  -> 110%   Ctrl + again -> 125%   Ctrl -  -> 110%
 *   at 500%, Ctrl +  -> 500%   (the last level)
 *   Ctrl 0  -> 100%, and the site forgotten
 *
 * A zoom is its site's (its host's), every page and tab of it, as in
 * Chrome -- which keeps it in the profile; here it lasts as long as the
 * program.
 *
 * https://support.google.com/chrome/answer/96810 *)

(* the sites zoomed, by host; those at 100% are not kept *)
type t = (string * float) list

val empty : t

(* Chrome's levels: 0.25, 0.33, 0.5, ... 1., 1.1, 1.25, ... 5. *)
val levels : float list

(* [step up z]: the level after [z] (before it, if not [up]); [z] at
 * either end *)
val step : bool -> float -> float

(* a host's zoom, 1. unless it was set *)
val of_host : t -> string -> float

val with_host : t -> string -> float -> t

(* what a key pressed with Ctrl asks, by the key's name (SDL's or the
 * web's, any case) or the character it types: "=", "+", "Keypad +" a
 * step up; "-", "Keypad -" a step down; "0", "Keypad 0" the size
 * things have by themselves again; None for any other *)
type change = Up | Down | Reset

val key : string -> change option

(* a zoom after a change: a step, or 1. *)
val apply : change -> float -> float

(* "125%"; "" at 100% *)
val label : float -> string
