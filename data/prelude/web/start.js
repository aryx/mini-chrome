// What a page's scripts expect of a browser beyond the DOM, where it
// can be written over what is already here: small web APIs, in the
// language the pages use. Run once in every page, before its scripts
// (src/dom/Script_prelude.mli).
(function () {
  var g = globalThis;
  function global(name, v) { if (typeof g[name] === "undefined") g[name] = v; }
  // a function that is there so that a page does not stop, and does
  // nothing: said when it is called (with -v, "missing: name()"), for
  // the day a page looks wrong because of it
  function stub(name, value) { return function () { if (typeof __missed === "function") __missed(name); return value; }; }

