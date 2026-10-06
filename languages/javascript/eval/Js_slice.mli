(* A long run of a script cut in slices, the browser's window alive
   between them.

   A page's script runs to its end before anything else happens: that
   is the web's rule (one thread, "run to completion"), and what makes
   a page's code simple -- nothing changes under it. Its price is the
   frozen page: an application that takes ten seconds to start is a
   window that does not answer for ten seconds, where the script and
   the window share a thread. Here they would: the evaluator is called
   by the program's update, and the program draws between two updates.

   So a run that may be long is made on a thread of its own, and the
   two threads take turns, never both at once:

     the window                      the script
     ----------                      ----------
     run f  ----------------------->  f starts
       (waits)                        ... a quarter of a second of work ...
     false  <-----------------------  breath (): "a slice is over"
     draws a frame                      (waits)
     continue ()  ------------------>  goes on where it was
       (waits)                        ... to its end
     true   <-----------------------  f is done

   [breath] is called by the evaluator at each call of a function
   (Js_eval.call_value): cheap, a counter, and the clock read every
   thousand calls. It is the one place where the script stops, so what
   the window finds between two slices is whole: no table half
   written. What the window must not do meanwhile is call the engine
   again -- the page's script is in the middle of a run: the program
   keeps what comes (a key, an answer from the network) for after
   (MiniChrome's update).

   The script itself sees nothing of it: no other code of the page
   runs between its slices, as the rule says.

   A slice is the run's own to end: [breath] must be called by the
   run's thread (or an async function's it resumed), never by a
   thread working beside it. One that did -- a worker of the pool
   reading a script ahead, the parser taking its breaths -- ended a
   slice of a run that was not its own; the run, never stopped,
   reached its end unseen, and the window, told to go on with a run
   that was no more, waited for it for ever (a load of GitHub in
   fifteen). Hence [Js_parse.parse ~aside], and [continue], which
   starts nothing if nothing is paused.

   A coroutine, then, as Js_coroutine's are (an async function stopped
   at an await), with one more partner: the thread that takes the
   breath may be an async function's own, deep in a run; it is that
   one which waits, and that one which is told to go on.

   modern:
   A browser draws on other threads and other processes than the
   page's script (Chrome's compositor): a page whose script is busy
   still scrolls. What a busy script blocks there is the page's own
   answers, and after some seconds the browser offers to stop it.

   Reference: HTML, "Event loops" (8.1.7): a task runs to completion. *)

(* a slice's length, in seconds; [enabled] false: [run] runs to the end
 * on the caller's thread (a test; threads=off) *)
val length : float ref
val enabled : bool ref

(* [run f]: f started; whether it is done (else a slice is over, and
 * [continue] goes on). An exception of f's is raised by the call
 * during which it ends *)
val run : (unit -> unit) -> bool

(* the next slice of the run started; whether it is done *)
val continue : unit -> bool

(* the evaluator's: a slice is over if its time is, and the run waits
 * for [continue]. Nothing, outside a [run] *)
val breath : unit -> unit

(* the same, the clock looked at now and not one call in a thousand:
 * for the evaluator's count of steps, so that a loop that calls
 * nothing (while (x) i++) lets the window be drawn too *)
val breath_now : unit -> unit
