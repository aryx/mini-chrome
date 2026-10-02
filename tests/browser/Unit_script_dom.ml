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
          check "no boxes for a script" ~html:list {|const r = document.getElementById("l").getBoundingClientRect(); [r.width, r.top, document.body.offsetWidth]|} "[0, 0, 0]");
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
          check "storage, observers, matchMedia, history: there, and quiet"
            {|localStorage.setItem("k", 1); localStorage.other = "o";
              const o = new MutationObserver(() => {}); o.observe(document.body, { childList: true }); o.disconnect();
              history.pushState({}, "", "/x");
              [localStorage.getItem("k"), localStorage.getItem("nope"), localStorage.length, sessionStorage.length, matchMedia("(min-width: 1px)").matches, typeof performance.now(), typeof requestAnimationFrame]|}
            {|["1", null, 2, 0, false, "number", "function"]|});
    ]
