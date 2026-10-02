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
      let requests () =
        List.iter
          (fun (r : Script_types.request) ->
            Printf.printf "request: %s %s\n" r.meth r.url;
            Browser_script.answer t r.rid (Error "no network here"))
          (Browser_script.take_requests t)
      in
      Browser_script.run_scripts t;
      requests ();
      for _ = 1 to 50 do
        Browser_script.advance t 100.;
        requests ()
      done;
      (* a third argument: an expression to ask the page afterwards *)
      (match rest with
      | _ :: ask :: _ -> Printf.printf "%s = %s\n" ask (match Browser_script.eval t ask with Ok v -> Js_value.display v | Error e -> "error: " ^ e.message)
      | _ -> ());
      Printf.printf "the page %s by its scripts\n" (if Browser_script.changed t then "was changed" else "was not changed")
  | [] -> prerr_endline "usage: Page_scripts.exe page.html [address]"
