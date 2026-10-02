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
 * the profile -- with the capabilities it is given. *)

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
  ?jar:Cookie_jar.t ->
  Browser_profile.t * string option ->
  desktop:float ->
  window:int * int ->
  Playground.flags ->
  model * msg Cmd.t
(* claude: [jar]: the browser's cookies, those kept from the last run in
 * it (the main's, which saves them: Browser_cookies); an empty one if
 * none is given *)

val update : < Cap.network ; Cap.open_out ; .. > -> msg -> model -> model * msg Cmd.t
