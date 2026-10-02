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

(* a handler run, a task of its own: its error in the console, not the
 * next handler's business; whether it returned false (DOM level 0's way
 * to cancel, onclick="...; return false") *)
let run_handler (t : t) (f : value) ~(this : value) (event : value) : bool =
  match Js_eval.call t.engine f ~this [ event ] with
  | Ok (Bool false) -> true
  | Ok _ -> false
  | Error e -> report t e; false

(* onclick="..." compiled once into a function of event, as browsers
 * do: the attribute's text is the function's body *)
let attribute_handler (t : t) (n : node) (typ : string) : value option =
  match attribute n ("on" ^ typ) with
  | None -> None
  | Some src -> (
      match List.assoc_opt src n.compiled with
      | Some f -> Some f
      | None -> (
          match Js_eval.eval t.engine ("(function (event) {\n" ^ src ^ "\n})") with
          | Ok f ->
              n.compiled <- (src, f) :: n.compiled;
              Some f
          | Error e -> report t e; None))

(* an event dispatched at [target]: its handlers, then its parent's, up
 * to the document (bubbling), unless one stops it; whether one
 * prevented the default *)
let dispatch (t : t) (target : node) (typ : string) (fields : (string * value) list) : bool =
  let prevented = ref false and stopped = ref false and stopped_now = ref false in
  let ev = new_object () in
  set_own ev "type" (String typ);
  set_own ev "target" (wrap t target);
  List.iter (fun (k, v) -> set_own ev k v) fields;
  set_own ev "defaultPrevented" (Bool false);
  set_own ev "preventDefault" (host_function "preventDefault" (fun ~this:_ _ -> prevented := true; set_own ev "defaultPrevented" (Bool true); Undefined));
  set_own ev "stopPropagation" (host_function "stopPropagation" (fun ~this:_ _ -> stopped := true; Undefined));
  (* and the other handlers of the same element not run either *)
  set_own ev "stopImmediatePropagation" (host_function "stopImmediatePropagation" (fun ~this:_ _ -> stopped := true; stopped_now := true; Undefined));
  let event = Object ev in
  let handle this (listeners : (string * value) list) (extra : value option) =
    set_own ev "currentTarget" this;
    List.iter (fun (ty, f) -> if ty = typ && (not !stopped_now) && run_handler t f ~this event then prevented := true) listeners;
    Option.iter (fun f -> if (not !stopped_now) && run_handler t f ~this event then prevented := true) extra
  in
  let rec up (n : node option) =
    match n with
    | Some n when not !stopped ->
        (* el.onclick = f, else onclick="..." *)
        let on = match List.assoc_opt ("on" ^ typ) n.expando with Some (Object _ as f) -> Some f | _ -> attribute_handler t n typ in
        handle (wrap t n) n.listeners on;
        up n.parent
    | _ -> ()
  in
  up (Some target);
  if not !stopped then handle (Js_eval.global t.engine "document" |> Option.value ~default:Undefined) t.document_listeners None;
  !prevented

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
      now = 0.; timers = []; next_timer = 0; alerts = []; base; requests = []; cookies }
  in
  (* Date's clock: the page's, from [epoch] *)
  clock := (fun () -> epoch +. t.now);
  lines := say t;
  let define name f = Js_eval.define engine name (host_function name (fun ~this:_ args -> f args)) in
  Js_eval.define engine "document" (document t);
  define "setTimeout" (fun args -> add_timer t args ~repeat:false);
  define "setInterval" (fun args -> add_timer t args ~repeat:true);
  define "clearTimeout" (clear_timer t);
  define "clearInterval" (clear_timer t);
  define "alert" (fun args -> t.alerts <- str (arg args 0) :: t.alerts; Undefined);
  (* window: the global object -- a global read or set through it; its
   * listeners the document's, its size the window's *)
  let window =
    host_object
      {
        class_name = "Window";
        get =
          (fun k ->
            match k with
            | "innerWidth" -> Number (fst viewport)
            | "innerHeight" -> Number (snd viewport)
            | "location" -> location t
            | "document" -> Option.value (Js_eval.global engine "document") ~default:Undefined
            | "addEventListener" | "removeEventListener" -> (
                match Js_eval.global engine "document" with Some (Object { kind = Host_object h; _ }) -> h.get k | _ -> Undefined)
            | "scrollTo" | "scrollBy" -> method_ k (fun _ -> Undefined)
            | k -> Option.value (Js_eval.global engine k) ~default:Undefined);
        set = (fun k v -> Js_eval.define engine k v);
        show = (fun () -> "Window");
      }
  in
  Js_eval.define engine "window" window;
  Js_eval.define engine "self" window;
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
  (* a GET queued for the browser to send ([take_requests]); its answer
   * not given back (no onload): enough for a vote, not for a page that
   * reads what it asked *)
  let queue url = t.requests <- Browser_url.resolve t.base url :: t.requests in
  define "XMLHttpRequest" (fun _ ->
      let url = ref None in
      let o = new_object () in
      set_own o "readyState" (Number 0.);
      set_own o "open" (host_function "open" (fun ~this:_ args -> url := Some (str (arg args 1)); Undefined));
      set_own o "setRequestHeader" (host_function "setRequestHeader" (fun ~this:_ _ -> Undefined));
      set_own o "send" (host_function "send" (fun ~this:_ _ -> Option.iter queue !url; Undefined));
      Object o);
  (* fetch: the GET queued, a promise that never settles (no promises
   * here: its then's are kept, never called) *)
  define "fetch" (fun args ->
      queue (str (arg args 0));
      let p = new_object () in
      let self = Object p in
      set_own p "then" (host_function "then" (fun ~this:_ _ -> self));
      set_own p "catch" (host_function "catch" (fun ~this:_ _ -> self));
      self);
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
    let children = List.map (fun c -> if is_text c then Dom.Text c.text else Dom.Element (go c)) n.children in
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

let take_requests (t : t) : string list =
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
