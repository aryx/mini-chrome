(* What this browser is, as it runs: about:version, and the few words
   of it shown at the end of the tab strip.

   One source builds several programs: with OCaml 4.14 or OCaml 5 (the
   pool's workers threads, or domains that run beside the window:
   Worker_spawn), drawn by Cairo or by the Playground's own rasterizer,
   with or without threads at all (threads=off). They look the same
   and do not behave the same -- a page that comes in 12 s in one
   takes 25 in another -- so the window says which one it is, in the
   corner where nothing else is:

     OCaml 5.5.1, 8 domains          OCaml 4.14.2, 8 threads

   and about:version says the rest: the compiler, the workers, where
   the profile and the cache are, how the program was started.

   modern:
   Chrome's chrome://version (about:version there too) is the page a
   bug report starts with: the version and its revision, the operating
   system, the JavaScript engine's version, the command line and its
   flags, the profile's path. Firefox's is about:support, longer. *)

(* "OCaml 5.5.1, 8 domains", "OCaml 4.14.2, 8 threads", "OCaml 4.14.2,
 * no threads": [threads] whether there is a pool, of [workers] asked *)
val label : threads:bool -> workers:int -> string

(* about:version *)
val page : threads:bool -> workers:int -> profile:string option -> cache:string option -> string
