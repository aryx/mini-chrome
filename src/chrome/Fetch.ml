(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Fetch.mli; after elm-playground's native_common/Commands.ml *)

type response = { url : string; status : int; headers : (string * string) list; body : string }
type error = Bad_url of string | Timeout | Network_error of string

let error_to_string (e : error) : string =
  match e with
  | Bad_url url -> "bad URL: " ^ url
  | Timeout -> "timeout"
  | Network_error why -> "network error: " ^ why

type answer = (response, error) result

(* the capability closed: it is stored *)
type 'msg request = { caps : Cap.network; url : string; post : (string * string) option; said : (string * string) list option; ready : response -> unit; reload : bool; k : answer -> 'msg }

let get ?said ?(ready = fun (_ : response) -> ()) ?(reload = false) (caps : < Cap.network ; .. >) (url : string) (k : answer -> 'msg) : 'msg request =
  { caps = (caps :> Cap.network); url; post = None; said; ready; reload; k }

let post ?said (caps : < Cap.network ; .. >) (url : string) ~(content_type : string) ~(body : string) (k : answer -> 'msg) : 'msg request =
  { caps = (caps :> Cap.network); url; post = Some (content_type, body); said; ready = ignore; reload = false; k }

type 'msg in_flight =
  | Now of 'msg
  | Request of Cap.network * Http_request.t * (answer -> 'msg)
  (* https://, on a thread of the pool *)
  | Blocking of answer Worker.job * (answer -> 'msg)

type 'msg t = {
  mutable in_flight : 'msg in_flight list;
  (* with threads: where what blocks is done *)
  pool : Worker.t option;
  (* the browser's cookies: said with each request, kept from
   * each answer (Cookie_jar) *)
  jar : Cookie_jar.t;
  (* what the browser says it is to each host (User-Agent) *)
  agent : (string -> string) option;
  (* the answers kept (Http_cache; the files: Browser_cache) *)
  cache : Http_cache.store option;
  (* the pages' WebSockets, stepped with the requests *)
  sockets : 'msg Web_sockets.t;
  (* a recording to answer from, and the network never asked (Browser_replay) *)
  replay : (string -> string option) option;
}

(* sixteen workers at most, as many as the machine has cores to spare
 * (Worker_spawn.workers: under OCaml 5 each is a domain; eight on a
 * machine of nine cores, three on one of four): that many names
 * resolved, https:// fetches and pictures decoded at once, the others
 * queued. It was eight, a browser's six connections a host and room
 * for a picture being decoded *)
let workers = 16

let create ?(threads = true) ?(jar = Cookie_jar.create ()) ?agent ?cache ?replay () : 'msg t =
  (* the pool's workers may be domains, reading answers at the same time *)
  if threads && Worker_spawn.parallel then Http.ready ();
  let pool = if threads then Some (Worker.create ~name:(Printf.sprintf "fetch %d") workers) else None in
  { in_flight = []; pool; jar; agent; cache; sockets = Web_sockets.create ?pool (); replay }

let jar (t : 'msg t) : Cookie_jar.t = t.jar
let cache (t : 'msg t) : Http_cache.store option = t.cache
let threads (t : 'msg t) : bool = t.pool <> None
let sockets (t : 'msg t) : 'msg Web_sockets.t = t.sockets

(* https://, by Http_client over our own TLS 1.3 (Tls_client, Tls13) --
 * blocking, so the frame waits while it fetches, or on a thread of the
 * pool. The answer in the same shape as Http_request's: the URL after
 * the redirections, the status, the headers, the body's bytes. *)
let is_https (url : string) : bool = String.length url >= 8 && String.lowercase_ascii (String.sub url 0 8) = "https://"

let https_get ?post ?agent ?said ?cache ?reload (jar : Cookie_jar.t) (caps : Cap.network) (url : string) : answer =
  match Http_client.fetch ?post ~jar ?agent ?said ?cache ?reload caps url with
  | Ok (url, response) -> Ok { url; status = response.status; headers = response.headers; body = response.body }
  | Error why -> Error (Network_error why)

let readying = Mutex.create ()

(* the blocking fetch: at once, the frame waiting, or on a thread *)
let blocking ?post ?said ?reload ?(ready = ignore) (t : 'msg t) (caps : Cap.network) (url : string) (k : answer -> 'msg) : 'msg in_flight =
  match t.pool with
  | None -> Now (k (https_get ?post ?said ?agent:t.agent ?cache:t.cache ?reload t.jar caps url))
  | Some pool ->
      (* [ready], on the pool's thread too: what the answer's reader
       * will need of it made there (a picture decoded), not in a frame *)
      let fetch () =
        let a = https_get ?post ?said ?agent:t.agent ?cache:t.cache ?reload t.jar caps url in
        (match a with
        | Ok r -> (
            (* with threads that take turns (OCaml 4.14: one runs at a
             * time), one answer made ready at a time: eight large
             * pictures decoded at once left the window one turn in
             * nine, and it did not answer a click for a minute
             * (dynamicland.org's report: eight photographs of eleven
             * million dots). Domains really run beside it *)
            if not Worker_spawn.parallel then Mutex.lock readying;
            Fun.protect ~finally:(fun () -> if not Worker_spawn.parallel then Mutex.unlock readying) (fun () -> try ready r with _ -> ()))
        | Error _ -> ());
        a
      in
      Blocking (Worker.submit pool fetch, k)

(* what -v shows: each request as it starts, and its answer
 * (said when it is handed back, in step: not on a thread of the pool) *)
let said (url : string) (a : answer) : unit =
  match a with
  | Ok r when r.url = url -> Logs.info (fun m -> m "%d %s (%d bytes)" r.status url (String.length r.body))
  | Ok r -> Logs.info (fun m -> m "%d %s (%d bytes), redirected from %s" r.status r.url (String.length r.body) url)
  | Error e -> Logs.info (fun m -> m "failed %s: %s" url (error_to_string e))

let perform (t : 'msg t) (r : 'msg request) : unit =
  Logs.info (fun m -> m "%s %s" (if r.post = None then "GET" else "POST") r.url);
  let k (a : answer) = said r.url a; r.k a in
  let f =
    match t.replay with
    | Some saved -> Now (k (match saved r.url with Some body -> Ok { url = r.url; status = 200; headers = []; body } | None -> Ok { url = r.url; status = 404; headers = []; body = "" }))
    | None ->
    if is_https r.url then blocking ?post:r.post ?said:r.said ~reload:r.reload ~ready:r.ready t r.caps r.url k
    else Request (r.caps, Http_request.start ?post:r.post ?resolver:t.pool ~jar:t.jar ?agent:t.agent r.caps r.url, k)
  in
  t.in_flight <- t.in_flight @ [ f ]

(* Http_request's answer, with the URL of the last redirection *)
let answer (request : Http_request.t) (r : (Http.response, Http_request.error) result) : answer =
  match r with
  | Ok response -> Ok { url = Http_request.url request; status = response.status; headers = response.headers; body = response.body }
  | Error (Bad_url why) -> Error (Bad_url why)
  | Error Timeout -> Error Timeout
  | Error (Failed why) -> Error (Network_error why)

let step (t : 'msg t) : 'msg list =
  let finished, pending =
    t.in_flight
    |> List.partition_map (fun f ->
           match f with
           | Now msg -> Left msg
           | Request (caps, r, k) -> (
               Http_request.step r;
               match Http_request.result r with
               | None -> Right f
               (* a redirection to https:// (what most http:// sites
                * answer today), which Http_request leaves to the
                * blocking client *)
               | Some (Error (Bad_url _)) when is_https (Http_request.url r) -> (
                   match blocking t caps (Http_request.url r) k with Now msg -> Left msg | f -> Right f)
               | Some result -> Left (k (answer r result)))
           | Blocking (job, k) -> (
               match Worker.poll job with
               | None -> Right f
               | Some (Ok result) -> Left (k result)
               | Some (Error e) -> Left (k (Error (Network_error (Printexc.to_string e))))))
  in
  t.in_flight <- pending;
  finished @ Web_sockets.step t.sockets
