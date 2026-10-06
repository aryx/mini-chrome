(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_browser_script.mli *)

(* a page's scripts run *)
let page (html : string) : Browser_script.t =
  let t = Browser_script.create (Html_tree.of_string html) in
  Browser_script.run_scripts t;
  t

(* the frozen body, blank text and scripts left out, as indented lines *)
let body (t : Browser_script.t) : string list =
  let root = Dom.without_blank_text (Browser_script.tree t) in
  match Dom.find_all "body" root with
  | [ b ] ->
      List.concat_map
        (fun (n : Dom.node) ->
          match n with
          | Element e when e.name = "script" -> []
          | Element e -> Dom.to_lines e
          | Text s -> [ Printf.sprintf "%S" s ])
        b.children
  | _ -> Alcotest.fail "no body"

(* a script's value, as the console shows it *)
let value (t : Browser_script.t) (s : string) : string =
  match Browser_script.eval t s with Ok v -> Js_value.display v | Error e -> "error: " ^ e.message

let check_body what t expected = Alcotest.(check (list string)) what expected (body t)

(* the element of id [id] in the frozen tree: what a click is given *)
let element (t : Browser_script.t) (id : string) : Dom.element =
  let rec find (e : Dom.element) : Dom.element option =
    if Dom.attribute "id" e = Some id then Some e
    else List.find_map (fun (n : Dom.node) -> match n with Element c -> find c | Text _ -> None) e.children
  in
  match find (Browser_script.tree t) with Some e -> e | None -> Alcotest.fail ("no element " ^ id)

let tests =
  Testo.categorize "Browser_script"
    [
      Testo.create "the worked example: a text changed" (fun () ->
          let t = Browser_script.create (Html_tree.of_string "<p id=x>a</p><script>document.getElementById(\"x\").textContent = \"b\"</script>") in
          Alcotest.(check bool) "not changed before the scripts" false (Browser_script.changed t);
          Browser_script.run_scripts t;
          Alcotest.(check bool) "changed after" true (Browser_script.changed t);
          check_body "the text" t [ "p id=\"x\""; "  \"b\"" ];
          Alcotest.(check bool) "frozen: not changed any more" false (Browser_script.changed t));
      Testo.create "a listener that is an object: its handleEvent" (fun () ->
          (* a framework's one object hearing every event, the method its class's *)
          let t =
            page
              "<p id=p>x</p><script>function L() { this.heard = [] }\nL.prototype.handleEvent = function (e) { this.heard.push(e.type + ' ' + e.target.id) };\nvar l = new L(); document.addEventListener('click', l, false);</script>"
          in
          ignore (Browser_script.click t (element t "p"));
          Alcotest.(check string) "called, the object for this" "[\"click p\"]" (value t "l.heard"));
      Testo.create "history.pushState: the page's address, no page loaded" (fun () ->
          let t = Browser_script.create ~base:"http://site.test/groups/a" (Html_tree.of_string "<p>x</p>") in
          Browser_script.run_scripts t;
          Alcotest.(check string) "before" "/groups/a" (value t "location.pathname");
          ignore (value t "history.pushState({ n: 1 }, '', '/latest?x=1')");
          Alcotest.(check string) "location follows" "http://site.test/latest?x=1 /latest 1" (value t "location.href + ' ' + location.pathname + ' ' + history.state.n");
          Alcotest.(check (list (pair string bool))) "the browser told, once" [ ("http://site.test/latest?x=1", false) ] (Browser_script.take_address t);
          Alcotest.(check (list (pair string bool))) "then nothing" [] (Browser_script.take_address t);
          ignore (value t "history.replaceState(null, '', '/b'); history.pushState(null, '', '/c')");
          Alcotest.(check (list (pair string bool))) "each one, in order" [ ("http://site.test/b", true); ("http://site.test/c", false) ] (Browser_script.take_address t);
          (* Back to a state of the same document: the address, and popstate *)
          ignore (value t "var popped = []; window.addEventListener('popstate', function () { popped.push(location.pathname) })");
          Browser_script.popstate t "http://site.test/b";
          Alcotest.(check string) "the script told" "[\"/b\"]" (value t "popped"));
      Testo.create "where an element is: asked of the browser, once between two changes" (fun () ->
          let t = page "<div id=a>x</div><div id=b>y</div>" in
          let asked = ref 0 in
          (* a browser that stacks the page's elements, each 10 high, 100 wide *)
          Browser_script.set_measure t (fun tree ->
              incr asked;
              let divs = Dom.find_all "div" tree in
              fun e -> List.find_map (fun (i, d) -> if d == e then Some (0., 10. *. float_of_int i, 100., 10.) else None) (List.mapi (fun i d -> (i, d)) divs));
          Alcotest.(check string) "sizes and places" "[10, 100, 10, 20]"
            (value t "var b = document.getElementById('b'), r = b.getBoundingClientRect(); [b.offsetHeight, b.offsetWidth, r.top, r.bottom]");
          Alcotest.(check int) "one layout for the four" 1 !asked;
          Alcotest.(check string) "after a change, again" "20"
            (value t "var d = document.createElement('div'); document.body.insertBefore(d, document.getElementById('a')); document.getElementById('b').offsetTop");
          Alcotest.(check int) "a second layout" 2 !asked);
      Testo.create "a value shown: five deep, no further" (fun () ->
          let t = page "<script>var o = { a: { b: { c: { d: { e: { f: 1 } } } } } }</script>" in
          Alcotest.(check string) "cut" "{a: {b: {c: {d: {e: ...}}}}}" (value t "o"));
      Testo.create "the worked example: a hundred items, one task" (fun () ->
          let t =
            page
              "<ul id=list></ul><script>\nconst list = document.getElementById(\"list\");\nfor (let i = 0; i < 100; i++) {\n  const li = document.createElement(\"li\");\n  li.textContent = \"item \" + i;\n  list.appendChild(li);\n}\n</script>"
          in
          Alcotest.(check int) "100 li" 100 (List.length (Dom.find_all "li" (Browser_script.tree t)));
          Alcotest.(check string) "the last" "item 99" (value t "document.querySelector(\"ul\").lastChild.textContent"));
      Testo.create "innerHTML, written and read" (fun () ->
          let t = page "<p id=x>a</p>" in
          ignore (value t "document.getElementById(\"x\").innerHTML = \"<b>3</b> & more\"");
          check_body "parsed" t [ "p id=\"x\""; "  b"; "    \"3\""; "  \" & more\"" ];
          Alcotest.(check string) "read back, escaped" "<b>3</b> &amp; more" (value t "document.getElementById(\"x\").innerHTML"));
      Testo.create "selectors: Css's, descendants and classes" (fun () ->
          let t = page "<ul><li class=done>a<li>b</ul><ol><li class=done>c</ol>" in
          Alcotest.(check string) "ul li.done: one" "1" (value t "document.querySelectorAll(\"ul li.done\").length");
          Alcotest.(check string) ".done: the first" "a" (value t "document.querySelector(\".done\").textContent");
          Alcotest.(check string) "within an element" "c" (value t "document.querySelector(\"ol\").querySelector(\"li\").textContent");
          Alcotest.(check string) "none" "null" (value t "document.querySelector(\"table\")"));
      Testo.create "style and class" (fun () ->
          let t = page "<p id=x>a</p>" in
          ignore (value t "const p = document.getElementById(\"x\"); p.style.color = \"red\"; p.style.backgroundColor = \"blue\"; p.className = \"done\"");
          check_body "the attributes" t [ "p id=\"x\" style=\"color: red; background-color: blue\" class=\"done\""; "  \"a\"" ];
          Alcotest.(check string) "read back" "blue" (value t "p.style.backgroundColor"));
      Testo.create "an element, one host object" (fun () ->
          let t = page "<p id=x>a</p>" in
          Alcotest.(check string) "===" "true" (value t "document.getElementById(\"x\") === document.getElementById(\"x\")");
          Alcotest.(check string) "an expando kept" "true" (value t "document.getElementById(\"x\").seen = true; document.body.firstElementChild.seen"));
      Testo.create "the tree edited" (fun () ->
          let t = page "<ul id=a><li>1<li>2</ul><ul id=b></ul>" in
          ignore (value t "const a = document.getElementById(\"a\"), b = document.getElementById(\"b\"); b.appendChild(a.firstChild)");
          check_body "moved" t [ "ul id=\"a\""; "  li"; "    \"2\""; "ul id=\"b\""; "  li"; "    \"1\"" ];
          ignore (value t "const li = document.createElement(\"li\"); li.textContent = \"0\"; b.insertBefore(li, b.firstChild); a.removeChild(a.firstChild)");
          check_body "inserted, removed" t [ "ul id=\"a\""; "ul id=\"b\""; "  li"; "    \"0\""; "  li"; "    \"1\"" ];
          Alcotest.(check string) "never inside itself" "error: HierarchyRequestError: The new child element contains the parent."
            (value t "b.firstChild.appendChild(b)"));
      Testo.create "the title" (fun () ->
          let t = page "<title>A</title><p>x" in
          ignore (value t "document.title = document.title + \"B\"");
          Alcotest.(check string) "AB" "AB" (Dom.text_content (List.hd (Dom.find_all "title" (Browser_script.tree t)))));
      Testo.create "Netscape's attributes kept through the copy" (fun () ->
          let t = page "<body bgcolor=white><center>x</center>" in
          let root = Browser_script.tree t in
          let b = List.hd (Dom.find_all "body" root) and c = List.hd (Dom.find_all "center" root) in
          Alcotest.(check (option string)) "bgcolor still an extension" (Some "white") (Dom.attribute ~extensions:true "bgcolor" b);
          Alcotest.(check (option string)) "not a core attribute" None (Dom.attribute "bgcolor" b);
          Alcotest.(check bool) "center still Netscape's" true (c.origin = Dtd.Netscape));
      Testo.create "events: a click bubbles" (fun () ->
          let t =
            page
              "<ul id=l><li id=a>x</ul><script>const log = [];\ndocument.getElementById(\"l\").addEventListener(\"click\", e => log.push(\"ul:\" + e.target.id));\ndocument.getElementById(\"a\").onclick = () => log.push(\"li\");\ndocument.addEventListener(\"click\", () => log.push(\"document\"))</script>"
          in
          Alcotest.(check bool) "not prevented" false (Browser_script.click t (element t "a"));
          Alcotest.(check string) "the li's, the ul's, the document's" "[\"li\", \"ul:a\", \"document\"]" (value t "log"));
      Testo.create "events: stopped, prevented, onclick=\"...\"" (fun () ->
          let t =
            page
              "<p id=p><a id=k href=next.html onclick=\"this.textContent = 'clicked'; return false\">go</a></p><script>let seen = false;\ndocument.getElementById(\"p\").addEventListener(\"click\", () => { seen = true })</script>"
          in
          Alcotest.(check bool) "return false: prevented" true (Browser_script.click t (element t "k"));
          check_body "this is the element" t [ "p id=\"p\""; "  a id=\"k\" href=\"next.html\" onclick=\"this.textContent = 'clicked'; return false\""; "    \"clicked\"" ];
          Alcotest.(check string) "and it still bubbled" "true" (value t "seen");
          ignore (value t "document.getElementById(\"k\").onclick = e => { e.stopPropagation(); e.preventDefault() }; seen = false");
          Alcotest.(check bool) "preventDefault" true (Browser_script.click t (element t "k"));
          Alcotest.(check string) "stopped: the p not told" "false" (value t "seen"));
      Testo.create "events: one handler for a whole table (delegation)" (fun () ->
          let t =
            page
              "<table id=board><tr><td id=c0>.</td><td id=c1>.</td></tr></table><script>document.getElementById(\"board\").addEventListener(\"click\", e => { e.target.textContent = \"X\" })</script>"
          in
          ignore (Browser_script.click t (element t "c1"));
          Alcotest.(check string) "the cell clicked" "[\".\", \"X\"]" (value t "[0, 1].map(i => document.getElementById(\"c\" + i).textContent)"));
      Testo.create "events: keys, and a field typed into" (fun () ->
          let t =
            page
              "<input id=f><script>let last = \"\", typed = \"\";\ndocument.addEventListener(\"keydown\", e => { last = e.key });\ndocument.getElementById(\"f\").addEventListener(\"input\", e => { typed = e.target.value })</script>"
          in
          ignore (Browser_script.key t "ArrowUp");
          Browser_script.input t (element t "f") "hello";
          Alcotest.(check string) "the key, the text" "[\"ArrowUp\", \"hello\"]" (value t "[last, typed]"));
      Testo.create "timers on the page's clock" (fun () ->
          let t = page "<script>let a = 0, b = 0;\nsetTimeout(() => { a = 1 }, 100);\nconst i = setInterval(() => { b++ }, 100)</script>" in
          Browser_script.advance t 50.;
          Alcotest.(check string) "50 ms: nothing yet" "[0, 0]" (value t "[a, b]");
          Browser_script.advance t 300.;
          Alcotest.(check string) "350 ms: the timeout once, the interval 3 times" "[1, 3]" (value t "[a, b]");
          ignore (value t "clearInterval(i)");
          Browser_script.advance t 1000.;
          Alcotest.(check string) "cleared" "[1, 3]" (value t "[a, b]"));
      Testo.create "promises: a timer awaited" (fun () ->
          let t =
            page
              "<p id=out></p><script>const sleep = ms => new Promise(done => setTimeout(done, ms));\nlet said = [];\nasync function steps() { said.push(\"start\"); await sleep(100); said.push(\"100\"); await sleep(100); said.push(\"200\"); document.getElementById(\"out\").textContent = said.join(\" \") }\nsteps().then(() => said.push(\"done\"))</script>"
          in
          Alcotest.(check string) "up to its first await" "[\"start\"]" (value t "said");
          Browser_script.advance t 150.;
          Alcotest.(check string) "the timer's function resolved it: the function goes on" "[\"start\", \"100\"]" (value t "said");
          Browser_script.advance t 100.;
          Alcotest.(check string) "to its end, and its promise's then" "[\"start\", \"100\", \"200\", \"done\"]" (value t "said");
          Alcotest.(check string) "the page changed from it" "start 100 200" (value t "document.getElementById(\"out\").textContent"));
      Testo.create "alert, and DOMContentLoaded" (fun () ->
          let t = page "<script>document.addEventListener(\"DOMContentLoaded\", () => alert(\"ready\"));\nalert(\"first\")</script>" in
          Alcotest.(check (list string)) "queued in order" [ "first"; "ready" ] (Browser_script.take_alerts t);
          Alcotest.(check (list string)) "taken" [] (Browser_script.take_alerts t));
      Testo.create "document.readyState: loading, interactive, complete" (fun () ->
          let t =
            page
              "<script>var said = [document.readyState];\n\
               document.addEventListener(\"readystatechange\", () => said.push(\"change \" + document.readyState));\n\
               document.addEventListener(\"DOMContentLoaded\", () => said.push(\"DOMContentLoaded \" + document.readyState));\n\
               window.addEventListener(\"load\", () => said.push(\"load \" + document.readyState))</script>"
          in
          Alcotest.(check string) "a script being read is told loading: what it waits for is yet to come"
            "[\"loading\", \"change interactive\", \"DOMContentLoaded interactive\", \"change complete\", \"load complete\"]" (value t "said"));
      Testo.create "an iframe's window: an empty page's" (fun () ->
          let t =
            page
              "<body><script>var f = document.createElement(\"iframe\"); document.body.appendChild(f);\n\
               var w = f.contentWindow; w.addEventListener(\"resize\", function () {}); w.document.open(); w.document.close();\n\
               var said = [typeof w, w === f.contentWindow, w.parent === window, f.contentDocument === w.document, typeof document.body.contentWindow]</script>"
          in
          Alcotest.(check string) "one window a frame, with a document; no other element has one" "[\"object\", true, true, true, \"undefined\"]" (value t "said"));
      Testo.create "errors to the console, the next script still run" (fun () ->
          let t = page "<script>\nx.y\n</script><script>console.log(\"next\", [1])</script>" in
          Alcotest.(check (list string)) "the console" [ "Uncaught ReferenceError: x is not defined (line 2)"; "next [1]" ] (Browser_script.console t));
      Testo.create "Script_dom's worked example: the copy thawed, read, changed, frozen" (fun () ->
          let tree = Html_tree.of_string "<p id=a>one <b>two</b>" in
          let root = Script_dom.thaw tree in
          let p = List.find (fun (n : Script_types.node) -> n.name = "p") (Script_dom.elements root) in
          Alcotest.(check (list string)) "its children: a text, a b" [ "#text"; "b" ] (List.map (fun (n : Script_types.node) -> n.name) p.children);
          Alcotest.(check bool) "each knows its parent" true (List.for_all (fun (n : Script_types.node) -> match n.parent with Some q -> q == p | None -> false) p.children);
          Alcotest.(check (option string)) "its attribute" (Some "a") (Script_dom.attribute p "id");
          Alcotest.(check string) "its text" "one two" (Script_dom.text_content p);
          Alcotest.(check string) "inner_html" "one <b>two</b>" (Script_dom.inner_html p);
          Alcotest.(check string) "html_of" {|<p id="a">one <b>two</b></p>|} (Script_dom.html_of p);
          Alcotest.(check bool) "frozen unchanged: the same tree" true (Script_dom.freeze root = tree);
          Script_dom.set_attribute p "id" "b";
          Script_dom.set_attribute p "class" "x";
          Script_dom.detach (List.nth p.children 1);
          Alcotest.(check string) "changed" {|<p id="b" class="x">one </p>|} (Script_dom.html_of p);
          Alcotest.(check (list string)) "a fragment's nodes" [ "i"; "#text" ] (List.map (fun (n : Script_types.node) -> n.name) (Script_dom.parse_fragment "<i>a</i>b")));
    ]
