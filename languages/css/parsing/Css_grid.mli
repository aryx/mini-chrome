(* Css_grid: a grid's values read -- its tracks, its named areas, where
   an item goes.

   CSS Grid (2017) lays a container's children in rows *and* columns,
   which the container declares; where flexbox says "these, in a row",
   a grid says "three rows and two columns, and this child there". It
   is how a page is cut into its header, its side column, its article
   and its footer -- Wikipedia's, since 2022:

     .mw-page-container-inner {
       display: grid;
       column-gap: 24px;
       grid-template: min-content 1fr min-content / 12.25rem minmax(0, 1fr);
       grid-template-areas: 'siteNotice  siteNotice'
                            'columnStart pageContent'
                            'footer      footer' }
     .vector-column-start  { grid-area: columnStart }
     .mw-content-container { grid-area: pageContent }

   read here as

     rows     [ min-content; 1fr; min-content ]         (before the /)
     columns  [ 12.25rem (196 px); minmax(0, 1fr) ]     (after it)
     areas    [ [siteNotice; siteNotice]; [columnStart; pageContent]; [footer; footer] ]
     and the two children's places, Area "columnStart" and Area "pageContent"

   A **track** is a row or a column, and its size a pair, its least and
   its most: "minmax(0, 1fr)" says them both, and a size alone is both
   ("12.25rem": never less, never more; "1fr", an [Fr], is "auto" at
   the least). The sizes:

     a length     12.25rem, 200px, 30% (of the grid)
     fr           a share of the room left once the others are served,
                  as flex-grow: 1fr 2fr is a third and two thirds
     min-content  the narrowest its content can be (its longest word)
     max-content  the widest it wants to be (nothing wrapped)
     auto         its content's, between the two, and what room is left

   What the arithmetic does with them is Grid_layout's (src/layout).

   Read: grid-template-columns and -rows (lengths, fr, min-content,
   max-content, auto, minmax(), repeat(n, ...), fit-content() as auto),
   grid-template-areas, the shorthand grid-template as "rows / columns"
   (Computed cuts it), grid-area as a name or as its four lines, and
   grid-row and grid-column as "start / end", each a line's number
   (negative from the end: "1 / -1" is the whole width) or "span n" --
   how a page on a grid of twelve columns says "this one takes four":

     .lead  { grid-column: 1 / span 8 }     columns 1 to 8
     .side  { grid-column: 9 / span 4 }     columns 9 to 12
     .wide  { grid-column: 1 / -1 }         all of them
     .card  { grid-column: span 3 }         three, wherever is free

   Not read: line names ("[main-start]"), repeat(auto-fill, ...), the
   four longhands (grid-row-start...), grid-auto-flow (rows),
   grid-auto-rows and -columns (auto).

   Reference: W3C, CSS Grid Layout Module Level 1, sections 7.2 (the
   track sizes), 7.3 (the named areas), 8.3 and 8.4 (placement). *)

(* one end of a track's size *)
type breadth = Length of Css_values.length | Fr of float | Min_content | Max_content | Auto

(* a track: the least it is, the most *)
type track = { min : breadth; max : breadth }

(* "auto": an implicit track's size, a row that no grid-template-rows
 * names *)
val auto : track

(* grid-template-columns' or -rows' value: its tracks, in order; [] if
 * "none" or not understood *)
val tracks : Css_values.context -> Css_syntax.component list -> track list

(* grid-template-areas' value: a row a string, a cell a word ("." a
 * cell of no area) *)
val areas : Css_syntax.component list -> string list list

(* one end of an item along an axis: wherever (auto), at a line of the
 * grid -- counted from 1, the first track being between lines 1 and 2;
 * negative from the end, -1 the last line -- or so many tracks from
 * its other end ("span 3") *)
type line = Auto | Line of int | Span of int

(* where an item goes: where the next free cell is, in the area of that
 * name, or between lines: its start and its end along the rows, and
 * along the columns *)
type placement = Auto_placed | Area of string | Lines of { row : line * line; column : line * line }

(* grid-area's value: a name, or row-start / column-start / row-end /
 * column-end *)
val placement : Css_syntax.component list -> placement

(* grid-row's or grid-column's value, "start / end": "2", "1 / 3",
 * "1 / span 4", "span 2", "1 / -1" *)
val axis : Css_syntax.component list -> line * line
