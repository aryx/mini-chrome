
// The DOM's members on its prototypes. An element here answers for its
// own members itself (a host object: src/webapi/dom); a real browser
// has them on Node.prototype, Element.prototype... as accessors and
// methods, and code that reaches under the DOM takes them from there:
//   Object.getOwnPropertyDescriptor(Node.prototype, "firstChild").get.call(node)
// -- a polyfill that keeps "the native one" before putting its own
// (Shady DOM, which YouTube runs in every browser, takes thirty-five
// so). Each is here as a thin one, asking the element itself.
(function () {
  if (typeof __host_get !== "function" || typeof Node !== "function") return;
  var get = __host_get, set = __host_set;
  function accessors(C, names) {
    if (typeof C !== "function") return;
    names.split(" ").forEach(function (k) {
      if (!Object.getOwnPropertyDescriptor(C.prototype, k))
        Object.defineProperty(C.prototype, k, { get: function () { return get(this, k); }, set: function (v) { set(this, k, v); }, configurable: true, enumerable: true });
    });
  }
  function methods(C, names) {
    if (typeof C !== "function") return;
    names.split(" ").forEach(function (k) {
      if (!Object.getOwnPropertyDescriptor(C.prototype, k))
        Object.defineProperty(C.prototype, k, { value: function () { var f = get(this, k); return typeof f === "function" ? f.apply(this, arguments) : undefined; }, writable: true, configurable: true });
    });
  }
  var G = typeof globalThis === "object" ? globalThis : this;
  methods(G.EventTarget, "addEventListener removeEventListener dispatchEvent");
  accessors(G.Node, "parentNode parentElement firstChild lastChild previousSibling nextSibling childNodes textContent nodeType nodeName nodeValue ownerDocument isConnected");
  methods(G.Node, "appendChild insertBefore removeChild replaceChild cloneNode contains hasChildNodes getRootNode compareDocumentPosition isEqualNode isSameNode normalize");
  accessors(G.Element, "children firstElementChild lastElementChild previousElementSibling nextElementSibling childElementCount innerHTML outerHTML id className classList tagName localName namespaceURI attributes shadowRoot slot scrollTop scrollLeft scrollWidth scrollHeight clientWidth clientHeight clientTop clientLeft");
  methods(G.Element, "getAttribute setAttribute removeAttribute hasAttribute toggleAttribute getAttributeNames hasAttributes querySelector querySelectorAll getElementsByTagName getElementsByClassName matches closest attachShadow append prepend before after remove replaceWith replaceChildren insertAdjacentHTML insertAdjacentElement insertAdjacentText getBoundingClientRect getClientRects scrollIntoView focus blur click");
  accessors(G.HTMLElement, "style dataset hidden title lang dir tabIndex innerText offsetParent offsetTop offsetLeft offsetWidth offsetHeight");
  accessors(G.CharacterData, "data length");
  accessors(G.Document, "documentElement body head activeElement children firstElementChild lastElementChild childElementCount readyState defaultView title cookie location URL");
  methods(G.Document, "createElement createElementNS createTextNode createComment createDocumentFragment createEvent createRange createTreeWalker getElementById getElementsByTagName getElementsByClassName getElementsByName querySelector querySelectorAll importNode adoptNode elementFromPoint append prepend");
  accessors(G.DocumentFragment, "children firstElementChild lastElementChild childElementCount");
  methods(G.DocumentFragment, "querySelector querySelectorAll getElementById append prepend");
  accessors(G.ShadowRoot, "host mode innerHTML activeElement");
})();
