(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_script_dom.mli *)

(* a page, then a script: its last expression's value as the console
 * shows it *)
let run ?(html = "") (script : string) : string =
  let t = Browser_script.create (Html_tree.of_string ("<body>" ^ html ^ "</body>")) in
  Browser_script.run_scripts t;
  match Browser_script.eval t script with Ok v -> Js_value.display v | Error e -> "error: " ^ e.message

let check what ?html script expected = Alcotest.(check string) what expected (run ?html script)
let list = "<ul id=l><li class=a>1</li><li>2</li></ul>"

let tests =
  Testo.categorize "Script dom"
    [
      Testo.create "the worked example: matches, closest, append, after" (fun () ->
          check "a selector tried on an element; its first ancestor that matches" ~html:list
            {|const l = document.getElementById("l"), first = l.firstElementChild;
              [first.matches("ul > li.a"), first.matches("li.b"), first.closest("ul") === l, first.closest("li") === first, first.closest("table")]|}
            "[true, false, true, true, null]";
          check "append: nodes and strings, at the end; after: beside" ~html:list
            {|const l = document.getElementById("l"), first = l.firstElementChild;
              l.append("3", document.createElement("li"));
              const then = l.innerHTML;
              first.after(l.lastElementChild);
              [then, l.innerHTML]|}
            {|["<li class=\"a\">1</li><li>2</li>3<li></li>", "<li class=\"a\">1</li><li></li><li>2</li>3"]|};
          check "prepend, before, replaceWith, replaceChildren" ~html:list
            {|const l = document.getElementById("l"), b = document.createElement("b");
              l.prepend("0"); l.lastElementChild.before(b); b.replaceWith("B", "b");
              const then = l.textContent;
              l.replaceChildren(); [then, l.childNodes.length]|}
            {|["01Bb2", 0]|});
      Testo.create "a tree a script made, not in the page" (fun () ->
          check "selectors work in it; it is not connected" 
            {|const d = document.createElement("div"); d.innerHTML = "<p class=x><b>t</b></p><p>u</p>";
              [d.querySelectorAll("p").length, d.querySelector("p.x b").textContent, d.firstChild.matches("div > p"), d.isConnected, document.body.isConnected, document.contains(d)]|}
            {|[2, "t", true, false, true, false]|};
          check "a copy: deep or not; the copy is another node" ~html:list
            {|const l = document.getElementById("l"), deep = l.cloneNode(true), shallow = l.cloneNode(false);
              deep.firstElementChild.textContent = "changed";
              [deep.children.length, shallow.children.length, shallow.id, l.firstElementChild.textContent, deep === l]|}
            {|[2, 0, "l", "1", false]|};
          check "a fragment: its children go in its place; a comment is a node, not shown" ~html:list
            {|const f = document.createDocumentFragment(), l = document.getElementById("l");
              f.append(document.createElement("li"), document.createComment("mark"));
              const kinds = [f.nodeType, f.lastChild.nodeType, f.lastChild.nodeValue];
              l.appendChild(f);
              [kinds, l.childNodes.length, l.children.length, f.childNodes.length, l.innerHTML.endsWith("<li></li><!--mark-->"), l.textContent]|}
            {|[[11, 8, "mark"], 4, 3, 0, true, "12"]|};
          check "who is first, who is inside" ~html:list
            {|const l = document.getElementById("l"), a = l.children[0], b = l.children[1];
              [a.compareDocumentPosition(b), b.compareDocumentPosition(a), a.compareDocumentPosition(l), l.compareDocumentPosition(a), a.compareDocumentPosition(a), l.contains(b), a.contains(l)]|}
            "[4, 2, 10, 20, 0, true, false]");
      Testo.create "attributes: as properties, as data, as a list" (fun () ->
          check "dataset; hasAttribute; toggleAttribute; attributes" ~html:{|<input id=i data-user-id=7 disabled>|}
            {|const i = document.getElementById("i");
              i.dataset.lastSeen = "now";
              [i.dataset.userId, i.getAttribute("data-last-seen"), i.hasAttribute("disabled"), i.toggleAttribute("disabled"), i.disabled, i.attributes.map(a => a.name)]|}
            {|["7", "now", true, false, false, ["id", "data-user-id", "data-last-seen"]]|};
          check "a property that is an attribute" ~html:{|<input id=i><div id=d></div><label id=lb for=i></label>|}
            {|const i = document.getElementById("i"), d = document.getElementById("d");
              i.type = "radio"; i.name = "n"; i.required = true;
              [i.getAttribute("type"), i.name, i.hasAttribute("required"), d.name, d.title, document.getElementById("lb").htmlFor, document.createElement("input").type]|}
            {|["radio", "n", true, undefined, "", "i", "text"]|};
          check "no boxes for a script, but the page's own size, the window's" ~html:list
            {|const r = document.getElementById("l").getBoundingClientRect(); [r.width, r.top, document.getElementById("l").offsetWidth, document.body.offsetWidth, document.documentElement.clientWidth === innerWidth]|}
            "[0, 0, 0, 1000, true]");
      Testo.create "events of a script's own" (fun () ->
          check "the worked example: a CustomEvent, its detail, bubbling to the document" ~html:list
            {|const l = document.getElementById("l"), seen = [];
              l.addEventListener("saved", e => seen.push("ul " + e.detail.id + " " + (e.target === l.firstElementChild)));
              document.addEventListener("saved", e => seen.push("document " + (e instanceof CustomEvent) + " " + (e instanceof Event)));
              const went = l.firstElementChild.dispatchEvent(new CustomEvent("saved", { detail: { id: 7 }, bubbles: true }));
              [seen, went]|}
            {|[["ul 7 true", "document true true"], true]|};
          check "one that does not bubble; stopPropagation; preventDefault" ~html:list
            {|const l = document.getElementById("l"), first = l.firstElementChild, seen = [];
              l.addEventListener("quiet", () => seen.push("never"));
              first.dispatchEvent(new Event("quiet"));
              first.addEventListener("loud", e => { e.stopPropagation(); e.preventDefault(); seen.push("li") });
              l.addEventListener("loud", () => seen.push("never"));
              [first.dispatchEvent(new Event("loud", { bubbles: true, cancelable: true })), seen]|}
            {|[false, ["li"]]|};
          check "once; an object with handleEvent; click(); createEvent" ~html:list
            {|const l = document.getElementById("l"), seen = [];
              l.addEventListener("click", () => seen.push("once"), { once: true });
              l.addEventListener("click", { handleEvent(e) { seen.push(e.type + " " + (this.handleEvent !== undefined)) } });
              l.firstElementChild.click(); l.click();
              const old = document.createEvent("CustomEvent"); old.initCustomEvent("made", true, false, "d");
              document.addEventListener("made", e => seen.push(e.detail));
              l.dispatchEvent(old); window.dispatchEvent(new Event("made"));
              seen|}
            {|["once", "click true", "click true", "d", null]|};
          check "a listener that throws: said, the next still run" ~html:list
            {|const l = document.getElementById("l"), seen = [];
              l.addEventListener("x", () => { throw new Error("first") }); l.addEventListener("x", () => seen.push("second"));
              l.dispatchEvent(new Event("x")); seen|}
            {|["second"]|});
      Testo.create "the document as a node; window's globals" (fun () ->
          check "what jQuery asks of a document" ~html:list
            {|[document.nodeType, document.documentElement.nodeName, document.childNodes.length, document.ownerDocument, document.body.ownerDocument === document,
               document.implementation.createHTMLDocument("").body.nodeName, document.createElement("p").ownerDocument === document]|}
            {|[9, "HTML", 1, null, true, "BODY", true]|};
          check "the classes: instanceof, constants, a method added to a prototype" ~html:list
            {|const l = document.getElementById("l");
              Element.prototype.shout = function () { return this.id.toUpperCase() };
              [l instanceof HTMLElement, l instanceof Node, l.firstChild.firstChild instanceof Text, l instanceof Text, document instanceof Document,
               Node.ELEMENT_NODE, l.shout(), l.hasOwnProperty("nope"), typeof l.toString]|}
            {|[true, true, true, false, true, 1, "L", false, "function"]|};
          check "window is the global object" {|var a = 1; window.b = 2; [window.a, b, window === self, window.window === window, globalThis === window, typeof window.setTimeout, window.innerWidth]|}
            {|[1, 2, true, true, true, "function", 1000]|};
          check "getComputedStyle: the element's own style, a few defaults" ~html:{|<p id=p style="color: red" hidden></p><p id=q></p>|}
            {|const s = getComputedStyle(document.getElementById("p"));
              [s.color, s.getPropertyValue("color"), s.display, getComputedStyle(document.getElementById("q")).display, s.marginTop]|}
            {|["red", "red", "none", "block", ""]|};
          check "storage, observers, history: there, and quiet; matchMedia: the window's size (1000 wide)"
            {|localStorage.setItem("k", 1); localStorage.other = "o";
              const o = new MutationObserver(() => {}); o.observe(document.body, { childList: true }); o.disconnect();
              history.pushState({}, "", "/x");
              [localStorage.getItem("k"), localStorage.getItem("nope"), localStorage.length, sessionStorage.length, matchMedia("(min-width: 1px)").matches, matchMedia("(max-width: 500px)").matches, typeof performance.now(), typeof requestAnimationFrame]|}
            {|["1", null, 2, 0, true, false, "number", "function"]|});
      Testo.create "selectors: the fast way and the simple one agree" (fun () ->
          let html = {|<div id=a class="x y"><ul><li class=first>1</li><li>2<span id=s>in</span></li><li>3</li></ul></div><p class=x>p</p>|} in
          let asks =
            {|var a = document.getElementById("a"), s = document.getElementById("s");
              JSON.stringify([document.querySelectorAll("li").length, a.querySelectorAll(":scope > ul > li").length, a.querySelectorAll("li:first-child")[0].textContent,
                a.querySelectorAll("li:last-child")[0].textContent, a.querySelector(".x") === null, document.querySelectorAll(".x").length,
                s.matches("div.x li span"), s.matches("ul > span"), s.closest("li").textContent, s.closest(".y").id, s.matches("li:nth-child(2) > span"),
                a.querySelectorAll("li + li").length, document.querySelectorAll("div p, body > p").length])|}
          in
          let ask opti =
            let before = !Mini_opti.enabled in
            Mini_opti.enabled := opti;
            Fun.protect ~finally:(fun () -> Mini_opti.enabled := before) (fun () -> run ~html asks)
          in
          Alcotest.(check string) "what they find" {|[3,3,"1","3",true,2,true,false,"2in","a",true,2,1]|} (ask true);
          Alcotest.(check string) "the same, the simple way" (ask true) (ask false));
      Testo.create "Event_loop, the worked example: a task, its microtasks, then the next task" (fun () ->
          let t = Browser_script.create ~base:"http://site.test/" (Html_tree.of_string "<body></body>") in
          let seen () = match Browser_script.eval t "seen.join(' ')" with Ok v -> Js_value.display v | Error e -> "error: " ^ e.message in
          ignore (Browser_script.eval t {|var seen = []; seen.push(1); setTimeout(() => seen.push(4), 0); Promise.resolve().then(() => seen.push(3)); seen.push(2)|});
          Alcotest.(check string) "the script to its end, then the promise's then; the timer is another task" "1 2 3" (seen ());
          Browser_script.advance t 1.;
          Alcotest.(check string) "the clock moved: the timer's turn" "1 2 3 4" (seen ());
          (* timers in the order they are due, an interval again and again, one cleared never *)
          ignore (Browser_script.eval t {|seen = []; setTimeout(() => seen.push("b"), 20); setTimeout(() => seen.push("a"), 10); const never = setTimeout(() => seen.push("x"), 15); clearTimeout(never);
                                           let n = 0; const every = setInterval(() => { seen.push("i" + ++n); if (n == 3) clearInterval(every) }, 10); requestAnimationFrame(() => seen.push("frame"))|});
          Browser_script.advance t 5.;
          Alcotest.(check string) "nothing due yet" "" (seen ());
          Browser_script.advance t 50.;
          Alcotest.(check string) "by their times, then by the order they were set" "a i1 frame b i2 i3" (seen ());
          (* a timer's own microtasks run before the next timer *)
          ignore (Browser_script.eval t {|seen = []; setTimeout(() => { seen.push("t1"); Promise.resolve().then(() => seen.push("m1")) }, 1); setTimeout(() => seen.push("t2"), 1)|});
          Browser_script.advance t 5.;
          Alcotest.(check string) "each task's microtasks before the next task" "t1 m1 t2" (seen ()));
      Testo.create "LocalStorage, the worked example: names and strings" (fun () ->
          let t = Browser_script.create ~base:"http://site.test/" (Html_tree.of_string "<body></body>") in
          let ask s = match Browser_script.eval t s with Ok v -> Js_value.display v | Error e -> "error: " ^ e.message in
          Alcotest.(check string) "set, got, as a property, counted, by its place"
            {|["dark", null, "dark", 1, "theme"]|}
            (ask {|localStorage.setItem("theme", "dark"); [localStorage.getItem("theme"), localStorage.getItem("nope"), localStorage.theme, localStorage.length, localStorage.key(0)]|});
          Alcotest.(check string) "strings only: a number, an object"
            {|["1", "[object Object]", "{\"a\":1}"]|}
            (ask {|localStorage.setItem("n", 1); localStorage.o = {a: 1}; localStorage.j = JSON.stringify({a: 1}); [localStorage.n, localStorage.getItem("o"), localStorage.j]|});
          Alcotest.(check string) "set again: its value changed, its place kept; removed; cleared"
            {|["light", "theme", 3, 0, undefined]|}
            (ask {|localStorage.setItem("theme", "light"); const a = [localStorage.theme, localStorage.key(0)]; localStorage.removeItem("n"); a.push(localStorage.length); localStorage.clear(); a.push(localStorage.length, localStorage.theme); a|});
          Alcotest.(check string) "sessionStorage: a store of its own" {|[null, "s"]|} (ask {|localStorage.setItem("only", "l"); sessionStorage.setItem("only", "s"); localStorage.clear(); [localStorage.getItem("only"), sessionStorage.getItem("only")]|}));
      Testo.create "a script sends the page elsewhere" (fun () ->
          let t = Browser_script.create ~base:"http://site.test/a/page.html?q=1#top" (Html_tree.of_string "<body></body>") in
          let ask s = match Browser_script.eval t s with Ok v -> Js_value.display v | Error e -> "error: " ^ e.message in
          Alcotest.(check string) "location's parts" {|["http:", "site.test", "/a/page.html", "?q=1", "#top", "http://site.test"]|}
            (ask "[location.protocol, location.host, location.pathname, location.search, location.hash, location.origin]");
          Alcotest.(check (option (pair string bool))) "nowhere yet" None (Browser_script.take_navigation t);
          ignore (ask {|location.href = "next.html"|});
          Alcotest.(check (option (pair string bool))) "href =: there, the page left kept in the history" (Some ("http://site.test/a/next.html", false)) (Browser_script.take_navigation t);
          Alcotest.(check (option (pair string bool))) "taken once" None (Browser_script.take_navigation t);
          ignore (ask {|location.replace("/other")|});
          Alcotest.(check (option (pair string bool))) "replace: in its place" (Some ("http://site.test/other", true)) (Browser_script.take_navigation t);
          ignore (ask {|window.location = "https://else.test/"; location.assign("last")|});
          Alcotest.(check (option (pair string bool))) "the last said wins" (Some ("http://site.test/a/last", false)) (Browser_script.take_navigation t));
      Testo.create "URLSearchParams" (fun () ->
          check "the worked example" {|const p = new URLSearchParams("q=caf%C3%A9+au+lait&lang=fr"); const q = p.get("q");
            p.set("lang", "en"); p.append("page", 2); [q, p.toString(), new URLSearchParams({ a: 1, b: "x y" }).toString()]|}
            {|["café au lait", "q=caf%C3%A9+au+lait&lang=en&page=2", "a=1&b=x+y"]|};
          check "a list: a name several times; gone through as pairs; from pairs, from another, from a ?query" {|
            const p = new URLSearchParams("?a=1&a=2&b=3"); p.delete("b"); p.append("c", "4");
            [p.getAll("a"), p.get("nope"), p.has("c"), [...p].map(kv => kv.join("=")), [...p.keys()], new URLSearchParams([["x", "1"]]).get("x"), new URLSearchParams(p).toString()]|}
            {|[["1", "2"], null, true, ["a=1", "a=2", "c=4"], ["a", "a", "c"], "1", "a=1&a=2&c=4"]|});
      Testo.create "what a page whose scripts run does not show; the script running" (fun () ->
          let t = Browser_script.create (Html_tree.of_string "<body><noscript><p id=no>enable scripts</p></noscript><p id=yes>content</p><script id=me>var mine = document.currentScript.id</script></body>") in
          Browser_script.run_scripts t;
          let ids = List.filter_map (Dom.attribute "id") (Dom.find_all "p" (Browser_script.tree t)) in
          Alcotest.(check (list string)) "a <noscript>'s content is not in the page laid out" [ "yes" ] ids;
          Alcotest.(check string) "document.currentScript, while it runs and after" {|["me", null]|}
            (match Browser_script.eval t "[mine, document.currentScript]" with Ok v -> Js_value.display v | Error e -> e.message);
          check "DOMParser: HTML read into a page of its own" {|const d = new DOMParser().parseFromString("<p class=a>one</p><p>two</p>", "text/html");
            [d.body.children.length, d.querySelector("p.a").textContent, d.querySelectorAll("p").length, document.querySelectorAll("p").length]|}
            {|[2, "one", 2, 0]|});
    ]
