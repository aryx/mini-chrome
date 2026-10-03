(* Node_host: JavaScript outside a browser -- what Node.js is to V8.

   The engine (languages/javascript) is a language and nothing else: it
   cannot print, wait, read a file, nor even be given a second file.
   Everything of the kind is its host's. In the browser the host is a
   page (src/webapi: document, window, the events). Here it is a terminal:

   cs-history:
   JavaScript outside a browser is as old as JavaScript: Netscape's
   server ran it in 1995 (LiveWire), and Rhino (1997) ran it on Java's
   machine. Neither caught on. Ryan Dahl's Node.js (2009) did, and
   not for the language: he wanted a server that never blocks -- one
   loop, every call to the network or the disk given a function to
   call back -- and found in JavaScript the one popular language whose
   programmers already wrote that way, because a page's script has
   always been one thread and its events; V8 (2008) made it fast
   enough. Its modules were CommonJS's (2009), a convention agreed on
   by people who needed one before the language had any (ES2015's
   import came six years later, and the two live side by side still);
   npm (Isaac Schlueter, 2010) made them a registry of millions. Deno
   (Dahl again, 2018) and Bun (2022) are its critics.

       languages/javascript          the language: values, functions,
              |                      promises -- no way out
       +------+--------+
       |               |
     src/webapi        tools/node
     a page         a terminal
     document       console (the standard output)
     events         process.argv, .env, .exit, .stdout.write
     timers on      timers on the machine's clock, and a loop that
     the frames     waits for them
     <script src>   require("./file.js"), require("fs")

   **The loop.** A script runs to its end; then its jobs (the promises'
   thens: Js_promise); then, as long as a timer is set, the program
   sleeps until the earliest is due, calls its function, runs the jobs
   again. With no timer left it ends: Node's "event loop", here with
   timers as its only events.

     setTimeout(() => console.log("c"), 10)
     Promise.resolve().then(() => console.log("b"))
     console.log("a")                           // a b c

   **Modules** (CommonJS, Node's first kind). require("./lib.js") reads
   the file and runs it inside a function, so that its variables are its
   own, with three things in reach: [require], [module] and [exports]
   (module.exports, what the require gives back):

     (function (exports, require, module, __filename, __dirname) {
        ... the file's text ...
     })

   A file is run once: a second require of it gives the same object. It
   is noted before it is run, so two files that require each other end
   (the second sees the first's exports so far). A path is relative to
   the file that asks; ".js" may be left out. The program's own file is
   a module too.

   Of Node's own modules there is "fs", with readFileSync, writeFileSync
   and existsSync. No npm, no node_modules, no import (ES modules).

   Worked example (tests/js/Unit_node_host.ml):

     // lib.js                        // main.js
     let calls = 0                    const lib = require("./lib")
     exports.twice = x => {           console.log(lib.twice(4), lib.twice(5))
       calls++; return x * 2 }        console.log(require("./lib.js") === lib)
                                      // 8 10
                                      // true

   Reference: Ryan Dahl's talk at JSConf EU, 2009, where it was
   shown first; Node.js's documentation, "The Node.js Event Loop" and
   "Modules: CommonJS modules" (the module wrapper). *)

type t

(* [create caps ~argv ()]: an engine with the host's globals. [argv] is
 * process.argv after its first ("mini-node"): the script, then its
 * arguments. For a test: [print] and [complain] instead of the
 * standard output and error, [now] and [sleep] (milliseconds) instead
 * of the machine's clock *)
val create :
  < Cap.stdout ; Cap.stderr ; Cap.open_in ; Cap.open_out ; Cap.env ; Cap.exit ; .. > ->
  ?print:(string -> unit) ->
  ?complain:(string -> unit) ->
  ?now:(unit -> float) ->
  ?sleep:(float -> unit) ->
  argv:string list ->
  unit ->
  t

(* a file run as the program's module, then the loop to its end;
 * whether all went without an uncaught error (said by [complain], as
 * "file:line: message") *)
val run_file : t -> string -> bool

(* the same of a text (-e): not a module, its declarations are globals *)
val run_text : t -> string -> bool

(* [line t text]: a line of a console -- run, then the loop; what to
 * show, its value (None: undefined) or its error *)
val line : t -> string -> (string option, string) result
