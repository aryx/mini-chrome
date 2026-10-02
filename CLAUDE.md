# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A web browser written from scratch in OCaml (HTML, CSS, a JavaScript
engine, its own HTTP/1.1 and TLS 1.3), forked from
[elm-playground](https://github.com/aryx/ocaml-elm-playground)'s
TinyChrome. It still stands on elm-playground's opam packages (0.3.1+):
`elm_playground` (the Elm-architecture runtime, window and drawing) and
`tiny_libs` (picture/sound/video decoders, cryptography, Hershey fonts).
The only C is SDL (and Cairo, optionally). `docs/history.md` says how
it came to be, the decisions taken on the way, and what was next;
`docs/architecture.md` the shape of the running program (the
Model-View-Update loop, the chrome's pieces in `libs/gui` and their
style, the one process and its threads next to Chrome's, the
capabilities). Keep it true when one of those changes.

## Commands

```bash
./configure            # opam deps; checks SDL2 and Cairo (--software: no Cairo)
make                   # dune build
make test              # dune runtest -f, all eleven suites
make run               # dune exec mini-chrome
make run-software      # dune exec mini-chrome-software
./bin/mini-node f.js   # the JavaScript engine in a terminal (no file: a console)
./bin/mini-curl -v URL # the network stack alone: the request and the answer's head
./bin/mini-httpd DIR   # a directory served on http://127.0.0.1:8000/
./bin/mini-lynx URL    # a page as text, its links numbered (-dump: no prompt)
./bin/mini-mosaic      # the browsers before: Mosaic 1993 (url=, wrap=pretty),
./bin/mini-netscape    #   Netscape 1994-97 (url=, css=off, images=off),
./bin/mini-firefox     #   Firefox 2004 (url=, panel=off): tools/mosaic's engine
make loc               # lines of OCaml, and the budget's (loc-v: a library a line)
make build-docker      # what CI runs (OCaml 4.14.4; build-docker-ocaml5 for 5.5.1)
```

One suite, or one test (Testo; each `tests/<suite>/Test.ml` is its own
runner, the suites being `html`, `css`, `js`, `layout`, `browser`,
`network`, `network_unix`, `tools`, `images`, `xml`, `compression`):

```bash
dune build @tests/css/runtest --force
dune exec tests/css/Test.exe -- run -s specificity   # tests whose name contains it
```

A word of the command line that is not a flag is a page to open, an
address or words to search (`./bin/mini-chrome news.ycombinator.com`;
several: a tab each). Program flags are `key=value` words
(`dune exec mini-chrome -- url=https://news.ycombinator.com panel=network`;
their names are `flag_names` in `Window_update`, to keep up to date):
`url=`, `css=off`, `panel=elements|network`, `search=duckduckgo`,
`scripts=off|host1,host2`, `threads=off`, `profile=DIR|off`, `scale=N`,
`opti=off`, `letters=segments` (a letter as its pen's strokes, not one
picture: `docs/plan_performance.md`, step 4b).

Everything is drawn at a scale (`Window_layout.scale_of`): the one
chosen (Ctrl+Shift with `+`, `-`, `0`; `scale=N`; the profile's
`"scale"`), else the desktop's, which `Gui_scale` reads from `xrdb`'s
`Xft.dpi` (2 on a screen GNOME scales twice). The model's `screen` and
`mouse` are in the program's units, the window's dots divided by the
scale (`window` has the dots), and `view` scales the whole picture. With
SDL's dummy driver the desktop's scale is 1, so a dumped frame is the
same on every machine.

The profile (`Browser_profile`: the window's size and each site's
zoom, for now) is `~/.config/mini-chrome/Preferences`, JSON, read at
the start (before the window is made: its size is in it) and written
whole once a change has been still for a second (`saved`, on `Tick`)
and when the program ends (`main`'s `at_exit`, from `unsaved`: the
Playground has no message for the window closed, it calls `exit`). `profile=off` neither reads nor
writes it; `profile=DIR` uses another directory. A `Preferences` that
is not JSON is reported (a warning) and left alone: that run saves
nothing.

The cookies with a date are beside it, in `Cookies` (JSON too,
readable by its owner alone: `Browser_cookies`), read at the start into
the browser's one jar (`Cookie_jar`, in the `Fetch.t`: the requests,
on threads or not, say and keep cookies through it) and written by
the main when the jar changed, at most every five seconds, and at the
end. `about:cookies` shows the jar. A session's cookies are never
written, and `profile=off` neither reads nor writes any.

