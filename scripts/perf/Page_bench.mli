(* Where a page's load goes: each stage of the pipeline timed, on a real
   page fetched as the browser fetches it.

     Page_bench.exe [URL] [WIDTHxHEIGHT] [opti=off]
                          (Wikipedia's article on OCaml, 1400x713;
                           opti=off: the simple code paths, Mini_opti)

   It does by hand what Browser_page.read and laid_out do, a clock
   around each step:

     the network   the page, then again (the first time reads the TLS
                   roots and resolves the name), then each style sheet
                   the page asks for (its @imports too)
     the stages    Charset, Html_lexer, Html_tree, Computed.styles (the
                   cascade and the computed styles), Box_layout.layout,
                   Box_tree.as_html_layout, Browser_boxes.draw
     the whole     Browser_page.read with no sheet yet (what shows
                   first), laid_out when the sheets have come (the
                   cascade run), laid_out again (the styles memoized:
                   what a picture's arrival costs), then what the view
                   asks of it: the shapes of the window's lines
                   (Browser_draw.between), and of every line

   A stage on the CPU is run three times and its best time kept; the
   network once, as it comes. No picture is fetched: a page's pictures
   move its text but are not what its layout costs.

   What it does not time is the program around the page: how many times
   a load lays the page out, and what a frame costs once it is shown.
   scripts/perf/load_timeline.sh shows those, on the real program.

   The numbers that started docs/plan_performance.md (2026-10-01, the
   page 354 KB, 3,904 elements, 16,000 pixels high):

     Html_lexer, Html_tree        33 + 28 ms
     Computed.styles             290 ms
     Box_layout.layout            33 ms
     Browser_boxes.draw          557 ms
     laid_out, styles memoized   520 ms

   and after the plan's step 2 (a line's shapes built when shown,
   Browser_draw.later; opti=off gives the lines above again):

     Browser_boxes.draw            3 ms
     laid_out, styles memoized    28 ms
     the first window's shapes     6 ms *)
