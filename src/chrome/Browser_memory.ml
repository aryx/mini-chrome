(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Browser_memory.mli *)
open Playground

let mb (bytes : int) : int = bytes / 1_048_576
let heap () : int = mb ((Gc.quick_stat ()).heap_words * (Sys.word_size / 8))

let resident (caps : < Cap.open_in ; .. >) : int =
  let statm = "/proc/self/statm" in
  let (_ : Cap.FS_.open_in) = caps#open_in statm in
  (* its second number: the pages in RAM, of 4096 bytes *)
  match String.split_on_char ' ' (In_channel.with_open_bin statm In_channel.input_all) with
  | _ :: pages :: _ when int_of_string_opt pages <> None -> mb (int_of_string pages * 4096)
  | _ | (exception Sys_error _) -> heap ()

let bars = 30
let graph_width = float_of_int (2 * bars)

let graph (samples : int list) ~(x : float) ~(y : float) : shape list =
  let top = float_of_int (List.fold_left max 1 samples) in
  (* the last first: drawn from the right *)
  List.mapi
    (fun i s ->
      let h = Float.max 1. (16. *. float_of_int s /. top) in
      rectangle (rgb 214 226 245) 2. h |> move (x -. 1. -. (2. *. float_of_int i)) (y -. 8. +. (h /. 2.)))
    (List.filteri (fun i _ -> i < bars) samples)

type tab = { title : string; kept : int; pictures : int; pixels_mb : int }

let tab (t : Browser_tab.t) : tab =
  let kept (entries : Browser_tab.entry list) = List.length (List.filter (fun (e : Browser_tab.entry) -> e.kept <> None) entries) in
  let pixels = List.fold_left (fun n (_, p) -> match p with Browser_picture.Arrived img -> n + (4 * img.width * img.height) | _ -> n) 0 t.pictures in
  { title = (match t.state with Shown p when p.title <> "" -> p.title | Shown p -> p.url | Loading url -> url);
    kept = kept t.history.behind + kept t.history.ahead; pictures = List.length t.pictures; pixels_mb = mb pixels }

let page ~(samples : int list) ~(tabs : tab list) ~(cache : (int * int * string) option) ~(profile : string option) : string =
  let esc = Browser_text.escape_html in
  let row (t : tab) = Printf.sprintf "<tr><td>%s</td><td>%d</td><td>%d</td><td>%d MB</td></tr>\n" (esc t.title) t.kept t.pictures t.pixels_mb in
  let now = match samples with s :: _ -> Printf.sprintf "%d MB" s | [] -> "not measured (memory=off, or a frame dumped)" in
  let high = List.fold_left max 0 samples and low = List.fold_left min max_int samples in
  Printf.sprintf
    {|<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><title>Memory</title>
<link rel="stylesheet" href="chrome.css">
<style>table { border-collapse: collapse; font-size: 13px } th { text-align: left; color: var(--muted) } td, th { padding: 3px 24px 3px 0 }</style>
</head><body>
<header><div><h1>Memory</h1><p>What the browser holds, and what it keeps on disk.</p></div>
<nav><a href="about:chrome">Home</a><a href="about:cache">Cache</a><a href="about:version">Version</a></nav></header>
<main><div class="card"><h2>In memory</h2>
<table>
<tr><th>In RAM now</th><td>%s</td></tr>
<tr><th>The last minute</th><td>%s</td></tr>
<tr><th>OCaml's heap</th><td>%d MB <small>(the pages' trees, the scripts' objects; not the pictures' pixels)</small></td></tr>
</table></div>
<div class="card"><h2>The tabs</h2>
<table><tr><th>Tab</th><th>Pages kept for Back</th><th>Pictures decoded</th><th>Their pixels</th></tr>
%s</table>
<p>A page left is kept whole, with its scripts' world, while it is one of the %d nearest behind or ahead; further, Back loads it again. A picture decoded is four bytes a dot: the page shown keeps its own, a tab %d MB of the pages before.</p></div>
<div class="card"><h2>On disk</h2>
<table>
<tr><th>Answers kept</th><td>%s</td></tr>
<tr><th>The profile</th><td>%s</td></tr>
</table></div>
</main></body></html>
|}
    now
    (if samples = [] then "-" else Printf.sprintf "from %d to %d MB" low high)
    (heap ())
    (String.concat "" (List.map row tabs))
    Bfcache.limit
    (mb Browser_picture.kept_bytes)
    (match cache with
    | Some (n, bytes, place) -> Printf.sprintf "%d, %d MB, in <code>%s</code> (<a href=\"about:cache\">about:cache</a>)" n (mb bytes) (esc place)
    | None -> "none (cache=off or profile=off)")
    (match profile with Some dir -> Printf.sprintf "<code>%s</code>: Preferences, Cookies, History" (esc dir) | None -> "none (profile=off)")
