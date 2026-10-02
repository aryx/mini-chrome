(* Browser_cookies: the cookies kept between two runs, and shown.

   A cookie with a date (Expires, Max-Age) outlives the browser: "keep
   me signed in" is that. Those are written in the profile's directory
   (Browser_profile's: ~/.config/mini-chrome), in a file beside
   Preferences, **Cookies**, JSON as it is:

     [ { "name": "lang", "value": "en-US", "domain": "example.com",
         "host_only": false, "path": "/", "expires": 1623233894,
         "secure": false, "http_only": false, "created": 1623147494 } ]

   read at the start (what is past its date left out) and written when
   the jar has changed (the main, a few seconds after, and when the
   program ends). A session's cookies, without a date, are not written:
   closing the browser signs out of what did not ask to be remembered.
   The file holds what signs its reader in: it is made readable by its
   owner alone. Chrome's is the same thing in SQLite, its values
   encrypted with a key of the desktop's keyring.

   And about:cookies ([page]): the jar as a table, a site's cookies
   together -- what a browser shows in its settings, here a page. *)

(* the file's text for those cookies of the jar that have a date *)
val to_string : Cookie.jar -> string

(* the cookies of that text; Error if it is not what [to_string] writes *)
val of_string : string -> (Cookie.jar, string) result

(* the cookies kept in [dir]'s Cookies file, without those past their
 * date at [now]: [] if there is no file yet; Error if it cannot be
 * read *)
val load : < Cap.open_in ; .. > -> now:float -> dir:string -> (Cookie.jar, string) result

(* the file written, the directory made if it is not there *)
val save : < Cap.open_out ; .. > -> dir:string -> Cookie.jar -> (unit, string) result

(* about:cookies: the jar's cookies at [now], by site *)
val page : now:float -> Cookie.jar -> string