The Playground's own flags start with a dash. `-v` (or `-verbose`),
`-debug` and `-quiet` set the `Logs` level, as in xix's programs: with
`-v` the terminal shows what a page's scripts say on their console
(`console: ...`, their errors too) and each file and URL opened (the profile's file,
the TLS roots, every request and its answer, a program run). New code
that opens a file or a URL, or runs a program, says so with
`Logs.info`; a thread of `Worker`'s pool
may log too (the reporter has a mutex, set in MiniChrome's `main`).

The program is run with `skip_same_view = true` (a field of
`Playground.window`, what `run_app ~window` takes; elm-playground
after 0.3.3): a frame is not drawn when `view` gives
back the very list (`==`) of the frame before, which `Window_view.view`
does for a model that is the same but for its `time`. So a change
that the view must show has to be in the model (a new value of one of
its fields), not in a mutable thing beside it; and a new field of the
model is named in `Window_view.same_but_time`. What moves by itself
(a loading tab's wheel, a player) is `Window_view.animated`'s.

Ctrl+Q quits: the Playground's key (its window's `platform_keys = false`
would give the program every key; not used here). That is
elm-playground after 0.3.1; in 0.3.1 it was a plain `q`, which no
program could then receive.

The others make a change checkable without a screen: `-dump-frame n file.png` writes the nth
frame and exits, `-size WxH` sets the window's size, `-script
"space:3"` presses a key at a frame (here a page down). With SDL's
dummy drivers, no display is needed:

```bash
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
  ./bin/mini-chrome -size 1400x800 -dump-frame 5 /tmp/page.png url=about:tube panel=elements profile=off
```

`profile=off` so the dump does not depend on the window's size and the
zooms saved in the user's profile, and a `-size` or a `-script` that
zooms does not change them. The
file comes right after `-dump-frame n`: another flag put between the
two is taken as the file's name.

Read the PNG to see the page. Two such dumps, before and after a
change that should not move a pixel, compared with `cmp`, are the
cheapest regression test of the chrome. What a dump cannot check is
what needs a hand: dragging the window and the wheel (`-script` does
keys, `"left ctrl:2-9,=:3"` a Ctrl and +, and clicks, `at(x;y):8-20,click:10`).

When a change is needed in elm-playground itself (sibling checkout
`../ocaml-elm-playground`), mini-chrome only sees it after
`(cd ../ocaml-elm-playground && make && make install)`. That changes
the user's opam switch: ask first. To try a Playground change without
touching the switch, install a copy into a scratch prefix (`dune build
-p tiny_libs,tiny_languages,tiny_appkits,elm_playground,elm_playground_software,elm_playground_native
@install`, then `dune install --prefix DIR` the same packages) and build
here with `OCAMLPATH=DIR/lib`. A change to the Playground's interface or
platforms is presented as a plan and agreed on before it is made.

## Architecture

Each folder is one dune library, listed in the README in dependency
order: `libs/dom` (the `Dom` tree alone, a library of its own under
the languages, since HTML and XML are both read into it and CSS
matches on it) → `languages/` (html,
xml, css, javascript, json) → `libs/` (gui, richtext,
typeset, network, images, compression) → `src/` (url, layout, display, www, dom, viewers, about,
chrome, window, main). Nothing in `languages/` or `libs/` depends on
`src/`; a language may use a library (the `Dom`) and a library a
language (`libs/images`' `Svg` reads its files with `Xml`). `tools/` has the small programs beside the
browser, made of its libraries, each a library (its logic, tested in
`tests/tools`) and a main of a few lines: `tools/node` (`mini-node`,
the JavaScript engine in a terminal), `tools/curl` (`mini-curl`, a URL
fetched by our HTTP and TLS; `-v` to see a request that fails in the
browser), `tools/httpd` (`mini-httpd`, a directory served, and an echo for a WebSocket: the pages
of a test or a demonstration, instead of `python3 -m http.server`),
`tools/lynx` (`mini-lynx`, a page as text over `Line_mode`),
`tools/mosaic`, `tools/netscape` and `tools/firefox` (the browsers
before this one, in the order the web grew: windows of their own,
over the first layout engine, `tools/mosaic`'s libraries; their
platform is `tools/platform`'s choice and `tools/typeset` breaks
mini-mosaic's lines the Knuth and Plass way). The
browser is the subject of this repository, and a program that is not
part of it goes there, not in `src/`. `languages/` and `src/layout` are pure OCaml: no
Playground, no shapes, no fonts (glyph widths are passed in by the
caller), which is why their tests run on plain strings.

### The page pipeline

`Browser_page.read` (src/www) is the whole engine in one function, and
keeps every stage in its record (the developer tools show them):

```
bytes -Charset-> text -Html_lexer-> tokens -Html_tree-> Dom tree
      -Cascade-> winning declarations -Computed-> a style record per element
      -Box_layout (+ Flex_layout, Grid_layout)-> boxes -Browser_boxes-> Playground shapes
```

The browser has one layout engine, CSS 2.1's box model: `Cascade` +
`Computed` + `Box_layout` + `Browser_boxes`. The one it replaced,
Mosaic's fixed looks, is in `tools/mosaic` (`Mosaic_looks`,
`Mosaic_layout`, `Mosaic_draw`, and `Mosaic_page.engine`, which puts
them together): `Browser_page`'s settings take an `engine` (`None` for
the box model), and the three older browsers of `tools/` give that one
-- `mini-mosaic` (1993), `mini-netscape` (its extensions and CSS1 on),
`mini-firefox` (the same, and scripts). What the two engines share
stays in `src/`: the geometry both produce (`Html_layout`: boxes, lines,
fragments; `Box_layout` makes them with `Box_tree.as_html_layout`), a
word's look (`Looks.t`), and what works on those, `Hit`, the form
controls and the drawing of words (`Browser_draw`). The old engine is
not in the budget, and a change to those shared types must keep it
building, and their pages as they were:
`scripts/tools/dump_old_browsers.sh DIR` before and after, the two
compared with `cmp`.

`Box_layout` is four modules over `Box_types`' types (the box, a line's
words and floats, a block being laid out): `Box_tree` (a box read),
`Box_inline` (words set on lines beside floats), `Box_flow` (a block's
width, margins and content), and `Box_layout` itself, the recursion
over the page's tree (blocks, flex, shrink-to-fit, positioned boxes,
tables) that cannot be cut. `Box_layout.mli` tells the whole. A grid
container is beside it, not in it: `Box_grid` lays the items out with
`Grid_layout`'s numbers (the cells, the tracks' sizes; pure arithmetic,
as `Flex_layout` and `Table_layout`) and `Css_grid`'s values
(`languages/css`), and is given the recursion's two functions it needs
(an item laid out, its content measured) -- the way to add a layout
without growing `Box_layout`.

The built-in site is the browser's demonstration: `about:chrome`
(`data/about/chrome.html`, `chrome.css`) has a card for each thing the
engine does (the box model, the attributes' hints, flexbox, grid,
SVG), with the CSS that does it said in the card. A new feature of the
engine gets its card there, or its own page.

JavaScript is cut in three. `languages/javascript` is the language
alone (values, functions, promises; an async function's body is a
thread, `Js_coroutine`): nothing in it knows of a page, and nothing
of a browser goes there. `src/dom` is JavaScript in a browser: the DOM
and what `window` has. `tools/node` is the same engine with a terminal
for host, `mini-node` (`bin/mini-node file.js`, `-e text`, or a
console: `Node_host` has console, process, timers and the loop that
waits for them, `require` and CommonJS modules, `fs`): what Node.js is
to V8, for teaching, and the way to run a script with no page.

The `Dom` tree is an immutable value. `Browser_script` (src/dom) gives a page's
scripts a mutable copy (`Script_dom`: thaw), reached through host
objects (`Script_host`; `Script_element`, `Script_events`,
`Script_document` and `Script_window` for what libraries ask;
`WebSocket` for a socket that stays open (its asks and what the
connection says go the same way: `take_socket_asks`, the program's
`Web_sockets` in the `Fetch.t`, stepped each frame, `Got_socket`);
`XMLHttpRequest` and `Script_fetch` for a script asking the network,
whose requests the tab sends (`take_requests`) and answers by their
number (`Got_answer`, `Browser_script.answer`: a task, then a layout),
after `Script_fetch`'s one check of CORS: a new
member of an element, a new global of `window`, goes in the one it is
of), and freezes it back when it changed; the page
is then laid out again whole (`Browser_page.with_tree`). The
JavaScript engine itself knows nothing of pages: everything outside the
language is a record of host functions that `Browser_script` supplies.
Scripts run only on the built-in pages and on allow-listed hosts
(`default_allowed` in `Window_tabs`).

### Tabs, fetching and the program

The program is an Elm-architecture one over the Playground
(`init`/`update`/`view`/`subscriptions`, a `model` and a `msg`): the
window's chrome, the omnibox, the panels, and a list of tabs. It is
`src/window`, a module a concern:

| Module | What it is |
|---|---|
| `Window_model` | the `model` and `msg` types (an `.mli` alone) |
| `Window_layout` | the model read: where each part of the window is, what is under the pointer, the `libs/gui` pieces built from it |
| `Window_tabs` | the model changed: a tab's settings and `config`, `on_tab`, tabs opened and closed, scroll, zoom, scale, the profile |
| `Window_update` | `init` and `update`: what each message does |
| `Window_view` | `view`: the shapes |

`src/main/MiniChrome.ml` is only the main: the flags, the profile read,
the capabilities handed down, `run_app`. No module should pass about
700 lines: when one nears it, look for a split along a concern as
this one, and leave it whole if there is none.

The program's screen is the window itself (`run_app ~window`, with
`follows_window = true`), not the Playground's usual 1000 by 1000
picture scaled to fit: the model keeps the window's size (`screen`,
from `Sub.on_resize`), the origin is the window's centre with y up, and
every position is a function of the model anchored to an edge (`top m`,
`left m`, `toolbar_y m`, `omnibox_w m`, ...). So no literal 500 or 1000
in the view or the hit tests. A `Resized` lays every tab's page out
again at the new width (`Browser_tab.relaid`). A positive wheel notch
scrolls the page up.

A `Browser_tab.t` never touches a socket. It is parameterized by a
`'msg config` and asks for what it needs by returning a
`'msg Fetch.request` wrapped in a message (`Start_fetch`); the program
holds the single `Fetch.t` and calls `Fetch.step` on every `Tick`,
which returns the messages of the requests answered (`Got`,
`Got_picture`, each carrying its tab's id). `http://` is
`Http_request`, a non-blocking state machine stepped each frame
(each request's User-Agent is `Browser_agent.for_host`'s: the
browser's own name, but for the sites of its table, each with its
reason -- empty: Google was in it for a day, and why it is not is
told there);
`https://` is the blocking `Http_client` over our TLS, on `Worker`'s
pool of four threads. A page is shown at once, then laid out again as
each style sheet, script and picture arrives.

Every function that opens a socket takes a `Cap.network` capability,
threaded from `Cap.main` in MiniChrome.ml through `Browser_tab` and
`Fetch`. Files are the same: `Browser_profile` takes `Cap.open_in` to
read, `Cap.open_out` to write, `Cap.env` to find the directory, and
asks the object for the path (`caps#open_in path`) before opening it.
`init` and `update` get the capabilities they need and narrow them to
`< Cap.network >` for the tabs. Running a program takes `Cap.forkew`
(fork, exec and wait): `Gui_scale.desktop` asks `xrdb` for the
desktop's scale. New code touching a file or the
environment follows this; `Tls_client` (the roots' file, /dev/urandom)
predates it.

### The chrome's pieces

What the window's chrome is made of and that is not a browser's goes in
`libs/gui` (`Gui_text`, `Gui_tabs`, `Gui_toolbar`, `Gui_menu`,
`Gui_field`, `Gui_scrollbar`, the colours in `Gui_kit`, the desktop's
scale in `Gui_scale`), as values built from the model: `shapes` for the
view, a hit test (`at`, `chosen`) for update, no state, callback or
message of their own. `Window_layout` and `Window_tabs` build them
(`strip m`, `buttons m`, `scrollbar m`) and `Window_update` decides
what a hit means. A new piece of chrome goes there
unless it is specific to a browser (then `src/chrome`, as
`Browser_menu`).

### Build wiring worth knowing

- **`libs/network` is the one wrapped library** (`Network`), because
  the Playground links `tiny_libs`' networking, whose unwrapped modules
  have the same names (`Url`, `Http`, ...). Code never writes
  `Network.`: any library or test using it adds
  `(flags (:standard -open Network))` to its dune file. Everything else
  is `(wrapped false)`, hence the `Js_`, `Browser_`, `Css_` prefixes.
- **Two executables from one source.** `elm_playground` is a virtual
  library; `src/main/dune` picks Cairo's implementation when
  `elm_playground_native` is installed, else the software rasterizer
  (dune `select`, `Platform_choice`). `src/main/software/` copies
  `MiniChrome.ml` at build time and always links the rasterizer. Tests
  that link `elm_playground` use `elm_playground_software`.
- **Generated modules.** `Ua_sheet.ml` is `languages/css/ua.css` as a
  string. `Site_pages.ml`, `Site_pictures.ml` and `Tube_files.ml` embed
  `data/about/*` and `data/tube/*` (rules in `src/about/dune`). A new
  built-in page needs its file in `data/about/`, an entry in the
  `Site_pages.ml` rule (both `deps` and the `echo`/`cat` pair), and a
  case in `Site.ml`.
- `bin` is a symlink into `_build/install/default/bin`, excluded from
  dune by the root `dune` file.
- The root `dune` disables warnings 6, 32, 37 and 69 in dev.

## The sites

`docs/sites.md` is where the browser stands on the real web: a row a
site, a column a part (network, HTML, CSS, text, JavaScript), each
cell green, yellow or red with what is missing; and the same for
twelve real scripts given to the engine, each library then used in a
small page (`uses` in `Js_survey.ml`: a library that loads is not yet
one that works). When a feature changes a
site's or a script's colour, change its cell, and the date.
`scripts/sites/dump_sites.sh` dumps them all to look at;
`scripts/js/Js_survey.exe` runs the scripts, and
`scripts/js/Page_scripts.exe` a saved page's own, with no window: the
way to find what a real site's script stops on (`mini-curl -o` the
page, run it, read the first error; `-v` on the browser itself says
the same console).

## The budget

The browser is to stay under 30,000 lines of OCaml: `languages/`,
`libs/` and `src/`, their `.mli` files, comments and blank lines
included; not `tests/`, `scripts/` nor `tools/`, and not the opening
comment of an `.mli` (the module's documentation, where it teaches:
a cap is not a reason to teach less). `make loc` says where it stands
(`scripts/stats/loc.py`). Before a large feature, say what it will
cost; after it, what it did.

## Performance

`docs/plan_performance.md` says where a page's load goes and the steps
to take. Measure before and after with `scripts/perf/` (`Page_bench.exe`:
each stage timed on a real page; `load_timeline.sh`: the real program's
load, a time on each line of `-v`).

The simple code should still be there to read first, the optimized one
later: a matter of judgment, not a hard rule, as in elm-playground's
`libs/`. A small optimization is just made. Simple lines replaced by a
few others can stay in a comment beside them. Simple lines replaced by
an algorithm (a memo, a laziness, an index) stay runnable: the simple
function as `xxx_simple`, the fast one as `xxx_opti`, and `xxx`
choosing on `Mini_opti.enabled` (our own switch, `libs/opti`, set by
`opti=off`; not `tiny_libs`' `Opti`, whose name it cannot share), with
a test that the two agree. The comments start `opti:` and give the numbers measured.

## Conventions

- Every module has an `.mli`, including tests. The `.mli` opens with a
  long comment that is the module's documentation: the idea, a diagram,
  a worked example, references. Tests check those worked examples;
  update both together.
- That comment teaches, as elm-playground's `libs/**/*.mli` do (read
  one of a neighbouring subject first: `libs/compression/Brotli.mli`):
  where the thing came from (who, when, which browser shipped it
  first), what came before it and what it changed, where it stands
  among its neighbours, and the papers, RFCs and standards to read --
  the web's history told module by module (`XMLHttpRequest.mli`,
  `Cascade.mli`, `Js_promise.mli`). Only what is certain: a date left
  out rather than guessed. A famous name of the web gets its own
  module, to be seen in the tree (`XMLHttpRequest`). These lines are
  welcome, and not in the budget: `make loc` says how many they are.
- A paragraph of that comment that is around the module rather than
  the module's own has a theme tag on a line of its own before it:
  `cs-history:` (who, when, why it mattered), `modern:` (how the real
  browsers do it), `others:`, `evolution:`, `design:`... the
  vocabulary of principia's `Tags.tex`, told for this repository in
  `docs/tags.md`. One tag a paragraph at most; a fact in passing is
  not tagged; `make loc` counts the tagged lines by tag.
- Comments are not tagged `claude:` here (the global rule is for
  projects written by hand): all of mini-chrome is Claude's. An
  optimization's comment starts `opti:`.
- Tests are `tests/<suite>/Unit_<module>.ml` exporting `tests`
  (`Testo.categorize`, Alcotest checks), listed by hand in that suite's
  `Test.ml`. `tests/network_unix` forks its own localhost HTTP server
  (`Testutil_server`), so nothing needs the Internet; its TLS tests use
  a local `openssl s_server`.
- `changes.txt` (org-mode) is the changelog, updated with each feature
  in its own commit or alongside it.
- Comments mentioning `appkits/browser/...`, `engine/...`,
  `src/browser/...`, `apps/internet/`, `TinyMosaic`/`TinyNetscape`/
  `TinyFirefox` refer to elm-playground's tree, not this one. The
  browser's own notes and plans were brought to `docs/` here
  (`notes_browser.md`, `notes_css_engine.md`, `notes_javascript.md`,
  `notes_tls.md`, `notes_browser_related_work.md`, `plan_tiny_chrome.md`
  -- the target sites and what each needs --, `plan_tiny_firefox.md`,
  `plan_browser_teaching.md`): tutorials written as the code was, with
  that tree's paths. The other `notes_*.md` and `plan_*.md` a comment
  cites (`notes_gui.md`, `notes_images.md`, `notes_opti_ocaml.md`...)
  are still in `../ocaml-elm-playground/docs/claude_notes/`.
- `libs/network` is a copy of elm-playground's networking meant to
  diverge here (cookies, done: `Cookie`, `Cookie_jar`; keep-alive); the cryptography stays
  `tiny_libs.crypto`, and the compressions (`Http` decompresses a body with
  `Content-Encoding: gzip`, `br` or `zstd`) are `tiny_libs.compression`'s
  `Gzip`, `Brotli` (its dictionary a library of its own,
  `compression_brotli_words`) and `Zstd`, which
  are in elm-playground after 0.3.3: a compression is not a browser's.
- What was born of the web is told here, not in elm-playground, even
  when it was written there first: a copy, meant to diverge, as
  `libs/network`. `libs/images` has the picture formats: WebP
  (in `webp/`: `Webp`, `Vp8l`, `Vp8`; written here, checked pixel for pixel
  against libwebp's output in `tests/images`, whose `data/make.py`
  made the files), SVG (`Svg`) and PNG (`Png`, with PngSuite in
  `tests/images/pngsuite`), the last two copies. GIF and JPEG stay
  `tiny_libs`', and so does what `Svg` draws with (`graphics/2d`).
  An SVG file is read by `languages/xml`'s `Xml` into a `Dom`, the
  tree of an `<svg>` written in a page: `Svg` draws a `Dom.element`,
  whichever parser made it.
  `libs/compression` has Brotli (`Brotli`, `Brotli_dictionary`, and
  the dictionary's 120 KB in the binary, `Brotli_words`); gzip,
  Zstandard and `Huffman` stay `tiny_libs.compression`'s.
  `libs/network` has `Websocket`.
- A copy must not meet its original in the program: two modules of
  one name do not link. `tiny_libs.graphics_svg` is simply not linked.
  The Playground itself links `tiny_libs`' `Png` (textures, a frame
  dumped), so `libs/images` is wrapped (`Images`), as `libs/network`,
  and its users say `(flags (:standard -open Images))`. Brotli was in
  `tiny_libs.compression`, which we link for the rest: elm-playground
  after 0.3.4 has it in a library of its own
  (`tiny_libs.compression_brotli`, not linked here), and mini-chrome
  needs that version.
- `tiny_languages` cannot be linked here: its libraries stand on its
  own JavaScript, whose unwrapped modules (`Js_ast`, `Js_lexer`, ...)
  have the names of ours. What is needed from it is copied
  (`languages/json` is its `Json`, plus a printer); its `Jsonnet` would
  be too, for a configuration written by hand.
