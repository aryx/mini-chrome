(* Window_layout: the model read -- where each part of the window is,
 * and what is under the pointer.
 *
 * The screen is the window, whatever its size (run_app's
 * ~window's follows_window), the origin at its centre and y up, so every
 * place is computed from the model's [screen], from an edge:
 *
 *    top m    +------------------------------------------------+
 *             |  tabs                       tab_y  = top - 19   |
 *             |  < > o  [ omnibox       ] w toolbar_y = top - 62 |
 *   area_top  +------------------------------------------------+ top - 86
 *             |                                                |
 *             |  the page: area_height m                       |
 *             |                                                |
 *  panel_top  +------------------------------------------------+ (the tools, when open)
 *             |  Inspect Elements Network                      |
 *   -top m    +------------------------------------------------+
 *            left m                                       -left m
 *
 * No function here changes the model; update and view both ask these. *)

open Window_model

(* {1 The model's tabs and sites} *)

val home : string

(* the tab shown *)
val current : model -> tab
val current_tab : model -> Browser_tab.t
val current_url : model -> string

(* "news.ycombinator.com" of https://news.ycombinator.com/item?id=1; ""
 * for an address without one (about:chrome) *)
val host_of : string -> string

(* a tab's zoom, its site's; the scale everything is drawn at (the one
 * chosen, else the desktop's) *)
val zoom_of : model -> Browser_tab.t -> float
val scale_of : model -> float

(* a tab whose page, or what the page asked for, is still coming *)
val loading : Browser_tab.t -> bool

(* {1 The window's geometry} *)

val width : model -> float
val height : model -> float
val left : model -> float
val top : model -> float

(* the developer tools' panel, at the bottom *)
val panel_height : model -> float
val panel_top : model -> float
val panel_header_y : model -> float

(* a letter of the chrome's text *)
val cell : float

(* the page's area, below the toolbar, above the panel if it is open *)
val area_top : model -> float
val area_left : model -> float
val area_bottom : model -> float
val area_height : model -> float
val page_width : model -> float

(* a line of the page, what the scroll counts in; those the area shows
 * of a tab's page, at its zoom *)
val line_height : float
val visible_lines : model -> Browser_tab.t -> int

(* the tabs' strip; the toolbar: its buttons, the omnibox, its "JS", the wrench *)
val tab_y : model -> float
val tab_left : model -> float
val toolbar_y : model -> float
val button_x : model -> int -> float
val omnibox_x : model -> float
val omnibox_w : model -> float
val js_x : model -> float
val wrench_x : model -> float

(* {1 The chrome's pieces (libs/gui), built from the model} *)

val buttons : model -> Gui_toolbar.t
val strip : model -> int Gui_tabs.t

(* {1 The pointer} *)

(* a point of the window in the page's units, if it is on the page;
 * the pointer's *)
val page_point_at : model -> float * float -> (float * float) option
val page_point : model -> (float * float) option

(* the link under the pointer (its href), the form control *)
val hovered : model -> string option
val pointed_control : model -> Dom.element option

(* [near x y w h m]: the pointer is in the box from [x], [w] wide, [h]
 * high around the line [y] *)
val near : float -> float -> float -> float -> model -> bool
val on_omnibox : model -> bool

(* the pages seen that what is typed in the omnibox may mean, a menu
   under it whose items are their addresses; the one the pointer is on *)
val suggestions : model -> string Gui_menu.t option
val suggestion_at : model -> string option

(* the omnibox, built from the model (src/chrome's Omnibox) *)
val omnibox : model -> Omnibox.t

(* the panel's header: "Inspect", "Elements", "Network" *)
val panel_button : model -> string option

(* whether a form's control is one that is typed in: a textarea, an
 * input of text, search, email, url, password, tel, number, or of no
 * type said *)
val is_text_control : Dom.element -> bool

(* the mouse's cursor for what is under it: a hand over a link, the
 * I-beam over the omnibox and a page's text field, the arrow elsewhere
 * and while the right click's menu is open. The main gives it to the
 * platform after each message (Playground_platform.set_cursor) *)
val cursor_of : model -> Playground.cursor
