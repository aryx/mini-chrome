(* Window_model: the state of the browser's window, and the messages
 * that change it -- the Model and the Msg of a Model-View-Update
 * program (docs/architecture.md). Types alone: what reads the model is
 * Window_layout, what changes it Window_tabs and Window_update, what
 * draws it Window_view; MiniChrome.ml (src/main) runs them.
 *
 *   msg ---> Window_update.update ---> model ---> Window_view.view ---> shapes
 *
 * Everything the window shows is in the model: nothing is kept on the
 * screen from one frame to the next. *)

(* a tab, and when each of its requests started and ended (the
 * network panel's times, this program's clock) *)
type tab = { id : int; tab : Browser_tab.t; times : (string * (float * float option)) list }

type panel = Closed | Elements | Network

type model = {
  tabs : tab list;
  current : int; (* the id of the tab shown *)
  next_id : int;
  omnibox : Gui_field.t option; (* its text, while it is typed into (libs/gui); None, it shows the page's address *)
  places : Places.t; (* the pages seen, which the omnibox suggests and completes from; changed in place, as the cookies' jar *)
  memory : int list; (* the megabytes the program holds, the last first, one every two seconds for a minute: the main's (Browser_version.resident); none, not shown *)
  suggested : int option; (* the suggestion the arrows chose, under the omnibox *)
  mouse : float * float;
  time : float;
  busy : float option; (* a page's script is in a long run, since then (the main's: Js_slice) *)
  css : bool; (* the page's style sheets honoured *)
  panel : panel;
  inspecting : bool; (* the next click on the page picks an element *)
  selected : Dom.element option;
  engine : string; (* the omnibox's searches: Omnibox.search_url *)
  allowed : string list; (* the sites whose scripts run (hosts): Chrome's per-site setting *)
  fetches : msg Fetch.t; (* the tabs' requests in flight, stepped on each Tick *)
  screen : float * float; (* the window's size in the program's units (its dots, divided by the scale): the page's width *)
  ctrl : bool; (* a Ctrl key held *)
  profile : Browser_profile.t; (* what is kept between runs: the window's size, the sites zoomed *)
  profile_dir : string option; (* where it is saved; None, it is not *)
  saved : Browser_profile.t; (* the profile as it is on disk *)
  changed : float; (* when the profile last changed (time) *)
  menu : Browser_menu.action Gui_menu.t option; (* the right click's menu, while it is open *)
  window : int * int; (* the window's size, in the screen's dots; [screen] is in the program's units *)
  desktop : float; (* the desktop's scale (Gui_scale), when none is chosen *)
  dots : float; (* the screen's dots for one of the window's points (Playground_platform.pixel_ratio): 2 on a Retina, else 1 *)
  shift : bool; (* a Shift key held *)
  grab : float option; (* the scrollbar's thumb held: how far under its top (Gui_scrollbar) *)
  selecting : bool; (* the button held since a click in the omnibox: the pointer drags its selection *)
  last_click : float; (* when the button last went down (time): a second one soon after is a double click *)
  pressed : bool; (* the button held since a press a page's script was told of: it is told when it is let go *)
  fresh : string list; (* the keys (and "mouse", the button) a page's script was told went down, since its last frame *)
  late : msg list; (* those let go before that frame: told after it (Window_update.update) *)
}

and msg =
  | Got of int * string * (Fetch.response, Fetch.error) result
  | Got_picture of int * string * (Fetch.response, Fetch.error) result
  | Got_answer of int * int * string * (Fetch.response, Fetch.error) result (* a tab's script's request: the tab, the request's number, its URL *)
  | Start_fetch of msg Fetch.request (* a tab's request, to start *)
  | Socket of int * Script_types.socket_ask (* a tab's script's WebSocket: opened, sent to, closed *)
  | Got_socket of int * int * Websocket_client.event (* what it said: the tab, the socket's number *)
  (* tabs=domains: the page's scripts were told of a message, on their
   * domain, and did not prevent it: the browser's own part of it, now
   * (and whether the button was down before, for a release's click);
   * and the same of a click *)
  | Told of msg * bool
  | Clicked
  | Tick of float
  | Key of string
  | Key_up of string
  | Typed of string
  | Wheel of float
  | Mouse_move of float * float
  | Click
  | Mouse_up
  | Right_click
  | Resized of int * int (* the window's new size *)
