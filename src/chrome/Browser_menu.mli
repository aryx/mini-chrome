(* Browser_menu: what the menu of a right click on the page offers,
 * Chrome's context menu, for what is under the pointer.
 *
 *   on a link    Open link in new tab | Open link with mpv | Inspect
 *   elsewhere    Open with mpv | Back | Forward | Reload | Inspect
 *
 * Open link in new tab opens it behind the tab shown, as Chrome does:
 * the reader stays on the page. Back and Forward are grey when there
 * is nowhere to go. Inspect is the developer tools, on the element
 * that was under the pointer. "Open with" is there when the profile
 * has a helper program for the address (Browser_helpers): the link's,
 * or the page's.
 *
 * The menu itself -- its place, its shapes, the item under a click --
 * is Gui_menu's (libs/gui), which knows nothing of pages; doing what
 * an item says is the program's (MiniChrome). *)

type action =
  | Open_in_new_tab of string (* the link's address, resolved *)
  | Open_with of string list (* a helper program's command, the address in it *)
  | Back
  | Forward
  | Reload
  | Inspect

(* the items for what is under the pointer: a link's address, or none;
 * [back] and [forward], whether the tab has a page to go to;
 * [helper], the program for that address and its command, if any *)
val items : ?helper:string * string list -> link:string option -> back:bool -> forward:bool -> unit -> action Gui_menu.item list
