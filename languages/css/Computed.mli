(* Computed: each element's style as values -- what layout reads.

   (notes_css_engine.md section 6.) The cascade gives each property's
   winning declaration as text; this module makes a value of each, in a
   record: lengths in pixels (or pixels plus a percentage the layout
   resolves, Css_values), colours as numbers, keywords as variants.

   terminology:
   A property has four values, and the words are the standard's (CSS
   2.1, section 6.1). The **specified** value is what the cascade
   gave, or the inherited or initial one: "width: 50%", "font-size:
   1.2em". The **computed** value is that made as absolute as it can
   be without laying anything out -- 1.2em is 19.2px; 50% stays 50% --
   and is what a child inherits (this module's record). The **used**
   value is after layout: 50% of a 600 px block, 300px. The **actual**
   value is what the screen can show: 300 dots, or 600 on a screen of
   double density. What a script reads with getComputedStyle is, for
   most properties and despite its name, the used value.

   What no declaration gives is **inherited** from the parent (the
   colour, the font, the alignment, white-space, line-height,
   visibility, list-style, and the custom properties) or takes its
   **initial value** (display inline, margins 0, background
   transparent...), as each property's definition says; the keywords
   inherit, initial and unset ask for either. font-size is computed
   first: an em everywhere else is this element's size, in font-size
   its parent's.

   **Shorthands** are expanded before: margin and padding (one to four
   values: top, right, bottom, left), border and border-top and its
   sides (a width, a style, a colour in any order), border-width,
   border-style, border-color, background (its colour, the rest
   ignored), font (style, weight, size, "/" line-height, family), flex
   (grow, shrink, basis), gap, inset, list-style (its type).

   The page's defaults are a style sheet like its own, the user agent's
   (ua.css, embedded as Ua_sheet): CSS 2.1's appendix D, Mosaic's table
   of looks (tools/mosaic's Mosaic_looks.mli) written in the language
   the pages use.

   ::before and ::after are elements the cascade makes (Cascade's
   cascade_all: content's text in an element named "::before"), styled
   here as children of theirs: [styles_all] gives each element's
   children with them, for the layout to go through.

   Not computed: the properties layout does not use yet (shadows,
   animations, a transform but for its translation: a rotation, a
   scale); content's counters and quotes. *)

(* the custom properties (--x) an element has, its own and its
 * ancestors', by name: a sheet of the 2020s declares hundreds on the
 * root, and each var(--x) looks one up *)
module Custom : Map.S with type key = string

type display =
  | Inline
  | Block
  | Inline_block
  | List_item
  | Flex
  | Inline_flex
  | Grid (* laid out as a block: plan_tiny_chrome.md *)
  | Table
  | Table_row_group
  | Table_row
  | Table_cell
  | Table_caption
  | Display_none
  | Contents (* no box of its own: its children's in its place *)

type position = Static | Relative | Absolute | Fixed | Sticky

(* a length that may be auto (widths, margins, offsets), or none (max-width) *)
type size = Auto | Len of Css_values.length

type family = Serif | Sans_serif | Monospace
type white_space = Normal | Pre | Nowrap | Pre_wrap | Pre_line
type text_align = Align_left | Align_right | Align_center | Align_justify
type vertical_align = Baseline | Middle | Top | Bottom | Text_top | Text_bottom | Sub | Super
type line_height = Line_normal | Factor of float | Line_px of float
type side = Side_none | Side_left | Side_right | Side_both
type flex_direction = Row | Row_reverse | Column | Column_reverse
type align = Start | End | Center | Stretch | Space_between | Space_around | Space_evenly | Align_baseline

type t = {
  display : display;
  position : position;
  float : side; (* Side_left, Side_right or Side_none *)
  clear : side;
  (* transform: its translation (translate, translateX, translateY,
   * translate3d), the percents of the box's own size; the rest of a
   * transform (a rotation, a scale) is not applied *)
  translate : (Css_values.length * Css_values.length) option;
  top : size;
  right : size;
  bottom : size;
  left : size;
  width : size;
  height : size;
  min_width : Css_values.length;
  min_height : Css_values.length;
  max_width : size; (* Auto: none *)
  max_height : size;
  margin : size * size * size * size; (* top, right, bottom, left *)
  padding : Css_values.length * Css_values.length * Css_values.length * Css_values.length;
  border_width : float * float * float * float; (* 0 where the style is none or hidden *)
  border_color : Css_values.color * Css_values.color * Css_values.color * Css_values.color;
  border_box : bool; (* box-sizing: border-box *)
  color : Css_values.color;
  background : Css_values.color;
  background_image : string option; (* its url(), as written (a sheet's resolved against it: Browser_page) *)
  mask_image : string option; (* mask-image's url() (or -webkit-'s): the box's background shows through its picture only *)
  font_size : float;
  bold : bool; (* font-weight 600 and more *)
  italic : bool;
  family : family;
  line_height : line_height;
  text_align : text_align;
  underline : bool;
  line_through : bool;
  uppercase : bool; (* text-transform: uppercase *)
  white_space : white_space;
  vertical_align : vertical_align;
  list_style : string; (* disc, circle, square, decimal, none... *)
  visible : bool; (* visibility: visible, and opacity not 0 *)
  overflow_hidden : bool; (* overflow other than visible: hidden, clip, auto, scroll (clipped, no scrollbar) *)
  flex_direction : flex_direction;
  flex_wrap : bool;
  justify_content : align;
  align_items : align;
  align_self : align option; (* None: the container's align-items *)
  flex_grow : float;
  flex_shrink : float;
  flex_basis : size;
  row_gap : Css_values.length;
  column_gap : Css_values.length;
  (* a grid (Css_grid): its columns and its rows, [] none said; its
   * named areas; where the element goes in its parent's; and how the
   * tracks are packed in the room across (None: normal, stretched) *)
  grid_columns : Css_grid.track list;
  grid_rows : Css_grid.track list;
  grid_areas : string list list;
  grid_area : Css_grid.placement;
  align_content : align option;
  custom : Css_syntax.component list Custom.t; (* the custom properties, inherited *)
}

(* the root's parent: what the root inherits (the initial values, a
 * font of 16 pixels) *)
val initial : t

(* [compute media ~root_font_size ~parent declared]: an element's
 * style, [declared] its cascaded declarations (Cascade) *)
val compute : Cascade.media -> root_font_size:float -> parent:t -> (string * Css_syntax.component list) list -> t

(* the browser's own style sheet, parsed *)
val user_agent_sheet : Cascade.sheet

(* the browser's sheets that come before the page's: the user agent's,
 * and with [quirks] quirks mode's (Cascade.explain's list starts so) *)
val browser_sheets : quirks:bool -> Cascade.sheet list

(* [styles media sheets root]: every element's computed style, the
 * browser's sheet first, then [sheets] (the page's); with [quirks]
 * (false), quirks mode's rules for a page without a DOCTYPE: a table's
 * fonts and alignment not inherited *)
(* the same, and each element's children with its ::before and ::after
 * (Cascade.cascade_all): what a layout goes through *)
val styles_all :
  ?visited:(string -> bool) -> ?quirks:bool -> Cascade.media -> Cascade.sheet list -> Dom.element -> (Dom.element -> t) * (Dom.element -> Dom.node list)

val styles : ?visited:(string -> bool) -> ?quirks:bool -> Cascade.media -> Cascade.sheet list -> Dom.element -> Dom.element -> t
