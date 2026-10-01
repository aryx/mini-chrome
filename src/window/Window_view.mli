(* Window_view: the model drawn -- the View of the Model-View-Update
 * program: every shape of the window, built again at each frame.
 *
 * Back to front: the page's colour, the page (its boxes, form
 * controls, players; the element inspected outlined), its scrollbar,
 * then the chrome over what overflows -- the frame, the toolbar, the
 * tabs' strip, the buttons, the omnibox (the address's host dark, the
 * rest grey; the zoom and "JS"), the wrench, the developer tools'
 * panel, the status bubble, an open menu.
 *
 * Built in the program's units and scaled whole to the screen's dots
 * (Window_layout.scale_of); the page inside it scaled by its site's
 * zoom. *)

val view : Window_model.model -> Playground.shape list
