(* Browser_cpu: how busy the program's threads are, said at the tab
   strip's end beside the memory and told in about:memory.

     ... tabs ...   ▁▁▅▇▇▂ 212%   ▁▂▂▅▇▇  412 MB   OCaml 5.5.1, ...
                    a minute of the processor, then of the memory

     about:memory     Thread         Busy
                      tab 2          100%  ████████
                      the window      61%  █████
                      fetch 5         12%  █
                      tab 0            0%

   For Linux a domain of OCaml 5 and a thread of OCaml 4.14 are tasks,
   each with a file, /proc/self/task/TID/stat, whose 14th and 15th
   fields count the time it had the processor, in the program and in
   the kernel, in ticks of a hundredth of a second ([ticks]). Two
   readings ([read]) two seconds apart say what each did in between
   ([busy]): the ticks gained, by the seconds, are percents of one
   core. So 100% is a thread that never waited, and the sum can pass
   it: that is what domains are for. Who a task is, is what its
   thread said of itself as it started (Task_names): the window, a
   tab's domain, a worker of the network's pool; the ones that said
   nothing are the runtime's own (a domain's ticker, the collector's
   helpers).

   What to read there: a tab's domain at 100% while the window's is
   near 0 is a page working, or looping, and the window still
   answering; the window at 100% is a window that does not answer --
   a layout, or a page's script without tabs=domains. Under OCaml
   4.14 the threads take turns under one lock: the sum does not pass
   100% but in the kernel (a socket read, a file).

   Elsewhere than Linux nothing is read, and nothing shown.

   cs-history:
   Chrome's task manager (2008, with the first version: Shift+Esc) is
   this table a process, memory and CPU a tab, and "End process":
   the argument of its comic book for a process a tab was that one
   could see which page was the greedy one, and kill it. top's H key
   shows the same threads of any program, by the same files.

   modern:
   The numbers a browser shows its users now are the energy's: a
   tab's "energy impact" (Safari, then Firefox's about:processes,
   2021), since on a laptop a busy core is a battery emptied. *)

(* a moment's reading: each task's number and its ticks so far *)
type reading = (int * int) list

val read : < Cap.open_in ; .. > -> reading

(* the ticks counted in a task's stat file *)
val ticks : string -> int option

(* a thread: who it is (Task_names), and the percents of a core it took *)
type task = { name : string; percent : int }

(* what each task did between two readings, the busiest first *)
val busy : before:reading -> after:reading -> seconds:float -> task list
val total : task list -> int

(* about:memory's card: a row a thread; nothing when none was read *)
val card : task list -> string
