(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_places.mli *)

let day = 86400.

let tests =
  Testo.categorize "Places"
    [
      Testo.create "the worked example: seen, suggested, completed" (fun () ->
          let now = 2000. *. day in
          let p = Places.create () in
          List.iter (fun _ -> Places.visit p ~now ~url:"https://dynamicland.org/" ~title:"Dynamicland front shelf") [ 1; 2; 3 ];
          List.iter (fun _ -> Places.visit p ~now:(now -. day) ~url:"https://news.ycombinator.com/" ~title:"Hacker News") (List.init 9 Fun.id);
          Places.visit p ~now ~url:"about:chrome" ~title:"not kept";
          let urls typed = List.map (fun (e : Places.entry) -> e.url) (Places.matching p ~now typed) in
          Alcotest.(check int) "two pages, twelve visits" 12 (List.fold_left (fun n (e : Places.entry) -> n + e.visits) 0 (Places.entries p));
          Alcotest.(check (list string)) "dyna" [ "https://dynamicland.org/" ] (urls "dyna");
          Alcotest.(check (list string)) "land: anywhere in the address" [ "https://dynamicland.org/" ] (urls "land");
          Alcotest.(check (list string)) "each word, in the title too, whatever the case" [ "https://news.ycombinator.com/" ] (urls "NEWS hack");
          Alcotest.(check (list string)) "nothing typed" [] (urls " ");
          Alcotest.(check (option string)) "completed: the site" (Some "dynamicland.org") (Places.completion p ~now "dyna");
          Alcotest.(check (option string)) "not from the middle" None (Places.completion p ~now "land");
          Alcotest.(check (option string)) "the page meant by it" (Some "https://dynamicland.org/") (Places.address p "dynamicland.org"));
      Testo.create "the likeliest first: how often, how lately; an address past its site" (fun () ->
          let now = 2000. *. day in
          let p =
            Places.create
              ~entries:
                [ { url = "https://www.example.org/old"; title = "Old"; visits = 5; last = now -. (200. *. day) };
                  { url = "http://example.org/new"; title = "New"; visits = 1; last = now } ]
              ()
          in
          Alcotest.(check (list string)) "one visit today (100) before five long ago (50)" [ "New"; "Old" ] (List.map (fun (e : Places.entry) -> e.title) (Places.matching p ~now "example"));
          Alcotest.(check string) "www. and the scheme are not typed" "example.org/old" (Places.bare "https://www.example.org/old");
          Alcotest.(check (option string)) "past the site: the whole address" (Some "example.org/old") (Places.completion p ~now "example.org/o");
          Alcotest.(check (option string)) "an address of http stays one" (Some "http://example.org/new") (Places.address p "example.org/new"));
      Testo.create "the History file: written, read back; what is not a list is an error" (fun () ->
          let p = Places.create ~entries:[ { url = "https://a.test/"; title = "A \"quoted\" title"; visits = 2; last = 12345. } ] () in
          Alcotest.(check bool) "the same entries" true (Places.of_string (Places.to_string p) = Ok (Places.entries p));
          Alcotest.(check bool) "an error" true (Result.is_error (Places.of_string "{}")));
    ]
