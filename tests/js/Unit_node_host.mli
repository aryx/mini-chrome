(* JavaScript outside a browser (tools/node's Node_host): the loop and
 * its timers, modules, fs, process -- Node_host.mli's worked examples,
 * on files of a temporary directory and a clock of the test's own *)
val tests : < Cap.stdout ; Cap.stderr ; Cap.open_in ; Cap.open_out ; Cap.env ; Cap.exit ; .. > -> Testo.t list
