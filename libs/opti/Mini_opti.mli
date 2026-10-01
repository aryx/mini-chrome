(* The switch between optimized code and the simpler code it replaced,
   which is kept, runnable, next to it.

   An optimization makes the code faster and harder to read. Someone
   reading the browser should be able to read the simple code first, to
   understand what is done, and the optimized one later, to learn the
   trick. So when a few simple lines become an algorithm (a memo, a
   laziness, an index), the simple function stays, as [xxx_simple], the
   fast one is [xxx_opti], and [xxx] chooses:

     let draw_simple b = (* every shape of the page, at once *) ...
     let draw_opti b = (* a line's shapes when it is shown *) ...
     let draw b = if !Mini_opti.enabled then draw_opti b else draw_simple b

   A test checks that the two agree, and the switch shows what the
   optimization buys: opti=off on mini-chrome's command line, and on
   scripts/perf/Page_bench.exe's, runs the simple paths.

   A matter of judgment, not a rule (docs/plan_performance.md, "The
   way"): a small optimization is just made, and simple lines replaced
   by a few others can stay in a comment beside them, with no switch.
   The comments of every kind start "claude: opti:" and give the
   numbers measured (grep -rn "opti:").

   After elm-playground's Opti (tiny_libs.graphics_core; its
   notes_opti_ocaml.md, section 18), which is the software rasterizer's
   switch and another one: opti=off does not touch it, so that what is
   measured with and without is our code alone.

   Code checking [enabled] (search for "Mini_opti.enabled"):
   - Browser_draw.later: a line's shapes built when it is first shown,
     not all the page's at each relayout (the simple way: built at
     once). A relayout of a long page 450 ms to 28; the explanation
     and its picture are in Browser_draw.mli. *)

(* true: the optimized versions (the default) *)
val enabled : bool ref
