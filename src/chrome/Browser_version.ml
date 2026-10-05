(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Browser_version.mli *)

let workers_of ~(threads : bool) ~(workers : int) : string =
  if not threads then "no threads"
  else Printf.sprintf "%d %s" (Worker_spawn.workers workers) (if Worker_spawn.parallel then "domains" else "threads")

let label ~(threads : bool) ~(workers : int) : string = Printf.sprintf "OCaml %s, %s" Sys.ocaml_version (workers_of ~threads ~workers)

let page ~(threads : bool) ~(workers : int) ~(profile : string option) ~(cache : string option) : string =
  let esc = Browser_text.escape_html in
  let row (name, value) = Printf.sprintf "<tr><th>%s</th><td>%s</td></tr>\n" name (esc value) in
  Printf.sprintf
    {|<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><title>Version</title>
<link rel="stylesheet" href="chrome.css">
<style>table { border-collapse: collapse; font-size: 14px } th { text-align: left; color: var(--muted); vertical-align: top; white-space: nowrap } td, th { padding: 4px 16px 4px 0 }</style>
</head><body>
<header><div><h1>Version</h1><p>What this browser is, as it runs.</p></div>
<nav><a href="about:chrome">Home</a><a href="about:cache">Cache</a><a href="about:cookies">Cookies</a></nav></header>
<main><div class="card">
<h2>MiniChrome</h2>
<table>
%s</table>
<p>%s</p>
</div></main></body></html>
|}
    (String.concat ""
       (List.map row
          [ ("Compiler", "OCaml " ^ Sys.ocaml_version);
            ("Workers", workers_of ~threads ~workers ^ if Worker_spawn.parallel && threads then ", beside the window on other cores" else if threads then ", taking turns with the window on one core" else "");
            ("System", Printf.sprintf "%s, %d bits" Sys.os_type Sys.word_size);
            ("Program", Sys.executable_name);
            ("Command line", String.concat " " (List.tl (Array.to_list Sys.argv)));
            ("Profile", Option.value profile ~default:"none (profile=off)");
            ("Cache", Option.value cache ~default:"none (cache=off, or profile=off)") ]))
    (if Worker_spawn.parallel then "Built with OCaml 5, the pool that fetches, decrypts, decompresses and decodes pictures is made of domains: they run at the same time as the window."
     else "Built with OCaml 4.14, the pool's threads and the window's take turns on one core. The same source built with OCaml 5 makes them domains, which run beside the window: a heavy page comes in half the time.")
