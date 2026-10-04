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
      let t = Browser_script.create ~log:(fun l -> print_endline ("console: " ^ l)) ~base ~cookies (Html_tree.of_string html) in
      (* FILES=DIR: a request whose path is a file under DIR is answered
       * with it (a site's bundles saved beside its page: no network,
       * and nothing said to the site while its errors are looked for) *)
      let saved ?(post = "") (url : string) : string option =
        match Sys.getenv_opt "FILES" with
        | None -> None
        (* a POST: by the request and what it sent (DIR/_post/<md5 of
         * the address, a newline, the body>), as recorded there *)
        | Some dir when post <> "" ->
            let file = Filename.concat (Filename.concat dir "_post") (Digest.to_hex (Digest.string (url ^ "\n" ^ post))) in
            if Sys.file_exists file then Some (In_channel.with_open_bin file In_channel.input_all) else None
        | Some dir ->
            let path = match Str.bounded_split (Str.regexp "://[^/]*/") url 2 with [ _; p ] -> List.hd (String.split_on_char '?' p) | _ -> "" in
            let file = Filename.concat dir path in
            if path <> "" && Sys.file_exists file && not (Sys.is_directory file) then Some (In_channel.with_open_bin file In_channel.input_all) else None
      in
      let requests () =
        List.iter
          (fun (r : Script_types.request) ->
            match saved ?post:(Option.map snd r.post) r.url with
            | Some body ->
                Printf.printf "request: %s %s (saved, %d bytes)\n" r.meth r.url (String.length body);
                (* as a CDN answers: any origin may read it *)
                Browser_script.answer t r.rid (Ok { status = 200; headers = [ ("Access-Control-Allow-Origin", "*") ]; body; final = r.url })
            | None ->
                Printf.printf "request: %s %s%s\n" r.meth r.url (match r.post with Some (_, body) when Sys.getenv_opt "BODIES" <> None -> "\n  " ^ body | _ -> "");
                Browser_script.answer t r.rid (Error "no network here"))
          (Browser_script.take_requests t)
      in
      (* a <script src> is a saved file too *)
      Browser_script.run_scripts ~source:(fun u -> saved (Browser_url.resolve base u)) t;
      requests ();
      for _ = 1 to 50 do
        Browser_script.advance t 100.;
        requests ()
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
      Printf.printf "the page %s by its scripts\n" (if Browser_script.changed t then "was changed" else "was not changed")
  | [] -> prerr_endline "usage: Page_scripts.exe page.html [address]"
