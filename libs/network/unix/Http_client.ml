(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Http_client.mli *)

let ( let* ) = Result.bind

(* opti: an https:// connection is kept for the next request to its
 * host (Keep_alive.mli, with the numbers): the request then says
 * "Connection: keep-alive", not "close" *)
let kept (url : Url.t) : bool = !Mini_opti.enabled && url.scheme = Some "https"

let prepare ?post ?jar ?agent ?said (url : Url.t) : (string * int * string, string) result =
  match (url.scheme, url.authority, Url.port url) with
  | Some ("http" | "https"), Some (a : Url.authority), Some port ->
      (* the Host header says the port only when it isn't the default *)
      let host_header = match a.port with Some p -> Printf.sprintf "%s:%d" a.host p | None -> a.host in
      (* "[::1]" in a URL, "::1" for the resolver *)
      let host =
        if String.starts_with ~prefix:"[" a.host then String.sub a.host 1 (String.length a.host - 2) else a.host
      in
      let target = Url.request_target url in
      (* the cookies kept for that URL, said back *)
      let cookie = Option.bind jar (fun jar -> Cookie_jar.header jar url) in
      (* what it says it is, to this host *)
      let agent = Option.map (fun f -> f a.host) agent in
      let bytes =
        match post with
        | None -> Http.request_to_string (Http.get ?cookie ?agent ?said ~keep:(kept url) ~host:host_header target)
        | Some (content_type, body) -> Http.request_to_string ~body (Http.post ?cookie ?agent ?said ~keep:(kept url) ~host:host_header ~content_type ~body target)
      in
      Ok (host, port, bytes)
  | Some ("http" | "https"), _, _ -> Error (Printf.sprintf "%s: no host" (Url.to_string url))
  | _ -> Error (Printf.sprintf "%s: not an http:// or https:// URL" (Url.to_string url))

(* one request, no redirection followed: over TCP, or inside TLS for
   https:// (Tls_client, our own TLS 1.3) *)
let get_once ?post ?jar ?agent ?said ?timeout (caps : < Cap.network ; .. >) (url : Url.t) : (Http.response, string) result =
  let* host, port, request = prepare ?post ?jar ?agent ?said url in
  let* (response : Http.response) =
    if url.scheme = Some "https" then
      let* answer = if kept url then Keep_alive.exchange ?timeout caps ~host ~port request else Tls_client.exchange ?timeout caps ~host ~port request in
      Http.parse_response answer
    else
      match Tcp.exchange ?timeout caps ~host ~port request with
      | answer -> Http.parse_response answer
      | exception Unix.Unix_error (e, _, _) -> Error (Printf.sprintf "%s: %s" (Url.to_string url) (Unix.error_message e))
      | exception Failure msg -> Error msg
  in
  (* the cookies it sets, kept -- a redirection's too, before
   * the next request is made (a login answers 302 and Set-Cookie) *)
  Option.iter (fun jar -> Cookie_jar.received jar url response.headers) jar;
  Ok response

(* the same through the cache (Http_cache.mli), for a GET: a fresh
 * copy is the answer and nothing is sent; one that is not is asked
 * about (a 304: the copy, renewed); what comes whole is kept if it
 * may be. [reload]: the copy asked about even if fresh *)
let get_once ?post ?jar ?agent ?(said = []) ?timeout ?(cache : Http_cache.store option) ?(reload = false) (caps : < Cap.network ; .. >) (url : Url.t) :
    (Http.response, string) result =
  match (cache, post) with
  | Some cache, None -> (
      let address = Url.to_string url and now = Unix.gettimeofday () in
      let keep (r : Http.response) = if Http_cache.storable r then cache.keep { url = address; stored = now; response = r } in
      match cache.find address with
      | Some copy when Http_cache.fresh ~now copy && not reload -> Ok copy.response
      | Some copy when Http_cache.validators copy <> [] -> (
          let* r = get_once ?jar ?agent ~said:(said @ Http_cache.validators copy) ?timeout caps url in
          match r.status with
          | 304 ->
              let copy = Http_cache.revalidated ~now copy r in
              cache.keep copy;
              Ok copy.response
          | _ -> keep r; Ok r)
      | _ ->
          let* r = get_once ?jar ?agent ~said ?timeout caps url in
          keep r;
          Ok r)
  | _ -> get_once ?post ?jar ?agent ~said ?timeout caps url

let once = get_once

let fetch ?post ?jar ?agent ?said ?cache ?reload ?(max_redirects = 5) ?timeout (caps : < Cap.network ; .. >) (s : string) : (string * Http.response, string) result =
  let rec follow ?post (url : Url.t) (left : int) =
    let* (response : Http.response) = get_once ?post ?jar ?agent ?said ?cache ?reload ?timeout caps url in
    match (Http.is_redirect response.status, Http.header "Location" response.headers) with
    | true, Some location ->
        if left = 0 then Error (Printf.sprintf "%s: too many redirections" s)
        else
          let* next = Url.parse location in
          (* a redirection is followed with a GET, as browsers do *)
          follow (Url.resolve url next) (left - 1)
    | _ -> Ok (Url.to_string url, response)
  in
  let* url = Url.parse s in
  follow ?post url max_redirects

let get ?jar ?agent ?max_redirects ?timeout (caps : < Cap.network ; .. >) (s : string) : (Http.response, string) result =
  Result.map snd (fetch ?jar ?agent ?max_redirects ?timeout caps s)
