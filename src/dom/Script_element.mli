(* Script_element: an element's members since the first DOM -- what
   libraries reach for.

   Script_host has the tree as the 1998 DOM gave it: parentNode,
   appendChild, getAttribute. Twenty years of libraries (jQuery first)
   showed what was missing, and browsers took it in: a selector tried
   on an element, nodes put beside one another without naming the
   parent, a copy of a subtree, the data-* attributes as an object.
   jQuery, htmx, Alpine and Vue use these when they are there, and some
   only these:

     el.matches("li.done")      whether the selector selects it
     el.closest("form")         itself or its first ancestor that matches
     el.contains(other)         whether other is it, or under it
     el.append(a, "text", b)    at its end (prepend: its start); a
                                string is a text node
     el.before(a) .after(b)     beside it, in its parent
     el.replaceWith(a)  .replaceChild(new, old)  .replaceChildren()
     el.cloneNode(true)         a copy, with its subtree if true; the
                                listeners are not copied
     el.dataset.userId          its data-user-id attribute
     el.hasAttribute, .attributes, .toggleAttribute, .getAttributeNames
     el.isConnected             whether it is in the page
     el.compareDocumentPosition(other)   who is first, who is inside:
                                how jQuery sorts what it found
     el.dispatchEvent(ev)  el.click()    Script_events

   A page here has no boxes a script can ask about (the layout is the
   browser's, after the script): getBoundingClientRect is all zeros,
   offsetWidth 0. A library that measures to decide gets "not shown".

   Worked example (tests/browser/Unit_script_element.ml):

     <ul id=l><li class=a>1</li><li>2</li></ul>
     const l = document.getElementById("l"), first = l.firstElementChild
     first.matches("ul > li.a")                      // true
     first.closest("ul") === l                       // true
     l.append("3", document.createElement("li"))     // 1, 2, "3", <li>
     first.after(l.lastElementChild)                 // 1, <li>, 2, "3"

   Reference: DOM Living Standard, sections 4.2.6 (ParentNode: append,
   prepend), 4.2.8 (ChildNode: before, after, replaceWith, remove),
   4.9 (Element: matches, closest). *)

open Js_value
open Script_types

(* [get t n k]: the member [k] of [n], if it is one of these *)
val get : t -> node -> string -> value option
