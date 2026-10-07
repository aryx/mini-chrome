(* Browser_replay: a session with a site written down as it goes, and
   given again later with no network.

   A site that needs an account cannot be asked twice the same thing:
   its pages are the person's own, its requests carry a number and a
   time, and each try of a fix would be a new visit. So a visit is
   recorded once, by the person, and run again as often as needed, by
   the program alone:

     MINI_DUMP_PAGE=DIR/page.html     the page's bytes as they came
     MINI_DUMP_ANSWERS=DIR            each answer to a script's request:
                                      DIR/_seq/<md5 of its address less
                                      the query>-<n>, the nth to that
                                      address ([record])

     MINI_REPLAY=DIR                  every request answered from DIR,
                                      or 404: nothing asked of anyone
                                      ([answers])

   An address is looked for as its nth answer in DIR/_seq, then as
   DIR/_long/<md5 of the address less its query> (a script or a sheet
   fetched beside, whose address is too long for a file's name), then
   as the file of its path under DIR; and the first address asked, the
   page's, is DIR/page.html. The same places as
   scripts/js/Page_scripts.exe reads (FILES=DIR), which runs the
   page's scripts alone; here the whole browser runs -- the layout, the
   pointer, the window -- so a click that does nothing in the window
   can be made again with -script and looked at:

     MINI_REPLAY=DIR ./bin/mini-chrome profile=off -script "at(-100;135):200-260" \
       -dump-frame 400 /tmp/after.png url=https://mail.google.com/mail/u/0/

   profile=off with it: the person's cookies are not read, and a
   recording holds what the site showed them, to be kept as their mail
   is. docs/dev/notes_debugging_techniques.txt tells the whole method.

   others:
   Chromium's Web Page Replay records a page's answers to play them
   back for its benchmarks, and a HAR file (Network panel, "Save all
   as HAR") is the same recording in JSON; mitmproxy does it from
   outside the browser, for any program. *)

(* [record dir url body]: the answer to [url], written as its next one *)
val record : string -> string -> string -> unit

(* [answers dir] is the recording read: an address's answer, None when
   it has none (the first address asked is the page's) *)
val answers : string -> string -> string option
