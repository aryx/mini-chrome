  // what a tree walker is told to show, and what its filter answers
  // IntersectionObserver (Chrome 51, 2016): told when an element comes
  // into view -- how a page puts a picture's address in only when it
  // is about to be seen ("lazy loading"), and asks for a list's next
  // page when its end is, where scripts once listened to every
  // scroll. Here an element is in view when its box is within a
  // window's height of the window: looked at a moment after it is
  // observed, then twice a second while some wait (the wheel tells no
  // script), and told once. When all was said to be in view, a list
  // without end grew without end (YouTube's results).
  var waiting = [], looking = false;
  var look = function () {
    looking = false;
    var still = [], told = [];
    waiting.forEach(function (w) {
      if (w.observer._observed.indexOf(w.element) < 0) return;
      var box = w.element.getBoundingClientRect();
      if (box.top > 2 * innerHeight || box.bottom < -innerHeight) { still.push(w); return; }
      // a picture with no address yet has no height, and a page asks
      // that what is seen of it have some (YouTube's thumbnails)
      var seen = box.height > 0 ? box : { x: box.x, y: box.y, left: box.left, top: box.top, right: box.right, bottom: box.top + 1, width: box.width, height: 1 };
      told.push([w.observer, Object.assign(new IntersectionObserverEntry(), { target: w.element, isIntersecting: true, intersectionRatio: 1, boundingClientRect: box, intersectionRect: seen, rootBounds: null, time: performance.now() })]);
    });
    waiting = still;
    told.forEach(function (t) { try { t[0]._callback([t[1]], t[0]); } catch (e) { console.error(e); } });
    watch(500);
  };
  var watch = function (delay) { if (waiting.length && !looking) { looking = true; setTimeout(look, delay); } };
  g.IntersectionObserver = class IntersectionObserver {
    constructor(callback, options) {
      this._callback = callback; this._observed = [];
      this.root = (options && options.root) || null; this.rootMargin = (options && options.rootMargin) || "0px"; this.thresholds = [0];
    }
    observe(element) {
      if (this._observed.indexOf(element) >= 0) return;
      this._observed.push(element);
      waiting.push({ observer: this, element: element });
      watch(0);
    }
    unobserve(element) { this._observed = this._observed.filter(function (e) { return e !== element; }); }
    disconnect() { this._observed = []; }
    takeRecords() { return []; }
  };
  // MutationObserver (2012): told, in a microtask, of what changed
  // in the nodes it observes. Before promises it was the one way to
  // run something "right after this script": change a text node
  // nobody sees and be told of it -- which Polymer still does for its
  // every debounced job (YouTube's lists fill that way), and Vue 2
  // where it finds no promise. That is the part done here: a text
  // node's data changed (the browser calls __mutated). A child added
  // or an attribute set is not told yet.
  var observers = [];
  g.MutationObserver = class MutationObserver {
    constructor(callback) { this._callback = callback; this._targets = []; this._records = []; }
    observe(target, options) {
      this._targets.push({ target: target, options: options || {} });
      target.__observed = true;
      if (observers.indexOf(this) < 0) observers.push(this);
    }
    disconnect() { this._targets = []; this._records = []; observers = observers.filter(function (o) { return o !== this; }, this); }
    takeRecords() { var records = this._records; this._records = []; return records; }
  };
  g.__mutated = function (target, type) {
    observers.slice().forEach(function (o) {
      if (!o._targets.some(function (t) { return t.target === target && t.options[type]; })) return;
      o._records.push({ type: type, target: target, addedNodes: [], removedNodes: [], previousSibling: null, nextSibling: null, attributeName: null, oldValue: null });
      if (o._records.length == 1) queueMicrotask(function () { var records = o.takeRecords(); if (records.length) o._callback(records, o); });
    });
  };
  // what the observer tells, as a class: a page looks for its
  // prototype's members before it trusts the observer, and brings its
  // own (the W3C's polyfill, which YouTube has) when they are not there
  g.IntersectionObserverEntry = class IntersectionObserverEntry {};
  IntersectionObserverEntry.prototype.intersectionRatio = 0;
  IntersectionObserverEntry.prototype.isIntersecting = false;
  // Range, as a name: new Range() is what document.createRange() gives
  global("Range", function Range() { return document.createRange(); });
