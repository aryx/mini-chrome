(* Script_host: the host objects -- what a script reaches the page
   through (Browser_script.mli's opening): [document], and an object per
   element it asks for, whose properties and methods are OCaml
   functions over the page's copy (Script_dom).

     document.getElementById("count")     the element whose id= is "count"
     document.querySelector("ul li.done") the first one Css.matches
     el.textContent = "3"                 its children replaced by the text "3"
     el.innerHTML = "<b>3</b>"            by Html_tree's parse of the string
     el.style.color = "red"               "color: red" in its style=
     el.className = "done"                its class=
     el.appendChild(document.createElement("li"))
     location.pathname, new URL(href).searchParams.get("q")

   An element keeps the same host object for as long as it lives
   ([wrap] makes it once), so getElementById("x") === getElementById("x")
   and a variable holding an element stays good. What changes the tree
   says so ([touch]): the browser then lays the page out again, once,
   after the task.

   Events, timers and the page's globals (window, console, setTimeout)
   are Browser_script's, which gives these objects to the engine. *)

open Js_value
open Script_types

(* a script has changed the tree: the page to be laid out again *)
val touch : t -> unit

(* an argument as a string; the [i]th argument, undefined past the last *)
val str : value -> string
val arg : value list -> int -> value

(* a host function of its arguments alone *)
val method_ : string -> (value list -> value) -> value

(* a node's host object, made once; the node a host object stands for
 * (a TypeError thrown for anything else) *)
val wrap : t -> node -> value
val node_of : t -> value -> node

(* an object of a URL's parts (href, protocol, host, pathname, search,
 * hash, origin), with searchParams and toString; the page's own *)
val url_object : string -> value
val location : t -> value

(* document: getElementById, querySelector(All), createElement,
 * createTextNode, body, title, ... *)
val document : t -> value
