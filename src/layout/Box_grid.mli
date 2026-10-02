(* Box_grid: a grid container's items laid out -- Grid_layout's numbers
   made boxes.

   What Box_layout's flex_children is to Flex_layout, in a module of
   its own: a grid's children are found ([items], which a flex
   container's are too), given their cells, the columns sized from
   their contents and the container's width, each item laid out in its
   columns, the rows sized from the heights that gives, and each item
   moved to its row.

       the container's width --.
       the items' narrowest    |--> the columns --> each item laid out
       and widest (measure)  --'                    at its columns' width
                                                          |
       the container's height, if it has one --.         v
                                                |--> the rows --> each item
                               the items' heights                 moved to its
                                                                  row, stretched

   An item fills its area across (unless it has a width of its own) and
   down (align-items and align-self: stretch, the start, the centre,
   the end). Laying an item out and measuring it are Box_layout's, its
   recursion: they are given ([lay_out], [measure]), so that this
   module is not in it.

   Measured itself (a grid in a shrink-to-fit box), a grid is as wide
   as its columns' contents.

   Not done: justify-items and justify-self (an item is stretched
   across, or is its own width at the start); an item's auto margins. *)

open Box_types

(* no margin at all: an item's, once they are taken off its area *)
val no_margins : Computed.size * Computed.size * Computed.size * Computed.size

(* a flex or a grid container's items: its element children, each a
 * block (an inline one "blockified"), and each run of text an
 * anonymous one in the container's style; not those out of the flow
 * (given to [absolute]) nor display: none *)
val items : absolute:(Dom.element -> Computed.t -> unit) -> env -> Dom.element -> Computed.t -> (Dom.element * Computed.t) list

(* the grid container [e]'s items laid out in the block [ctx], its
 * style [s]: [ctx]'s children, and its bottom. [lay_out c cs ~x ~y
 * ~width ~content]: the item as a block at (x, y) in a containing
 * block [width] wide, its content [content] wide if said; [measure c
 * cs ~available]: its content's width, shrunk to fit *)
val children :
  lay_out:(Dom.element -> Computed.t -> x:float -> y:float -> width:float -> content:float option -> box) ->
  measure:(Dom.element -> Computed.t -> available:float -> float) ->
  absolute:(Dom.element -> Computed.t -> unit) ->
  relative:(Computed.t -> box -> box) ->
  ctx ->
  Dom.element ->
  Computed.t ->
  unit
