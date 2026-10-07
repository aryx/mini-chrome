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
  // ... and changed: a row put in a table or a section at a place
  // (-1, or none given: the end), a cell in a row, one taken out.
  // Gmail builds a message's header this way.
  function put(parent, made, list, i) {
    if (i === undefined || i === -1 || i === list.length) parent.appendChild(made);
    else if (i >= 0 && i < list.length) list[i].parentNode.insertBefore(made, list[i]);
    else throw new DOMException("The index is not in the allowed range.", "IndexSizeError");
    return made;
  }
  method(E, "insertRow", function (i) {
    var row = document.createElement("tr"), rows = this.rows;
    // a table with no row yet: in its body, made if there is none
    if (this.localName === "table" && rows.length === 0) return (this.tBodies[0] || this.appendChild(document.createElement("tbody"))).appendChild(row);
    if (this.localName === "table" && (i === undefined || i === -1 || i === rows.length)) return rows[rows.length - 1].parentNode.appendChild(row);
    return put(this, row, rows, i);
  });
  method(E, "insertCell", function (i) { return put(this, document.createElement("td"), this.cells, i); });
  function taken(list, i) { var e = list[i === -1 ? list.length - 1 : i]; if (e) e.parentNode.removeChild(e); }
  method(E, "deleteRow", function (i) { taken(this.rows, i); });
  method(E, "deleteCell", function (i) { taken(this.cells, i); });
  function section(name) {
    return function () {
      var had = kids(this, [name])[0];
      return had || (name === "thead" || name === "caption" ? this.insertBefore(document.createElement(name), this.firstChild) : this.appendChild(document.createElement(name)));
    };
  }
  method(E, "createTHead", section("thead"));
  method(E, "createTFoot", section("tfoot"));
  method(E, "createCaption", section("caption"));
  method(E, "createTBody", function () { return this.appendChild(document.createElement("tbody")); });

  // An <iframe>'s window. A frame's page is not loaded here; what a
  // script is given is the window of an empty one (about:blank's): a
  // document it can write in, listeners that are never called. Gmail
  // makes a hidden frame for the "resize" of its window alone -- the
  // old trick to be told that the size of the text changed.
  getter(E, "contentWindow", function () {
    if (this.localName !== "iframe") return undefined;
    if (!this.__frame) {
      var d = document.implementation.createHTMLDocument(""), el = this;
      d.open = d.close = d.write = function () {};
      var nothing = function () {};
      this.__frame = { document: d, parent: window, top: window, frameElement: this, location: { href: "about:blank" },
        addEventListener: nothing, removeEventListener: nothing, dispatchEvent: function () { return true; },
        // to the frame's own document, if it has scripts (Browser_script.adopt)
        postMessage: function (data) { if (typeof __post_frame === "function") __post_frame(el, data); }, focus: nothing, blur: nothing, close: nothing };
      this.__frame.self = this.__frame.window = this.__frame;
    }
    return this.__frame;
  });
  getter(E, "contentDocument", function () { return this.localName === "iframe" ? this.contentWindow.document : undefined; });

