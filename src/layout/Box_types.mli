(* Box_types: what Box_layout's modules speak of -- the box a page is
   made of, the words and floats of a line being set, and a block while
   it is laid out. Types alone.

     Box_tree     a box read: its fragments, its edges, moved
     Box_inline   words set on lines beside floats    (word, item, placed)
     Box_flow     a block being laid out               (env, ctx)
     Box_layout   the recursion over the page's tree, giving boxes

   Box_layout.mli tells the whole of the layout. *)

(* {1 The box} *)

(* a block's border box, or an anonymous box of lines *)
type box = {
  element : Dom.element option; (* None: an anonymous box of lines *)
  style : Computed.t; (* its element's; an anonymous box's, its block's *)
  x : float; (* the border box, page's coordinates (y down) *)
  y : float;
  width : float;
  height : float;
  border : float * float * float * float; (* its widths: top, right, bottom, left *)
  children : box list; (* its blocks; an anonymous box's inline-blocks and floats *)
  lines : Html_layout.line list; (* an anonymous box's *)
  backdrops : box list; (* an anonymous box's: its inline elements' boxes, a piece per line, drawn under its words *)
  marker : Html_layout.marker option; (* a list item's *)
  (* the positioned boxes (absolute, fixed) written in it: out of its
   * flow, but moved with it wherever it is put (Box_tree.moved), and
   * drawn after the page's flow (Box_layout.layout gathers them). Each
   * with the bottom it waits to be placed by, if it is placed so in a
   * block whose height was not known yet *)
  lifted : (box * float option) list;
}

(* {1 A line's content} *)

(* a word's room above and below the baseline (half-leading), and its
 * baseline moved down by [shift] (sub; up for super) *)
type word_style = { look : Looks.t; above : float; below : float; shift : float; shown : bool }

type side = On_left | On_right

(* what a unit of a line may be besides text: a picture, a control, an
 * inline-block (laid out at its place's origin; its margins) *)
type boxed =
  | Pic of Html_layout.picture
  | Ctl of Html_layout.control
  | Inline of { ib : box; ml : float; mt : float; mb : float }

(* an inline element whose box is drawn (a background, a border): its
 * horizontal margins, which its box leaves out *)
type decoration = { de : Dom.element; ds : Computed.t; dml : float; dmr : float }

(* a spacer word's place at an inline element's edge: its margin,
 * border and padding, left or right *)
type edge = Body | Lead | Trail

type word = {
  text : string;
  ws : word_style;
  space_before : bool;
  glue : bool; (* no break before it: white-space: nowrap *)
  space : float; (* the width of the space before it *)
  width : float;
  boxed : boxed option;
  owner : Dom.element;
  decorations : decoration list; (* the inline elements it is in whose boxes are drawn *)
  edge : edge;
}

type item =
  | Word of word
  | Break
  | Anchor of string
  | Float of { fbox : box; fside : side; fmargin : float * float * float * float; mutable placed : bool }
  | Clear of side list

(* a float in its place: its margin box *)
type placed = { pside : side; left : float; right : float; ptop : float; pbottom : float }

(* {1 A block being laid out} *)

(* what a whole layout shares *)
type env = {
  metrics : Html_layout.metrics;
  picture_size : string -> (float * float) option;
  style : Dom.element -> Computed.t;
  kids : Dom.element -> Dom.node list; (* its children, its ::before and ::after among them (Computed.styles_all) *)
  viewport : float * float;
  positioned : (box * float option) list ref; (* the positioned boxes of the block being laid out: its [lifted], when done *)
  late : int ref; (* how many wait to be placed by their bottom *)
  (* shrink-to-fit's measure: lines on the left (a centred line at an
   * unlimited width would be far to the right) *)
  measuring : bool;
  (* inside a <center> or an align=center: blocks centred (HTML's
   * "align descendants", -webkit-center) *)
  centring : bool;
  (* the nearest positioned ancestor's padding box: x, y, width, and
   * its height when it is known before its content is (a height said,
   * the window's) *)
  containing : float * float * float * float option;
  (* the height of the block whose children are being laid out, when
   * it is known before they are: what a child's height in percents is of *)
  known_height : float option;
  (* shrink-to-fit's measures, this layout's: an element's content at an
   * unlimited width and at 0, by the element (==), its display, the width *)
  measured : (int, Dom.element * Computed.display * float * float) Hashtbl.t;
}

(* a block being laid out: where its content goes, what is stacked
 * (its bottom [cursor], the margin [pending] below it), the inline
 * content not yet set *)
type ctx = {
  env : env;
  floats : placed list ref; (* its formatting context's *)
  block : Computed.t;
  x : float; (* the content box *)
  width : float;
  mutable cursor : float;
  mutable pending : float;
  mutable absorbed : bool; (* the next child's top margin is already the block's (collapsed through) *)
  mutable children : box list; (* the last first *)
  mutable items : item list; (* the last first *)
  mutable space : bool;
  mutable owner : Dom.element;
  mutable link : string option;
  mutable counter : int; (* its list items so far *)
  mutable decorations : decoration list; (* the inline elements the words now read are in, whose boxes are drawn *)
}
