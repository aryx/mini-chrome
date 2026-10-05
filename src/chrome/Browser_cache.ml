(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Browser_cache.mli *)

let default_dir (caps : < Cap.env ; .. >) : string option =
  let env name = match CapSys.getenv caps name with "" -> None | v -> Some v | exception Not_found -> None in
  match (env "XDG_CACHE_HOME", env "HOME") with
  | Some cache, _ -> Some (Filename.concat cache "mini-chrome")
  | None, Some home -> Some (Filename.concat (Filename.concat home ".cache") "mini-chrome")
  | None, None -> None

let file (dir : string) (url : string) : string = Filename.concat dir (Sha256.hex (Sha256.digest url))

(* the directory's files, each with its size and when it was last used *)
let files (dir : string) : (string * int * float) list =
  match Sys.readdir dir with
  | names ->
      List.filter_map
        (fun name ->
          let path = Filename.concat dir name in
          match Unix.stat path with { st_kind = S_REG; st_size; st_mtime; _ } -> Some (path, st_size, st_mtime) | _ | (exception Unix.Unix_error _) -> None)
        (Array.to_list names)
  | exception Sys_error _ -> []

(* over [limit]: the files used longest ago removed, until a tenth is free *)
let trim ~(limit : int) (dir : string) : unit =
  let all = List.sort (fun (_, _, a) (_, _, b) -> compare a b) (files dir) in
  let total = List.fold_left (fun sum (_, size, _) -> sum + size) 0 all in
  if total > limit then (
    Logs.info (fun m -> m "cache: %d MB in %s, the oldest removed" (total / 1_000_000) dir);
    ignore
      (List.fold_left
         (fun total (path, size, _) -> if total > limit / 10 * 9 then ((try Sys.remove path with Sys_error _ -> ()); total - size) else total)
         total all))

(* a copy's head, without its body: the file's first four kilobytes *)
let entries (caps : < Cap.open_in ; .. >) ~(now : float) ~(dir : string) : (string * int * float * bool) list =
  List.sort (fun (_, _, a) (_, _, b) -> compare b a) (files dir)
  |> List.filter_map (fun (path, size, _) ->
         let (_ : Cap.FS_.open_in) = caps#open_in path in
         match In_channel.with_open_bin path (fun ic -> really_input_string ic (min size 4096)) with
         | head -> (
             (* cut at the headers' end, or where the read stopped *)
             let cut = match Str.search_forward (Str.regexp_string "\n\n") head 0 with i -> String.sub head 0 (i + 2) | exception Not_found -> head ^ "\n\n" in
             match Http_cache.of_string cut with
             | Some e -> Some (e.url, size - String.length cut, e.stored, Http_cache.fresh ~now e)
             | None -> None)
         | exception (Sys_error _ | End_of_file) -> None)

let store (caps : < Cap.open_in ; Cap.open_out ; .. >) ?(limit = 200_000_000) ~(dir : string) () : Http_cache.store =
  (* how many were written: the size looked at now and then, not at each *)
  let written = Atomic.make 0 in
  let find (url : string) : Http_cache.entry option =
    let path = file dir url in
    let (_ : Cap.FS_.open_in) = caps#open_in path in
    match In_channel.with_open_bin path In_channel.input_all with
    | text -> (
        match Http_cache.of_string text with
        | Some e when e.url = url ->
            Logs.info (fun m -> m "cache: %s read from %s" url path);
            (* used: now the last to go *)
            (try Unix.utimes path 0. 0. with Unix.Unix_error _ -> ());
            Some e
        | _ -> None)
    | exception Sys_error _ -> None
  in
  let keep (e : Http_cache.entry) : unit =
    let path = file dir e.url in
    let (_ : Cap.FS_.open_out) = caps#open_out path in
    let rec make (dir : string) = if not (Sys.file_exists dir) then (make (Filename.dirname dir); try Sys.mkdir dir 0o700 with Sys_error _ -> ()) in
    let n = Atomic.fetch_and_add written 1 in
    (* whole or not at all: written beside, then given its name *)
    let beside = Printf.sprintf "%s.%d.tmp" path n in
    try
      make dir;
      Out_channel.with_open_gen [ Open_wronly; Open_creat; Open_trunc; Open_binary ] 0o600 beside (fun oc -> Out_channel.output_string oc (Http_cache.to_string e));
      Sys.rename beside path;
      Logs.info (fun m -> m "cache: %s kept in %s" e.url path);
      if n mod 100 = 0 then trim ~limit dir
    with Sys_error why -> Logs.warn (fun m -> m "cache: %s not kept: %s" e.url why)
  in
  { find; keep; entries = (fun ~now -> entries caps ~now ~dir); place = dir }

let page ~(now : float) (cache : Http_cache.store option) : string =
  let entries = match cache with Some c -> c.entries ~now | None -> [] in
  let esc = Browser_text.escape_html in
  let ago (t : float) =
    let s = now -. t in
    if s < 3600. then Printf.sprintf "%.0f minutes ago" (s /. 60.) else if s < 172800. then Printf.sprintf "%.0f hours ago" (s /. 3600.) else Printf.sprintf "%.0f days ago" (s /. 86400.)
  in
  (* an address's start and end, when it is long *)
  let short s = if String.length s > 46 then String.sub s 0 28 ^ "..." ^ String.sub s (String.length s - 15) 15 else s in
  let row (url, size, stored, fresh) =
    Printf.sprintf "<tr><td><code>%s</code></td><td>%d KB</td><td>%s</td><td>%s</td></tr>\n" (esc (short url)) ((size + 999) / 1000) (ago stored)
      (if fresh then "fresh" else "to ask about")
  in
  let total = List.fold_left (fun sum (_, size, _, _) -> sum + size) 0 entries in
  Printf.sprintf
    {|<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><title>Cache</title>
<link rel="stylesheet" href="chrome.css">
<style>table { width: 100%%; table-layout: fixed; border-collapse: collapse; font-size: 13px } th { text-align: left; color: var(--muted) } td, th { padding: 3px 8px 3px 0 }</style>
</head><body>
<header><div><h1>Cache</h1><p>The answers kept, to be given again without asking the network.</p></div>
<nav><a href="about:chrome">Home</a><a href="about:cookies">Cookies</a></nav></header>
<main><div class="card">
<h2>%d kept, %.1f MB</h2>
<p>A server says how long an answer may be used again (<code>Cache-Control: max-age=...</code>). While it is fresh the copy is
the answer and nothing is sent; after, the browser asks whether it changed (<code>If-None-Match</code>) and a
<code>304</code> means the copy still. %s</p>
<table><tr><th>Address</th><th style="width: 70px">Size</th><th style="width: 120px">Kept</th><th style="width: 100px"></th></tr>
%s</table>
</div></main></body></html>
|}
    (List.length entries)
    (float_of_int total /. 1e6)
    (match cache with Some c -> "The files are in " ^ esc c.place ^ "." | None -> "No cache is kept in this run (<code>profile=off</code> or <code>cache=off</code>).")
    (String.concat "" (List.map row entries))
