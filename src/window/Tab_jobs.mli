(* Tab_jobs: a tab's work done on a domain of its own, beside the
   window's -- so that a page that computes for a long time, or for
   ever, freezes its own tab and nothing else.

   Without it (the default), a message for a tab -- its page has come,
   a timer of its scripts is due, an answer to its request -- is work
   done in the window's own update: parsing, the scripts' run, the
   layout, each as long as it takes, the window drawn again after. A
   long run is cut in slices (Js_slice) so that the window can say
   "running the page's scripts", but nothing else is done meanwhile.

   With tabs=domains (OCaml 5: under 4.14 there is one domain), that
   work is a job given to a domain, and the window goes on:

     window's domain                         a tab's domain
     ---------------                         --------------
     Got (tab 3's page)
       on_tab 3 f  --------- job: f cfg tab --------->  parse, scripts,
     draws tab 3 as it was                               layout ...
     a click on the strip: tab 5 shown                   ...
     keys typed in the omnibox                           ...
     Tick: is 3's job done?  <------- (tab', commands) --
       tab 3 is tab'; its commands run (requests to send)

   What makes this possible is the program's shape: a tab is a value
   (Browser_tab.t) that [f] makes another of, and the window draws the
   value it has. Three rules keep it sound:

   - one job a tab at a time. What comes for a tab that is away waits
     its turn ([later]), in order; a timer's time that passed is added
     up ([owe]) and given in one go.
   - the window does not touch a tab's scripts while it is away: a
     click or a key meant for its page is kept ([hold]) and given when
     it is back. The chrome answers at once -- the strip, the omnibox,
     Back, the wheel (a scroll is shown at once and done again on the
     tab that comes back).
   - what the tabs' code kept in globals is a domain's own
     (Per_domain), or locked.

   A tab is given a domain by its number, of sixteen at most (a quarter
   of the machine's cores): its caches
   stay warm there, and two tabs on one domain take turns.

   wib: a script started by a click (not by the page's load or its
   timers) still runs in the window's domain, where its answer is
   waited for (did the page prevent the click?); a tab closed while
   away keeps its domain busy until its work ends, which a loop that
   never ends does not.

   modern:
   Chrome gives each site a process and the window another; Firefox
   came to the same in 2016-2017 ("Electrolysis"), after years of
   one process where a slow script froze the menus. A process can be
   killed, its memory given back, its crash survived; a domain shares
   the window's heap and cannot be -- what is bought here is the
   window's time, not its safety. *)

open Window_model

type work = msg Browser_tab.config -> Browser_tab.t -> Browser_tab.t * msg Cmd.t

(* tabs=domains, and a compiler that has domains: how many, 0 for none *)
val start : int -> unit
val enabled : unit -> bool
val domains : unit -> int

(* no more: the tabs' work in the window's domain again (what was away is forgotten; a test's end) *)
val stop : unit -> unit

(* whether a tab's work is being done elsewhere *)
val away : int -> bool

(* a tab's work given to its domain: [cfg] and the tab as they are now *)
val send : int -> msg Browser_tab.config -> Browser_tab.t -> work -> unit

(* work for a tab that is away, for when it is back; milliseconds of
   its scripts' clock that passed meanwhile; a message meant for its
   page *)
val later : int -> work -> unit
val owe : int -> float -> unit
val hold : msg -> unit

(* the tabs whose work is done: for each, the tab as it is now and its
   commands, what waited for it (in order), the clock's time owed. A
   job that raised is said and its tab left as it was *)
val back : unit -> (int * (Browser_tab.t * msg Cmd.t) option * work list * float) list

(* the messages kept, to give again, once no tab shown is away *)
val holding : unit -> bool
val held : unit -> msg list
