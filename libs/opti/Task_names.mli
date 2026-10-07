(* Task_names: what each of the program's threads is for, by the
   number the system knows it by.

     Task_names.here "tab 3"        said by a thread as it starts
     Task_names.of_task 48213       = Some "tab 3"

   A domain of OCaml 5 and a thread of OCaml 4.14 are both, for Linux,
   a task: a line of /proc/self/task, with its own count of the
   processor's time (Browser_cpu reads them). The system knows a task
   by a number and OCaml gives a domain another, so each pool's thread
   says here who it is, once: the task's number is read from
   /proc/thread-self, a link the kernel makes point to the thread that
   reads it (Linux 3.17; elsewhere nothing is kept, and no name is
   found). The one file this library opens, and not through a
   capability: it is the thread's own name tag.

   others:
   A C program names its threads for the system itself
   (pthread_setname_np, prctl's PR_SET_NAME: sixteen bytes, shown by
   top -H and by a debugger): Chrome's are "CrRendererMain",
   "ThreadPoolForegroundWorker", "Chrome_IOThread". OCaml's standard
   library has no such call. *)

(* the calling thread is [name] from now on *)
val here : string -> unit

(* the name said by the thread whose task this is *)
val of_task : int -> string option
