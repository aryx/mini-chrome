(* Window_tabs: the model changed -- what update composes: a tab's
 * settings and what it is given to work with, one tab changed, one
 * opened or closed, the shown page scrolled, zoomed, laid out again,
 * the profile kept.
 *
 * A Browser_tab.t never touches the window nor a socket: it is given a
 * [config] (its page's settings, the messages its answers come back
 * as) and returns itself changed with commands. [on_tab] is that step
 * for one tab of the model:
 *
 *   on_tab m id (fun cfg tab -> Browser_tab.visit cfg network url tab)
 *     = the model with tab [id] visiting [url], and the fetch to start
 *
 * The shown page's place is its tab's [scroll], in lines; its size its
 * site's zoom (the profile's) over the window's scale. *)

open Window_model

(* {1 A tab's settings} *)

(* a page's: the window's width at the tab's zoom, its sheets and
 * pictures, style sheets honoured or not *)
val settings : model -> Browser_tab.t -> Browser_page.settings

(* the sites whose scripts run unless scripts= says otherwise *)
val default_allowed : string list

(* "*": every site's scripts run; and whether the model says so *)
val everywhere : string
val scripts_on : model -> bool

(* what tab [id] works with *)
val config : model -> int -> msg Browser_tab.config

(* {1 One tab changed} *)

(* the tab [id] changed by a step of Browser_tab's, its requests given
 * their times (the network panel's) *)
val on_tab : model -> int -> (msg Browser_tab.config -> Browser_tab.t -> Browser_tab.t * msg Cmd.t) -> model * msg Cmd.t
val on_current : model -> (msg Browser_tab.config -> Browser_tab.t -> Browser_tab.t * msg Cmd.t) -> model * msg Cmd.t

(* the shown tab goes to an address (its history kept); loads one *)
val visit : < Cap.network ; .. > -> string -> model -> model * msg Cmd.t
(* the page scrolled by the wheel's notches: the tab's scroll alone,
 * nothing of its script's (so it can be done while a script runs) *)
val wheeled : float -> model -> model

val load : ?reload:bool -> < Cap.network ; .. > -> string -> model -> model * msg Cmd.t

(* a new tab, shown, loading an address; a tab closed (the last one: a
 * new one on the home page) *)
val open_tab : < Cap.network ; .. > -> string -> model -> model * msg Cmd.t
val close_tab : < Cap.network ; .. > -> int -> model -> model * msg Cmd.t

(* {1 The shown page's place and size} *)

(* scrolled by lines; [pages m n]: the lines of [n] pages *)
val scrolled : int -> model -> model
val pages : model -> int -> int

(* its scrollbar, in lines *)
val scrollbar : model -> Gui_scrollbar.t

(* every tab's page laid out again, its scroll moved with its new height *)
val relaid_all : model -> model

(* the window's size or the scale changed: [screen] set from [window],
 * and the pages laid out again if it changed *)
val rescreened : model -> model

(* the shown page's site at the zoom the function gives from its own *)
val zoomed : (float -> float) -> model -> model

(* {1 The profile} *)

(* the profile changed (noted, with the time); saved once it has been
 * still for a second (on each Tick) *)
val with_profile : Browser_profile.t -> model -> model
val saved : < Cap.open_out ; .. > -> model -> model

(* {1 The omnibox and the panel} *)


(* the panel showing a view, or closed: the pages laid out again if the
 * page area's height changed (it is their 100vh) *)
val with_panel : panel -> model -> model
val toggle_panel : model -> model
