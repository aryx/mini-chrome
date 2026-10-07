  // Custom elements: a name with a dash given a class
  // (customElements.define("user-card", class extends HTMLElement {})).
  // An element of that name is *upgraded*: the class's prototype made
  // its own, the class's constructor run on it, then its callbacks --
  // attributeChangedCallback for the attributes the class observes,
  // connectedCallback when it is in the page. It is there that a
  // component attaches its shadow tree (libs/dom/Shadow_tree.mli). The
  // browser says when an element enters the page (__connected).
  // An attribute set or removed later by setAttribute and
  // removeAttribute is told too (__attribute).
  // Not done: new UserCard() (an element is made by its name), the
  // callback of an element removed.
  (function () {
    var classes = {}, waiting = {};
    function upgrade(el) {
      var C = classes[el.localName];
      if (!C || el.__upgraded) return;
      el.__upgraded = true;
      Object.setPrototypeOf(el, C.prototype);
      try {
        C.call(el);
        if (el.attributeChangedCallback) (C.observedAttributes || []).forEach(function (a) {
          if (el.hasAttribute(a)) el.attributeChangedCallback(a, null, el.getAttribute(a));
        });
        if (el.isConnected && el.connectedCallback) el.connectedCallback();
      } catch (e) { console.error(e); }
    }
    function under(node) {
      var all = node.querySelectorAll ? Array.from(node.querySelectorAll("*")) : [];
      if (node.nodeType === 1) all.unshift(node);
      // and in the shadow trees of those
      all.slice().forEach(function (el) { if (el.shadowRoot) all = all.concat(under(el.shadowRoot)); });
      return all;
    }
    g.customElements = {
      define: function (name, C) {
        if (classes[name]) throw new DOMException("the name \"" + name + "\" has already been used with this registry", "NotSupportedError");
        classes[name] = C;
        // those of that name now in the page: asked of the browser,
        // which has them without a list of all the others. Simply:
        //   under(document.documentElement).forEach(function (el) { if (el.localName === name) upgrade(el); });
        __named(name).forEach(upgrade);
        (waiting[name] || []).forEach(function (resolve) { resolve(C); });
        delete waiting[name];
      },
      get: function (name) { return classes[name]; },
      getName: function (C) { for (var name in classes) if (classes[name] === C) return name; return null; },
      whenDefined: function (name) {
        if (classes[name]) return Promise.resolve(classes[name]);
        return new Promise(function (resolve) { (waiting[name] = waiting[name] || []).push(resolve); });
      },
      upgrade: function (root) { under(root).forEach(upgrade); }
    };
    // an attribute set or removed later, said by the browser
    g.__attribute = function (el, name, old, now) {
      var C = classes[el.localName];
      if (!C || !el.attributeChangedCallback || (C.observedAttributes || []).indexOf(name) < 0) return;
      // not in a <template>'s content (Polymer writes its bindings
      // there as attributes, "[[data]]", and takes them away)
      if (el.getRootNode().__inert) return;
      el.attributeChangedCallback(name, old, now);
    };
    g.__connected = function (node) {
      under(node).forEach(function (el) {
        if (!classes[el.localName]) return;
        if (!el.__upgraded) upgrade(el);
        else if (el.connectedCallback) try { el.connectedCallback(); } catch (e) { console.error(e); }
      });
    };
    // an element made by a script is upgraded at once: its methods are
    // there before it is put in the page (document.createElement tells)
    g.__created = upgrade;
  })();
  global("DOMException", class DOMException extends Error { constructor(message, name) { super(message); this.name = name || "Error"; } });
  method(E, "scrollTo", nothing);
  method(E, "scrollBy", nothing);
  reflects(E, "role", "role");
  reflects(E, "nonce", "nonce");
  reflects(E, "slot", "slot");
  reflects(E, "ariaLabel", "aria-label");
  reflects(E, "ariaHidden", "aria-hidden");
  reflects(E, "ariaExpanded", "aria-expanded");
  // a <style>'s sheet: the object a script adds rules through, one at
  // a time (sheet.insertRule: how a CSS-in-JS library writes a
  // component's style when it is first drawn -- styled-components,
  // Emotion). Its rules are written after the element's own text.
  getter(E, "sheet", function () {
    if (this.tagName !== "STYLE") return null;
    if (!this.__sheet) { var s = new CSSStyleSheet(); s._style = this; s._text = this.textContent; s.ownerNode = this; this.__sheet = s; }
    return this.__sheet;
  });
  getter(D, "styleSheets", function () { return Array.prototype.map.call(this.querySelectorAll("style"), function (s) { return s.sheet; }); });
  getter(E, "draggable", function () { return this.getAttribute("draggable") === "true"; }, function (v) { this.setAttribute("draggable", String(!!v)); });
  getter(E, "inert", function () { return this.hasAttribute("inert"); }, function (v) { this.toggleAttribute("inert", !!v); });
  getter(E, "contentEditable", function () { return this.getAttribute("contenteditable") || "inherit"; }, function (v) { this.setAttribute("contenteditable", v); });
  getter(E, "isContentEditable", function () { return this.getAttribute("contenteditable") === "true"; });
  getter(E, "assignedSlot", function () { return null; });
  // a <slot>'s nodes: its host's children that name it (slot="name"),
  // or that name none for the slot with no name
  method(E, "assignedNodes", function () {
    var root = this.getRootNode ? this.getRootNode() : null, host = root && root.host;
    if (!host) return [];
    var name = this.getAttribute("name") || "";
    return Array.prototype.filter.call(host.childNodes, function (n) {
      return (n.nodeType === 1 || n.nodeType === 3) && ((n.nodeType === 1 && n.getAttribute("slot")) || "") === name;
    });
  });
  method(E, "assignedElements", function () { return this.assignedNodes().filter(function (n) { return n.nodeType === 1; }); });

  if (typeof navigator === "object") {
    var browser = {
      languages: ["en-US", "en"], onLine: true, cookieEnabled: true, platform: "Linux x86_64", vendor: "", product: "Gecko",
      appName: "Netscape", appVersion: "5.0", hardwareConcurrency: 1, maxTouchPoints: 0, doNotTrack: null, webdriver: false,
      plugins: [], mimeTypes: [], sendBeacon: function () { return true; }
    };
    Object.keys(browser).forEach(function (k) { if (!(k in navigator)) navigator[k] = browser[k]; });
  }
  if (typeof performance === "object") {
    var empty = function () { return []; };
    ["getEntries", "getEntriesByType", "getEntriesByName"].forEach(function (k) { if (!(k in performance)) performance[k] = empty; });
    ["clearMarks", "clearMeasures", "clearResourceTimings"].forEach(function (k) { if (!(k in performance)) performance[k] = nothing; });
    if (!("timing" in performance)) performance.timing = { navigationStart: Date.now() };
    if (!("navigation" in performance)) performance.navigation = { type: 0, redirectCount: 0 };
  }
  if (typeof history === "object" && !("scrollRestoration" in history)) history.scrollRestoration = "auto";
  global("visualViewport", { width: g.innerWidth, height: g.innerHeight, scale: 1, offsetLeft: 0, offsetTop: 0, pageLeft: 0, pageTop: 0, addEventListener: nothing, removeEventListener: nothing });
})();
