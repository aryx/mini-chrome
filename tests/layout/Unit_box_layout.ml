(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_box_layout.mli *)

(* the tests' font: a character as wide as its look's size *)
let metrics (l : Looks.t) (s : string) : float = l.size *. float_of_int (String.length s)

(* the page laid out in a window [width] wide, the root's font 10 (a
 * line 12 high), [css] the page's sheet *)
let page ?(width = 200.) ?(css = "") (html : string) : Box_types.box =
  let root = Html_tree.of_string html in
  let media : Cascade.media = { width; height = 600. } in
  let sheet : Cascade.sheet = { origin = Author; rules = Css_syntax.parse_stylesheet ("html { font-size: 10px } " ^ css) } in
  Box_layout.layout metrics ~viewport:(width, 600.) (Computed.styles media [ sheet ] root) root

(* the box of the element of id [id] *)
let rec find (id : string) (b : Box_types.box) : Box_types.box option =
  match b.element with
  | Some e when Dom.attribute "id" e = Some id -> Some b
  | _ -> List.find_map (find id) b.children

let box id p = match find id p with Some b -> b | None -> Alcotest.fail ("no box " ^ id)
let near = Alcotest.float 1e-6

(* x, y, width, height *)
let geometry (b : Box_types.box) = [ b.x; b.y; b.width; b.height ]

(* the words, left to right *)
let words (b : Box_types.box) : (string * float) list =
  List.filter_map (fun (f : Html_layout.fragment) -> if f.text = "" then None else Some (f.text, f.x)) (Box_tree.fragments b)
  |> List.stable_sort (fun (_, a) (_, b) -> compare a b)

let word = Alcotest.(pair string near)

