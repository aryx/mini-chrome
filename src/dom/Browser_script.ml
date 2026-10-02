(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Browser_script.mli *)
open Js_value
open Script_types
open Script_dom (* the copy *)
open Script_host (* the host objects *)

type t = Script_types.t

(*****************************************************************************)
(* Entry points *)
(*****************************************************************************)

let say (t : t) (line : string) : unit =
  t.console <- line :: t.console;
  t.log line

let report (t : t) (e : Js_eval.error) : unit =
  let m = e.message in
  say t (Printf.sprintf "%s (line %d)" (if String.starts_with ~prefix:"Uncaught" m then m else "Uncaught " ^ m) e.line)

(*****************************************************************************)
(* Events *)
(*****************************************************************************)

(* a handler run. The browser's event (a click, a timer) is a task of
 * its own: the engine's budget renewed, its jobs run after. One
 * dispatched by a script ([nested]) is in that script's run. Either
 * way its error is said in the console, not the next handler's
 * business; whether it returned false (DOM level 0's way to cancel,
 * onclick="...; return false") *)
let run_handler ?(nested = false) (t : t) (f : value) ~(this : value) (event : value) : bool =
  let result =
    if nested then try Ok (Js_eval.call_in_run t.engine f ~this [ event ]) with Throw v -> Error (Js_eval.error_of t.engine v)
    else Js_eval.call t.engine f ~this [ event ]
  in
  match result with
  | Ok (Bool false) -> true
  | Ok _ -> false
  | Error e -> report t e; false

(* onclick="..." compiled once into a function of event, as browsers
 * do: the attribute's text is the function's body *)
let attribute_handler ?(nested = false) (t : t) (n : node) (typ : string) : value option =
  match attribute n ("on" ^ typ) with
  | None -> None
  | Some src -> (
      match List.assoc_opt src n.compiled with
      | Some f -> Some f
      | None -> (
          let text = "(function (event) {\n" ^ src ^ "\n})" in
          match if nested then (try Ok (Js_eval.eval_in_run t.engine text) with Throw v -> Error (Js_eval.error_of t.engine v)) else Js_eval.eval t.engine text with
          | Ok f ->
              n.compiled <- (src, f) :: n.compiled;
              Some f
          | Error e -> report t e; None))

(* an event (Script_events) dispatched at [target] (None: the
 * document): its handlers, then, if it bubbles, its parent's, up to
 * the document, unless one stops it; whether one prevented the
 * default. What the event says of itself is its properties, read
 * after each handler *)
