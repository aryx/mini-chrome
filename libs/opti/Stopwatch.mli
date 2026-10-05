(* Where the time goes: named stopwatches around the stages of the
   program, and the table of them when it ends (timings=on).

   A page that is slow is slow somewhere, and guessing where is how an
   afternoon is lost: GitHub's page with its scripts took a minute, and
   the JavaScript engine, the first suspect, was a quarter of it -- the
   styles computed again at each change of the tree were nearly half.
   So each stage of the pipeline is run in a span with its name:

     Stopwatch.time "styles" (fun () -> Computed.styles_all ...)

   and the program run with timings=on says, when it ends:

     timings: 61.2 s of 97.9 measured
       styles     39 times   25.5 s   (25.5 with what it calls)
       scripts   412 times   17.1 s   (24.0)
       boxes      39 times    4.2 s   ( 4.2)
       ...
       the collector: 212 major collections, a heap of 1,480 MB at most

   **Own time.** Spans nest: a script that asks where an element is
   has the page laid out, so "styles" runs inside "scripts". A span's
   own time is its time less its children's, and the own times add up
   to what was measured, which is what makes the table readable: the
   second number, the span with what it calls, counts the same second
   twice. A stack is all it takes -- a span, when it ends, gives its
   whole time to the one under it to take off.

   Off (the default), [time] is a test and a call: the spans stay in
   the code. They are few and wide, a stage and not a function: what
   says which part of the browser to look at. Which function of that
   part is a profiler's question (callgrind, or gdb interrupted every
   second: docs/dev/notes_debugging_techniques.txt).

   One stack for the program: a script's long run is on a thread of
   its own, but that thread and the window's take turns and never run
   together (Js_slice), so a frame drawn in the middle of a script is
   a span that opens and closes above the script's -- its child, and
   taken off it. What Worker's threads do (a request, its bytes
   decompressed) is not measured.

   modern:
   The real browsers answer the same question with the same idea at
   two scales. For a page's author, the User Timing API
   (performance.mark, performance.measure) is named spans the page
   makes itself, shown with the browser's own (style, layout, paint,
   script) on one timeline: the Performance panel of Chrome's
   developer tools, the Firefox Profiler. For the browser's own
   developers, Chrome's trace events (TRACE_EVENT in its C++, read in
   about:tracing, now Perfetto) are these spans, with a thread and a
   time each, kept rather than summed. Summed is the simple end: no
   timeline, the answer to "which stage" alone.

   References: W3C, User Timing (https://www.w3.org/TR/user-timing/);
   The Chromium Projects, "The Trace Event Profiling Tool
   (about:tracing)". *)

(* timings=on: spans are measured (off: [time name f] is [f ()]) *)
val enabled : bool ref

(* [time name f]: [f ()], its time added to [name]'s *)
val time : string -> (unit -> 'a) -> 'a

(* each name, how many times, its own seconds, its seconds with what
 * it called; the longest own time first *)
val spans : unit -> (string * int * float * float) list

(* the table, as lines: [since] the time the program started at *)
val report : since:float -> string list
