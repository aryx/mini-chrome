  // base64 (RFC 4648): three bytes as four letters. The bytes are a
  // "binary string", a character a byte (its code under 256): what
  // atob gives back, and all that btoa takes
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

  // text to bytes and back (the Encoding standard): a string's
  // characters as UTF-8's bytes, one to four each, and bytes read as
  // characters -- what is not UTF-8 read as U+FFFD, the mark of it
  global("TextEncoder", class TextEncoder {
    get encoding() { return "utf-8"; }
    encode(s) {
      s = s === undefined ? "" : String(s);
      var out = [];
      for (var i = 0; i < s.length; i++) {
        var c = s.codePointAt(i);
        if (c > 0xffff) i++;
        if (c >= 0xd800 && c <= 0xdfff) c = 0xfffd;
        if (c < 0x80) out.push(c);
        else if (c < 0x800) out.push(0xc0 | (c >> 6), 0x80 | (c & 0x3f));
        else if (c < 0x10000) out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
        else out.push(0xf0 | (c >> 18), 0x80 | ((c >> 12) & 0x3f), 0x80 | ((c >> 6) & 0x3f), 0x80 | (c & 0x3f));
      }
      return new Uint8Array(out);
    }
  });
  global("TextDecoder", class TextDecoder {
    constructor(label) { this.encoding = (label || "utf-8").toLowerCase(); }
    decode(bytes) {
      if (!bytes) return "";
      if (bytes instanceof ArrayBuffer) bytes = new Uint8Array(bytes);
      else if (bytes.buffer instanceof ArrayBuffer && !(bytes instanceof Uint8Array)) bytes = new Uint8Array(bytes.buffer, bytes.byteOffset, bytes.byteLength);
      var s = "", units = [], n = bytes.length, latin = this.encoding !== "utf-8" && this.encoding !== "utf8";
      for (var i = 0; i < n; ) {
        var b = bytes[i++], c = b, more = latin || b < 0x80 ? 0 : b >= 0xf0 && b <= 0xf4 ? 3 : b >= 0xe0 ? 2 : b >= 0xc2 ? 1 : -1;
        if (more < 0) c = 0xfffd;
        else if (more > 0) {
          c = b & (0x3f >> more);
          for (var k = 0; k < more; k++) {
            var next = bytes[i];
            if (next === undefined || (next & 0xc0) !== 0x80) { c = 0xfffd; break; }
            c = (c << 6) | (next & 0x3f); i++;
          }
        }
        if (c < 0x10000) units.push(c);
        else { c -= 0x10000; units.push(0xd800 + (c >> 10), 0xdc00 + (c & 0x3ff)); }
        if (units.length > 8192) { s += String.fromCharCode.apply(null, units); units = []; }
      }
      return s + String.fromCharCode.apply(null, units);
    }
  });

