(* Tests of Browser_memory: the reading, the graph, about:memory; and
   of Browser_cpu beside it: a task's ticks, the threads' share *)
val tests : < Cap.open_in ; .. > -> Testo.t list
