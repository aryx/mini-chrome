(* A site for a test: files in a temporary directory, and mini-httpd's
 * server (Httpd) forked on it *)

(* a new directory with these files (a name with a / makes its
 * directory); its path *)
val directory : (string * string) list -> string

(* the worked examples' site: index.html (a menu with two links),
 * recipes.html, notes/a.txt *)
val site : (string * string) list

(* [with_server caps files f]: [f] run with the URL of a server of
 * [files] ("http://127.0.0.1:PORT", no / at its end); the server
 * killed after *)
val with_server : < Cap.network ; Cap.open_in ; .. > -> (string * string) list -> (string -> unit) -> unit
