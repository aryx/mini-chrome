(* Script_window: the globals of a page -- what a library looks for on
   window before it does anything.

   A script in a page has, besides the language's own globals
   (languages/javascript) and document, a crowd of things that are the
   browser's: classes to test a value against, the window's size,
   places to keep a little data, ways to be told of a change. A library
   takes stock of them as it starts, and one that is missing ends it at
   its first line. So they are here, most of them less than the real
   thing, each as much as a page here can mean:

     Node, Element, HTMLElement, Text, Document, EventTarget ...
         the classes of the host objects: el instanceof HTMLElement,
         Node.ELEMENT_NODE, and a method a library adds to
         Element.prototype is every element's. Every element is an
         HTMLElement and nothing more precise (no HTMLInputElement of
         its own)
     getComputedStyle(el)
         what the element's own style= says, and the defaults of a few
         properties (display: block). The cascade's answer is the
         browser's, after the script: a script cannot ask for it
     MutationObserver, ResizeObserver, IntersectionObserver
         can be made and told to observe; are never called back
     localStorage, sessionStorage
         kept as long as the page is, not after
     matchMedia(query)       never matches
     history.pushState       the address does not change
     performance.now()       the page's clock
     screen, devicePixelRatio, scrollX, scrollY, getSelection,
     customElements, CSS.supports, requestIdleCallback's absence...

   and window itself: an object through which every global is read and
   set (window.x = 1 makes the global x), with its size, its location,
   and the document's listeners for its own.

   Reference: HTML Living Standard, section 7.2 (the Window object);
   CSSOM, section 7.2 (getComputedStyle); Web IDL, for what "an
   interface object" such as Node is. *)

open Js_value
open Script_types

(* the globals above defined, the host objects' prototypes noted in the
 * page's state; the window object, for a viewport's width and height *)
val install : t -> viewport:float * float -> (string -> value -> unit) -> value
