  // ---- what a page asks of its document, its elements and its window,
  // where an answer can be given without the browser's insides ----

  function method(proto, name, f) { if (proto && !(name in proto)) Object.defineProperty(proto, name, { value: f, writable: true, configurable: true }); }
  function getter(proto, name, f, set) { if (proto && !(name in proto)) Object.defineProperty(proto, name, { get: f, set: set || function (v) { if (typeof __host_set === "function") __host_set(this, name, v); }, configurable: true }); }
  // a property that is an attribute: el.role is role="..."
  function reflects(proto, name, attribute) {
    getter(proto, name, function () { return this.getAttribute(attribute); }, function (v) { this.setAttribute(attribute, v); });
  }
  var nothing = function () {};

  var D = typeof Document === "undefined" ? null : Document.prototype;
  getter(D, "domain", function () { return location.hostname; });
  getter(D, "baseURI", function () { return location.href; });
  getter(D, "contentType", function () { return "text/html"; });
  getter(D, "dir", function () { return ""; });
  getter(D, "scrollingElement", function () { return this.documentElement; });
  // document.all (Internet Explorer 4's, 1997: every element of the
  // page): kept by the standard as a thing no page should use, and
  // still compared with -- "x === document.all" must not be true of
  // an x that is undefined, which it is if there is no such thing
  getter(D, "all", function () { return this.querySelectorAll("*"); });
  getter(D, "fullscreenEnabled", function () { return false; });
  // CSSStyleSheet made by a script (Constructable Stylesheets, Chrome
  // 73, 2019): a sheet with no element, given its text by replaceSync
  // and put on the page by document.adoptedStyleSheets = [sheet] --
  // how a component library shares one sheet between its components.
  // Here each adopted sheet is a <style> of the head, kept up to date.
  (function () {
    function CSSStyleSheet() { this._text = ""; this._rules = []; this._style = null; this.cssRules = this._rules; this.disabled = false; }
    var P = CSSStyleSheet.prototype;
    // a rule is an object with its text (cssRules[i].cssText)
    P._sync = function () { if (this._style) this._style.textContent = this._text + "\n" + this._rules.map(function (r) { return r.cssText; }).join("\n"); };
    P.replaceSync = function (text) { this._text = String(text); this._rules.length = 0; this._sync(); };
    P.replace = function (text) { this.replaceSync(text); return Promise.resolve(this); };
    P.insertRule = function (rule, index) {
      index = index === undefined ? 0 : index;
      rule = String(rule);
      this._rules.splice(index, 0, { cssText: rule, selectorText: rule.split("{")[0].trim(), type: 1, parentStyleSheet: this });
      this._sync();
      return index;
    };
    P.deleteRule = function (index) { this._rules.splice(index, 1); this._sync(); };
    g.CSSStyleSheet = CSSStyleSheet;
    var adopted = [];
    getter(D, "adoptedStyleSheets", function () { return adopted; });
    // document.adoptedStyleSheets = sheets (the document tells us: Script_document)
    g.__adopt = function (sheets) {
      var doc = document;
      adopted.forEach(function (s) { if (Array.prototype.indexOf.call(sheets, s) < 0 && s._style) { s._style.remove(); s._style = null; } });
      adopted = Array.prototype.slice.call(sheets);
      adopted.forEach(function (s) {
        if (!s._style && doc.head) { s._style = doc.createElement("style"); s._style.setAttribute("data-adopted", ""); doc.head.appendChild(s._style); }
        if (s._sync) s._sync();
      });
    };
  })();
  getter(D, "fonts", function () { return { ready: Promise.resolve(), status: "loaded", addEventListener: nothing, removeEventListener: nothing, load: function () { return Promise.resolve([]); }, check: function () { return true; } }; });
  method(D, "importNode", function (node, deep) { return node.cloneNode(deep); });
  method(D, "adoptNode", function (node) { return node; });
  method(D, "getSelection", function () { return getSelection(); });
  method(D, "hasFocus", function () { return true; });
  method(D, "elementFromPoint", function () { return null; });
  method(D, "elementsFromPoint", function () { return []; });
  method(D, "execCommand", function () { return false; });
  method(D, "write", nothing);
  method(D, "writeln", nothing);
  method(D, "open", nothing);
  method(D, "close", nothing);
  // the nodes under a root, one after the other in the document's
  // order, those a filter keeps: a walk a script steps through
  method(D, "createTreeWalker", function (root, whatToShow, filter) {
    var show = whatToShow === undefined ? 0xffffffff : whatToShow;
    var accept = typeof filter === "function" ? filter : filter && filter.acceptNode ? function (n) { return filter.acceptNode(n); } : function () { return 1; };
    function next(n) {
      if (n.firstChild) return n.firstChild;
      while (n && n !== root) { if (n.nextSibling) return n.nextSibling; n = n.parentNode; }
      return null;
    }
    // 1 a node is the walk's, 2 nor it nor what is under it, 3 not it
    // but what is under it
    function kept(n) { return (show >> (n.nodeType - 1)) & 1 ? accept(n) : 3; }
    // the walk's children of a node: its own that are kept, and those
    // of the ones skipped
    function kids(n) {
      var out = [];
      for (var c = n.firstChild; c; c = c.nextSibling) {
        var k = kept(c);
        if (k === 1) out.push(c); else if (k !== 2) out = out.concat(kids(c));
      }
      return out;
    }
    function parent(n) {
      for (n = n === root ? null : n.parentNode; n; n = n === root ? null : n.parentNode) if (n === root || kept(n) === 1) return n;
      return null;
    }
    function to(walker, n) { if (n) walker.currentNode = n; return n || null; }
    function sibling(walker, by) {
      var p = parent(walker.currentNode);
      if (!p) return null;
      var all = kids(p);
      return to(walker, all[all.indexOf(walker.currentNode) + by]);
    }
    return {
      root: root, currentNode: root, whatToShow: show, filter: filter || null,
      nextNode: function () {
        for (var n = next(this.currentNode); n; n = next(n))
          if (kept(n) === 1) { this.currentNode = n; return n; }
        return null;
      },
      // the one before in the document's order: found from the root
      previousNode: function () {
        var last = null;
        for (var n = root; n && n !== this.currentNode; n = next(n)) if (n === root || kept(n) === 1) last = n;
        return this.currentNode === root ? null : to(this, last);
      },
      firstChild: function () { return to(this, kids(this.currentNode)[0]); },
      lastChild: function () { var all = kids(this.currentNode); return to(this, all[all.length - 1]); },
      nextSibling: function () { return sibling(this, 1); },
      previousSibling: function () { return this.currentNode === root ? null : sibling(this, -1); },
      parentNode: function () { return to(this, parent(this.currentNode)); }
    };
  });
  method(D, "createNodeIterator", D && D.createTreeWalker);
  method(D, "createRange", function () {
    var doc = this;
    return {
      collapsed: true, startContainer: doc, endContainer: doc, startOffset: 0, endOffset: 0, commonAncestorContainer: doc,
      setStart: nothing, setEnd: nothing, setStartBefore: nothing, setEndAfter: nothing, selectNode: nothing, selectNodeContents: nothing,
      collapse: nothing, detach: nothing, deleteContents: nothing, insertNode: nothing, cloneRange: function () { return this; },
      getBoundingClientRect: function () { return { x: 0, y: 0, top: 0, left: 0, right: 0, bottom: 0, width: 0, height: 0 }; },
      getClientRects: function () { return []; },
      // a text of HTML made nodes: what a library that builds from strings asks
      createContextualFragment: function (html) {
        var holder = doc.createElement("div"), fragment = doc.createDocumentFragment();
        holder.innerHTML = html;
        while (holder.firstChild) fragment.appendChild(holder.firstChild);
        return fragment;
      }
    };
  });

  var E = typeof Element === "undefined" ? null : Element.prototype;
  method(E, "isSameNode", function (other) { return this === other; });
  method(E, "isEqualNode", function (other) { return !!other && this.outerHTML === other.outerHTML; });
  method(E, "checkVisibility", function () { return true; });
  method(E, "getAnimations", function () { return []; });
