(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_browser_profile.mli *)

let example : Browser_profile.t = { window = Some (1400, 800); scale = Some 1.5; zooms = [ ("news.ycombinator.com", 1.5); ("en.wikipedia.org", 0.9); ("", 1.25) ]; helpers = [] }

let text = {|{
  "window": {
    "width": 1400,
    "height": 800
  },
  "scale": 1.5,
  "zoom": {
    "news.ycombinator.com": 1.5,
    "en.wikipedia.org": 0.9,
    "": 1.25
  }
}
|}

let zooms = Alcotest.(result (list (pair string (float 0.0001))) string)
let window = Alcotest.(result (option (pair int int)) string)
let scale_of (s : string) = Result.map (fun (p : Browser_profile.t) -> p.scale) (Browser_profile.of_string s)
let window_of (s : string) = Result.map (fun (p : Browser_profile.t) -> p.window) (Browser_profile.of_string s)
let read (s : string) = Result.map (fun (p : Browser_profile.t) -> p.zooms) (Browser_profile.of_string s)

let tests (caps : < Cap.open_in ; Cap.open_out ; Cap.env ; .. >) =
  let loaded dir = Result.map (fun (p : Browser_profile.t) -> p.zooms) (Browser_profile.load caps ~dir) in
  Testo.categorize "Browser_profile"
    [
      Testo.create "the worked example: the file's text, and back" (fun () ->
          Alcotest.(check string) "written" text (Browser_profile.to_string example);
          Alcotest.(check zooms) "read" (Ok example.zooms) (read text);
          Alcotest.(check window) "its window" (Ok (Some (1400, 800))) (window_of text);
          Alcotest.(check (result (option (float 0.001)) string)) "its scale" (Ok (Some 1.5)) (scale_of text);
          Alcotest.(check string) "nothing chosen: neither written" "{\n  \"zoom\": {}\n}\n" (Browser_profile.to_string Browser_profile.empty));
      Testo.create "what is not understood is skipped; not JSON is an error" (fun () ->
          Alcotest.(check zooms) "y.org alone" (Ok [ ("y.org", 2.) ])
            (read {|{ "cookies": true, // a newer version's
                      "zoom": { "a.org": "big", "b.org": 0, "c.org": 9, "d.org": 1, "y.org": 2, }, }|});
          Alcotest.(check zooms) "no zoom" (Ok []) (read "{}");
          Alcotest.(check window) "no window" (Ok None) (window_of "{}");
          Alcotest.(check (result (option (float 0.001)) string)) "no scale: the desktop's" (Ok None) (scale_of "{}");
          Alcotest.(check (result (option (float 0.001)) string)) "a scale of nothing" (Ok None) (scale_of {|{ "scale": 0 }|});
          Alcotest.(check window) "a window of nothing" (Ok None) (window_of {|{ "window": { "width": 0, "height": 700 } }|});
          Alcotest.(check window) "half a window" (Ok None) (window_of {|{ "window": { "width": 700 } }|});
          Alcotest.(check zooms) "zoom not an object" (Ok []) (read {|{ "zoom": 2 }|});
          Alcotest.(check bool) "a brace lost" true (Result.is_error (read {|{ "zoom": { "y.org": 2 }|}));
          Alcotest.(check bool) "an empty file" true (Result.is_error (read "")));
      Testo.create "saved to a new directory, loaded again; a broken one left alone" (fun () ->
          let dir = Filename.concat (Filename.concat (Filename.get_temp_dir_name ()) (Printf.sprintf "mini-chrome-test-%d" (Unix.getpid ()))) "profile" in
          let file = Filename.concat dir "Preferences" in
          Alcotest.(check zooms) "no Preferences yet" (Ok []) (loaded dir);
          Alcotest.(check (result unit string)) "saved" (Ok ()) (Browser_profile.save caps ~dir example);
          Alcotest.(check zooms) "loaded" (Ok example.zooms) (loaded dir);
          Alcotest.(check (result unit string)) "saved over" (Ok ()) (Browser_profile.save caps ~dir Browser_profile.empty);
          Alcotest.(check zooms) "loaded: none" (Ok []) (loaded dir);
          Alcotest.(check bool) "no Preferences.tmp left" false (Sys.file_exists (file ^ ".tmp"));
          Out_channel.with_open_bin file (fun oc -> Out_channel.output_string oc "{ \"zoom\": {\n");
          Alcotest.(check (result (list (pair string (float 0.0001))) string))
            "broken: the file and the line" (Error (file ^ ": line 2: unexpected end of the text")) (loaded dir);
          Sys.remove file;
          Sys.rmdir dir;
          Sys.rmdir (Filename.dirname dir));
      Testo.create "a directory that cannot be made: an error, not an exception" (fun () ->
          Alcotest.(check bool) "Error" true (Result.is_error (Browser_profile.save caps ~dir:"/dev/null/profile" example)));
      Testo.create "the directory: mini-chrome, in the environment's configuration directory" (fun () ->
          match Browser_profile.default_dir caps with
          | Some dir -> Alcotest.(check string) "mini-chrome" "mini-chrome" (Filename.basename dir)
          | None -> Alcotest.(check bool) "no HOME" true (Sys.getenv_opt "HOME" = None));
    ]
