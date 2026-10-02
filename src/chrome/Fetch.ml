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
type 'msg request = { caps : Cap.network; url : string; post : (string * string) option; k : answer -> 'msg }

let get (caps : < Cap.network ; .. >) (url : string) (k : answer -> 'msg) : 'msg request =
  { caps = (caps :> Cap.network); url; post = None; k }

let post (caps : < Cap.network ; .. >) (url : string) ~(content_type : string) ~(body : string) (k : answer -> 'msg) : 'msg request =
  { caps = (caps :> Cap.network); url; post = Some (content_type, body); k }

type 'msg in_flight =
  | Now of 'msg
  | Request of Cap.network * Http_request.t * (answer -> 'msg)
  (* https://, on a thread of the pool *)
  | Blocking of answer Worker.job * (answer -> 'msg)

type 'msg t = {
  mutable in_flight : 'msg in_flight list;
  (* with threads: where what blocks is done *)
  pool : Worker.t option;
  (* claude: the browser's cookies: said with each request, kept from
   * each answer (Cookie_jar) *)
  jar : Cookie_jar.t;
}

(* four threads, Netscape's four connections: at most four names
 * resolved or https:// fetches waiting at once, the others queued *)
let create ?(threads = true) ?(jar = Cookie_jar.create ()) () : 'msg t =
  { in_flight = []; pool = (if threads then Some (Worker.create 4) else None); jar }

let jar (t : 'msg t) : Cookie_jar.t = t.jar

(* https://, by Http_client over our own TLS 1.3 (Tls_client, Tls13) --
 * blocking, so the frame waits while it fetches, or on a thread of the
 * pool. The answer in the same shape as Http_request's: the URL after
 * the redirections, the status, the headers, the body's bytes. *)
let is_https (url : string) : bool = String.length url >= 8 && String.lowercase_ascii (String.sub url 0 8) = "https://"

let https_get ?post (jar : Cookie_jar.t) (caps : Cap.network) (url : string) : answer =
  match Http_client.fetch ?post ~jar caps url with
  | Ok (url, response) -> Ok { url; status = response.status; headers = response.headers; body = response.body }
  | Error why -> Error (Network_error why)

(* the blocking fetch: at once, the frame waiting, or on a thread *)
let blocking ?post (t : 'msg t) (caps : Cap.network) (url : string) (k : answer -> 'msg) : 'msg in_flight =
  match t.pool with
  | None -> Now (k (https_get ?post t.jar caps url))
  | Some pool -> Blocking (Worker.submit pool (fun () -> https_get ?post t.jar caps url), k)

(* claude: what -v shows: each request as it starts, and its answer
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
    if is_https r.url then blocking ?post:r.post t r.caps r.url k
    else Request (r.caps, Http_request.start ?post:r.post ?resolver:t.pool ~jar:t.jar r.caps r.url, k)
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
  finished
