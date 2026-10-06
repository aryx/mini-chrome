(* Box_layout: a page laid out by CSS 2.1's box model -- TinyChrome's
   layout, over each element's computed style (Computed).

   (notes_css_engine.md section 7.) Html_layout, the teaching browsers',
   reads Mosaic's looks and a few declarations; this one reads nothing
   but the computed style, so that what a page's style sheets say is
   what it gets. It keeps Html_layout's lines and fragments (a word, a
   picture, a control, where it goes), so that Hit, the form controls
   and the drawing of words work on both ([as_html_layout]).

   cs-history:
   Where the box model came from. Before CSS a page was laid out by
   its tags (tools/mosaic's Mosaic_layout.mli: Mosaic's flow) and, from 1995, by tables
   used for what they were not meant for (Table_layout.mli). CSS1
   (1996) gave every element a box -- content, padding, border, margin
   -- and CSS2 (1998) the rules by which boxes are placed: blocks
   stacked, inline boxes flowed into lines, floats (born as Netscape's
   <img align=left>, text flowing round a picture) and positioning.
   Browsers disagreed on it for a decade. Internet Explorer 5 counted
   padding and border inside "width"; the standard counts them outside;
   pages were written for each, and to keep the old ones working
   browsers took the page's <!DOCTYPE> as a switch between "quirks" and
   "standards" (2000) -- still there. CSS 2.1 (a Recommendation only in
   2011) is CSS2 corrected to what browsers could be made to agree on,
   chapter 9 above all; the Acid2 test (2005) is how they were held to
   it. Its vocabulary -- block formatting context, containing block,
   margin collapsing -- is this module's.

   **The box.** Every block is a content box inside its padding, its
   border and its margin; the box kept here is the border box (what a
   background fills), its border's widths with it:

     margin-left | border | padding | content | padding | border | margin-right

   Their sum is the containing block's width: CSS 2.1's section 10.3.3,
   one equation, the autos its unknowns. A width auto takes what the
   margins, borders and paddings leave; a width given with both margins
   auto shares the rest between them -- centring:

     containing block 976, width 400, padding 10, border 1, margins auto
       (976 - 400 - 22) / 2 = 277 each: the box at x 277, 422 wide

   box-sizing: border-box counts padding and border inside the width
   (GitHub's and Google's sheets set it everywhere); min-width and
   max-width clamp it (max-width: 100%, the responsive picture).

   **Vertical margins collapse** where two touch, the larger counting
   (a negative one subtracted): between siblings, and between a block
   and its first child (or last) when no border or padding comes
   between them -- the body's 8 and an h1's 21.4 are 21.4 above the h1,
   not 29.4, the h1's margin showing outside the body. An empty block's
   two margins are one. A block whose own layout is apart (a block
   formatting context: overflow other than visible, a float, an
   inline-block, a table cell, the root) keeps its margins in.

   **Inline content** is set on lines as in Html_layout -- words cut at
   spaces, units the words with no space between, a baseline shared --
   but each word's room above and below the baseline is its own
   element's line-height (normal: 1.2 em) split as half-leading around
   its font's ascent and descent (0.8 and 0.2 em), and the block's own
   font gives every line a minimum (the "strut": an empty line is as
   tall as a line of the block's text). white-space: normal and nowrap
   (no break between its words), pre and pre-wrap (the lines kept),
   pre-line (spaces collapsed, newlines kept); text-align, text-transform:
   uppercase, vertical-align: sub and super (the baseline moved).

   **An inline element's box** (a <code> on a grey background, a
   badge, a navigation's link with its padding) is not a block: its
   left margin, border and padding are a spacer word joined to its
   first word, its right ones one joined to its last, so the line makes
   room for them; its background and border, if it has one, are a box
   per line it is on ([backdrops]), from its first word there to its
   last, as tall as its font plus its vertical padding and border --
   which do not make the line taller, and may overlap the lines around,
   as in every browser:

     a <span style="padding: 0 5px; background: yellow">b</span> c
       "a" at 0, the span's box from 20 (the space after "a") to 40,
       "b" at 25, "c" after the box and a space: 50

   **An inline-block** (a button, a navigation's item) is laid out as a
   block of its own width -- given, or **shrink-to-fit**: its content's
   widest line, at most the room there is, at least its widest word --
   and set in the line as one unit, its last line's baseline on the
   line's. A picture is a unit of its own size (width and height, the
   page's attributes being style: Cascade's presentational hints; one
   of them and the picture's ratio; or the picture's own, once it has
   come), a form's control one of Html_layout.control_size's.

   **Floats** are taken out of the flow, laid out shrink-to-fit, and put
   against the left or right edge where they meet a line (below a line
   that has begun); the lines beside them are shortened until their
   bottom, the blocks' boxes are not (only their lines: the clearfix's
   story). clear moves a block below them. A block formatting context
   beside a float is narrowed instead (overflow: hidden beside a
   sidebar), and holds its own floats, its height enclosing them.

     float: left, width 40, height 30; then "aa bb cc", a page 200
       the float at x 8..48; the line beside it from 48, 144 wide

   **Positioning**: relative moves a box by its offsets after it is laid
   out (what is around it stays); absolute takes it out of the flow,
   placed by its offsets in the nearest positioned ancestor's padding
   box (its place in the flow where they are auto), laid out
   shrink-to-fit, and drawn after the rest (the boxes of the page's
   root, last); fixed is absolute in the window's first screen (it
   scrolls with the page here: an exercise). Down, the offsets need a
   height: the ancestor's when it is known before its content is (a
   length; percents of a height itself known, the window's at the
   root; what a column gives its item) -- then top and bottom together
   make the box's height, bottom alone places it, and its own height
   in percents is of that. An application's frame is made so: a side
   bar and a pane, each absolute and 100% high, in a body as high as
   the window. Where its height is not known (its content gives it),
   a box placed by its bottom waits: it is put there when the block is
   done (a tab's line under its label). A positioned box is kept by
   the box it was written in ([lifted]) and moves with it -- an
   inline-block set on its line, a flex item, a table's cell, each
   laid out at the origin then put in its place -- and all are
   gathered at the end, drawn after the flow. transform: translate(...) moves a box the same way
   relative does, its percents of the box's own size: a long list's
   rows, all at the top and each moved down to its place.

   **Tables** (display: table) are laid out as Mosaic_layout's: the grid and the
   columns' widths from Table_layout, each cell asked its minimum and
   maximum by being laid out at width 0 and without limit; each row as
   tall as its tallest cell, the cell's content at its top, middle or
   bottom (vertical-align); cellspacing= apart (2), a cell without a
   background showing its row's.

   **Lists**: a list-item's marker (a bullet, or its number when its
   list-style-type counts: decimal, lower-alpha...), drawn outside, left
   of its first line.

   **A flex container** (display: flex, inline-flex) lays its children
   out as items: each blockified (a run of its text an anonymous item),
   measured here -- its base size its flex-basis, its width, or its
   content's (shrink-to-fit at an unlimited width), its minimum its
   widest word, measured only when the line is too full -- then
   Flex_layout's arithmetic: the lines, the room shared by grow and
   shrink, the items placed along (justify-content, auto margins) and
   across (align-items, stretched); a single line as tall as its
   container when that is given. A column's items are laid out at their
   width first, their heights then their base sizes.

   **A grid container** (display: grid) puts its children, items as a
   flex container's, in the cells of its rows and columns: Box_grid,
   in a module of its own, over Grid_layout's arithmetic (the cells,
   the tracks' sizes, where each starts) and Css_grid's values; it asks
   here for an item laid out and for its content measured, which are
   the recursion's.

   **Measuring** (shrink-to-fit, a flex item's base, a table's column)
   lays the content out at a width without limit (its widest line) and
   at 0 (its widest word), and so a few things are taken differently
   there, as CSS's intrinsic sizes say or nearly: lines on the left, a
   <center> not centring, a percentage width as auto (it would be of
   the size being measured), a right float on the left, a flex row
   neither growing nor shrinking nor spread by justify-content, and its
   end, its last item's margin included, marked by an empty box.

   Not done: rowspan=,
   bottom and right of an absolute box whose top and left are auto,
   fixed boxes staying on screen, flex's order and baseline alignment.

   **The drawing's order.** The page's box has, after its flow, every
   positioned box (absolute, fixed, and the relative ones, taken out of
   where they were written -- their place is theirs already), sorted by
   z-index and, among equals, by the document's order: CSS 2.1's
   appendix E, less its finer layers (floats over blocks, negative
   z-index under the flow -- here first of the positioned). A box with
   a z-index is a stacking context: what is positioned inside is drawn
   with it. A relative box under an ancestor that clips stays in the
   flow: lifted, it would be drawn whole.

   Worked example (the tests'), a character as wide as its size, the
   root's font 10 (line-height normal: 12), a page 200 wide:

     <body style="margin: 8px"><div style="width: 100px; margin: 0
       auto; padding: 5px; border: 2px solid">ab</div>

     body   x 8, width 184
     div    margins (184 - 100 - 14) / 2 = 35: x 43, width 114 (its
            border box), y 8 (the body's margin and the div's 0
            collapsed); "ab" at x 43 + 2 + 5 = 50, its line from 15, 12
            high: the div 12 + 14 = 26 high

   **The code** is four modules over Box_types' types, each using only
   those before it; this one is the recursion, which cannot be cut --
   a block lays out its children, a flex container its items, a table
   its cells, each of them a block again:

     Box_tree     a box read: its fragments, its edges, moved
     Box_inline   words set on lines, beside floats
     Box_flow     a block being laid out: its width and margins, its
                  words gathered, its inline content set
     Box_layout   blocks, flex containers, shrink-to-fit, positioned
                  and floated boxes, pictures, tables: the page's tree
                  walked

   and beside them Box_grid, a grid container's items, given the
   recursion's two functions it needs rather than being in it.

   Reference: Bert Bos, Tantek Çelik, Ian Hickson and Håkon Wium Lie
   (editors), CSS 2.1 (W3C, 2011), chapters 8 (the box model, collapsing
   margins), 9 (the visual formatting model: block and inline
   formatting contexts, floats, positioning), 10 (widths and heights:
   10.3.3's equation, shrink-to-fit in 10.3.5, line height in 10.8) and
   17 (tables); Web Browser Engineering, chapters 5 and 6;
   notes_css_engine.md section 7. *)

(* [layout metrics ?picture_size ~viewport styles root]: the page laid
 * out in a window [viewport] (width, height), [styles e] each element's
 * computed style (Computed.styles), [picture_size src] a picture's own
 * size if it has come *)
val layout :
  Html_layout.metrics ->
  ?picture_size:(string -> (float * float) option) ->
  ?kids:(Dom.element -> Dom.node list) ->
  viewport:float * float ->
  (Dom.element -> Computed.t) ->
  Dom.element ->
  Box_types.box
