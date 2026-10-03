(* An inline <svg> as the Playground's shapes, when it is made of what
   they are: the Playground's own pictures read back.

   The Playground has a web platform (elm-playground's
   playground/platforms/web): a program compiled to JavaScript whose
   every frame is an <svg> in the page, a shape an element --

     circle red 20 |> move 100 50      <circle r="20" fill="rgb(204,0,0)"
                                               transform="translate(100, -50)">
     rectangle c w h                   <rect width height fill
                                             transform="translate(x, -y) translate(-w/2, -h/2)">
     words c "TINY" |> scale 4         <text text-anchor="middle" dominant-baseline="central"
                                             font-size="10" transform="... scale(4)">TINY</text>
     image w h "p.png"                 <image href="p.png" width height transform=...>
     group shapes                      <g transform=...> ... </g>

   -- y down where the Playground's is up, a rotation the other way,
   a rectangle from its corner and not its centre. The browser itself
   is drawn with those shapes. So a page that is a Playground program
   (its menu, tinybox: docs/plans/plan_tinybox.md) is drawn here by
   undoing that: each element made the shape it was written from, the
   whole scaled from the viewBox to the element's box. The letters
   are then the platform's (Playground.words, as a program run
   natively shows them), a picture is the page's own, fetched as an
   <img>'s is, and nothing is made pixels before the platform draws
   it: what a frame costs is its shapes, not the window's size.

   Else there is Svg (libs/images), the general way: any drawing
   rasterized to a picture, its paths, strokes and curves, which is
   what an icon needs and what [shapes] answers None for -- a path, a
   stroke, a transform that is not a translation, a rotation or one
   scale, a text not centred.

   design:
   The browser has two ways to draw an svg, and this one is the
   special case. It is here because a picture of 1100 by 620 made
   again sixty times a second is not what a rasterizer written to draw
   icons once is for; a real browser draws SVG as it draws everything,
   a display list given to the GPU, and has no such case. *)

(* [shapes ~picture_of svg ~width ~height]: the drawing's shapes,
 * around the centre of a box of that size (the Playground's axes: y
 * up); None if something in it is not a shape. [picture_of]: an
 * <image>'s picture by its address as written, if it has come *)
val shapes : picture_of:(string -> Rgba_image.t option) -> Dom.element -> width:float -> height:float -> Playground.shape list option
