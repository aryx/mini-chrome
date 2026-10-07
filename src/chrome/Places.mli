(* Places: the pages already seen, and which of them is meant by a few
   letters typed in the omnibox.

   Each page shown is remembered -- its address, its title, how many
   times it was visited and when last -- and what is typed is looked
   for in all of them:

     visited      https://dynamicland.org/          "Dynamicland front shelf"   3 times, today
                  https://news.ycombinator.com/     "Hacker News"               9 times, yesterday

     typed "dyna"   suggested: Dynamicland front shelf - dynamicland.org
                    completed: dyna|micland.org|     (the end selected: typing on replaces it)
     typed "land"   suggested: the same (the letters are anywhere in the address or the title)
                    completed: nothing (no address starts with them)
     typed "news y" suggested: Hacker News (each word is looked for)

   [matching] is the list under the omnibox, the likeliest first;
   [completion] the one address put in the omnibox itself, when what
   is typed is the start of it ("www." and the scheme not counted).
   The likeliest is by a score of how often and how lately:

     score = visits x (100 if seen in the last 4 days, 70 in the last
             14, 50 in the last 31, 30 in the last 90, else 10)

   Kept in the profile's directory as History (JSON, its owner's
   alone: where one has been is one's own), written when it changed
   as the cookies are, the 2,000 best at most. profile=off keeps none.

   cs-history:
   The address bar completed addresses from the start: Netscape and
   Internet Explorer offered the URLs typed before that began with the
   same letters, http:// and www. included -- one had to remember how
   an address started. Firefox 3 (June 2008) changed what the bar was:
   its "awesomebar" looked for the letters anywhere, in the titles
   too, and ranked the pages by "frecency", a word made there of
   frequency and recency, computed from the visits kept in a SQLite
   database, Places, the name this module takes. Chrome (September
   2008) went one further and made the address bar and the search box
   one field, the omnibox: what is typed is an address, a page seen,
   or words to search, and the browser guesses which.

   modern:
   A real browser's bar asks more sources than its history, each a
   "provider" with a score, merged: bookmarks, open tabs, the search
   engine's own suggestions (asked as one types: what is typed leaves
   the machine), a calculator. Firefox's frecency also weighs how a
   page was reached (typed counts more than a link followed) and
   decays with time; the buckets above are its, the weights are not. *)

type entry = { url : string; title : string; visits : int; last : float (* seconds since 1970 *) }

(* the pages seen: changed in place, as the cookies' jar is *)
type t

val create : ?entries:entry list -> unit -> t
val entries : t -> entry list

(* how many times it was changed: what says it is to be written again *)
val changes : t -> int

(* a page shown, now: one visit more, its title as it is now (an
   address of about: is not kept) *)
val visit : t -> now:float -> url:string -> title:string -> unit

(* an address as it is typed and shown: no scheme, no www. *)
val bare : string -> string

(* the pages that have every word typed, in their address or their
   title, the likeliest first; six at most *)
val matching : t -> now:float -> string -> entry list

(* the address what is typed begins, to put in its place: the site
   alone ("dynamicland.org") unless what is typed goes past it *)
val completion : t -> now:float -> string -> string option

(* the page meant by an address as [bare] and [completion] write it *)
val address : t -> string -> string option

(* the History file's text, and back *)
val to_string : t -> string
val of_string : string -> (entry list, string) result

(* the file, in the profile's directory *)
val load : < Cap.open_in ; .. > -> dir:string -> (entry list, string) result
val save : < Cap.open_out ; .. > -> dir:string -> t -> (unit, string) result
