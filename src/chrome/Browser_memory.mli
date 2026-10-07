(* Browser_memory: how much memory the browser holds, said at the tab
   strip's end and told in about:memory.

     ... tabs ...   +      ▁▂▂▅▇▇  412 MB   OCaml 5.5.1, 8 domains
                           a minute, a bar every two seconds

   The number is what the system says the program has in RAM
   ([resident]: Linux's /proc/self/statm; elsewhere OCaml's heap, which
   leaves out the pictures' pixels, kept outside it). The main reads
   it every two seconds into the model, the last thirty kept: the
   graph ([graph]), each bar a share of the highest of them.

   about:memory ([page]) says where it goes, as far as the browser
   knows -- a tab's pictures decoded (four bytes a dot: a photograph
   of eleven million dots is 44 MB, whatever its file's size), the
   pages it keeps for Back and Forward with their scripts' worlds
   (Bfcache: all of them, for as long as the tab), OCaml's heap -- and
   what is on disk: the answers kept (Browser_cache), the profile's
   files.

   Two limits keep a tab from only growing: the pages kept whole are
   the nearest ones (Bfcache.limit each way), and the pictures of the
   pages before stay decoded up to Browser_picture.kept_bytes. OCaml's
   heap, once grown (a large picture's decoding takes ten times its
   pixels for a moment), is not given back to the system.

   cs-history:
   about:memory is Firefox's (2011, from its "MemShrink" effort: the
   browser had a name for using too much), a tree of who holds what,
   measured by reporters each part of the program registers. Chrome
   has a task manager instead (Shift+Esc), a line a process: since
   each tab is a process, the system itself can say what a tab costs
   -- and can take it all back when the tab is closed, which no
   collector promises.

   modern:
   A browser under memory pressure discards: decoded pictures first
   (they can be decoded again), then the pages kept for Back, then
   whole tabs not looked at for long, reloaded when shown again
   (Chrome's "tab discarding", Memory Saver). *)

(* megabytes in RAM *)
val resident : < Cap.open_in ; .. > -> int

(* megabytes of OCaml's heap *)
val heap : unit -> int

(* the samples as bars, the last one last, ending at [x] on the line [y] *)
val graph : int list -> x:float -> y:float -> Playground.shape list
val graph_width : float

(* what a tab holds: its title, the pages kept behind and ahead, its
   pictures decoded and their megabytes *)
type tab = { title : string; kept : int; pictures : int; pixels_mb : int; heap_mb : int (* all that is reached from it in OCaml's heap (Obj.reachable_words) *) }

val tab : Browser_tab.t -> tab

(* about:memory: the samples (the last first), the tabs, the cache on
   disk (how many answers, their bytes, where), the profile's directory *)
val page : samples:int list -> tabs:tab list -> cache:(int * int * string) option -> profile:string option -> string
