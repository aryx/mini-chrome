(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_browser_cache.mli *)

let copy (url : string) (body : string) : Http_cache.entry =
  { url; stored = 1000.; response = { version = "HTTP/1.1"; status = 200; reason = "OK"; headers = [ ("Cache-Control", "max-age=600") ]; body } }

let tests (caps : < Cap.open_in ; Cap.open_out ; .. >) =
  Testo.categorize "Browser_cache"
    [
      Testo.create "kept, found, removed when over the size; about:cache" (fun () ->
          let dir = Filename.concat (Filename.get_temp_dir_name ()) (Printf.sprintf "mini-chrome-cache-%d" (Unix.getpid ())) in
          Fun.protect
            ~finally:(fun () -> (try Array.iter (fun f -> Sys.remove (Filename.concat dir f)) (Sys.readdir dir) with Sys_error _ -> ()); try Sys.rmdir dir with Sys_error _ -> ())
            (fun () ->
              let cache = Browser_cache.store caps ~limit:2500 ~dir () in
              Alcotest.(check bool) "nothing yet, and no directory" true (cache.find "https://x.org/a.css" = None && not (Sys.file_exists dir));
              cache.keep (copy "https://x.org/a.css" "a { }\n\nb { }");
              (match cache.find "https://x.org/a.css" with
              | Some e -> Alcotest.(check string) "the body, whole" "a { }\n\nb { }" e.response.body
              | None -> Alcotest.fail "not found");
              Alcotest.(check bool) "another address: none" true (cache.find "https://x.org/b.css" = None);
              Alcotest.(check (list (pair string bool))) "what is kept, and whether fresh" [ ("https://x.org/a.css", true) ]
                (List.map (fun (url, _, _, fresh) -> (url, fresh)) (cache.entries ~now:1100.));
              let page = Browser_cache.page ~now:5000. (Some cache) in
              let has s = try ignore (Str.search_forward (Str.regexp_string s) page 0); true with Not_found -> false in
              Alcotest.(check bool) "about:cache: the address, stale by then, the directory" true (has "https://x.org/a.css" && has "to ask about" && has dir);
              (* a hundred more, a kilobyte each: over 2500 bytes, all but the last few go *)
              for i = 1 to 100 do cache.keep (copy (Printf.sprintf "https://x.org/%d.js" i) (String.make 1000 'x')) done;
              let left = Array.length (Sys.readdir dir) in
              Alcotest.(check bool) "held under its size" true (left < 100)));
      Testo.create "about:version, and the strip's label: the compiler, the pool" (fun () ->
          let label = Browser_version.label ~threads:true ~workers:8 in
          let has text s = try ignore (Str.search_forward (Str.regexp_string s) text 0); true with Not_found -> false in
          Alcotest.(check bool) "the compiler's version; domains with OCaml 5, threads before" true
            (has label ("OCaml " ^ Sys.ocaml_version) && has label (if Worker_spawn.parallel then "domains" else "8 threads"));
          Alcotest.(check string) "threads=off" ("OCaml " ^ Sys.ocaml_version ^ ", no threads") (Browser_version.label ~threads:false ~workers:8);
          let page = Browser_version.page ~threads:true ~workers:8 ~profile:(Some "/home/x/.config/mini-chrome") ~cache:None in
          Alcotest.(check bool) "the page: the profile's place, no cache" true (has page "/home/x/.config/mini-chrome" && has page "none (cache=off"));
    ]
