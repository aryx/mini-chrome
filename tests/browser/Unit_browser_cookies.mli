(* Browser_cookies: the Cookies file's text and back (the cookies with a
 * date only), the file written and read in a directory, those past
 * their date left out; about:cookies' page; and document.cookie, a
 * page's script reading and setting the jar (Browser_script) *)
val tests : < Cap.open_in ; Cap.open_out ; .. > -> Testo.t list
