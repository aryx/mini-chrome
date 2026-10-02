# How mini-chrome came to be

A record of where this repository comes from and of the decisions taken
while it was set up (September 30 and October 1, 2026), written at the
end of the session that did it, so that later sessions and readers need
not rediscover them. `changes.txt` says *what* changed; this says *why
it is the way it is*.

## Before: the Tiny browsers of elm-playground

[elm-playground](https://github.com/aryx/ocaml-elm-playground) is an
OCaml port of Elm's playground that grew into a collection of small
programs, each a famous program rewritten from scratch for teaching,
and each held to a budget of 5,000 lines of its own code. Among them, a
family of web browsers showing how a browser grew:

| Program | After | What it added |
|---|---|---|
| TinyMosaic | NCSA Mosaic | HTML read and laid out, fixed looks |
| TinyNetscape | Netscape 1.0 | its extensions, pictures four at once |
| TinyFirefox | Firefox 1.0 | JavaScript, the DOM, a console after Firebug |
| TinyChrome | Chrome 1.0 (2008) | CSS's cascade and box model, flexbox, tabs, developer tools, real sites |

TinyChrome was the first aimed at the web as it is rather than at a
lesson, and it outgrew the budget (it was one of the listed exceptions).
A browser that should one day show Wikipedia and YouTube properly cannot
stay under 5,000 lines, so it needed a home of its own.

## What made the move possible: the opam packages

A separate repository needs to depend on elm-playground's code without
copying all of it. Just before the move, elm-playground's from-scratch
libraries were made installable on their own:

- `tiny_libs`: the libraries of `libs/`, which know nothing of the
  Playground (decoders, crypto, compression, fonts, ...)
- `tiny_languages`, `tiny_appkits`, `elm_playground_gamekits`: the
  languages, the kits that draw nothing, the game kits
- `elm_playground` and its platforms, as before

They were released together as 0.3.0, then 0.3.1 (opam-repository PR
#30843, still under review when this was written).

## The move (September 30, 2026)

The name is `mini-chrome`: the continuation of TinyChrome, one size up.

**What was copied, what is reused.** The rule the author gave:

- *Copied here, to grow*: TinyChrome itself, the browser code it shared
  with the other Tiny browsers, the languages a page is written in
  (HTML, CSS, JavaScript), and the networking.
- *Reused from `tiny_libs`*: everything else from scratch: pictures,
  sound and video decoders, cryptography, compression, fonts.
- *Reused from the Playground*: only the window and the drawing. "The
  main thing we rely on the Playground for is its core graphics."

So `tiny_languages` is not a dependency (the languages are here), and
the copy of the networking is meant to diverge (cookies, compression,
keep-alive), while its cryptography stays `tiny_libs.crypto`.

**The layout** imitates [mmm](https://github.com/aryx/mmm)'s:
`languages/`, `libs/`, then `src/` by role, each folder a library, in
dependency order (the README lists them). Later adjustments, all asked
for by the author:

- `src/protocols` was renamed `src/about`: there was already a
  `libs/network/protocols`.
- The built-in site's pages and about:tube's clips went to `data/` at
  the top level: "those are not src/ material".

**The networking is wrapped, but never prefixed.** The Playground links
`tiny_libs`' networking, whose unwrapped modules have the same names as
our copy's (`Url`, `Http`, ...), and `Net` was taken too (a neural
network in `tiny_libs`). The copy is therefore the one wrapped library,
`Network`. The author did not want `Network.Http_request` all over the
code ("Network. is long to type", "I prefer wrapped false"), so every
library using it passes `-open Network`, and the code reads as if it
were unwrapped.

**Fetching without the Playground.** In elm-playground a page is
fetched by a Playground command (`Http.get`), performed by the platform.
Here `src/chrome/Fetch` does it (a port of the platform's `Commands`): a
tab asks for a fetch by a message, the program steps the requests in
flight on every tick. The Playground no longer fetches anything for the
browser. Checked at the time: `https://example.com` rendered pixel for
pixel as in TinyChrome; Hacker News and Wikipedia loaded.

**No Cairo needed.** Two programs come from one source: `mini-chrome`
(Cairo's platform when installed, else the Playground's own rasterizer)
and `mini-chrome-software` (always the rasterizer). One binary choosing
at run time was considered and dropped: the Playground's platform is a
dune virtual library, chosen at link time. `./configure --software`
leaves Cairo out.

**The usual infrastructure**, modeled on the author's other projects:
`./configure`, `Dockerfile`, a GitHub Actions workflow, `make
build-docker`, the `bin` symlink, `changes.txt` in org-mode.

## The first fixes (October 1, 2026)

- **The window could not be resized usefully.** The Playground gives a
  program a fixed 1000 by 1000 screen and scales it into the window with
  black bars: right for a game, wrong for a browser. This needed a
  change in the Playground itself, `run_app ~screen_follows_window`
  (elm-playground 0.3.1, both native platforms): the screen is the
  window, drawn 1 to 1, and the program is told its size. MiniChrome's
  fixed geometry became functions of that size. The window starts at
  1280 by 900.
- **The wheel scrolled the wrong way**: a sign.

This is why mini-chrome requires 0.3.1 and not 0.3.0.

## Where it stood, and what was next

Discussed but not started when this was written, in the order proposed:

1. A missing `<h1>` (seen on example.com), a bug shared with TinyChrome.
   Not a bug, found the day it was to be fixed: example.com's page was
   rewritten and has no `<h1>` any more; the older page's heading is
   drawn. What that page did show (`light-dark()` and `100vh` of a
   constant 768, both fixed since; the grid) is in
   `notes_debugging_techniques.txt`.
2. CSS grid, at least what Wikipedia uses: its contents column is laid
   out above the article instead of beside it. Done (2026-10-02):
   `Css_grid`, `Grid_layout`, `Box_grid`; and example.com's
   `place-content: center`.
3. Speed: a Wikipedia article is slow to lay out, and a resize lays
   every tab out again. Measure first. Measured: the layout is 22 ms,
   the page's shapes built whole at each relayout are the half second,
   24 times a load: `plan_performance.md`.
4. Networking: gzip (the Inflate decoder is in `tiny_libs`, and the HTTP
   code refuses compressed bodies), then keep-alive, then cookies.
   gzip is done: `Gzip` added to `tiny_libs.compression` (it is no
   browser's), `Http` asking for it and decompressing. Cookies are
   done (2026-10-02): `Cookie`, `Cookie_jar`, `Browser_cookies`.

YouTube is the far goal: its pages need a modern JavaScript engine and
streaming video formats nothing here decodes yet.

Known loose ends:

- Until 0.3.1 is in opam-repository, `./configure` pins elm-playground's
  packages from the tag.
- gzip needs `tiny_libs`' `Gzip`, and the window at rest
  `run_app ~window` (`skip_same_view`), both in elm-playground after
  0.3.3 and in
  no release yet: the bounds (`dune-project`, 0.3.1) and the tag
  `./configure` pins are behind, and the CI fails until a release has
  it.
- `tests/network_unix` opens sockets on localhost and runs the `openssl`
  program. elm-playground's copy of those tests learned to skip itself
  in a sandbox without network (opam's on macOS); this copy has not.
- Comments in the copied code still name elm-playground's folders and
  notes (`appkits/browser`, `plan_tiny_chrome.md`, ...): see CLAUDE.md.
