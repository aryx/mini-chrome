(* How fast the JavaScript engine is: small loops, and a real program.

     Js_bench.exe [page.html [frames]] [opti=off] [loops=off]

   The loops, each a script of its own, timed:

     a loop        3M turns of s = (s + i) | 0 in a function: names
                   read and written, two operators
     calls         1M calls of a function of two arguments
     properties    1M reads and writes of an object's property
     arrays        1M reads of an array's item
     closures      300,000 functions made and called once

   Then, if a page is given, the page's scripts run with no window
   (Browser_script, as scripts/js/Page_scripts.exe does): the time to
   run them, and the time of each of [frames] turns of 16 ms of its
   timers (10 by default) -- an animation frame of a program that draws
   with requestAnimationFrame. Its requests are answered "no network".

   The page it was written for is the Playground's menu compiled by
   js_of_ocaml (docs/plans/plan_tinybox.md): the page of
   https://aryx.github.io/ocaml-elm-playground/tinybox.html saved with
   its script inline (mini-curl -o), 538 KB of JavaScript that an
   engine must run sixty times a second.

   loops=off runs the page alone (under a profiler: valgrind
   --tool=callgrind, then callgrind_annotate). opti=off runs the simple code paths (Mini_opti): what an
   optimization of the engine buys is the two runs compared. *)
