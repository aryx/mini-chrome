(* Script_types: what Browser_script's modules speak of -- the page's
   mutable copy, a node at a time, and the state of a page's scripts.
   Types alone.

     Script_dom      the copy: thawed from the page's tree, changed,
                     frozen back; its HTML; a selector's elements
     Script_host     the host objects a script sees: an element's,
                     document, location, a URL
     Browser_script  the tasks: the page's scripts run, an event
                     dispatched, the timers; what the browser asks

   Browser_script.mli tells the whole. *)

open Js_value

(* an element, or a text ([name] "#text", its [text]) *)
type node = {
  name : string;
  mutable text : string;
  mutable attributes : (string * string) list; (* all of them, core and Netscape's *)
  mutable children : node list;
  mutable parent : node option;
  mutable expando : (string * value) list; (* what a script set on it: el.done = true *)
  mutable wrapper : value option; (* its host object, made once *)
  mutable listeners : (string * value) list; (* addEventListener's, in order *)
  mutable compiled : (string * value) list; (* its onclick="..." attributes, compiled once *)
}

(* a setTimeout's or a setInterval's *)
(* a request a script made (XMLHttpRequest, fetch), for the
 * browser to send: its number, by which its answer comes back; and an
 * answer, as the script is given it *)
type request = { rid : int; meth : string; (* "GET", "POST" *) url : string; post : (string * string) option (* a body's content type, and it *) }
type answer = { status : int; headers : (string * string) list; body : string; final : string (* the URL, after the redirections *) }

type timer = { tid : int; mutable due : float; every : float option; fn : value }

type t = {
  engine : Js_eval.t;
  root : node;
  mutable changed : bool;
  mutable console : string list; (* the newest first *)
  log : string -> unit;
  nodes : (int, node) Hashtbl.t; (* a host object's id to its node *)
  mutable document_listeners : (string * value) list;
  mutable frozen : (Dom.element * node) list; (* the last frozen tree's elements, and their nodes *)
  mutable now : float; (* the page's clock, in ms *)
  mutable timers : timer list;
  mutable next_timer : int;
  mutable alerts : string list; (* the newest first *)
  base : string; (* the page's address: an a's href resolved, location, new URL *)
  mutable requests : request list; (* XMLHttpRequest's and fetch's, for the browser to send; the newest first *)
  (* those sent and not answered yet: what to do with each one's answer, or with why there is none *)
  mutable waiting : (int * ((answer, string) result -> unit)) list;
  mutable next_request : int;
  (* document.cookie, read and assigned to: the browser's jar,
   * for the page's address, without its HttpOnly cookies *)
  cookies : (unit -> string) * (string -> unit);
  (* an element's members past the first DOM's (Script_element:
   * matches, closest, append, dataset...), asked when Script_host has
   * none of that name; and an event dispatched by a script
   * (el.dispatchEvent(ev), el.click(); None: at the document), whether
   * it was prevented. Both set by Browser_script, which is after them *)
  mutable more : node -> string -> value option;
  mutable dispatch : node option -> value -> bool;
  (* addEventListener's { once: true }: the listeners to remove when called *)
  mutable once : (string * value) list;
  (* the prototypes of the host objects, by kind ("element", "text",
   * "comment", "fragment"): HTMLElement.prototype... (Script_window) *)
  mutable protos : (string * obj) list;
}
