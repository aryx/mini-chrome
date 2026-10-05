(* Window_update: what each message does to the model -- the Update of
 * the Model-View-Update program, and its first model.
 *
 * The order of update's cases is the order of who gets an event:
 *
 *   a click      the open menu, the scrollbar, the omnibox, the wrench,
 *                "JS", the tabs' strip, the panel's header, the
 *                toolbar's buttons, then the page (its scripts first,
 *                then a form's control, a link)
 *   a key        Ctrl and Shift held; with Ctrl, the zoom's keys (with
 *                Shift too, the scale's); the omnibox while it is typed
 *                into; the page's focused field; then scrolling, F12,
 *                Backspace
 *
 * update is not pure: it starts the fetches (Fetch.perform, on
 * Start_fetch), steps them and the page's scripts (on Tick), and saves
 * the profile -- with the capabilities it is given.
 *
 * cs-history:
 * The shape is Elm's. Evan Czaplicki's language (his thesis, Harvard,
 * 2012) is for programs in a page, and its programs came to be all
 * written one way, which was named afterwards: The Elm Architecture
 * -- a model (the whole state, one value), an update (a message and
 * the model give the next model), a view (the model gives what is
 * shown), and nothing else changing anything. It reads as the oldest
 * idea of the field turned strict: Model-View-Controller (Trygve
 * Reenskaug, Smalltalk at Xerox PARC, 1979) with the model immutable
 * and the controller a pure function. It went from Elm into the
 * mainstream as Redux (Dan Abramov, 2015), written after it, and is
 * how React programs keep their state. elm-playground is this
 * architecture in OCaml, and a browser's window is here one such
 * program. *)

open Window_model

(* the flags' names: a word of the command line that is none of them is
 * a page to open *)
val flag_names : string list

(* the pages to open first: url=, and the words that are not flags, as
 * if typed in the omnibox; the home page without any *)
val first_pages : string -> Playground.flags -> string list

(* [init network (profile, where it is saved) ~desktop ~window flags]:
 * the first model, a tab a page; [desktop] the desktop's scale,
 * [window] the size the window starts at, in the screen's dots *)
val init :
  < Cap.network ; .. > ->
  ?jar:Cookie_jar.t -> ?cache:Http_cache.store ->
  Browser_profile.t * string option ->
  desktop:float ->
  window:int * int ->
  Playground.flags ->
  model * msg Cmd.t
(* [jar]: the browser's cookies, those kept from the last run in
 * it (the main's, which saves them: Browser_cookies); an empty one if
 * none is given *)

val update : < Cap.network ; Cap.open_out ; Cap.exec ; .. > -> msg -> model -> model * msg Cmd.t