let dispatch_event ?(nested = false) (t : t) (target : node option) (event : value) : bool =
  let ev = match event with Object o -> o | _ -> throw "TypeError" "parameter 1 is not of type 'Event'" in
  let typ = match get_own ev "type" with Some v -> to_string v | None -> "" in
  let flag = Script_events.flag event in
  let document = Js_eval.global t.engine "document" |> Option.value ~default:Undefined in
  set_own ev "target" (match target with Some n -> wrap t n | None -> document);
  let prevent () = set_own ev "defaultPrevented" (Bool true) in
  let handle this (listeners : (string * value) list) ~(remove : value -> unit) (extra : value option) =
    set_own ev "currentTarget" this;
    List.iter
      (fun (ty, f) ->
        if ty = typ && not (flag "@@immediate") then (
          (* { once: true }: gone before it is called *)
          if List.exists (fun (ty', g) -> ty' = typ && g == f) t.once then (
            t.once <- List.filter (fun (ty', g) -> not (ty' = typ && g == f)) t.once;
            remove f);
          (* a listener is a function, or an object with handleEvent *)
          let f, this = match f with Object ({ kind = Plain; _ } as o) -> ( match get_own o "handleEvent" with Some h -> (h, f) | None -> (f, this)) | _ -> (f, this) in
          if run_handler ~nested t f ~this event then prevent ()))
      listeners;
    Option.iter (fun f -> if (not (flag "@@immediate")) && run_handler ~nested t f ~this event then prevent ()) extra
  in
  let rec up (n : node option) =
    match n with
    | Some n when not (flag "cancelBubble") ->
        (* el.onclick = f, else onclick="..." *)
        let on = match List.assoc_opt ("on" ^ typ) n.expando with Some (Object _ as f) -> Some f | _ -> attribute_handler ~nested t n typ in
        handle (wrap t n) n.listeners ~remove:(fun f -> n.listeners <- List.filter (fun (ty, g) -> not (ty = typ && g == f)) n.listeners) on;
        if flag "bubbles" then up n.parent
    | _ -> ()
  in
  up target;
  if (target = None || flag "bubbles") && not (flag "cancelBubble") then
    handle document t.document_listeners ~remove:(fun f -> t.document_listeners <- List.filter (fun (ty, g) -> not (ty = typ && g == f)) t.document_listeners) None;
  flag "defaultPrevented"

(* an event of the browser's: a click, a key *)
let dispatch (t : t) (target : node) (typ : string) (fields : (string * value) list) : bool =
  dispatch_event t (Some target) (Script_events.make ~bubbles:true typ fields)

(* the node a frozen element came from *)
let node_of_element (t : t) (e : Dom.element) : node option = List.find_map (fun (e', n) -> if e' == e then Some n else None) t.frozen

(*****************************************************************************)
(* Timers *)
(*****************************************************************************)

let add_timer (t : t) (args : value list) ~(repeat : bool) : value =
  let f = arg args 0 in
  (* 1 ms at least: a setInterval(f, 0) must let the clock move *)
  let ms = Float.max 1. (match arg args 1 with Undefined -> 0. | v -> to_number v) in
  t.next_timer <- t.next_timer + 1;
  t.timers <- t.timers @ [ { tid = t.next_timer; due = t.now +. ms; every = (if repeat then Some ms else None); fn = f } ];
  Number (float_of_int t.next_timer)

let clear_timer (t : t) (args : value list) : value =
  let id = int_of_float (to_number (arg args 0)) in
  t.timers <- List.filter (fun tm -> tm.tid <> id) t.timers;
  Undefined

(*****************************************************************************)
(* Entry points *)
(*****************************************************************************)

let create ?(seed = 1) ?(log = fun _ -> ()) ?(base = "about:blank") ?(epoch = 0.) ?(viewport = (1000., 768.))
    ?(cookies = ((fun () -> ""), fun (_ : string) -> ())) (tree : Dom.element) : t =
  let lines = ref (fun (_ : string) -> ()) in
  let clock = ref (fun () -> epoch) in
  let engine = Js_eval.create ~log:(fun l -> !lines l) ~seed ~now:(fun () -> !clock ()) () in
  let t =
    { engine; root = thaw tree; changed = false; console = []; log; nodes = Hashtbl.create 64; document_listeners = []; frozen = [];
      now = 0.; timers = []; next_timer = 0; alerts = []; base; requests = []; waiting = []; next_request = 0; cookies;
      more = (fun _ _ -> None); dispatch = (fun _ _ -> false); once = []; protos = [] }
  in
  t.more <- Script_element.get t;
  t.dispatch <- dispatch_event ~nested:true t;
  (* Date's clock: the page's, from [epoch] *)
  clock := (fun () -> epoch +. t.now);
  lines := say t;
  let define name f = Js_eval.define engine name (host_function name (fun ~this:_ args -> f args)) in
  (* window and what a library looks for on it, the classes of the
   * host objects first: document is one *)
  let (_ : value) = Script_window.install t ~viewport (Js_eval.define engine) in
  Script_events.install (Js_eval.define engine);
  Js_eval.define engine "document" (Script_document.document t);
  define "setTimeout" (fun args -> add_timer t args ~repeat:false);
  define "setInterval" (fun args -> add_timer t args ~repeat:true);
  define "clearTimeout" (clear_timer t);
  define "clearInterval" (clear_timer t);
  (* the next frame: a timer of a sixtieth of a second *)
  define "requestAnimationFrame" (fun args -> add_timer t [ arg args 0; Number 16. ] ~repeat:false);
  define "cancelAnimationFrame" (clear_timer t);
  define "alert" (fun args -> t.alerts <- str (arg args 0) :: t.alerts; Undefined);
  Js_eval.define engine "location" (location t);
  Js_eval.define engine "navigator"
    (let o = new_object () in
     set_own o "userAgent" (String "Mozilla/5.0 (TinyChrome; elm_playground)");
     set_own o "language" (String "en-US");
     Object o);
  (* new URL(href, base) *)
  define "URL" (fun args ->
      let base = match arg args 1 with Undefined -> t.base | v -> str v in
      url_object (Browser_url.resolve base (str (arg args 0))));
  (* a script asking the network: its requests queued for the browser
   * ([take_requests]), their answers given back ([answer]) *)
  XMLHttpRequest.install t (Js_eval.define engine);
  Script_fetch.install t (Js_eval.define engine);
  t

let eval (t : t) (text : string) : (value, Js_eval.error) result =
  let r = Js_eval.eval t.engine text in
  (match r with Error e -> report t e | Ok _ -> ());
  r

(* a script the page's: JavaScript by its type= (not JSON-LD, not a
 * module, not a template) *)
let runnable (s : node) : bool =
  match Option.map String.lowercase_ascii (attribute s "type") with
  | None | Some "" | Some "text/javascript" | Some "application/javascript" -> true
  | Some _ -> false

let script_sources (t : t) : string list =
  List.filter_map
    (fun (s : node) -> if runnable s then Option.map (Browser_url.resolve t.base) (attribute s "src") else None)
    (List.filter (fun e -> e.name = "script") (elements t.root))

let run_scripts ?(source = fun (_ : string) -> None) (t : t) : unit =
  List.iter
    (fun (s : node) ->
      match attribute s "src" with
      | Some src -> (
          match source (Browser_url.resolve t.base src) with
          | Some text -> ignore (eval t text)
          | None -> say t (Printf.sprintf "<script src=\"%s\"> could not be had" src))
      | None -> ignore (eval t (text_content s)))
    (List.filter (fun e -> e.name = "script" && runnable e) (elements t.root));
  (* then the document is loaded: its listeners told *)
  List.iter
    (fun typ ->
      let listeners = List.filter (fun (ty, _) -> ty = typ) t.document_listeners in
      List.iter (fun (_, f) -> ignore (run_handler t f ~this:Undefined Undefined)) listeners)
    [ "DOMContentLoaded"; "load" ]

let tree (t : t) : Dom.element =
  t.changed <- false;
  let pairs = ref [] in
  let rec go (n : node) : Dom.element =
    let origin = Dtd.element_origin n.name in
    let attributes, extensions =
      match origin with
      | Netscape -> (n.attributes, [])
      | Core -> List.partition (fun a -> Dtd.attribute_origin n.name a = Dtd.Core) n.attributes
    in
    (* a comment is not the page's *)
    let children = List.filter_map (fun c -> if is_text c then Some (Dom.Text c.text) else if is_element c then Some (Dom.Element (go c)) else None) n.children in
    let e : Dom.element = { name = n.name; attributes; extensions; origin; children } in
    pairs := (e, n) :: !pairs;
    e
  in
  let root = go t.root in
  t.frozen <- !pairs;
  root

let click (t : t) (e : Dom.element) : bool =
  match node_of_element t e with Some n -> dispatch t n "click" [] | None -> false

let key (t : t) (k : string) : bool =
  let body = match List.find_opt (fun n -> n.name = "body") (elements t.root) with Some b -> b | None -> t.root in
  dispatch t body "keydown" [ ("key", String k) ]

let input (t : t) (e : Dom.element) (text : string) : unit =
  match node_of_element t e with
  | Some n ->
      set_attribute n "value" text;
      touch t;
      ignore (dispatch t n "input" [])
  | None -> ()

let advance (t : t) (ms : float) : unit =
  t.now <- t.now +. ms;
  (* the timers due, the earliest first, each a task; an interval put
   * back at its next time; a thousand at most, so that a page cannot
   * keep the browser here *)
  let rec go (runs : int) =
    match List.sort (fun a b -> compare (a.due, a.tid) (b.due, b.tid)) (List.filter (fun tm -> tm.due <= t.now) t.timers) with
    | tm :: _ when runs < 1000 ->
        (match tm.every with
        | Some every -> tm.due <- tm.due +. every
        | None -> t.timers <- List.filter (fun x -> x.tid <> tm.tid) t.timers);
        ignore (run_handler t tm.fn ~this:Undefined Undefined);
        go (runs + 1)
    | _ -> ()
  in
  go 0

(* a request's answer, given to the script that asked: a task of its
 * own (its promises' thens run after it) *)
let answer (t : t) (rid : int) (result : (answer, string) result) : unit =
  let give = host_function "answer" (fun ~this:_ _ -> Script_fetch.answer t rid result; Undefined) in
  match Js_eval.call t.engine give ~this:Undefined [] with Ok _ -> () | Error e -> report t e

let take_requests (t : t) : request list =
  let r = List.rev t.requests in
  t.requests <- [];
  r

let take_alerts (t : t) : string list =
  let a = List.rev t.alerts in
  t.alerts <- [];
  a

let changed (t : t) : bool = t.changed
let console (t : t) : string list = List.rev t.console
let print (t : t) (line : string) : unit = say t line
let engine (t : t) : Js_eval.t = t.engine
