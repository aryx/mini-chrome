(* Script_dom: the page's mutable copy -- the tree a script changes
   (Browser_script.mli's "The copy").

   The browser's tree (Dom) is a value. A script needs to change it, so
   it works on nodes that know their parent and whose children and
   attributes can be changed, thawed from the page's tree; the browser
   takes it back frozen when it must lay the page out again:

     page's Dom  --thaw-->  nodes  --freeze-->  Dom  -->  layout

     <p id=a>one <b>two</b>   thawed: a node "p", its attributes
                              [id=a], its children a text "one " and a
                              node "b", each with the p as parent
     inner_html of the p      one <b>two</b>
     html_of the p            <p id="a">one <b>two</b></p>

   A text is a node named "#text". Netscape's attributes sit with the
   others while thawed, and are put apart again when frozen (as the
   lexer has them). Nothing here runs a script: the host objects that
   scripts reach these nodes through are Script_host's. *)

open Script_types

(* {1 Nodes} *)

val text_name : string
val is_text : node -> bool

(* a node of its own, no parent yet: an element named so, or a text *)
val make : ?text:string -> ?attributes:(string * string) list -> string -> node

(* the page's tree copied, and back *)
val thaw : Dom.element -> node
val freeze : node -> Dom.element

(* every element under a node (itself too), in document order *)
val elements : node -> node list

val text_content : node -> string
val attribute : node -> string -> string option

(* an attribute set: changed in its place, or added last *)
val set_attribute : node -> string -> string -> unit

(* a node taken out of its parent; nodes given a parent (which must be
 * given them as children too) *)
val detach : node -> unit
val adopt : node -> node list -> unit

(* {1 HTML: innerHTML read and written} *)

(* a node as HTML, with its tags; its children alone *)
val html_of : node -> string
val inner_html : node -> string

(* the nodes a string of HTML stands for *)
val parse_fragment : string -> node list

(* {1 Selectors} *)

(* the elements matching a selector, in document order, among those
 * under [within] (itself not): matched on the frozen tree, with their
 * ancestors, as the page's style sheets are. A selector that cannot be
 * read is JavaScript's SyntaxError, thrown *)
val select : t -> string -> within:node -> node list
