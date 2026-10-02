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

(* opti: [view m] is the very list (==) it gave for the model
 * before when the window has nothing new to show, and the platform
 * then does not draw the frame (run_app ~window's skip_same_view, MiniChrome's
 * main). With opti=off (Mini_opti), [view_simple]: a new list at each
 * frame, and each frame drawn.
 *
 * The problem. A Model-View-Update program is drawn sixty times a
 * second: the platform sends a Tick, update gives a model, view its
 * shapes, and the platform draws them all -- 20,000 for a window of
 * text, a letter being ten to twenty shapes. A game moves at each
 * frame; a page being read does not, and was drawn all the same: 12
 * ms of CPU a frame for an empty page, 72 for about:chrome, a core
 * kept busy by a window nobody touches (docs/plans/plan_performance.md).
 *
 *     Tick --> update --> model --> view --> shapes --> draw: 72 ms
 *     Tick --> update --> model --> view --> shapes --> draw: 72 ms
 *     ...                                    the same     the same
 *                                            shapes       pixels
 *
 * Why this works. The platform cannot tell that two lists of shapes
 * are the same picture without looking at all of them; but it can tell
 * for nothing that they are the same list. So the view keeps the last
 * model it drew and its shapes, and gives those back when the model is
 * the same -- which it never quite is: a Tick puts the time in it. The
 * view reads the time for two things only, a loading tab's wheel and a
 * player's picture ([animated]); without them, a model whose every
 * other field is the very value it was ([same_but_time]) draws the
 * same window:
 *
 *     Tick --> update --> model --> view --> shapes --> draw: 72 ms
 *     Tick --> update --> model' -> view: model' is model but for
 *                                   its time: the shapes of before
 *                                            == --> nothing drawn
 *     a key, the pointer, an answer: a field differs
 *                       --> model'' --> view --> shapes --> draw
 *
 * Fields are compared by ==, not =: it costs nothing, and update
 * leaves a field it does not touch as it is ({ m with time }), so the
 * same value means nobody changed it. It asks update not to rebuild
 * what did not change (Window_tabs.on_tab gives the model back when
 * the tab's function left the tab alone).
 *
 * What it does not buy: a frame that does change is drawn whole, as
 * before -- a scroll, the pointer over a link (the model's [mouse] is
 * new at each move). That is the number of shapes a letter
 * (plan_performance.md, step 4b). *)
val view : Window_model.model -> Playground.shape list

(* the window drawn from the model, whatever was drawn before *)
val view_simple : Window_model.model -> Playground.shape list
