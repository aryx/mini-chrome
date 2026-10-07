  // CSS: what a script asks of the style engine. supports() says no
  // (a library then takes its older way); escape() makes a name safe
  // in a selector
  global("CSS", {
    supports: function () { return false; },
    escape: function (s) { return String(s).replace(/[^a-zA-Z0-9_\-\u00a0-\uffff]/g, function (c) { return "\\" + c; }); }
  });
  global("NodeFilter", { SHOW_ALL: -1, SHOW_ELEMENT: 1, SHOW_TEXT: 4, SHOW_COMMENT: 128, FILTER_ACCEPT: 1, FILTER_REJECT: 2, FILTER_SKIP: 3 });
  // a <template>'s content: its children, in a fragment of their own
  // (what cloneNode and importNode copy into the page)
  getter(E, "content", function () {
    if (this.localName !== "template") return undefined;
    if (!this.__content) {
      var f = document.createDocumentFragment();
      while (this.firstChild) f.appendChild(this.firstChild);
      // of a document of its own in a browser, where no element is a
      // custom one: here marked, for the registry to leave it alone
      f.__inert = true;
      this.__content = f;
    }
    return this.__content;
  });

  // A table as its rows and cells (DOM Level 1's HTMLTableElement):
  // table.rows, a section's rows, a row's cells, and where each is.
  // Gmail's list is a table, and a click is read as "which cell of
  // this row": row.cells[i].
  function kids(el, names) { return Array.prototype.filter.call(el.children, function (c) { return names.indexOf(c.localName) >= 0; }); }
  function table_rows(t) {
    var rows = [];
    kids(t, ["thead"]).forEach(function (g) { rows = rows.concat(kids(g, ["tr"])); });
    Array.prototype.forEach.call(t.children, function (c) { if (c.localName === "tr") rows.push(c); else if (c.localName === "tbody") rows = rows.concat(kids(c, ["tr"])); });
    kids(t, ["tfoot"]).forEach(function (g) { rows = rows.concat(kids(g, ["tr"])); });
    return rows;
  }
  function listed(a) { a.item = function (i) { return this[i] || null; }; return a; }
  getter(E, "cells", function () { return this.localName === "tr" ? listed(kids(this, ["td", "th"])) : undefined; });
  getter(E, "rows", function () {
    var n = this.localName;
    return n === "table" ? listed(table_rows(this)) : n === "tbody" || n === "thead" || n === "tfoot" ? listed(kids(this, ["tr"])) : undefined;
  });
  getter(E, "tBodies", function () { return this.localName === "table" ? listed(kids(this, ["tbody"])) : undefined; });
  getter(E, "cellIndex", function () {
    if (this.localName !== "td" && this.localName !== "th") return undefined;
    return this.parentNode ? kids(this.parentNode, ["td", "th"]).indexOf(this) : -1;
  });
  getter(E, "sectionRowIndex", function () { return this.localName === "tr" && this.parentNode ? kids(this.parentNode, ["tr"]).indexOf(this) : this.localName === "tr" ? -1 : undefined; });
  getter(E, "rowIndex", function () {
    if (this.localName !== "tr") return undefined;
    var t = this.closest("table");
    return t ? table_rows(t).indexOf(this) : -1;
  });

  // An <iframe>'s window. A frame's page is not loaded here; what a
  // script is given is the window of an empty one (about:blank's): a
  // document it can write in, listeners that are never called. Gmail
  // makes a hidden frame for the "resize" of its window alone -- the
  // old trick to be told that the size of the text changed.
  getter(E, "contentWindow", function () {
    if (this.localName !== "iframe") return undefined;
    if (!this.__frame) {
      var d = document.implementation.createHTMLDocument("");
      d.open = d.close = d.write = function () {};
      var nothing = function () {};
      this.__frame = { document: d, parent: window, top: window, frameElement: this, location: { href: "about:blank" },
        addEventListener: nothing, removeEventListener: nothing, dispatchEvent: function () { return true; }, postMessage: nothing, focus: nothing, blur: nothing, close: nothing };
      this.__frame.self = this.__frame.window = this.__frame;
    }
    return this.__frame;
  });
  getter(E, "contentDocument", function () { return this.localName === "iframe" ? this.contentWindow.document : undefined; });

