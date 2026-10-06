(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Page_scripts.mli *)
let () =
  match List.tl (Array.to_list Sys.argv) with
  | file :: rest ->
      let base = match rest with b :: _ -> b | [] -> "http://page.test/" in
      (* WALK=1: the evaluator, whose errors say more (Js_compile's are shorter) *)
      if Sys.getenv_opt "WALK" <> None then Mini_opti.compiled := false;
      (* SIMPLE=1: the simple scopes too (opti=off): a wrong answer that
       * goes away so is the fast paths' *)
      if Sys.getenv_opt "SIMPLE" <> None then (Mini_opti.enabled := false; Mini_opti.compiled := false);
      let html = In_channel.with_open_bin file In_channel.input_all in
      (* its cookies kept here, each one set said *)
      let jar = ref [] in
      let cookies =
        ( (fun () -> String.concat "; " (List.rev !jar)),
          fun c ->
            print_endline ("cookie set: " ^ c);
            jar := List.hd (String.split_on_char ';' c) :: !jar )
      in
      (* VIEW=WxH: the window's size, as the browser's tab gives it;
       * NOW=1: the clock's real time, not the tests' fixed one *)
      let viewport = Option.bind (Sys.getenv_opt "VIEW") (fun v -> try Some (Scanf.sscanf v "%fx%f" (fun w h -> (w, h))) with _ -> None) in
      let epoch = if Sys.getenv_opt "NOW" <> None then Some (Unix.gettimeofday () *. 1000.) else None in
      let seed = Option.map int_of_string (Sys.getenv_opt "SEED") in
      let t = Browser_script.create ?seed ?epoch ?viewport ~log:(fun l -> print_endline ("console: " ^ l)) ~base ~cookies (Html_tree.of_string ~comments:true html) in
      (* FILES=DIR: a request whose path is a file under DIR is answered
       * with it (a site's bundles saved beside its page: no network,
       * and nothing said to the site while its errors are looked for) *)
      (* DIR/_seq/<md5 of the address less its query>-<n>: the nth
       * answer to that address, as the browser wrote them in a live run
       * (MINI_DUMP_ANSWERS) -- for the requests whose parameters are
       * not the same twice (a request's number, a time) *)
      let asked : (string, int) Hashtbl.t = Hashtbl.create 16 in
      let in_order (dir : string) (url : string) : string option =
        let key = Digest.to_hex (Digest.string (List.hd (String.split_on_char '?' url))) in
        let n = 1 + Option.value (Hashtbl.find_opt asked key) ~default:0 in
        let file = Filename.concat (Filename.concat dir "_seq") (Printf.sprintf "%s-%d" key n) in
        if Sys.file_exists file then (
          Hashtbl.replace asked key n;
          Some (In_channel.with_open_bin file In_channel.input_all))
        else None
      in
      let found = ref None in
      let saved ?(post = "") (url : string) : string option =
        match Sys.getenv_opt "FILES" with
        | None -> None
        | Some dir when (match in_order dir url with Some body -> (found := Some body; true) | None -> false) -> !found
        (* a POST: by the request and what it sent (DIR/_post/<md5 of
         * the address, a newline, the body>), as recorded there *)
        | Some dir when post <> "" ->
            let file = Filename.concat (Filename.concat dir "_post") (Digest.to_hex (Digest.string (url ^ "\n" ^ post))) in
            if Sys.file_exists file then Some (In_channel.with_open_bin file In_channel.input_all) else None
        | Some dir ->
            let path = match Str.bounded_split (Str.regexp "://[^/]*/") url 2 with [ _; p ] -> List.hd (String.split_on_char '?' p) | _ -> "" in
            let file = Filename.concat dir path in
            (* an address too long to be a file's name (Gmail's modules:
             * 1800 characters): DIR/_long/<md5 of the address less its query> *)
            let long = Filename.concat (Filename.concat dir "_long") (Digest.to_hex (Digest.string (List.hd (String.split_on_char '?' url)))) in
            let read f = Some (In_channel.with_open_bin f In_channel.input_all) in
            if Sys.file_exists long then read long
            else if path <> "" && (try Sys.file_exists file && not (Sys.is_directory file) with Sys_error _ -> false) then read file
            else None
      in
      let requests () =
        List.iter
          (fun (r : Script_types.request) ->
            match saved ?post:(Option.map snd r.post) r.url with
            | Some body ->
                Printf.printf "request: %s %s (saved, %d bytes)\n" r.meth r.url (String.length body);
                (* as a CDN answers: any origin may read it *)
                Browser_script.answer t r.rid (Ok { status = 200; headers = [ ("Access-Control-Allow-Origin", "*") ]; body; final = r.url })
            (* OK=regexp: a request whose address has it is answered 200
             * and empty (a site's own logs and error reports, which fail
             * here and are then reported in turn, without end) *)
            | None when (match Sys.getenv_opt "OK" with Some re -> (try ignore (Str.search_forward (Str.regexp re) r.url 0); true with Not_found -> false) | None -> false) ->
                Printf.printf "request: %s %s (said OK)\n" r.meth (List.hd (String.split_on_char '?' r.url));
                Browser_script.answer t r.rid (Ok { status = 200; headers = [ ("Access-Control-Allow-Origin", "*") ]; body = ""; final = r.url })
            | None ->
                Printf.printf "request: %s %s%s\n" r.meth r.url (match r.post with Some (_, body) when Sys.getenv_opt "BODIES" <> None -> "\n  " ^ body | _ -> "");
                Browser_script.answer t r.rid (Error "no network here"))
          (Browser_script.take_requests t)
      in
      (* a <script src> is a saved file too *)
      (* TIMES=1: what each task took, when it is long (where a page's
       * start goes: its scripts' first run, then each turn of its timers
       * and each answer) *)
      let timed (what : string) (f : unit -> unit) =
        let t0 = Unix.gettimeofday () in
        f ();
        let dt = Unix.gettimeofday () -. t0 in
        if Sys.getenv_opt "TIMES" <> None && dt > 0.2 then Printf.printf "took %.1f s: %s\n" dt what
      in
      timed "the scripts' first run" (fun () -> Browser_script.run_scripts ~source:(fun u -> saved (Browser_url.resolve base u)) t);
      timed "the first answers" requests;
      (* five seconds of the page's time, a tenth at a turn (TURNS=n: n turns) *)
      for i = 1 to (match Option.bind (Sys.getenv_opt "TURNS") int_of_string_opt with Some n -> n | None -> 50) do
        timed (Printf.sprintf "timers, turn %d" i) (fun () -> Browser_script.advance t 100.);
        timed (Printf.sprintf "answers, turn %d" i) requests
      done;
      (* a third argument: an expression to ask the page afterwards *)
      let say ask = Printf.printf "%s = %s\n" ask (match Browser_script.eval t ask with Ok v -> Js_value.display v | Error e -> "error: " ^ e.message) in
      (* a fourth: another, asked after three more seconds of the page
       * (what the first one started, a click, has then happened) *)
      (match rest with
      | _ :: first :: second :: _ ->
          say first;
          for _ = 1 to 30 do
            Browser_script.advance t 100.;
            requests ()
          done;
          say second
      | _ :: ask :: _ -> Printf.printf "%s = %s\n" ask (match Browser_script.eval t ask with Ok v -> Js_value.display v | Error e -> "error: " ^ e.message)
      | _ -> ());
      (* DUMP=file: the page as its scripts left it, written (to open
       * with scripts=off and see what they built) *)
      (match Sys.getenv_opt "DUMP" with
      | Some file -> (
          match Browser_script.eval t "document.documentElement.outerHTML" with
          | Ok (String html) -> Out_channel.with_open_bin file (fun oc -> Out_channel.output_string oc html)
          | Ok v -> Out_channel.with_open_bin file (fun oc -> Out_channel.output_string oc (Js_value.to_string v))
          | Error _ -> ())
      | None -> ());
      Printf.printf "the page %s by its scripts\n" (if Browser_script.changed t then "was changed" else "was not changed")
  | [] -> prerr_endline "usage: Page_scripts.exe page.html [address]"
