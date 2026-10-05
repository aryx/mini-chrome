(* Browser_cache: copies kept in a directory and found again by their
 * address, the files used longest ago removed when the whole passes
 * its size, and about:cache's page; and Browser_version, its label
 * and about:version. *)
val tests : < Cap.open_in ; Cap.open_out ; .. > -> Testo.t list
