(* Browser_profile: its worked example (the Preferences file's text
 * and back), what is not understood skipped, a text that is not JSON
 * an error; a profile saved to a directory that is not there yet and
 * loaded again, a broken one left alone, and where the environment
 * puts the directory *)
val tests : < Cap.open_in ; Cap.open_out ; Cap.env ; .. > -> Testo.t list
