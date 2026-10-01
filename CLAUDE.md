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
make test              # dune runtest -f, all seven suites
make run               # dune exec mini-chrome
make run-software      # dune exec mini-chrome-software
make build-docker      # what CI runs (OCaml 4.14.4; build-docker-ocaml5 for 5.5.1)
```

One suite, or one test (Testo; each `tests/<suite>/Test.ml` is its own
runner, the suites being `html`, `css`, `js`, `layout`, `browser`,
`network`, `network_unix`):

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
`scripts=off|host1,host2`, `threads=off`, `profile=DIR|off`, `scale=N`.

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

The Playground's own flags start with a dash. `-v` (or `-verbose`),
`-debug` and `-quiet` set the `Logs` level, as in xix's programs: with
`-v` the terminal shows each file and URL opened (the profile's file,
the TLS roots, every request and its answer, a program run). New code
that opens a file or a URL, or runs a program, says so with
`Logs.info`; a thread of `Worker`'s pool
may log too (the reporter has a mutex, set in MiniChrome's `main`).

Ctrl+Q quits: the Playground's key (its `run_app ~platform_keys:false`
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
order: `languages/` (html, css, javascript, json) → `libs/` (gui, richtext,
typeset, network) → `src/` (url, layout, display, www, viewers, about,
chrome, window, main). `languages/` and `src/layout` are pure OCaml: no
Playground, no shapes, no fonts (glyph widths are passed in by the
caller), which is why their tests run on plain strings.

### The page pipeline

`Browser_page.read` (src/www) is the whole engine in one function, and
keeps every stage in its record (the developer tools show them):

```
bytes -Charset-> text -Html_lexer-> tokens -Html_tree-> Dom tree
      -Cascade-> winning declarations -Computed-> a style record per element
      -Box_layout (+ Flex_layout)-> boxes -Browser_boxes-> Playground shapes
```

There are two layout engines, a legacy of the teaching browsers this
came from. `Html_layout` + `Looks` + `Css` + `Browser_draw` are Mosaic's
fixed looks; `Box_layout` + `Cascade` + `Computed` + `Browser_boxes` are
CSS 2.1's box model. MiniChrome always sets `settings.boxes = true`, so
the second is the live path. `Box_layout` still produces `Html_layout`'s
lines and fragments (`Box_tree.as_html_layout`), because `Hit`, the form
controls and the drawing of words work on those.

`Box_layout` is four modules over `Box_types`' types (the box, a line's
words and floats, a block being laid out): `Box_tree` (a box read),
`Box_inline` (words set on lines beside floats), `Box_flow` (a block's
width, margins and content), and `Box_layout` itself, the recursion
over the page's tree (blocks, flex, shrink-to-fit, positioned boxes,
tables) that cannot be cut. `Box_layout.mli` tells the whole.

The `Dom` tree is an immutable value. `Browser_script` gives a page's
scripts a mutable copy (thaw), and freezes it back when it changed; the
page is then laid out again whole (`Browser_page.with_tree`). The
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

The program's screen is the window itself (`run_app
~screen_follows_window:true`), not the Playground's usual 1000 by 1000
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
`Http_request`, a non-blocking state machine stepped each frame;
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

## Conventions

- Every module has an `.mli`, including tests. The `.mli` opens with a
  long comment that is the module's documentation: the idea, a diagram,
  a worked example, references. Tests check those worked examples;
  update both together.
- Tests are `tests/<suite>/Unit_<module>.ml` exporting `tests`
  (`Testo.categorize`, Alcotest checks), listed by hand in that suite's
  `Test.ml`. `tests/network_unix` forks its own localhost HTTP server
  (`Testutil_server`), so nothing needs the Internet; its TLS tests use
  a local `openssl s_server`.
- `changes.txt` (org-mode) is the changelog, updated with each feature
  in its own commit or alongside it.
- Comments mentioning `appkits/browser/...`, `engine/...`,
  `src/browser/...`, `apps/internet/`, `TinyMosaic`/`TinyNetscape`/
  `TinyFirefox`, and the `notes_*.md` / `plan_*.md` files refer to
  elm-playground's tree, not this one. The notes and plans are in
  `../ocaml-elm-playground/docs/claude_notes/` (`tutorials/`, `plans/`);
  `plan_tiny_chrome.md` lists the target sites and what each needs.
- `libs/network` is a copy of elm-playground's networking meant to
  diverge here (cookies, compression, keep-alive); the cryptography
  stays `tiny_libs.crypto`.
- `tiny_languages` cannot be linked here: its libraries stand on its
  own JavaScript, whose unwrapped modules (`Js_ast`, `Js_lexer`, ...)
  have the names of ours. What is needed from it is copied
  (`languages/json` is its `Json`, plus a printer); its `Jsonnet` would
  be too, for a configuration written by hand.
