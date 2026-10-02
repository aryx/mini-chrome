(* Script_events: an event as a script makes one.

   The browser makes events (a click, a key: Browser_script) and so do
   scripts, to talk to each other: a library announces what it did with
   an event of its own name, and the page listens for it.

     el.addEventListener("saved", e => console.log(e.detail.id))
     el.dispatchEvent(new CustomEvent("saved", { detail: { id: 7 }, bubbles: true }))

   An event is a plain object:

     type              "saved"
     bubbles           whether, after its target, it goes up to the
                       target's parents and the document
     cancelable, detail, and whatever the second argument has
     target, currentTarget     set as it is dispatched
     preventDefault()          sets defaultPrevented
     stopPropagation()         sets cancelBubble: no further up
     stopImmediatePropagation()   nor to the next listener

   and what a dispatch looks at is those properties: there is no state
   of an event anywhere else.

   Two ways to make one, the constructors (new Event(type, init), new
   CustomEvent, new MouseEvent...: all the same object here) and the
   older document.createEvent("CustomEvent") followed by
   initCustomEvent(type, bubbles, cancelable, detail), which htmx and
   jQuery still fall back on.

   Reference: DOM Living Standard, section 2 (events): 2.2 Event, 2.4
   CustomEvent, 2.9 dispatch. *)

open Js_value

(* an event of a type, with these properties; not dispatched yet *)
val make : ?bubbles:bool -> string -> (string * value) list -> value

(* Event, CustomEvent, MouseEvent, KeyboardEvent... defined (each
 * instanceof Event) *)
val install : (string -> value -> unit) -> unit

(* document.createEvent(kind): an event with no type yet, and
 * initEvent, initCustomEvent to give it one *)
val create : unit -> value

(* an event's property as a flag: bubbles, cancelBubble,
 * defaultPrevented *)
val flag : value -> string -> bool
