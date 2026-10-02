(* Dom: a page as a tree -- elements with attributes and children, and
   text.

   The Document Object Model is what the rest of a browser works on:
   the looks are computed on it, the layout walks it, a click finds its
   way back to it (and, in browsers with scripts, JavaScript changes
   it). Two parsers build it: Html_tree from a page's tokens, with all
   of HTML's rules; Xml from an XML file, with none (an SVG picture's
   elements are the same nodes as the <svg> written in a page, and
   Svg draws either). Nothing here knows those rules, only the shape
   -- which is why it is a library of its own (libs/dom), under the
   languages and not in one of them:

   cs-history:
   The name is a standard's. When scripts came to pages, each browser
   gave them its own view of the page: Netscape 2 and 3 (1995, 1996)
   only the forms, images and links ("DOM Level 0", named afterwards);
   then, for "Dynamic HTML" (1997), Netscape 4 its layers and Internet
   Explorer 4 document.all, every element -- two incompatible models,
   and pages written twice. The W3C's Document Object Model (Level 1,
   October 1998) is the one tree both agreed on, defined apart from any
   language: nodes, with a parent, children and attributes. Levels 2
   (2000) and 3 (2004) added events, styles and ranges; it is now a
   living standard of the WHATWG's. Here it is the tree alone, as
   an OCaml value; what a script sees of it is src/dom's.

     html                       the root, always there (Html_tree
      +- head                    makes the three of them even when the
      |   +- title               page wrote none)
      |       +- "Lunch"
      +- body
          +- h1
          |   +- "Menu"
          +- p
              +- "Soup of the day"

   An element keeps **where it comes from** ([origin]): HTML 2.0's
   core, or Netscape's extensions -- an element of its own (<font>),
   or the attributes it gave a core one (<body bgcolor=silver>), kept
   apart from the core's, so that code reading HTML 2.0 sees HTML 2.0
   and asks for the rest by name ([attribute ~extensions:true]).

   The real DOM has more kinds of node (the document itself, comments,
   the doctype, processing instructions) and each node knows its
   parent; ours keeps elements and text, and is a value: built once,
   then only read, so a parent is where you came from.

   Reference: W3C, "Document Object Model (DOM) Level 1 Specification"
   (1998); WHATWG, "DOM Living Standard", section 4 (nodes, trees);
   notes_browser.md section 4. *)

(* where an HTML element or attribute comes from (languages/html's Dtd
 * says which): an XML element is Core *)
type origin =
  | Core (* HTML 2.0, what Mosaic read *)
  | Netscape (* Netscape's extensions *)

type node = Element of element | Text of string

and element = {
  name : string; (* as its parser gives it: HTML's lowercased ("p"), XML's as written *)
  attributes : (string * string) list; (* all of a Netscape element's *)
  extensions : (string * string) list; (* a core element's Netscape ones *)
  origin : origin; (* the element's *)
  children : node list;
}

(* an element of this name, core, with these (core) attributes *)
val element : ?attributes:(string * string) list -> string -> node list -> element

(* the value of an attribute: a core one; or, with [extensions], one of
 * Netscape's too *)
val attribute : ?extensions:bool -> string -> element -> string option

(* the elements named so, in document order, [root] included *)
val find_all : string -> element -> element list

(* the text inside, in document order, concatenated *)
val text_content : element -> string

(* the tree without the text nodes that are only spaces and newlines
 * (the source's indentation, which layout ignores): what a person
 * reading the tree wants, and the tests' way to write it *)
val without_blank_text : element -> element

(* the tree as indented lines, two spaces a level, an element as
 * [name attr="value"] (Netscape's marked: [font size="+1" {Netscape}],
 * [hr {Netscape: noshade=""}]), a text quoted with its newlines as \n:
 *
 *   html
 *     head
 *       title
 *         "Lunch"
 *)
val to_lines : element -> string list
