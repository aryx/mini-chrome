  // el.animate(keyframes, timing) (Web Animations, Chrome 36, 2014):
  // an animation here is over as soon as it starts -- the element is
  // where its own style has it, which is where an animation that
  // keeps nothing ends -- and says so a moment later: its finished
  // promise, onfinish, its "finish" listeners. A dialog that fades
  // away waits for that to take itself out (Polymer's; YouTube's
  // stayed on the page). It has every member the W3C's polyfill looks
  // for, which then leaves it alone.
  method(E, "animate", function (keyframes, timing) {
    var listeners = [], done = false, settle;
    var a = {
      id: "", effect: null, timeline: null, currentTime: 0, startTime: 0, playbackRate: 1, playState: "running", pending: false, onfinish: null, oncancel: null,
      ready: Promise.resolve(),
      play: nothing, pause: nothing, reverse: nothing, updatePlaybackRate: nothing, commitStyles: nothing, persist: nothing,
      addEventListener: function (type, f) { if (type === "finish") listeners.push(f); },
      removeEventListener: function (type, f) { listeners = listeners.filter(function (g) { return g !== f; }); },
      cancel: function () { done = true; a.playState = "idle"; },
      finish: function () {
        if (done) return;
        done = true; a.playState = "finished";
        var e = new Event("finish"); e.currentTime = a.currentTime;
        settle(a);
        if (typeof a.onfinish === "function") a.onfinish(e);
        listeners.slice().forEach(function (f) { f.call(a, e); });
      }
    };
    a.finished = new Promise(function (resolve) { settle = resolve; });
    setTimeout(a.finish, 0);
    return a;
  });
  method(E, "requestFullscreen", function () { return Promise.reject(new TypeError("fullscreen is not supported")); });
  method(E, "setPointerCapture", nothing);
  method(E, "releasePointerCapture", nothing);
  method(E, "hasPointerCapture", function () { return false; });
  // an <svg>'s point and matrix: how a program turns the pointer's
  // place in the window into its drawing's units,
  // pt.matrixTransform(svg.getScreenCTM().inverse()) -- for an svg
  // that fills the window (the Playground's), its viewBox fitted in it
  function matrix(a, d, e, f) {
    return { a: a, b: 0, c: 0, d: d, e: e, f: f, inverse: function () { return matrix(1 / a, 1 / d, -e / a, -f / d); } };
  }
  function point(x, y) {
    return { x: x, y: y, matrixTransform: function (m) { return point(m.a * this.x + m.e, m.d * this.y + m.f); } };
  }
  method(E, "createSVGPoint", function () { return point(0, 0); });
  method(E, "getScreenCTM", function () {
    var box = String(this.getAttribute("viewBox") || this.getAttribute("viewbox") || "").split(/[ ,]+/).map(Number);
    if (box.length !== 4 || !(box[2] > 0) || !(box[3] > 0)) return matrix(1, 1, 0, 0);
    var k = Math.min(innerWidth / box[2], innerHeight / box[3]);
    return matrix(k, k, (innerWidth - box[2] * k) / 2 - box[0] * k, (innerHeight - box[3] * k) / 2 - box[1] * k);
  });
  // a <canvas> not drawn yet: a script that draws on one goes on, and
  // its picture is empty (docs/plans/plan_tinybox.md, "later")
  method(E, "getContext", function () {
    var canvas = this, context = { canvas: canvas };
    if (typeof __missed === "function") __missed("canvas.getContext (nothing is drawn)");
    ["putImageData", "drawImage", "fillRect", "clearRect", "strokeRect", "beginPath", "closePath", "moveTo", "lineTo", "arc", "rect", "fill", "stroke",
     "fillText", "strokeText", "save", "restore", "translate", "rotate", "scale", "setTransform", "clip"].forEach(function (k) { context[k] = nothing; });
    context.measureText = function (text) { return { width: 8 * String(text).length }; };
    context.getImageData = context.createImageData = function (x, y, w, h) { return new ImageData(w || x, h || y); };
    return context;
  });
  method(E, "toDataURL", function () { return "data:,"; });
  // a canvas of no page (a worker's, a picture made aside): the same
  // one, not drawn either
  global("OffscreenCanvas", function OffscreenCanvas(width, height) {
    var canvas = document.createElement("canvas");
    this.width = width; this.height = height;
    this.getContext = function () { var c = canvas.getContext.apply(canvas, arguments); c.canvas = this; return c; };
  });
  global("ImageData", function ImageData(data, width, height) {
    if (typeof data === "number") { this.width = data; this.height = width; this.data = new Uint8ClampedArray(4 * data * width); }
    else { this.data = data; this.width = width; this.height = height; }
  });
  // Web Audio, the least of it: a context, its clock, a buffer of
  // samples and its source started at a time (AudioContext.mli); the
  // clock and the playing are the browser's (__audio)
  if (typeof __audio === "object") {
    global("AudioContext", class AudioContext {
      constructor() { this.state = "running"; this.sampleRate = 44100; this.destination = { context: this }; this.baseLatency = 0; this.outputLatency = 0; }
      get currentTime() { return __audio.now(); }
      resume() { this.state = "running"; return Promise.resolve(); }
      suspend() { return Promise.resolve(); }
      close() { this.state = "closed"; return Promise.resolve(); }
      createBuffer(channels, length, rate) {
        var data = [];
        for (var c = 0; c < channels; c++) data.push(new Float32Array(length));
        return { numberOfChannels: channels, length: length, sampleRate: rate, duration: length / rate, getChannelData: function (c) { return data[c]; } };
      }
      createBufferSource() {
        return {
          buffer: null, onended: null, connect: function (to) { return to; }, disconnect: nothing, stop: nothing,
          start: function (when) {
            var b = this.buffer;
            if (b) __audio.play(b.getChannelData(0), b.getChannelData(b.numberOfChannels > 1 ? 1 : 0), b.sampleRate, when || 0);
          }
        };
      }
    });
    global("webkitAudioContext", g.AudioContext);
  }
  // an SVG element's attribute that can be animated (its href, its
  // class): asked by instanceof, never made here
  global("SVGAnimatedString", function SVGAnimatedString() {});
