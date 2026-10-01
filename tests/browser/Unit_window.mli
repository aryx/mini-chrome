(* src/window's pure parts: a URL's host (Window_layout), what is typed
 * in the omnibox made an address (Window_tabs), the command line's
 * words made the first pages (Window_update); and the program run by
 * hand (init, update, the commands' messages given back): the view of
 * a window at rest is the very list of the frame before (Window_view) *)
val tests : < Cap.network ; Cap.open_out ; .. > -> Testo.t list
