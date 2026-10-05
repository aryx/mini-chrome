(* What a worker of the pool is: a thread, or a domain -- the one line
   of Worker that depends on the compiler.

     OCaml 4.14                          OCaml 5
     ---------------------------------   ---------------------------------
     Thread.create                       Domain.spawn
     one lock for the whole runtime:     a heap a domain for what is young,
     a single thread runs OCaml at a     one shared for the rest: the
     time, the others wait or block      domains run at the same time, a
     in a system call                    core each

   The same program is built by both. dune copies one of two files to
   Worker_spawn.ml, by the compiler's version (libs/network/dune):

     spawn/threads.ml.in    (enabled_if (< %{ocaml_version} 5.0))
     spawn/domains.ml.in    (enabled_if (>= %{ocaml_version} 5.0))

   Nothing else changes: Mutex and Condition have the same names and
   the same meaning in both (in 4.14 they come with the threads
   library, in 5 they are the standard library's, and work between
   domains), and a job is a closure either way.

   What changes is what a job may assume. Under 4.14 a job that only
   computes is never run at the same instant as the window's code, and
   two threads writing one table take turns without knowing it. Under
   5 they really run together: what jobs share must be behind a mutex
   (Keep_alive's connections, Cookie_jar, Tls_client's chains checked,
   Browser_picture's pictures decoded ahead, Js_module's texts read
   ahead, the log's reporter), or made before the first job starts
   (Http.ready; the parser's table of operators). [parallel] says which world it
   is, for who must do something more in that one.

   cs-history:
   OCaml had threads from 1995 (Xavier Leroy's, over the bytecode
   interpreter, then POSIX threads) and for twenty-five years a
   runtime that one thread at a time could enter. Multicore OCaml
   (KC Sivaramakrishnan, Stephen Dolan and others, from 2014) gave the
   collector a minor heap a domain and a shared major heap collected
   concurrently; it was merged as OCaml 5.0, released in December
   2022.

   Reference: KC Sivaramakrishnan et al., "Retrofitting Parallelism
   onto OCaml" (ICFP 2020). *)

(* do the pool's workers run at the same time as the window's code? *)
val parallel : bool

(* how many workers for a pool asked of that many: as asked for
 * threads, which mostly wait; a core each at most for domains *)
val workers : int -> int

(* a worker running [f], which does not return *)
val spawn : (unit -> unit) -> unit
