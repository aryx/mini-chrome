  // EventTarget made by a page itself (new EventTarget(), a class that
  // extends it): listeners kept on the object, told in order. An
  // element's own are the browser's (Script_host), found before these
  // -- and reached through these too, when a library calls the
  // prototype's method on an element
  // (EventTarget.prototype.dispatchEvent.call(el, e): Polymer keeps
  // the "native" methods so; the event went to a list of no listener,
  // and a dialog waiting to be told its animation was over waited).
  (function () {
    var P = g.EventTarget && g.EventTarget.prototype;
    if (!P) return;
    // the browser's own method of that name, if this is one of its objects
    function own(o, name) { var f = typeof __host_get === "function" ? __host_get(o, name) : undefined; return typeof f === "function" ? f : null; }
    function listeners(o, type) { var all = o.__listeners || (o.__listeners = {}); return all[type] || (all[type] = []); }
    Object.defineProperty(P, "addEventListener", { value: function (type, f, options) {
      var h = own(this, "addEventListener"); if (h) return h.apply(this, arguments);
      var l = listeners(this, type), self = this;
      if (!f || l.some(function (e) { return e.f === f; })) return;
      l.push({ f: f, once: !!(options && options.once) });
      var signal = options && typeof options === "object" && options.signal;
      if (signal) signal.addEventListener("abort", function () { self.removeEventListener(type, f); });
    }, writable: true, configurable: true });
    Object.defineProperty(P, "removeEventListener", { value: function (type, f) {
      var h = own(this, "removeEventListener"); if (h) return h.apply(this, arguments);
      var all = this.__listeners; if (all && all[type]) all[type] = all[type].filter(function (e) { return e.f !== f; });
    }, writable: true, configurable: true });
    Object.defineProperty(P, "dispatchEvent", { value: function (event) {
      var h = own(this, "dispatchEvent"); if (h) return h.apply(this, arguments);
      var self = this; try { event.target = this; event.currentTarget = this; } catch (e) {}
      listeners(this, event.type).slice().forEach(function (e) {
        if (e.once) self.removeEventListener(event.type, e.f);
        if (typeof e.f === "function") e.f.call(self, event); else if (e.f && e.f.handleEvent) e.f.handleEvent(event);
      });
      return !event.defaultPrevented;
    }, writable: true, configurable: true });
  })();

  // the kinds of lists the DOM gives, as names a page tests against
  // (NodeList.prototype.isPrototypeOf(x)); the lists themselves are arrays
  // the class of window.screen, as a name a page tests against
  global("Screen", function Screen() {});
  // and window.screen is one, which can be listened to (its "change":
  // never said here), as an EventTarget is
  if (typeof screen === "object" && screen) {
    Object.setPrototypeOf(screen, Screen.prototype);
    Screen.prototype.addEventListener = Screen.prototype.removeEventListener = function () {};
    Screen.prototype.dispatchEvent = function () { return true; };
    if (screen.colorDepth === undefined) { screen.colorDepth = screen.pixelDepth = 24; screen.availLeft = screen.availTop = 0; }
  }
  global("NodeList", function NodeList() {});
  global("HTMLCollection", function HTMLCollection() {});

  // window.postMessage (HTML5's cross-document messaging, 2008): a
  // message for a window, told to its "message" listeners in a task
  // of its own. Here a page can only post to itself -- which is how a
  // library gets a task sooner than a timer's, and how two parts of
  // one page that share nothing else talk.
  window.postMessage = function (data, options, transfer) {
    var ports = Array.isArray(transfer) ? transfer : (options && Array.isArray(options.transfer) ? options.transfer : []);
    setTimeout(function () {
      var e = new Event("message");
      e.data = data; e.origin = location.origin; e.source = window; e.ports = ports; e.lastEventId = "";
      window.dispatchEvent(e);
    }, 0);
  };

  // MessageChannel (HTML5's channel messaging): two ports, what is
  // posted on one given to the other's onmessage in a task of its own.
  // Frameworks use it as a timer that is not held back (a scheduler's
  // "as soon as the browser has drawn").
  global("MessageChannel", function MessageChannel() {
    function port() {
      var p = { onmessage: null, _other: null, _listeners: [],
        postMessage: function (data) {
          var to = p._other;
          setTimeout(function () {
            var e = { data: data, target: to, ports: [] };
            if (typeof to.onmessage === "function") to.onmessage(e);
            to._listeners.forEach(function (f) { f(e); });
          }, 0);
        },
        addEventListener: function (type, f) { if (type === "message") p._listeners.push(f); },
        removeEventListener: function (type, f) { p._listeners = p._listeners.filter(function (g) { return g !== f; }); },
        start: function () {}, close: function () {} };
      return p;
    }
    this.port1 = port(); this.port2 = port();
    this.port1._other = this.port2; this.port2._other = this.port1;
  });

