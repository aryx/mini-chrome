(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Browser_cookies.mli *)

(*****************************************************************************)
(* The Cookies file's text *)
(*****************************************************************************)

let to_string (jar : Cookie.jar) : string =
  let cookie (c : Cookie.cookie) : Json.t option =
    Option.map
      (fun expires ->
        Json.Object
          [ ("name", String c.name); ("value", String c.value); ("domain", String c.domain); ("host_only", Bool c.host_only); ("path", String c.path);
            ("expires", Number expires); ("secure", Bool c.secure); ("http_only", Bool c.http_only); ("created", Number c.created) ])
      c.expires
  in
  Json.to_string (Array (List.filter_map cookie jar)) ^ "\n"

let of_string (s : string) : (Cookie.jar, string) result =
  let cookie (j : Json.t) : Cookie.cookie option =
    let string k = match Json.member k j with Some (String s) -> Some s | _ -> None in
    let bool k = match Json.member k j with Some (Bool b) -> b | _ -> false in
    let number k = match Json.member k j with Some (Number n) -> Some n | _ -> None in
    match (string "name", string "value", string "domain", string "path", number "expires") with
    | Some name, Some value, Some domain, Some path, Some expires when name <> "" && domain <> "" ->
        Some
          { name; value; domain; host_only = bool "host_only"; path; expires = Some expires; secure = bool "secure"; http_only = bool "http_only";
            created = Option.value (number "created") ~default:0. }
    | _ -> None
  in
  Result.bind (Json.parse s) (fun json -> match json with Array cookies -> Ok (List.filter_map cookie cookies) | _ -> Error "not a list of cookies")

(*****************************************************************************)
(* The file *)
(*****************************************************************************)

let file (dir : string) : string = Filename.concat dir "Cookies"

let load (caps : < Cap.open_in ; .. >) ~(now : float) ~(dir : string) : (Cookie.jar, string) result =
  let path = file dir in
  let (_ : Cap.FS_.open_in) = caps#open_in path in
  if not (Sys.file_exists path) then (
    Logs.info (fun m -> m "cookies: no %s yet" path);
    Ok [])
  else (
    Logs.info (fun m -> m "cookies: reading %s" path);
    Result.map_error
      (fun why -> path ^ ": " ^ why)
      (match In_channel.with_open_bin path In_channel.input_all with
      | s -> Result.map (Cookie.alive ~now) (of_string s)
      | exception Sys_error why -> Error why))

let save (caps : < Cap.open_out ; .. >) ~(dir : string) (jar : Cookie.jar) : (unit, string) result =
  let path = file dir in
  let (_ : Cap.FS_.open_out) = caps#open_out path in
  let rec make (dir : string) = if not (Sys.file_exists dir) then (make (Filename.dirname dir); Sys.mkdir dir 0o700) in
  Logs.info (fun m -> m "cookies: writing %s" path);
  try
    make dir;
    (* its owner's alone: it is what signs in *)
    Out_channel.with_open_gen [ Open_wronly; Open_creat; Open_trunc; Open_binary ] 0o600 (path ^ ".tmp") (fun oc -> Out_channel.output_string oc (to_string jar));
    Sys.rename (path ^ ".tmp") path;
    Ok ()
  with Sys_error why -> Error why

(*****************************************************************************)
(* about:cookies *)
(*****************************************************************************)

let page ~(now : float) (jar : Cookie.jar) : string =
  let esc = Browser_text.escape_html in
  let jar = List.sort (fun (a : Cookie.cookie) (b : Cookie.cookie) -> compare (a.domain, a.path, a.name) (b.domain, b.path, b.name)) (Cookie.alive ~now jar) in
  let short s = if String.length s > 20 then String.sub s 0 17 ^ "..." else s in
  let until (c : Cookie.cookie) =
    match c.expires with
    | None -> "the session"
    | Some e ->
        let left = e -. now in
        if left < 3600. then Printf.sprintf "%.0f minutes" (left /. 60.)
        else if left < 172800. then Printf.sprintf "%.0f hours" (left /. 3600.)
        else Printf.sprintf "%.0f days" (left /. 86400.)
  in
  let row (c : Cookie.cookie) =
    Printf.sprintf "<tr><td>%s%s</td><td>%s</td><td><code>%s</code></td><td><code>%s</code></td><td>%s</td><td>%s</td></tr>\n" (esc c.domain)
      (if c.host_only then "" else " <small>and under it</small>")
      (esc c.path) (esc c.name) (esc (short c.value)) (until c)
      (String.concat ", " ((if c.secure then [ "Secure" ] else []) @ if c.http_only then [ "HttpOnly" ] else []))
  in
  Printf.sprintf
    {|<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><title>Cookies</title>
<link rel="stylesheet" href="chrome.css">
<style>table { width: 100%%; border-collapse: collapse; font-size: 13px } th { text-align: left; color: var(--muted) } td, th { padding: 3px 8px 3px 0 }</style>
</head><body>
<header><div><h1>Cookies</h1><p>What sites asked this browser to remember, and to say back.</p></div>
<nav><a href="about:chrome">Home</a><a href="about:history">History</a></nav></header>
<main><div class="card">
<h2>%d kept</h2>
<p>A response's <code>Set-Cookie: name=value</code> is kept here, and said back in each later request to its site
(<code>Cookie: name=value</code>): how a site knows who is signed in. Those with a date outlive the browser, in the profile's
<code>Cookies</code> file; a session's are forgotten when it closes.</p>
%s
</div></main></body></html>
|}
    (List.length jar)
    (if jar = [] then {|<p class="muted">None yet. Visit a site, and load this page again.</p>|}
     else "<table><tr><th>Site</th><th>Path</th><th>Name</th><th>Value</th><th>Kept for</th><th></th></tr>\n" ^ String.concat "" (List.map row jar) ^ "</table>")
