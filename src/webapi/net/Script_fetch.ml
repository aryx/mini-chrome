(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Script_fetch.mli *)
open Js_value
open Script_types
open Script_host

let header (a : answer) (name : string) : string option = Cors.header a.headers name

(*****************************************************************************)
(* The request out, the answer back *)
(*****************************************************************************)

let ask ?(cors = true) (t : t) ~(meth : string) ~(url : string) ~(post : (string * string) option) (k : (answer, string) result -> unit) : int =
  t.next_request <- t.next_request + 1;
  let rid = t.next_request in
  if not cors then t.exempt <- rid :: t.exempt;
  let meth = String.uppercase_ascii meth in
  (* what the browser's Fetch cannot send is answered at once, by a failure *)
  if meth <> "GET" && meth <> "POST" then k (Error (meth ^ " is not sent here: GET and POST only"))
  else (
    t.requests <- { rid; meth; url = Browser_url.resolve t.base url; post = (if meth = "POST" then Some (Option.value post ~default:("text/plain;charset=UTF-8", "")) else None) } :: t.requests;
    t.waiting <- (rid, k) :: t.waiting);
  rid

let forget (t : t) (rid : int) : unit = t.waiting <- List.remove_assoc rid t.waiting

let answer (t : t) (rid : int) (result : (answer, string) result) : unit =
  match List.assoc_opt rid t.waiting with
  | None -> ()
  | Some k ->
      forget t rid;
      k
        (match result with
        (* an answer the page may not read (Cors) is no answer *)
        | Ok a when (not (List.mem rid t.exempt)) && not (Cors.readable ~page:t.base ~url:a.final a.headers) ->
            let why = Cors.blocked ~page:t.base ~url:a.final in
            t.console <- why :: t.console;
            t.log why;
            Error why
        | r -> r)

let call (t : t) (f : value) ~(this : value) (args : value list) : unit =
  match f with
  | Object { kind = Closure _ | Host_function _; _ } -> (
      try ignore (Js_eval.call_in_run t.engine f ~this args)
      with Throw v ->
        let e = Js_eval.error_of t.engine v in
        let line = Printf.sprintf "%s (line %d)" (if String.starts_with ~prefix:"Uncaught" e.message then e.message else "Uncaught " ^ e.message) e.line in
        t.console <- line :: t.console;
        t.log line)
  | _ -> ()

(*****************************************************************************)
(* fetch *)
(*****************************************************************************)

let fn (name : string) (f : value list -> value) : value = host_function name (fun ~this:_ args -> f args)

(* a promise already settled *)
let resolved (t : t) (f : unit -> value) : value =
  let p, resolve, reject = Js_eval.promise t.engine in
  (match f () with v -> resolve v | exception Throw e -> reject e);
  p

(* JSON.parse, the engine's *)
let parse_json (t : t) (text : string) : value =
  match Js_eval.global t.engine "JSON" with
  | Some json -> Js_eval.call_in_run t.engine (Js_eval.get t.engine json "parse") ~this:json [ String text ]
  | None -> Undefined

(* what fetch's promise gives: the answer, its body as promises *)
let response (t : t) (a : answer) : value =
  let o = new_object () in
  let headers = new_object () in
  set_own headers "get" (fn "get" (fun args -> match header a (str (arg args 0)) with Some v -> String v | None -> Null));
  set_own headers "has" (fn "has" (fun args -> Bool (header a (str (arg args 0)) <> None)));
  set_own headers "forEach" (fn "forEach" (fun args -> List.iter (fun (k, v) -> call t (arg args 0) ~this:Undefined [ String v; String (String.lowercase_ascii k) ]) a.headers; Undefined));
  set_own o "ok" (Bool (a.status >= 200 && a.status < 300));
  set_own o "status" (Number (float_of_int a.status));
  set_own o "statusText" (String (Http.reason a.status));
  set_own o "url" (String a.final);
  set_own o "redirected" (Bool false);
  set_own o "headers" (Object headers);
  set_own o "text" (fn "text" (fun _ -> resolved t (fun () -> String a.body)));
  set_own o "json" (fn "json" (fun _ -> resolved t (fun () -> parse_json t a.body)));
  set_own o "clone" (fn "clone" (fun _ -> Object o));
  Object o

let install (t : t) (define : string -> value -> unit) : unit =
  define "fetch"
    (fn "fetch" (fun args ->
         (* fetch(url, init), fetch(request): an object with a url *)
         let property (v : value) (k : string) : value = match v with Object _ -> Js_eval.get t.engine v k | _ -> Undefined in
         let url = match arg args 0 with Object _ as r when property r "url" <> Undefined -> str (property r "url") | v -> str v in
         let init = arg args 1 in
         let meth = match property init "method" with Undefined -> "GET" | m -> str m in
         let content_type = match property (property init "headers") "Content-Type" with Undefined -> "text/plain;charset=UTF-8" | c -> str c in
         let post = match property init "body" with Undefined | Null -> None | b -> Some (content_type, str b) in
         let p, resolve, reject = Js_eval.promise t.engine in
         ignore
           (ask t ~meth ~url ~post (fun result ->
                match result with
                | Ok a -> resolve (response t a)
                (* no answer, or one not to be read: as browsers say it *)
                | Error _ -> reject (error "TypeError" "Failed to fetch")));
         p))
