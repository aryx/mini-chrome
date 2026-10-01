(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_browser_zoom.mli *)

let pressed (name : string) (z : float) : float = Browser_zoom.apply (Option.get (Browser_zoom.key name)) z
let zoom = Alcotest.float 0.0001

let tests =
  Testo.categorize "Browser_zoom"
    [
      Testo.create "the worked example: the steps, their ends, Ctrl 0" (fun () ->
          Alcotest.(check zoom) "Ctrl +" 1.1 (pressed "=" 1.);
          Alcotest.(check zoom) "again" 1.25 (pressed "+" 1.1);
          Alcotest.(check zoom) "Ctrl -" 1.1 (pressed "-" 1.25);
          Alcotest.(check zoom) "the last level" 5. (pressed "=" 5.);
          Alcotest.(check zoom) "the first" 0.25 (pressed "-" 0.25);
          Alcotest.(check zoom) "Ctrl 0" 1. (pressed "0" 2.5));
      Testo.create "a site's zoom is its own; at 100% it is forgotten" (fun () ->
          let zooms = Browser_zoom.with_host Browser_zoom.empty "news.ycombinator.com" 1.5 in
          Alcotest.(check zoom) "the site's" 1.5 (Browser_zoom.of_host zooms "news.ycombinator.com");
          Alcotest.(check zoom) "another's" 1. (Browser_zoom.of_host zooms "en.wikipedia.org");
          let zooms = Browser_zoom.with_host zooms "news.ycombinator.com" 1.25 in
          Alcotest.(check int) "set again: one entry" 1 (List.length zooms);
          Alcotest.(check int) "back to 100%: none" 0 (List.length (Browser_zoom.with_host zooms "news.ycombinator.com" 1.)));
      Testo.create "the keys' names, the label" (fun () ->
          Alcotest.(check zoom) "SDL's keypad" 1.1 (pressed "Keypad +" 1.);
          Alcotest.(check bool) "a letter: not a zoom key" true (Browser_zoom.key "a" = None);
          Alcotest.(check string) "150%" "150%" (Browser_zoom.label 1.5);
          Alcotest.(check string) "67%" "67%" (Browser_zoom.label 0.67);
          Alcotest.(check string) "nothing at 100%" "" (Browser_zoom.label 1.));
    ]
