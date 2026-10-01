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
it came to be, the decisions taken on the way, and what was next.

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

Program flags are `key=value` words on the command line
(`dune exec mini-chrome -- url=https://news.ycombinator.com panel=network`):
`url=`, `css=off`, `panel=elements|network`, `search=duckduckgo`,
`scripts=off|host1,host2`, `threads=off`.

The Playground's own flags start with a dash, and make a change
checkable without a screen: `-dump-frame n file.png` writes the nth
frame and exits, `-size WxH` sets the window's size, `-script
"space:3"` presses a key at a frame (here a page down). With SDL's
dummy drivers, no display is needed:

```bash
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
  ./bin/mini-chrome -size 1400x800 -dump-frame 5 /tmp/page.png url=about:tube panel=elements
```

Read the PNG to see the page. Two such dumps, before and after a
change that should not move a pixel, compared with `cmp`, are the
cheapest regression test of the chrome. What a dump cannot check is
what needs a hand: dragging the window, the wheel, clicks.

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
order: `languages/` (html, css, javascript) → `libs/` (richtext,
typeset, network) → `src/` (url, layout, display, www, viewers, about,
chrome, main). `languages/` and `src/layout` are pure OCaml: no
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
lines and fragments (`as_html_layout`), because `Hit`, the form controls
and the drawing of words work on those.

The `Dom` tree is an immutable value. `Browser_script` gives a page's
scripts a mutable copy (thaw), and freezes it back when it changed; the
page is then laid out again whole (`Browser_page.with_tree`). The
JavaScript engine itself knows nothing of pages: everything outside the
language is a record of host functions that `Browser_script` supplies.
Scripts run only on the built-in pages and on allow-listed hosts
(`default_allowed` in MiniChrome.ml).

### Tabs, fetching and the program

`src/main/MiniChrome.ml` is an Elm-architecture program over the
Playground (`init`/`update`/`view`/`subscriptions`, a `model` and a
`msg`): the window's chrome, the omnibox, the panels, and a list of
tabs.

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
`Fetch`.

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
