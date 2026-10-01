# mini-chrome

A small web browser written from scratch in OCaml, after Google Chrome
(2008): HTML, CSS (the cascade, the box model, flexbox), a JavaScript
engine, SVG, pictures, `<video>` and `<audio>`, tabs, an omnibox and
developer tools.

From scratch all the way down: its own networking too (HTTP/1.1 over
its own TLS 1.3 client), and its pictures, sound and video decoders,
its cryptography and even its drawing, by a software rasterizer instead
of Cairo if you like, are elm-playground's, written from scratch as
well. Of C it needs only SDL, for the window.

It started as [elm-playground](https://github.com/aryx/ocaml-elm-playground)'s
TinyChrome, a toy held to 5,000 lines of its own code; here it grows,
towards the web as it is (Wikipedia first, YouTube one day).

## Building

It stands on elm-playground's packages, 0.3.1 or later: the Playground
for its window and drawing, on one of its two native platforms (SDL
for the window either way, and Cairo, `elm_playground_native`, or the
Playground's own rasterizer, `elm_playground_software`), and
`tiny_libs` for the pictures, sound and video decoders.

```bash
./configure    # the opam dependencies, and checks for SDL2 and Cairo
make
make test
```

`./configure --software` leaves Cairo out altogether, as it does by
itself when Cairo is not found.

Working on both repositories side by side, install elm-playground's
packages from its checkout into your switch instead (again whenever
mini-chrome should see a change there), then build here:

```bash
(cd ../ocaml-elm-playground && make && make install)
./configure
make
```

Then `./bin/mini-chrome` (a symlink into `_build`, alive after a
`make`), or `make run`: drawn by Cairo when its platform is installed,
else by the Playground's own rasterizer. `./bin/mini-chrome-software`
(`make run-software`) is always the latter, for comparison.

Flags: `url=` the first page (`about:chrome`), `css=off`,
`panel=elements` or `panel=network`, `search=duckduckgo`,
`profile=DIR` or `profile=off`. With `-v` the terminal shows each
file and URL opened (`-debug` more, `-quiet` nothing).

Ctrl and `+`, `-` or the wheel zoom the page, Ctrl and `0` back to
100%; each site keeps its zoom, saved with the window's size in the
profile (`~/.config/mini-chrome/Preferences`, JSON).

## Layout

After [mmm](https://github.com/aryx/mmm)'s: the languages a page is
written in, general libraries, then the browser by role, each folder a
library, in the order they depend on each other:

```
languages/html        HTML read: bytes to text, tokens, the tree (Dom)
languages/css         style sheets read and cascaded, computed styles
languages/javascript  a small JavaScript
languages/json        JSON read and written, over JavaScript's lexer
libs/richtext         a look (Style), text laid out on pages
libs/typeset          lines broken, greedy or by Knuth and Plass
libs/network          URLs, HTTP/1.1, TLS 1.3 and the sockets: a GET that
                      never blocks, stepped each frame (Http_request)
src/url/              links resolved (Browser_url)
src/layout/           where everything goes: CSS's box model, flexbox,
                      tables, Mosaic's flow; a point back to a link (Hit)
src/display/          a page drawn as shapes: Hershey's letters, pictures,
                      boxes (Browser_draw, Browser_boxes)
src/www/              the page as a document (Browser_page), its scripts
                      and DOM (Browser_script), its forms
src/viewers/          <video> and <audio> (Browser_media, Media)
src/about/            the about: pages, the built-in site and about:tube
src/chrome/           a tab (Browser_tab), its requests in flight (Fetch),
                      the history, the developer tools
src/main/             the window: tabs, omnibox, panels (MiniChrome.ml)
tests/                html, css, js, layout, browser, network, network_unix
data/about/           the built-in site's pages, sheets, scripts, pictures
data/tube/            about:tube's two clips made elsewhere (ffmpeg, LAME)
```

## License

LGPL 2.1 (see LICENSE), as elm-playground.
