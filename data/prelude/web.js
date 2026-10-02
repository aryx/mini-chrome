// What a page's scripts expect of a browser beyond the DOM, where it
// can be written over what is already here: small web APIs, in the
// language the pages use. Run once in every page, before its scripts
// (src/dom/Script_prelude.mli).
(function () {
  var g = globalThis;
  function global(name, v) { if (typeof g[name] === "undefined") g[name] = v; }

  // base64 (RFC 4648): three bytes as four letters. A string here is
  // its bytes, so btoa takes any string and atob gives bytes back
  var letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  global("btoa", function (s) {
    s = String(s);
    var out = "";
    for (var i = 0; i < s.length; i += 3) {
      var a = s.charCodeAt(i), b = s.charCodeAt(i + 1), c = s.charCodeAt(i + 2);
      var n = (a << 16) | ((b || 0) << 8) | (c || 0);
      out += letters[n >> 18] + letters[(n >> 12) & 63] + (i + 1 < s.length ? letters[(n >> 6) & 63] : "=") + (i + 2 < s.length ? letters[n & 63] : "=");
    }
    return out;
  });
  global("atob", function (s) {
    s = String(s).replace(/[\s=]/g, "");
    var out = "", bits = 0, n = 0;
    for (var i = 0; i < s.length; i++) {
      var v = letters.indexOf(s[i]);
      if (v < 0) throw new Error("InvalidCharacterError: the string to be decoded is not correctly encoded");
      n = (n << 6) | v; bits += 6;
      if (bits >= 8) { bits -= 8; out += String.fromCharCode((n >> bits) & 255); }
    }
    return out;
  });

  // text to bytes and back: UTF-8, which a string here already is
  global("TextEncoder", class TextEncoder {
    get encoding() { return "utf-8"; }
    encode(s) {
      s = s === undefined ? "" : String(s);
      var bytes = new Uint8Array(s.length);
      for (var i = 0; i < s.length; i++) bytes[i] = s.charCodeAt(i);
      return bytes;
    }
  });
  global("TextDecoder", class TextDecoder {
    constructor(label) { this.encoding = (label || "utf-8").toLowerCase(); }
    decode(bytes) {
      var s = "";
      if (bytes) for (var i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
      return s;
    }
  });

  // a way to say stop: the controller's abort() tells the signal's
  // listeners, and whoever was given the signal gives up
  class AbortSignal {
    constructor() { this.aborted = false; this.reason = undefined; this.onabort = null; this._listeners = []; }
    addEventListener(type, f) { if (type === "abort") this._listeners.push(f); }
    removeEventListener(type, f) { this._listeners = this._listeners.filter(function (x) { return x !== f; }); }
    throwIfAborted() { if (this.aborted) throw this.reason; }
    _abort(reason) {
      if (this.aborted) return;
      this.aborted = true;
      this.reason = reason === undefined ? new Error("AbortError: signal is aborted without reason") : reason;
      var event = { type: "abort", target: this };
      if (typeof this.onabort === "function") this.onabort(event);
      this._listeners.slice().forEach(function (f) { f(event); });
    }
    static abort(reason) { var s = new AbortSignal(); s._abort(reason); return s; }
    static timeout(ms) { var s = new AbortSignal(); setTimeout(function () { s._abort(new Error("TimeoutError: signal timed out")); }, ms); return s; }
    static any(signals) {
      var s = new AbortSignal();
      signals.forEach(function (other) { if (other.aborted) s._abort(other.reason); else other.addEventListener("abort", function () { s._abort(other.reason); }); });
      return s;
    }
  }
  global("AbortSignal", AbortSignal);
  global("AbortController", class AbortController {
    constructor() { this.signal = new AbortSignal(); }
    abort(reason) { this.signal._abort(reason); }
  });

  // a copy all the way down: arrays, plain objects, dates, maps and
  // sets; a function cannot be copied, as the standard has it
  global("structuredClone", function (value) {
    var seen = new Map();
    function copy(v) {
      if (typeof v === "function") throw new Error("DataCloneError: a function could not be cloned");
      if (v === null || typeof v !== "object") return v;
      if (seen.has(v)) return seen.get(v);
      var out;
      if (Array.isArray(v)) { out = []; seen.set(v, out); v.forEach(function (x, i) { out[i] = copy(x); }); return out; }
      if (v instanceof Date) return new Date(v.getTime());
      if (v instanceof Map) { out = new Map(); seen.set(v, out); v.forEach(function (x, k) { out.set(copy(k), copy(x)); }); return out; }
      if (v instanceof Set) { out = new Set(); seen.set(v, out); v.forEach(function (x) { out.add(copy(x)); }); return out; }
      out = {}; seen.set(v, out);
      Object.keys(v).forEach(function (k) { out[k] = copy(v[k]); });
      return out;
    }
    return copy(value);
  });

  global("reportError", function (e) { console.error("Uncaught " + (e && e.stack ? e.name + ": " + e.message : e)); });
  global("requestIdleCallback", function (f) {
    return setTimeout(function () { f({ didTimeout: false, timeRemaining: function () { return 50; } }); }, 1);
  });
  global("cancelIdleCallback", function (id) { clearTimeout(id); });

  // random numbers for a page: Math.random's here, not the kernel's
  // (a page run twice does the same)
  global("crypto", {
    getRandomValues: function (a) { for (var i = 0; i < a.length; i++) a[i] = Math.floor(Math.random() * 256); return a; },
    randomUUID: function () {
      return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function (c) {
        var r = Math.floor(Math.random() * 16);
        return (c === "x" ? r : (r & 3) | 8).toString(16);
      });
    }
  });

  // a request's or an answer's headers: names whatever their case
  global("Headers", class Headers {
    constructor(init) {
      this._h = {};
      var self = this;
      if (init instanceof Headers) init.forEach(function (v, k) { self.append(k, v); });
      else if (Array.isArray(init)) init.forEach(function (pair) { self.append(pair[0], pair[1]); });
      else if (init) Object.keys(init).forEach(function (k) { self.append(k, init[k]); });
    }
    append(k, v) { k = String(k).toLowerCase(); this._h[k] = k in this._h ? this._h[k] + ", " + v : String(v); }
    set(k, v) { this._h[String(k).toLowerCase()] = String(v); }
    get(k) { k = String(k).toLowerCase(); return k in this._h ? this._h[k] : null; }
    has(k) { return String(k).toLowerCase() in this._h; }
    delete(k) { delete this._h[String(k).toLowerCase()]; }
    forEach(f, self) { var h = this._h, me = this; Object.keys(h).sort().forEach(function (k) { f.call(self, h[k], k, me); }); }
    keys() { return Object.keys(this._h).sort()[Symbol.iterator](); }
    values() { var h = this._h; return Object.keys(h).sort().map(function (k) { return h[k]; })[Symbol.iterator](); }
    entries() { var h = this._h; return Object.keys(h).sort().map(function (k) { return [k, h[k]]; })[Symbol.iterator](); }
    [Symbol.iterator]() { return this.entries(); }
  });

  // a form's fields as a script builds them
  global("FormData", class FormData {
    constructor() { this._f = []; }
    append(k, v) { this._f.push([String(k), String(v)]); }
    set(k, v) { this.delete(k); this.append(k, v); }
    get(k) { var f = this._f.find(function (p) { return p[0] === String(k); }); return f ? f[1] : null; }
    getAll(k) { return this._f.filter(function (p) { return p[0] === String(k); }).map(function (p) { return p[1]; }); }
    has(k) { return this._f.some(function (p) { return p[0] === String(k); }); }
    delete(k) { this._f = this._f.filter(function (p) { return p[0] !== String(k); }); }
    forEach(f, self) { var me = this; this._f.forEach(function (p) { f.call(self, p[1], p[0], me); }); }
    entries() { return this._f.slice()[Symbol.iterator](); }
    keys() { return this._f.map(function (p) { return p[0]; })[Symbol.iterator](); }
    values() { return this._f.map(function (p) { return p[1]; })[Symbol.iterator](); }
    [Symbol.iterator]() { return this.entries(); }
  });

  // one language and one way to write a number or a date: what a page
  // asks of Intl is answered, in English
  if (typeof g.Intl === "undefined") {
    var options = function () { return { locale: "en-US", timeZone: "UTC", calendar: "gregory", numberingSystem: "latn" }; };
    var supported = function () { return ["en-US"]; };
    g.Intl = {
      DateTimeFormat: class DateTimeFormat {
        format(d) { return (d === undefined ? new Date() : new Date(d)).toString(); }
        formatToParts(d) { return [{ type: "literal", value: this.format(d) }]; }
        resolvedOptions() { return options(); }
        static supportedLocalesOf() { return supported(); }
      },
      NumberFormat: class NumberFormat {
        format(n) { return String(n); }
        formatToParts(n) { return [{ type: "integer", value: String(n) }]; }
        resolvedOptions() { return options(); }
        static supportedLocalesOf() { return supported(); }
      },
      PluralRules: class PluralRules {
        select(n) { return n === 1 ? "one" : "other"; }
        resolvedOptions() { return options(); }
        static supportedLocalesOf() { return supported(); }
      },
      RelativeTimeFormat: class RelativeTimeFormat {
        format(n, unit) { var u = Math.abs(n) === 1 ? unit : unit + "s"; return n < 0 ? -n + " " + u + " ago" : "in " + n + " " + u; }
        resolvedOptions() { return options(); }
        static supportedLocalesOf() { return supported(); }
      },
      ListFormat: class ListFormat {
        format(items) { items = Array.from(items); return items.length < 3 ? items.join(" and ") : items.slice(0, -1).join(", ") + ", and " + items[items.length - 1]; }
        static supportedLocalesOf() { return supported(); }
      },
      Collator: class Collator {
        compare(a, b) { return a < b ? -1 : a > b ? 1 : 0; }
        resolvedOptions() { return options(); }
        static supportedLocalesOf() { return supported(); }
      },
      getCanonicalLocales: function (l) { return l === undefined ? [] : [].concat(l); }
    };
  }

  // ---- what a page asks of its document, its elements and its window,
  // where an answer can be given without the browser's insides ----

  function method(proto, name, f) { if (proto && !(name in proto)) Object.defineProperty(proto, name, { value: f, writable: true, configurable: true }); }
  function getter(proto, name, f, set) { if (proto && !(name in proto)) Object.defineProperty(proto, name, { get: f, set: set || function () {}, configurable: true }); }
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
  getter(D, "fullscreenEnabled", function () { return false; });
  getter(D, "adoptedStyleSheets", function () { return []; });
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
    return {
      root: root, currentNode: root,
      nextNode: function () {
        for (var n = next(this.currentNode); n; n = next(n))
          if ((show >> (n.nodeType - 1)) & 1 && accept(n) === 1) { this.currentNode = n; return n; }
        return null;
      }
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
  method(E, "animate", function () {
    return { finished: Promise.resolve(), ready: Promise.resolve(), playState: "finished", onfinish: null, cancel: nothing, finish: nothing, play: nothing, pause: nothing, addEventListener: nothing, removeEventListener: nothing };
  });
  method(E, "requestFullscreen", function () { return Promise.reject(new TypeError("fullscreen is not supported")); });
  method(E, "setPointerCapture", nothing);
  method(E, "releasePointerCapture", nothing);
  method(E, "hasPointerCapture", function () { return false; });
  method(E, "scrollTo", nothing);
  method(E, "scrollBy", nothing);
  reflects(E, "role", "role");
  reflects(E, "nonce", "nonce");
  reflects(E, "slot", "slot");
  reflects(E, "ariaLabel", "aria-label");
  reflects(E, "ariaHidden", "aria-hidden");
  reflects(E, "ariaExpanded", "aria-expanded");
  getter(E, "draggable", function () { return this.getAttribute("draggable") === "true"; }, function (v) { this.setAttribute("draggable", String(!!v)); });
  getter(E, "inert", function () { return this.hasAttribute("inert"); }, function (v) { this.toggleAttribute("inert", !!v); });
  getter(E, "contentEditable", function () { return this.getAttribute("contenteditable") || "inherit"; }, function (v) { this.setAttribute("contenteditable", v); });
  getter(E, "isContentEditable", function () { return this.getAttribute("contenteditable") === "true"; });
  getter(E, "shadowRoot", function () { return null; });
  getter(E, "assignedSlot", function () { return null; });

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
