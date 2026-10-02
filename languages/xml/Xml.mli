(* Xml: XML read into a tree -- elements, their attributes, and the
   text between them.

   XML is a syntax and nothing more: named elements that nest, each
   with attributes, around text. What the names mean is somebody
   else's business -- SVG's (a drawing: libs/images' Svg, this
   module's first user), Atom's (a feed), XHTML's (a page). One
   reader serves them all, which was the point.

     <?xml version="1.0"?>
     <feed xmlns="http://www.w3.org/2005/Atom">
       <title>News &amp; notes</title>
       <entry id="1"><title>First</title></entry>
       <link href="/"/>
     </feed>

   is read as the tree a page is read as, a Dom (libs/dom), and
   Dom.to_lines shows it:

     feed xmlns="http://www.w3.org/2005/Atom"
       title
         "News & notes"
       entry id="1"
         title
           "First"
       link href="/"

   One tree for both markups, as in a browser: what is drawn from an
   .svg file is drawn the same from an <svg> in a page (Svg), and a
   selector or a script would find an element of either.

   What there is to read, all of it:

     <a x="1" y='2'>    a start tag, its attributes quoted either way
     </a>               its end tag
     <a/>               an empty element: both at once
     text               between tags; &lt; &gt; &amp; &quot; &apos;
                        and &#233; &#xe9; for the characters that
                        cannot be written, there and in attributes
     <![CDATA[ a < b ]]>   text where nothing means anything, as it is
     <!-- ... -->       a comment: skipped
     <?xml ... ?>       the declaration, and other instructions to
                        programs (<?xml-stylesheet ...?>): skipped
     <!DOCTYPE a ...>   the grammar this document claims to follow,
                        perhaps with declarations of its own between
                        brackets: skipped

   Compare with HTML (Html_lexer.mli, Html_tree.mli): no element is
   special. No tag may be left out, none closes another, none is
   empty by its name (<br> must be <br/>), none holds raw text
   (<script>'s < must be &lt; or in CDATA); names keep their case. A
   reader of XML knows no vocabulary, and is a hundred lines where
   HTML's is a thousand.

   Names are kept as written, prefix and all (svg:rect, xlink:href):
   namespaces -- the xmlns attributes that say whose vocabulary a
   prefix stands for -- are attributes like others here, and [local]
   gives a name without its prefix. Text that is only spaces, the
   indentation between elements, is dropped: with no grammar to say
   where spaces matter, that is the usual guess.

   Where this reader departs from XML, on purpose: it forgives. An end
   tag closes the element being read whatever its name; a file that
   stops early closes everything open; an attribute may lack its
   quotes or its value; an entity not known stays as written. XML's
   own rule is the opposite (below), and a reader that checked would
   be a validator, another program. A DOCTYPE's own entities are not
   read, so a name it declares is left as &name; -- and the files
   that define an entity as ten of another, ten levels deep, to make
   a reader fill the memory (the billion laughs) do nothing here.

   cs-history:
   Where it came from. Markup that says what a piece of text is and
   not how to print it is Charles Goldfarb's, at IBM from 1969 (GML),
   and an ISO standard in 1986: SGML, a language for defining markup
   languages, each by a grammar, its DTD. SGML was large -- tags that
   could be left out, shortened, or implied, by rules the DTD gave, so
   that no document could be read without its DTD -- and its users
   were publishers and governments with the money for the tools. HTML
   was said to be one such language (Dtd.mli tells how true that
   was).

   cs-history:
   In 1996 a group at the W3C chaired by Jon Bosak, of Sun, set out to
   cut SGML down to what could be sent over the web and read by a
   program written in a week. XML 1.0 was a Recommendation on 10
   February 1998, edited by Tim Bray, Jean Paoli and Michael
   Sperberg-McQueen: thirty pages where SGML had five hundred. Its
   one deep change: every tag written out, so a document can be read
   with no DTD at all. Among its ten stated goals: that it shall be
   easy to write programs which process XML documents, and that
   terseness in XML markup is of minimal importance.

   terminology:
   Well-formed and valid. A document is well-formed if its tags
   nest and its attributes are quoted: syntax, checked without
   knowing the vocabulary. It is valid if, besides, it follows its
   DTD: this element only inside that one, this attribute required.
   SGML had only the second; XML's invention is the first, and almost
   every XML on the web is read as well-formed and never validated.

   design:
   The draconian rule. The specification says that a reader meeting
   a document not well-formed must stop and report, and must not go
   on guessing: the reaction of people who had watched browsers
   compete at guessing what broken HTML meant, each differently
   (Html_tree.mli). It made XML safe between programs, which write
   it right or are fixed. It failed for people: a page served as
   XHTML with one & not escaped -- in a comment a visitor typed --
   was an error message instead of a page, and authors chose the
   forgiving parser. Postel's law, be liberal in what you accept,
   against its critics: the web's two markup languages are the two
   answers.

   evolution:
   For some years everything was to be XML. The W3C's languages: XHTML
   (2000), SVG (2001), MathML; XSLT to turn one vocabulary into
   another; namespaces (1999) to mix them in one document. Between
   programs: feeds (RSS, 1999; Atom, RFC 4287, 2005), remote calls
   (XML-RPC, SOAP), and the answers of a server to a page's script,
   which gave XMLHttpRequest its name and Ajax its x
   (XMLHttpRequest.mli). Then JSON (Douglas Crockford, 2001) -- the
   fat-free alternative, his site said -- took the data: a script's
   own literals, read by one call, with arrays and numbers where XML
   has only text. HTML5 ended XHTML. What stayed is where XML is a
   document's syntax and not a message's: SVG, feeds, sitemaps,
   office files, and configuration nobody dares to convert.

   modern:
   A browser has a real XML parser (Chrome's is libxml2, a C library
   from the GNOME project), used for an .svg or .xml file opened, for
   XMLHttpRequest's responseXML and DOMParser's XML kinds, and it
   builds the same DOM as the HTML parser does. Here too the tree is
   the same, but only Svg asks for it yet: a script's DOMParser reads
   HTML alone (Script_document), and XMLHttpRequest has no
   responseXML.

   References: Extensible Markup Language (XML) 1.0, W3C
   Recommendation (1998; fifth edition 2008); Namespaces in XML
   (1999); ISO 8879:1986 for SGML; Tim Bray's The Annotated XML
   Specification (xml.com, 1998), the specification with its editor's
   reasons beside each paragraph. *)

(* a document's nodes, in order: its one element usually, more if it
 * is not well-formed; each element Core, with no extensions (those
 * are HTML's history). Never raises. *)
val parse : string -> Dom.node list

(* a text's references replaced: the five names and the characters by
 * number; what is not one stays *)
val entities : string -> string

(* a name without its prefix: rect for svg:rect *)
val local : string -> string

(* [find name nodes]: the first element of that local name, in
 * document order (Dom.find_all looks for a name as written;
 * Dom.text_content gives an element's text) *)
val find : string -> Dom.node list -> Dom.element option
