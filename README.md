# mini-chrome

A small web browser written from scratch in OCaml, after Google Chrome
(2008): HTML, CSS (the cascade, the box model, flexbox, grid), a JavaScript
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
`make`), or `make run`; with an address, `./bin/mini-chrome
news.ycombinator.com`, that page (several: a tab each; words that are
not an address are searched): drawn by Cairo when its platform is installed,
else by the Playground's own rasterizer. `./bin/mini-chrome-software`
(`make run-software`) is always the latter, for comparison.

Flags: `url=` the first page (`about:chrome`), `css=off`,
`panel=elements` or `panel=network`, `search=duckduckgo`,
`profile=DIR` or `profile=off`, `scale=N`, `opti=off` (the simple code
where an optimized one replaced it), `letters=segments` (a letter drawn
as its pen's strokes). With `-v` the terminal shows each
file and URL opened (`-debug` more, `-quiet` nothing). Ctrl+Q quits
(with elm-playground after 0.3.1; with 0.3.1 a plain `q` does, wherever
it is typed).

A page longer than the window has a scrollbar at its right: drag its
thumb, or click above or below it for a page.

A right click on the page opens a menu: on a link, Open link in new
tab; elsewhere Back, Forward, Reload; Inspect in both.

On a screen of many dots everything is drawn bigger, at the desktop's
scale (`Xft.dpi`, GNOME's setting: twice at 192); Ctrl+Shift and `+` or
`-` change it, Ctrl+Shift+`0` goes back to the desktop's, `scale=N`
sets it.

Ctrl and `+`, `-` or the wheel zoom the page, Ctrl and `0` back to
100%; each site keeps its zoom, saved with the window's size in the
profile (`~/.config/mini-chrome/Preferences`, JSON).

## Layout

After [mmm](https://github.com/aryx/mmm)'s: the languages a page is
written in, general libraries, then the browser by role, each folder a
library, in the order they depend on each other:

```
libs/dom              the document as a tree (Dom): what HTML and XML are
                      read into, what CSS matches on and the rest walks
languages/html        HTML read: bytes to text, tokens, the tree
languages/xml         XML read into the same tree (Xml): an SVG file
languages/css         style sheets read and cascaded, computed styles
languages/javascript  a small JavaScript, with modules (Js_module) and
                      the later library written in itself (Js_prelude)
languages/json        JSON read and written, over JavaScript's lexer
libs/gui              the chrome's pieces that know no browser, as values
                      drawn and asked what is under a point: text in
                      cells (Gui_text), the tabs' strip (Gui_tabs), the
                      toolbar's buttons (Gui_toolbar), a menu opened at
                      a point (Gui_menu), a line typed into (Gui_field),
                      a scrollbar (Gui_scrollbar), the desktop's scale
                      (Gui_scale)
libs/compression      Brotli, the web's own compression (Content-
                      Encoding: br), decoded, with its dictionary of
                      the web's words; gzip and Zstandard are
                      elm-playground's
libs/images           the picture formats born of the web. PNG (Png:
                      filters, DEFLATE, Adam7). WebP, in webp/: the
                      file's chunks (Webp), the lossless format
                      (Vp8l), the lossy one, a key frame of the VP8
                      video codec (Vp8). SVG made pixels (Svg: paths, shapes,
                      fills and strokes; from an <svg> of a page or a
                      file, one tree). GIF and JPEG are
                      elm-playground's
libs/video            video as the web has it: a WebM file's frames found
                      (Webm) and decoded (Vp8_video: VP8's frames
                      predicted from others, over libs/images' Vp8);
                      what <video> plays of today's web
libs/audio            sound as the web has it: Vorbis decoded (Vorbis:
                      codebooks, floors, residues, the MDCT), an Ogg
                      file's packets (Ogg): a WebM's sound, and <audio>'s
libs/opti             the switch between an optimized function and the
                      simple one kept beside it (Mini_opti; opti=off)
libs/richtext         a look (Style): what the pen drawing a letter is told
libs/network          URLs, HTTP/1.1, cookies, TLS 1.3 and the sockets: a
                      GET that never blocks, stepped each frame
                      (Http_request); WebSocket, its handshake and
                      frames (Websocket) and a connection stepped
                      each frame (Websocket_client)
src/url/              links resolved (Browser_url)
src/layout/           where everything goes: CSS's box model (Box_layout,
                      over Box_tree, Box_inline and Box_flow), flexbox,
                      grid (Box_grid, Grid_layout), tables, Mosaic's flow; a point back to a link (Hit)
src/display/          a page drawn as shapes: Hershey's letters (and those
                      with an accent, put together: Glyph_unicode), pictures,
                      boxes (Browser_draw, Browser_boxes)
src/www/              the page as a document (Browser_page), its forms
src/dom/              JavaScript in a browser: the DOM a page's scripts
                      see (Script_dom, Script_host, Script_element,
                      Script_events, Script_document), window's globals
                      (Script_window), a script asking the network
                      (XMLHttpRequest, Script_fetch, WebSocket), a
                      page's modules (Script_modules) and their tasks (Browser_script:
                      the scripts, the events, the timers)
src/viewers/          <video> and <audio> (Browser_media, Media)
src/about/            the about: pages, the built-in site and about:tube
src/chrome/           a tab (Browser_tab), its requests in flight (Fetch),
                      the history, the developer tools, each site's zoom
                      (Browser_zoom), what the right click's menu offers
                      (Browser_menu), what is kept between runs
                      (Browser_profile), what it says it is to each
                      site (Browser_agent)
src/window/           the window as a Model-View-Update program over
                      those and libs/gui's pieces: Window_model (the
                      state, the messages), Window_layout (where each
                      part is, what is under the pointer), Window_tabs
                      (a tab changed, opened, closed; scroll, zoom),
                      Window_update, Window_view
src/main/             the main: the flags, the profile, the capabilities
                      handed down, the Playground run (MiniChrome.ml)
tools/                small programs beside the browser, made of its
                      libraries, for teaching:
                      node   mini-node: JavaScript outside a browser, the
                             same engine with a terminal for host (console,
                             process, timers and their loop, require, fs)
                      curl   mini-curl: a URL fetched and printed, by our
                             own HTTP, TLS, gzip and cookies (-v, -i, -L)
                      httpd  mini-httpd: a directory's files served, the
                             other end of the conversation; a
                             WebSocket asked for is an echo
                      lynx   mini-lynx: a page as text in the terminal,
                             its links numbered, a number typed to follow
                      mosaic    mini-mosaic: NCSA Mosaic, 1993 -- and the
                                web's first layout engine, the browser's
                                until CSS's replaced it: a look for each
                                element from a table (Mosaic_looks),
                                blocks and lines in one pass
                                (Mosaic_layout), drawn (Mosaic_draw)
                      netscape  mini-netscape: Netscape, 1994-1997: the
                                same engine with its extensions (fonts,
                                colours, floats, tables) and CSS1
                      firefox   mini-firefox: 2004: the same again, and
                                the page's scripts, a console, the tree
                      typeset   lines broken by Knuth and Plass
                                (mini-mosaic's wrap=pretty)
                      platform  the window the three are linked with
tests/                tools, html, xml, css, js, layout, browser, images, video, compression, network, network_unix
docs/                 architecture.md: the running program's shape (the
                      loop, the chrome's pieces, its one process and
                      threads next to Chrome's); dependencies.md: what
                      it stands on outside this repository, by kind;
                      history.md: how it came to be; sites.md: the sites it shows, and
                      what each lacks, by part, in colours; tags.md:
                      the theme tags of the interfaces' comments
                      (cs-history:, modern:...)
docs/tutorials/       a browser built stage by stage: notes_browser.md,
                      notes_css_engine.md, notes_javascript.md,
                      notes_tls.md
docs/plans/           what is being done: plan_performance.md (where a
                      load's time goes, what to change); done/: the
                      plans the tutorials followed (plan_browser_teaching,
                      plan_tiny_firefox, plan_tiny_chrome: the target
                      sites)
docs/related-work/    notes_browser_related_work.md: the browsers since
                      1990, and where this one stands
docs/dev/             notes_debugging_techniques.txt: how a page that
                      looks wrong, or slow, was looked into
scripts/              perf/: a page's stages timed (Page_bench), a load
                      in time (load_timeline.sh)
data/                 what is embedded and is not OCaml (data/README.md):
                      about/ the built-in site's pages, sheets, scripts,
                      pictures; tube/ about:tube's three clips made
                      elsewhere (ffmpeg, LAME); css/ua.css the
                      browser's own style sheet; prelude/ the library
                      and the small web APIs written in JavaScript
```

## License

LGPL 2.1 (see LICENSE), as elm-playground.