let tests =
  Testo.categorize "Box_layout"
    [
      Testo.create "the worked example: auto margins centre" (fun () ->
          let p = page {|<body style="margin: 8px"><div id=d style="width: 100px; margin: 0 auto; padding: 5px; border: 2px solid">ab</div>|} in
          Alcotest.(check (list near)) "the div: x, y, width, height" [ 43.; 8.; 114.; 26. ] (geometry (box "d" p));
          Alcotest.(check (list word)) "its word, inside padding and border" [ ("ab", 50.) ] (words p));
      Testo.create "what GitHub's page asked: floats, percents and pictures in flex items" (fun () ->
          (* a font of 10: a letter is 10 wide *)
          let floats = {|<body style="margin:0"><div id=row style="display:flex"><div id=grow style="flex:1 1 auto">a</div><div id=fit style="flex-shrink:0;max-width:70%"><span id=f1 style="float:left;margin-right:3px">aaa</span><span id=f2 style="float:left;margin-right:3px">bb</span><span id=f3 style="float:left">c</span></div></div>|} in
          let p = page ~width:300. floats in
          Alcotest.(check near) "as wide as its three floats and their margins; max-width: 70% is of the row, not of itself" 66. (box "fit" p).width;
          Alcotest.(check (list near)) "the three on one line" [ 0.; 0.; 0. ] (List.map (fun id -> (box id p).y) [ "f1"; "f2"; "f3" ]);
          (* a width in percents inside what is being measured is the content's *)
          let p =
            page ~width:300.
              {|<body style="margin:0"><div style="display:flex"><div id=item><div id=btn style="display:flex;width:100%"><span id=label style="flex:1 0 auto;width:100%">main</span></div></div><div id=next>x</div></div>|}
          in
          Alcotest.(check near) "a button of width 100% in a flex item: its label's width" 40. (box "item" p).width;
          Alcotest.(check near) "and what follows is beside it" 40. (box "next" p).x;
          (* a control measured is its own width, not the room's *)
          let p = page ~width:300. {|<body style="margin:0"><div style="display:flex"><div id=item><span style="display:flex"><input id=field style="width:100%"></span></div><div id=next>x</div></div>|} in
          Alcotest.(check bool) "a field of width 100% in a flex item: a field's width, not the row's" true ((box "item" p).width < 250. && (box "next" p).x < 250.);
          (* an svg that is a flex item is a picture *)
          let p = page ~width:300. {|<body style="margin:0"><a id=a style="display:inline-flex"><svg id=icon width="16" height="16" viewBox="0 0 16 16"></svg><span>go</span></a>|} in
          Alcotest.(check (list near)) "the icon's box: 16 by 16" [ 16.; 16. ] [ (box "icon" p).width; (box "icon" p).height ];
          (* the least a flex item shrinks to is not more than its max-width *)
          let p =
            page ~width:100.
              {|<body style="margin:0"><div style="display:flex"><div id=readme style="flex-grow:1;max-width:100%"><div style="overflow:auto"><pre>a-line-of-code-far-too-long-for-the-page</pre></div></div></div>|}
          in
          Alcotest.(check near) "a README with a long line of code: as wide as the page, no more" 100. (box "readme" p).width);
      Testo.create "notes_css_engine.md's centring" (fun () ->
          let p = page ~width:976. {|<body style="margin: 0"><div id=d style="width: 400px; padding: 10px; border: 1px solid; margin: 0 auto">x</div>|} in
          let d = box "d" p in
          Alcotest.(check (list near)) "277 each side: x, width" [ 277.; 422. ] [ d.x; d.width ]);
      Testo.create "box-sizing: border-box" (fun () ->
          let p = page {|<div id=d style="box-sizing: border-box; width: 100px; padding: 10px">x</div>|} in
          Alcotest.check near "the border box is the width" 100. (box "d" p).width);
      Testo.create "margins collapse: through the body, between siblings" (fun () ->
          let p = page {|<body style="margin: 8px"><p id=a style="margin: 20px 0">a</p><p id=b style="margin: 10px 0">b</p>|} in
          Alcotest.check near "the body's 8 and the p's 20: 20" 20. (box "a" p).y;
          Alcotest.check near "the body starts there too" 20. (Option.get (find "a" p)).y;
          Alcotest.check near "20 between the two, not 30" (20. +. 12. +. 20.) (box "b" p).y);
      Testo.create "an empty block's margins are one" (fun () ->
          let p = page {|<body style="margin: 0"><p id=a style="margin: 0">a</p><div style="margin: 15px 0"></div><p id=b style="margin: 5px 0">b</p>|} in
          Alcotest.check near "15, once" (12. +. 15.) (box "b" p).y);
      Testo.create "a float: the lines beside it shortened" (fun () ->
          let p =
            page {|<body style="margin: 8px"><div id=f style="float: left; width: 40px; height: 30px"></div>aa bb cc|}
          in
          Alcotest.(check (list near)) "the float: x, y, width" [ 8.; 8.; 40. ] (let f = box "f" p in [ f.x; f.y; f.width ]);
          Alcotest.(check (list word)) "the words from its right" [ ("aa", 48.); ("bb", 78.); ("cc", 108.) ] (words p));
      Testo.create "clear: below the float" (fun () ->
          let p = page {|<body style="margin: 0"><div style="float: left; width: 40px; height: 30px"></div><div id=c style="clear: left">x</div>|} in
          Alcotest.check near "at the float's bottom" 30. (box "c" p).y);
      Testo.create "a field in an inline-block is under the pointer (Google's search box)" (fun () ->
          let p = page ~width:400. {|<body style="margin: 0"><form>q: <div style="display: inline-block"><input name=q size=10></div> <b>go</b></form>|} in
          let layout = Box_tree.as_html_layout p in
          let field = List.find (fun (f : Html_layout.fragment) -> f.control <> None) (Box_tree.fragments p) in
          let at x = Option.map (fun (f : Html_layout.fragment) -> (f.text, f.control <> None)) (Hit.fragment_at layout ~x ~y:(field.baseline -. 2.)) in
          Alcotest.(check (option (pair string bool))) "on the field, inside its inline-block" (Some ("", true)) (at (field.x +. 5.));
          Alcotest.(check (option (pair string bool))) "on the word before" (Some ("q:", false)) (at 5.);
          Alcotest.(check (option (pair string bool))) "on the word after" (Some ("go", false)) (at ((List.find (fun (f : Html_layout.fragment) -> f.text = "go") (Box_tree.fragments p)).x +. 2.)));
      Testo.create "a field that is a block, or an item of a flex container (Google's, on a phone)" (fun () ->
          let p =
            page ~width:400.
              {|<body style="margin: 0"><form><div style="display: flex"><div id=box style="flex: 1; display: flex"><input id=q name=q style="display: block; width: 100%; border: none; padding: 0"></div><b id=go style="width: 40px">go</b></div></form>|}
          in
          let layout = Box_tree.as_html_layout p in
          let fields = List.filter (fun (f : Html_layout.fragment) -> f.control <> None) (Box_tree.fragments p) in
          Alcotest.(check int) "one control on the page" 1 (List.length fields);
          let field = List.hd fields in
          Alcotest.check near "as wide as its block: the room the button leaves" (box "box" p).width field.width;
          Alcotest.(check bool) "and under the pointer, at its middle" true
            (match Hit.fragment_at layout ~x:(field.x +. (field.width /. 2.)) ~y:(field.baseline -. 2.) with Some f -> f.control <> None | None -> false));
      Testo.create "an inline-block: shrink-to-fit, in the line" (fun () ->
          let p = page {|<body style="margin: 0">a <span id=s style="display: inline-block; padding: 2px">bcd</span> e|} in
          let s = box "s" p in
          Alcotest.(check (list near)) "its width: its word and padding; x after 'a '" [ 34.; 20. ] [ s.width; s.x ];
          Alcotest.(check (list word)) "e after it" [ ("a", 0.); ("bcd", 22.); ("e", 64.) ] (words p));
      Testo.create "position: relative and absolute" (fun () ->
          let p =
            page
              {|<body style="margin: 0"><div id=r style="position: relative; top: 5px; margin-left: 10px"><div id=a style="position: absolute; left: 3px; top: 7px; width: 20px">x</div>y</div>|}
          in
          Alcotest.check near "relative: moved down 5" 5. (box "r" p).y;
          let a = box "a" p in
          Alcotest.(check (list near)) "absolute: in its positioned parent, moved with it" [ 13.; 12.; 20. ] [ a.x; a.y; a.width ]);
      (* an application's frame: everything absolute, in heights known
       * before the content is (the window's 600, here) *)
      Testo.create "absolute boxes in a height that is known" (fun () ->
          let p =
            page
              ~css:"html, body { height: 100%; margin: 0 } body { display: flex; flex-direction: column } #app { flex: 1 1 auto; position: relative }"
              {|<div id=app><div id=side style="position: absolute; top: 0; left: 0; width: 50px; height: 100%">s</div><div id=main style="position: absolute; top: 10px; bottom: 20px; left: 50px; right: 0"><div id=corner style="position: absolute; bottom: 5px; right: 5px; width: 10px; height: 10px"></div></div></div>|}
          in
          let side = box "side" p and main = box "main" p and corner = box "corner" p in
          Alcotest.(check (list near)) "height: 100% of the column's item, itself the window's" [ 600.; 600. ] [ (box "app" p).height; side.height ];
          Alcotest.(check (list near)) "top and bottom: the box fills between them" [ 50.; 10.; 150.; 570. ] [ main.x; main.y; main.width; main.height ];
          Alcotest.(check (list near)) "bottom and right, in a box itself absolute: moved with it" [ 185.; 565. ] [ corner.x; corner.y ]);
      Testo.create "a click finds the box drawn on top" (fun () ->
          (* the frame fills the window, its side bar is drawn over it:
           * the link there is what is under the pointer *)
          let p =
            page ~css:"html, body { height: 100%; margin: 0 } #app { position: relative; height: 100% }"
              {|<div id=app><div style="position: absolute; top: 0; left: 0; width: 80px; height: 100%"><a id=l href=x>side</a></div></div>|}
          in
          let h = Box_tree.as_html_layout p in
          Alcotest.(check (option string)) "the link" (Some "a") (Option.map (fun (e : Dom.element) -> e.name) (Hit.element_at h ~x:10. ~y:5.));
          Alcotest.(check (option string)) "its address" (Some "x") (Hit.link_at h ~x:10. ~y:5.);
          Alcotest.(check (option string)) "beside the side bar: the frame" (Some "app")
            (Option.bind (Hit.element_at h ~x:150. ~y:300.) (Dom.attribute "id")));
      Testo.create "white-space: pre-wrap keeps the lines and the spaces, and wraps" (fun () ->
          (* letters 10 wide, a box of 100: "aaa bbb ccc" is 110 *)
          let p = page {|<body style="margin: 0"><pre id=p style="margin: 0; width: 100px; white-space: pre-wrap">aaa bbb ccc
  x  y</pre>|} in
          Alcotest.(check (list (pair string (float 0.01)))) "cut at a space; the next line's spaces kept"
            [ ("  x", 0.); (" y", 40.); ("aaa", 0.); ("bbb", 40.); ("ccc", 0.) ] (List.sort compare (words p));
          let q = page {|<body style="margin: 0"><pre style="margin: 0; width: 100px">aaa bbb ccc</pre>|} in
          Alcotest.(check int) "pre alone: one line, past the edge" 1 (List.length (words q)));
      Testo.create "::before and ::after: boxes of their own, with their content" (fun () ->
          let root = Html_tree.of_string {|<body style="margin: 0"><p id=p>bc</p><span id=b class=badge><span>x</span></span>|} in
          let media : Cascade.media = { width = 200.; height = 600. } in
          let css = {|html { font-size: 10px } p { margin: 0 } p::before { content: "a" } p::after { content: attr(id) "!" }
                     .badge { display: flex } .badge::before { content: ""; width: 7px; height: 5px }|} in
          let sheet : Cascade.sheet = { origin = Author; rules = Css_syntax.parse_stylesheet css } in
          let style, kids = Computed.styles_all media [ sheet ] root in
          let p = Box_layout.layout metrics ~kids ~viewport:(200., 600.) style root in
          Alcotest.(check (list string)) "the words, in order" [ "a"; "bc"; "p!" ] (List.map fst (words (box "p" p)));
          let square = List.hd (box "b" p).children in
          Alcotest.(check (list near)) "an empty content is still a box: a flex item of its size" [ 7.; 5. ] [ square.width; square.height ]);
      Testo.create "bottom, in a block whose height its content gives" (fun () ->
          let p =
            page ~css:"#card { position: relative; width: 100px } #tag { position: absolute; left: 0; bottom: 2px; width: 10px; height: 4px }"
              {|<body style="margin: 0"><div id=card>one<br>two<br>three<span id=tag></span></div>|}
          in
          let card = box "card" p and tag = box "tag" p in
          Alcotest.check near "the card: three lines" 36. card.height;
          Alcotest.check near "the tag: 2 above its bottom" (36. -. 2. -. 4.) tag.y);
      Testo.create "a table row's own borders" (fun () ->
          let p =
            page ~css:"table { border-collapse: collapse; border-spacing: 0 } td { padding: 0 } tr { border-bottom: 3px solid rgb(50%, 50%, 50%) }"
              {|<body style="margin: 0"><table><tr id=r><td>a</td></tr><tr><td>b</td></tr></table>|}
          in
          let r = box "r" p in
          let _, _, wb, _ = r.style.border_width and _, _, cb, _ = r.style.border_color in
          Alcotest.(check (pair near int)) "the row has a box, its border's width and colour read (rgb(...) is a colour, not a width)" (3., 127) (wb, cb.r);
          Alcotest.(check bool) "the row's box is as high as its cell" true (r.height >= 12.));
      Testo.create "transform: translate moves a box" (fun () ->
          let p =
            page
              {|<body style="margin: 0"><div style="position: relative; height: 100px"><div id=a style="position: absolute; top: 0; left: 0; width: 20px; height: 10px; transform: translate3d(0,90px,0)"></div></div><div id=b style="width: 40px; height: 10px; transform: translateX(50%) translateY(3px)"></div>|}
          in
          let a = box "a" p and b = box "b" p in
          Alcotest.(check (list near)) "a list's row, moved down to its place" [ 0.; 90. ] [ a.x; a.y ];
          Alcotest.(check (list near)) "percents of the box's own size" [ 20.; 103. ] [ b.x; b.y ]);
      Testo.create "a list's markers" (fun () ->
          let p = page "<ol><li id=a>x<li id=b>y</ol><ul><li id=c>z</ul>" in
          Alcotest.(check (list bool))
            "2, then a bullet" [ true; true ]
            [ (box "b" p).marker = Some (Number 2); (box "c" p).marker = Some Bullet ]);
      Testo.create "a table: Table_layout's columns" (fun () ->
          let p = page {|<body style="margin: 8px"><table id=t><tr><td id=a>a<td id=b>bb</table>|} in
          let t = box "t" p in
          (* each cell its word and its 1 of padding each side: 12 and
           * 22; 2 of spacing around them *)
          Alcotest.(check (list near)) "the table: x, width" [ 8.; 2. +. 12. +. 2. +. 22. +. 2. ] [ t.x; t.width ];
          Alcotest.(check (list near)) "the cells' x" [ 10.; 24. ] [ (box "a" p).x; (box "b" p).x ];
          Alcotest.(check (list word)) "the words" [ ("a", 11.); ("bb", 25.) ] (words p));
      Testo.create "presentational hints: Hacker News' table" (fun () ->
          let p = page {|<body style="margin: 0"><table id=t width="50%" cellpadding=0 cellspacing=0><tr><td id=a bgcolor=ff6600>a</table>|} in
          let a = box "a" p in
          Alcotest.check near "width=50%" 100. (box "t" p).width;
          Alcotest.(check (list int)) "bgcolor=" [ 255; 102; 0 ] [ a.style.background.r; a.style.background.g; a.style.background.b ];
          Alcotest.(check (list word)) "no padding" [ ("a", 0.) ] (words p));
      Testo.create "an inline element's padding and background" (fun () ->
          let p = page {|<body style="margin: 0">a <span id=s style="padding: 0 5px; background: yellow">b</span> c|} in
          Alcotest.(check (list word)) "room made for its padding" [ ("a", 0.); ("b", 25.); ("c", 50.) ] (words p);
          let rec backdrops (b : Box_types.box) = b.backdrops @ List.concat_map backdrops b.children in
          match backdrops p with
          | [ d ] -> Alcotest.(check (list near)) "its box: x, width, height" [ 20.; 20.; 10. ] [ d.x; d.width; d.height ]
          | _ -> Alcotest.fail "one box");
      Testo.create "srcset: its first address" (fun () ->
          Alcotest.(check (option string)) "no src" (Some "a.png")
            (Box_tree.picture_src (Dom.element ~attributes:[ ("srcset", "a.png 1x, b.png 2x") ] "img" [])));
      Testo.create "flex: a row, an auto margin" (fun () ->
          let p = page {|<body style="margin: 0"><div style="display: flex; width: 200px"><div id=a style="width: 50px">a</div><div id=b style="margin-left: auto">bb</div></div>|} in
          Alcotest.(check (list near)) "a: x, width" [ 0.; 50. ] (let a = box "a" p in [ a.x; a.width ]);
          Alcotest.(check (list near)) "b pushed right, shrunk to its word" [ 180.; 20. ] (let b = box "b" p in [ b.x; b.width ]));
      Testo.create "flex: grow" (fun () ->
          let p = page {|<body style="margin: 0"><div style="display: flex"><div id=a style="flex: 1">a</div><div id=b style="flex: 2">b</div></div>|} in
          Alcotest.(check (list near)) "a third, two thirds" [ 200. /. 3.; 400. /. 3. ] [ (box "a" p).width; (box "b" p).width ];
          Alcotest.check near "b after a" (200. /. 3.) (box "b" p).x);
      Testo.create "flex: align-items center, the row stretched" (fun () ->
          let p =
            page {|<body style="margin: 0"><div style="display: flex; height: 100px; align-items: center"><div id=a>a</div></div><div style="display: flex; height: 50px"><div id=s>s</div></div>|}
          in
          Alcotest.check near "centred: (100 - 12) / 2" 44. (box "a" p).y;
          Alcotest.check near "stretched to the row" 50. (box "s" p).height);
      Testo.create "flex: wrap, and a column with a gap" (fun () ->
          let p =
            page
              {|<body style="margin: 0"><div style="display: flex; flex-wrap: wrap; width: 100px"><div style="width: 40px">a</div><div style="width: 40px">b</div><div id=c style="width: 40px">c</div></div><div style="display: flex; flex-direction: column; row-gap: 5px"><div id=d>d</div><div id=e>e</div></div>|}
          in
          Alcotest.(check (list near)) "c on a second line" [ 0.; 12. ] (let c = box "c" p in [ c.x; c.y ]);
          Alcotest.check near "e below d and the gap" (24. +. 12. +. 5.) (box "e" p).y);
      Testo.create "grid: named areas, a column said and an fr, a row stretched (Wikipedia's shape)" (fun () ->
          let css =
            {|body { margin: 0 }
              #g { display: grid; column-gap: 10px; grid-template: min-content 1fr min-content / 50px minmax(0, 1fr);
                   grid-template-areas: 'top top' 'side main' 'foot foot' }
              #top { grid-area: top } #side { grid-area: side } #main { grid-area: main; height: 30px } #foot { grid-area: foot }|}
          in
          (* said in another order than they are placed *)
          let p = page ~css {|<div id=g><div id=main>m</div><div id=foot>f</div><div id=side>s</div><div id=top>t</div></div>|} in
          Alcotest.(check (list near)) "the top, across" [ 0.; 0.; 200.; 12. ] (geometry (box "top" p));
          Alcotest.(check (list near)) "the side column: 50 wide, as high as its row" [ 0.; 12.; 50.; 30. ] (geometry (box "side" p));
          Alcotest.(check (list near)) "the main one: the rest, past the gap" [ 60.; 12.; 140.; 30. ] (geometry (box "main" p));
          Alcotest.(check (list near)) "the foot, across, under them" [ 0.; 42.; 200.; 12. ] (geometry (box "foot" p));
          Alcotest.(check (list near)) "the grid: its rows' heights" [ 0.; 0.; 200.; 54. ] (geometry (box "g" p)));
      Testo.create "grid: the next free cell, three columns, gaps; a cell said" (fun () ->
          let css = {|body { margin: 0 } #g { display: grid; grid-template-columns: repeat(3, 1fr); gap: 4px 10px } #e { grid-area: 3 / 2 }|} in
          let p = page ~css {|<div id=g><div id=a>a</div><div id=b>b</div><div id=c>c</div><div id=d>d</div><div id=e>e</div></div>|} in
          Alcotest.(check (list near)) "a" [ 0.; 0.; 60.; 12. ] (geometry (box "a" p));
          Alcotest.(check (list near)) "b" [ 70.; 0.; 60.; 12. ] (geometry (box "b" p));
          Alcotest.(check (list near)) "c" [ 140.; 0.; 60.; 12. ] (geometry (box "c" p));
          Alcotest.(check (list near)) "d: the next row, past the row gap" [ 0.; 16.; 60.; 12. ] (geometry (box "d" p));
          Alcotest.(check (list near)) "e: the third row, the second column" [ 70.; 32.; 60.; 12. ] (geometry (box "e" p)));
      Testo.create "grid: place-content: center in a min-height (example.com's shape)" (fun () ->
          let css = {|body { margin: 0; min-height: 100px; display: grid; place-content: center; text-align: center }|} in
          let p = page ~css {|<body id=b><p id=p style="margin: 0">a line</p><a id=a href=/x>more</a>|} in
          Alcotest.(check (list near)) "the body: its min-height" [ 0.; 0.; 200.; 100. ] (geometry (box "b" p));
          Alcotest.(check (list near)) "the paragraph: 24 of content in 100, 38 above; the widest content, centred" [ 70.; 38.; 60.; 12. ] (geometry (box "p" p));
          Alcotest.(check (list near)) "the link, a block under it, as wide as the column" [ 70.; 50.; 60.; 12. ] (geometry (box "a" p)));
      Testo.create "grid: an item at its own width, centred down its row; text between items" (fun () ->
          let css = {|body { margin: 0 } #g { display: grid; grid-template-columns: 100px 100px; align-items: center } #a { width: 40px } #b { height: 40px }|} in
          let p = page ~css {|<div id=g><div id=a>a</div><div id=b>b</div>loose</div>|} in
          Alcotest.(check (list near)) "a: 40 wide, in the middle of the row's 40" [ 0.; 14.; 40.; 12. ] (geometry (box "a" p));
          Alcotest.(check (list near)) "b" [ 100.; 0.; 100.; 40. ] (geometry (box "b" p));
          Alcotest.(check (list (pair string near))) "the loose text: an item of its own, in the next row" [ ("a", 0.); ("b", 100.); ("loose", 0.) ]
            (List.sort compare (words (box "g" p))));
      Testo.create "a picture: its size, max-width" (fun () ->
          let p = page {|<body style="margin: 0"><img src=a.png width=400 height=100 style="max-width: 100%">|} in
          match List.filter_map (fun (f : Html_layout.fragment) -> Option.map (fun (pic : Html_layout.picture) -> (f.width, pic.height)) f.picture) (Box_tree.fragments p) with
          | [ (w, h) ] -> Alcotest.(check (list near)) "scaled to the page" [ 200.; 50. ] [ w; h ]
          | _ -> Alcotest.fail "one picture");
      Testo.create "Box_flow's worked examples: the horizontal equation, two margins one" (fun () ->
          let p = page ~width:976. {|<body style="margin: 0"><div id=d style="width: 400px; padding: 10px; border: 1px solid; margin: 0 auto">x</div><div id=a style="padding: 10px; border: 1px solid">y</div>|} in
          let ml, w, mr = Box_flow.horizontal (box "d" p).style ~cb_width:976. () in
          Alcotest.(check (list near)) "margins auto share the rest" [ 277.; 400.; 277. ] [ ml; w; mr ];
          let ml, w, mr = Box_flow.horizontal (box "a" p).style ~cb_width:976. () in
          Alcotest.(check (list near)) "width auto takes what is left" [ 0.; 954.; 0. ] [ ml; w; mr ];
          let ml, w, mr = Box_flow.horizontal (box "a" p).style ~cb_width:976. ~content:100. () in
          Alcotest.(check (list near)) "a width already decided" [ 0.; 100.; 854. ] [ ml; w; mr ];
          Alcotest.(check near) "the larger" 21.4 (Box_flow.collapse 8. 21.4);
          Alcotest.(check near) "a negative one subtracted" 6. (Box_flow.collapse 10. (-4.));
          Alcotest.(check near) "two negative: the lower" (-4.) (Box_flow.collapse (-1.) (-4.)));
      Testo.create "Box_tree's worked example: a box moved, all it holds with it" (fun () ->
          let p = page {|<body style="margin: 8px"><div id=d style="padding: 2px">ab</div>|} in
          let d = box "d" p in
          let m = Box_tree.moved 5. 100. d in
          Alcotest.(check (list near)) "the box" [ d.x +. 5.; d.y +. 100.; d.width; d.height ] (geometry m);
          Alcotest.(check (list word)) "its word" [ ("ab", 15.) ] (words m);
          Alcotest.(check (option near)) "its baseline" (Option.map (fun b -> b +. 100.) (Box_tree.last_baseline d)) (Box_tree.last_baseline m);
          Alcotest.(check bool) "not moved: the same box" true (Box_tree.moved 0. 0. d == d);
          Alcotest.(check near) "how far right its content reaches" 30. (Box_tree.inner_right d));
      Testo.create "Box_inline's worked example: the room beside a float" (fun () ->
          let floats : Box_types.placed list = [ { pside = On_left; left = 8.; right = 48.; ptop = 8.; pbottom = 38. } ] in
          Alcotest.(check (pair near near)) "beside it" (48., 144.) (Box_inline.room floats ~x:8. ~width:184. ~top:8. ~height:12.);
          Alcotest.(check (pair near near)) "under it" (8., 184.) (Box_inline.room floats ~x:8. ~width:184. ~top:38. ~height:12.);
          Alcotest.(check near) "cleared: below it" 38. (Box_inline.cleared floats [ On_left ] 8.);
          Alcotest.(check near) "cleared of the other side: where it was" 8. (Box_inline.cleared floats [ On_right ] 8.));
    ]
