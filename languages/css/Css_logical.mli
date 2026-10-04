(* Logical properties: a box's sides named by the text's direction, not
   by the page's.

   margin-left is the left of the page. In a page written right to
   left (Arabic, Hebrew) the space meant to be before a line's first
   word is on the right; in one written top to bottom (Japanese set
   vertically) "before the paragraph" is to its right and "the start
   of a line" at the top. So CSS has a second set of names, relative
   to the flow of the text:

     block       the direction blocks follow one another    (down, here)
     inline      the direction of a line's words            (to the right, here)
     start, end  of each

     margin-block-start   the margin before the block        margin-top
     padding-inline-end   after a line's last word           padding-right
     inline-size          a line's length                    width
     border-start-end-radius   block start, inline end       border-top-right-radius

   and shorthands for a pair: margin-inline: 0 auto is margin-left and
   margin-right. A style sheet written with them lays a page out the
   right way round in every script with one set of rules, and the
   component libraries of the 2020s are written so: GitHub's (Primer)
   has 1,600 such declarations.

   This browser sets its text left to right and top to bottom only
   (no direction, no writing-mode). So a logical name is the physical
   one it is in that writing mode, and this module is the table: a
   declaration translated, before the cascade sees it. With a
   direction one day, the table takes it as an argument and the rest
   stays.

   cs-history:
   Flow-relative names came with flexbox and grid, whose alignment
   says start and end, not left and right (2012); the properties
   themselves are CSS Logical Properties and Values Level 1, in
   Firefox first (2015, behind -moz- names since 2010 for margins),
   in Chrome and Safari in 2019-2020.

   Reference: https://www.w3.org/TR/css-logical-1/ *)

(* [physical (name, value)]: the declarations it is in a text left to
 * right, top to bottom -- one, or two for a pair's shorthand
 * (margin-block: 4px 8px), each perhaps a shorthand itself
 * (border-inline-start: 1px solid); None if [name] is not a logical
 * property *)
val physical : string * Css_syntax.component list -> (string * Css_syntax.component list) list option
