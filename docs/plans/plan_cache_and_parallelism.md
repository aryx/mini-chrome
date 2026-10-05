# Plan: a cache on disk, and work done in parallel

Two ways to make a page come faster that are not a better algorithm:
not asking the network again for what it already gave, and using the
machine's other cores. Both are what the real browsers lean on, and
both are independent of `plan_performance.md`'s steps, which make each
stage cheaper.

## Where the time is (2026-10-05)

GitHub's repository page with its scripts on, the heaviest page the
browser runs (`timings=on`, after `plan_performance.md`'s step 7):

| | |
|---|---|
| to the last picture | 45 s |
| scripts | 10 s |
| styles | 6 s (24 passes) |
| boxes | 3.5 s |
| pictures decoded | 4.5 s (14 screenshots) |
| the rest of `update` | about 5 s |
| on the pool: TLS, Brotli, the bodies read | not measured |
| 143 answers, 7.9 MB | from 1 s to 36 s |

Everything in the first column but the last line runs on one core:
the window's thread, or the script's, which takes turns with it
(`Js_slice`). The pool's six threads fetch, but under OCaml 4.14 a
single lock lets one thread compute at a time: a thread there buys a
window that answers, not speed.

And what the servers say of their answers (`mini-curl -i`):

| | |
|---|---|
| `github.githubassets.com/assets/*.js`, `*.css` | `Cache-Control: public, max-age=31536000, immutable` |
| Hacker News' `news.css` | `max-age=312726389` |
| GitHub's page itself | `max-age=0, private, must-revalidate`, an `ETag` |
| Wikipedia's article | `max-age=0, must-revalidate`, `Last-Modified` |
| Discourse's page | `no-cache, no-store` |

About 125 of GitHub's 143 answers are files that will never change.

## Part one: the cache (RFC 9111)

**C1. `Http_cache`** (`libs/network`, pure: no file). From a
request and an answer's headers, three questions:

- may it be kept? A GET, a 200, no `no-store`; `private` is fine (the
  cache is one person's); a `Vary` other than `Accept-Encoding` is
  not kept, for a start;
- is the copy fresh? `max-age` (and `immutable`), else `Expires`,
  against the copy's age;
- if not, how to ask whether it changed: `If-None-Match` with the
  `ETag`, `If-Modified-Since` with `Last-Modified`; a 304 means the
  copy, with its date renewed.

Tested on strings, with the RFC's examples.

**C2. `Browser_cache`** (`src/chrome`): the files. A directory beside
the profile's, `~/.cache/mini-chrome/` (`XDG_CACHE_HOME`), a file an
entry named by the SHA-256 of its address (`tiny_libs.crypto`): the
headers that matter and the time, then the body as it was decoded. A
cap on the whole (200 MB), the oldest used going first. Opened with
`Cap.open_in` and `Cap.open_out`, and each file opened said with
`Logs.info`, as the profile's are.

**C3. The wiring.** In `Fetch.https_get`, which already runs on a
thread of the pool: the cache asked first, the network for what is
missing or stale, the answer kept. So the disk is never read on the
window's thread. `Http_request` (plain `http://`) the same.
`profile=off` uses no cache; `cache=off` alone turns it off; Reload
asks the network again (a real browser's reload revalidates).
`about:cache` lists the entries, as `about:cookies` the jar. The
network panel says "from cache".

**What it buys.** The second visit to GitHub sends some 18 requests
instead of 143. On this machine and line that is the seconds between
1 and 6 of the load, and more where the line is slow. It buys nothing
of the 30 s of computing: a cache of bytes is not a cache of work.

**What is left out, and why.** Chrome also keeps what it made of the
bytes -- V8's code cache, decoded pictures. Measured here: reading a
script (lexing, parsing, `Js_quicken`) is 0.7 s of a 13 s start, and
parsing GitHub's 2.2 MB of CSS 0.35 s. Keeping those trees
(`Marshal`) would save a second and add a format to keep right. Not
now. Heuristic freshness (a tenth of the time since `Last-Modified`)
and `Vary` on other headers: later, if a site needs them.

**Cost:** about 300 lines (`Http_cache` 120, `Browser_cache` 100, the
wiring 40, `about:cache` 40).

## Part two: in parallel

**The idea.** One `Worker` interface, as today (`submit`, `poll`),
whose workers are threads under OCaml 4.14 and domains under OCaml 5,
the choice made by dune: `Worker_spawn.ml` is copied from
`Worker_spawn.threads.ml` or `Worker_spawn.domains.ml` by two rules,
`(enabled_if (>= %{ocaml_version} 5.0))` and its opposite. `Mutex`
and `Condition` have the same names in both. The program is the same
source; under 5 a job on the pool really runs beside the window.

Why not processes (`fork`), which would work on both compilers: what
a job reads and gives back would cross a pipe as a copy. Fine for a
picture (bytes in, pixels out), wrong for a page's styles (a large
shared value, memo tables that would not come back); and a fork from
a program with threads and a window open is fragile. Chrome's
processes are for isolation first -- a tab that crashes, a site that
cannot read another's memory -- which is not what is wanted here.

**The steps**, each useful alone:

**P0. One layout a frame (done).** Not parallelism, but the same
goal: a picture come or a tree changed marks the tab (`stale`), and
the layout is made once at the next `Tick` (`Browser_tab.settle`).
GitHub: 39 layouts to 24, the same picture.

**P1. Pictures decoded on the pool.** The job that fetched a picture
decodes it before answering. 4.5 s off the window's thread on GitHub;
under 4.14 the window stays alive meanwhile, under 5 the pictures
decode beside it and beside each other.

**P2. Domains.** The dune rules above, the pool's size from
`Domain.recommended_domain_count` (eight at most; six threads under
4.14 as now, or more: they wait on the network). Then what the jobs
share must be safe, which a single lock no longer gives:

| Shared | Today | To do |
|---|---|---|
| `Keep_alive.pool` | a mutex | nothing |
| `Cookie_jar` | to check | a mutex if it has none |
| `Tls_client.roots`, `verified` | plain | a mutex |
| `Logs`' reporter | a mutex | nothing |
| `Stopwatch` | one stack | a mutex, or the window's thread only |
| the decoders (`Png`, `Jpeg`, `Gif`, `Webp`, `Svg`, Brotli, Zstd) | to read: any table filled at first use, any `lazy` | made at start, or locked |

Tested by building in the OCaml 5 switch this machine has (5.3.0;
the Playground installed in a scratch prefix, `OCAMLPATH`, so no
switch is changed) and by `make build-docker-ocaml5`, which CI runs.

**P3. Styles and boxes on the pool.** The page is an immutable
value: a job computes `Browser_page.with_tree` while the tab shows
the page it had, and the new one is put in its place at a `Tick` --
or thrown away if the tree changed again meanwhile. To make safe
first: `Cascade.last_index`, `Browser_page.last_styles` and
`parsed_sheets` (global memos: one layout job at a time, or a lock),
and the widths of letters the layout asks for (`Browser_text`). A
script that asks where an element is still gets its answer at once,
on its own thread. This is the step that keeps scrolling smooth
while a page restyles; under 5 it also puts the 10 s of styles and
boxes beside the 10 s of scripts.

**P4. Scrolling while a script runs.** Today what comes during a
script's run waits for its end. The wheel and the scrollbar touch
nothing a script reads: let them through between slices. Both
compilers.

**P5. The script on a domain of its own.** A script's run truly
beside the window, not in turns with it. The engine is used by one
domain at a time, but the window reads the script's tree
(`Browser_script.tree`) and tells it of events: every such meeting
becomes a message. The largest change and the last; to plan again
once P3 has shown what sharing costs.

**What it buys.** Under 4.14: no time, a window that answers during
a load. Under 5, a guess to be measured: the pictures, the pool's
TLS and Brotli, and the styles and boxes leave the script's core --
GitHub's 45 s towards 25. The scripts' own 10 s stay: one script,
one core, as in every browser.

**Cost:** about 250 lines (`Worker` and its two spawns 30, pictures
30, the locks 40, the layout job 120, scrolling 30). P5 not counted.

**The risks.** A data race is a bug that does not show in a test
that passes: under 5 each step is run under ThreadSanitizer once if
the switch has it, and the simple path stays (`threads=off`: no
pool at all, as today). OCaml 5's collector stops every domain for a
minor collection: more domains than cores makes that slower, hence
the cap.

## What was done, and what it gave (2026-10-05)

P0, P1, the cache (C1 to C3), P2 and P4, in a day; 415 lines.

| GitHub's page with its scripts, to its last picture | |
|---|---|
| the morning | 58 s |
| the styles cheaper (`plan_performance.md`, step 7) | 45 s |
| one layout a frame, pictures on the pool; OCaml 4.14 | 25 s |
| the same source, OCaml 5.5.1: the pool's workers domains | 12 s |

Three runs each, the two compilers in turn. The files' list has its
commits at 12 s with 4.14 and at 9 s with 5.5.1.

**The cache** did what was said and no more: the second visit reads
138 of 160 answers from the disk and has the files' list 5 s sooner;
the last picture comes no earlier, being behind the scripts.

**Domains** gave more than the guess (25 s, said the plan: 12). The
stages on the window's thread are themselves shorter under 5 (the
styles 4 s where 4.14 has 7): they no longer share the one lock with
eight threads decrypting and decoding.

What the audit found, each a line of `Worker_spawn.mli`'s list:

- two lazy tables in the Playground's decompressors (`Inflate`'s
  fixed codes, `Zstd`'s defaults), which two domains could ask for at
  once: made before the pool, by decompressing two small bodies
  (`Http.ready`). To be made plain values in the Playground one day;
- an SVG is drawn with the letters' tables, the window's: not decoded
  on a worker;
- OCaml 5 forks no process once a domain is there: `xrdb` is asked
  before the pool is made (it was), and a test starts its server
  before its pool;
- and one that was not parallelism's: OCaml 5.5 reads a carriage
  return and a newline in a quoted string as a newline, which broke
  Brotli's dictionary, embedded that way.

Left: P3 (styles and boxes on the pool: 5.6 s of the window's thread
on this page under 5.5.1, and what would keep scrolling smooth
through a restyle) and P5. ThreadSanitizer was not run.

## The order

1. P0 (done), P1: the window alive.
2. C1 to C3: the cache -- independent of the rest, and felt on every
   site at the second visit.
3. P2: domains, and the audit.
4. P3, then P4.
5. P5, after a look at what the others gave.

Both parts together: about 550 lines of the 3,700 the budget has
left.

## To decide

- The budget: 550 lines for speed is a seventh of what is left.
- Whether OCaml 5 becomes the compiler the README recommends, 4.14
  staying supported (CI builds both today).
- The cache's place and size: `~/.cache/mini-chrome`, 200 MB.
