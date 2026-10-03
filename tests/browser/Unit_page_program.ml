(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_page_program.mli *)
open Js_value

let page (html : string) : Browser_script.t =
  let t = Browser_script.create ~viewport:(1000., 500.) (Html_tree.of_string html) in
  Browser_script.run_scripts t;
  t

let value (t : Browser_script.t) (s : string) : string =
  match Browser_script.eval t s with Ok v -> Js_value.display v | Error e -> "error: " ^ e.message

let check what expected t s = Alcotest.(check string) what expected (value t s)

let svg (inside : string) : Dom.element =
  match Dom.find_all "svg" (Html_tree.of_string ("<svg viewBox=\"-100 -50 200 100\">" ^ inside ^ "</svg>")) with
  | [ e ] -> e
  | _ -> Alcotest.fail "no svg"

let tests =
  Testo.categorize "A page that is a program"
    [
      Testo.create "window.onload starts it, after the load listeners" (fun () ->
          let t = page "<script>var order = [];\nwindow.onload = function () { order.push('onload') };\nwindow.addEventListener('load', function () { order.push('listener') })</script>" in
          check "both, the listener first" "[\"listener\", \"onload\"]" t "order");
      Testo.create "an animation frame is given the time" (fun () ->
          let t = page "<script>var times = [];\nfunction frame(now) { times.push(typeof now + ' ' + (now > 0)); if (times.length < 2) requestAnimationFrame(frame) }\nrequestAnimationFrame(frame);\nvar late; setTimeout(function (x) { late = typeof x }, 5)</script>" in
          Browser_script.advance t 17.;
          Browser_script.advance t 17.;
          check "two frames, a number each" "[\"number true\", \"number true\"]" t "times";
          check "a timer is given nothing" "undefined" t "late");
      Testo.create "the window's keys and pointer" (fun () ->
          let t =
            page
              "<script>var seen = [];\nwindow.addEventListener('keydown', function (e) { seen.push(e.type + ' ' + JSON.stringify(e.key) + ' ' + e.shiftKey); if (e.key === 'Tab') e.preventDefault() }, true);\nwindow.addEventListener('mousedown', function (e) { seen.push('down ' + e.clientX + ',' + e.clientY + ' ' + e.buttons) }, true)</script>"
          in
          let key k = Browser_script.window_event t "keydown" [ ("key", String k); ("shiftKey", Bool false) ] in
          Alcotest.(check bool) "listened for" true (Browser_script.listens t "keydown");
          Alcotest.(check bool) "not that one" false (Browser_script.listens t "keyup");
          Alcotest.(check bool) "an arrow: not prevented" false (key "ArrowLeft");
          ignore (key "return");
          ignore (key "space");
          ignore (key "left shift");
          Alcotest.(check bool) "tab: the page's, prevented" true (key "tab");
          Alcotest.(check bool) "nobody listens: nothing" false (Browser_script.window_event t "keyup" [ ("key", String "a") ]);
          ignore (Browser_script.window_event t "mousedown" [ ("clientX", Number 30.); ("clientY", Number 40.); ("buttons", Number 1.) ]);
          check "the web's names for the keys, the pointer's place"
            "[\"keydown \\\"ArrowLeft\\\" false\", \"keydown \\\"Enter\\\" false\", \"keydown \\\" \\\" false\", \"keydown \\\"Shift\\\" false\", \"keydown \\\"Tab\\\" false\", \"down 30,40 1\"]" t "seen");
      Testo.create "the pointer's place in an svg's units" (fun () ->
          (* a window of 1000 by 500, a viewBox of 200 by 100 around 0, 0: 5 dots a unit *)
          let t =
            page
              "<script>var s = document.createElementNS('http://www.w3.org/2000/svg', 'svg');\ns.setAttribute('viewBox', '-100 -50 200 100');\nfunction at(x, y) { var p = s.createSVGPoint(); p.x = x; p.y = y; var q = p.matrixTransform(s.getScreenCTM().inverse()); return [q.x, q.y] }</script>"
          in
          check "the window's centre is the drawing's" "[0, 0]" t "at(500, 250)";
          check "its corner" "[-100, -50]" t "at(0, 0)";
          check "a point" "[40, -10]" t "at(700, 200)");
      Testo.create "a request for bytes fails; a canvas does not stop the script" (fun () ->
          let t =
            page
              "<script>var said = 'waiting';\nvar x = new XMLHttpRequest(); x.open('GET', 'big.bin'); x.responseType = 'arraybuffer';\nx.onload = function () { said = 'loaded' }; x.onerror = function () { said = 'failed' }; x.send();\nvar c = document.createElement('canvas'), ctx = c.getContext('2d'); ctx.putImageData(new ImageData(2, 2), 0, 0); var url = c.toDataURL('image/png')</script>"
          in
          Alcotest.(check int) "not sent" 0 (List.length (Browser_script.take_requests t));
          check "not yet" "waiting" t "said";
          Browser_script.advance t 5.;
          check "failed, a moment later" "failed" t "said";
          check "an empty picture" "data:," t "url");
      Testo.create "Svg_shapes: the Playground's shapes read back" (fun () ->
          let shapes inside = Svg_shapes.shapes ~picture_of:(fun _ -> None) (svg inside) ~width:400. ~height:200. in
          let open Playground in
          let fitted inside = Some [ group [ group inside |> move 0. 0. ] |> scale 2. ] in
          Alcotest.(check bool) "a rectangle from its corner is one about its centre, y up" true
            (shapes "<rect width=\"20\" height=\"10\" fill=\"rgb(12,10,28)\" transform=\"translate(30, -5) translate(-10, -5)\"></rect>"
            = fitted [ rectangle (rgb 12 10 28) 20. 10. |> move 10. (-5.) |> move (-10.) 5. |> move 30. 5. ]);
          Alcotest.(check bool) "words, scaled" true
            (shapes "<text text-anchor=\"middle\" dominant-baseline=\"central\" font-size=\"10\" fill=\"#ff0000\" transform=\"translate(5, 5) scale(4)\">TINY</text>"
            = fitted [ words (rgb 255 0 0) "TINY" |> scale 1. |> move 0. (-0.) |> scale 4. |> move 5. (-5.) ]);
          Alcotest.(check bool) "a picture not come: nothing" true (shapes "<image href=\"p.png\" width=\"8\" height=\"8\"></image>" = fitted []);
          Alcotest.(check bool) "a path is not a shape: the rasterizer's" true (shapes "<path d=\"M0 0L5 5\"></path>" = None);
          Alcotest.(check bool) "nor a stroke" true (shapes "<circle r=\"5\" stroke=\"red\"></circle>" = None));
    ]
