# The architecture of mini-chrome

How the program is put together, and how that compares with the real
Chrome. `README.md` lists the folders, `CLAUDE.md` the page's pipeline
and the build's wiring, `docs/history.md` how it came to be; this file
is about the shape of the running program.

## One program, three layers

```
languages/   html, xml, css, javascript,      text in, values out; no window
             json
libs/        dom, gui, richtext, network,     general, not a browser's
             images, video, compression
src/         url, layout, display, www, dom,  the browser, by role
             viewers, about, chrome, window, main
tools/       node, curl, httpd, lynx,         programs beside the browser, made of
             mosaic, netscape, firefox        its libraries: mini-node, mini-curl,
                                              mini-httpd, mini-lynx; and the browsers
                                              before it, over the first layout engine
```

JavaScript is in three places, and the cut matters. `languages/javascript`
is the language alone: it cannot print, wait, nor read a file, and
knows nothing of pages. What a script can reach outside itself is its
host's, and there are two hosts:

```
                 languages/javascript     values, functions, promises
                    |              |
                 src/dom        tools/node
                 a page         a terminal (mini-node)
                 document,      console, process, require and its
                 events,        modules, fs, timers on the machine's
                 timers on      clock and the loop that waits for
                 the frames     them
```

Each folder is one library, and a library only uses those above it in
this list. `languages/` and `src/layout` are pure: no Playground, no
fonts, no sockets, which is why their tests run on strings.

## The program is Model-View-Update

The browser's window is an Elm-architecture program over the
Playground's `run_app`, in `src/window`; `src/main/MiniChrome.ml` is
its main (the flags, the profile read, the capabilities handed down):

```
            +-------------------- msg --------------------+
            |                                             |
            v                                             |
   update : msg -> model -> model * cmd        subscriptions: Tick, Key,
            |                                   Click, Right_click, Wheel,
            v                                   Resized, ...
          model  ---- view ---->  shapes  ----> the window (SDL)
```

- The **model** is the whole state: the tabs, which one is shown, the
  omnibox's text, the pointer, the window's size, the developer tools,
  the profile, an open menu.
- **update** is the only place it changes. It is not pure: it starts
  fetches (`Fetch.perform`), runs the page's scripts, and saves the
  profile. Those effects are few and all there.
- **view** rebuilds every shape of the window from the model at each
  frame. Nothing on screen is kept from the frame before.

A module a concern, each using only those above it:

| Module | Its concern | Lines |
|---|---|---|
| `Window_model` | the state and the messages: types alone | 58 |
| `Window_layout` | the model read: where each part is, what is under the pointer, the `libs/gui` pieces built from it | 129 |
| `Window_tabs` | the model changed: a tab's settings, one changed, opened, closed; scroll, zoom, scale, the profile | 167 |
| `Window_update` | `init` and `update`: what each message does, in the order of who gets an event | 235 |
| `Window_view` | `view`: the shapes, back to front | 145 |

It was one file of 875 lines; the rule of thumb is that a module stays
under about 700, split along a concern when there is one.

A tab (`Browser_tab.t`) is a value inside the model. It never touches a
socket: it returns the requests it wants as messages, and the program
holds the one `Fetch.t` that performs them and steps it on every `Tick`.

## Units: the window's dots, the program's, the page's

Three sizes of "one", each a multiple of the next:

```
   the screen's dots        what the window is measured in (model.window)
     / scale                the desktop's (Gui_scale: Xft.dpi / 96), or the
                            one chosen with Ctrl+Shift + and -
   the program's units      the chrome is laid out in these (model.screen,
                            model.mouse): a toolbar 42 high, letters 6 wide
     / zoom                 the shown page's site's (Ctrl + and -)
   the page's units         CSS's px: what the page is laid out in
```

`view` builds the picture in the program's units and scales it whole;
the pointer and the window's size are divided on the way in. So nothing
in the chrome or the layout knows the scale. With a scale of 2 a window
of 2560 dots is 1280 units wide, and a page sees 1280 CSS px: what
Chrome calls the device scale factor.

## The chrome's pieces: `libs/gui`

The window's chrome is made of pieces that are not specific to a
browser: text in cells, the strip of tabs, the toolbar's picture
buttons, the status bubble, the right click's menu. They live in
`libs/gui`, in the same Model-View-Update style, in its plainest form:

```
   a piece is a value, built from the model when it is needed

   in view     Gui_tabs.shapes (strip m) ~time      the value, drawn
   in update   Gui_tabs.at (strip m) m.mouse        on a click: what is there?
```

A piece has no state of its own, no callback and no message type. What
it would have to remember (a menu open, the tab shown) is a field of
the program's model, and the program's `update` decides what a hit
means.

elm-playground's `notes_gui.md` (section 4) compares four ways to build
a GUI on the 7GUIs tasks. Placed among them:

| Style | Who holds the widget's state | Used here? |
|---|---|---|
| Callbacks (Tk, GTK) | each widget object, plus the program | no |
| MVC (Smalltalk-80) | a model, observed by views that still hold some | no |
| Immediate mode (Dear ImGui) | nobody: asked for and drawn once a frame, in `update` | no (`tiny_libs.gui`'s `Immediate`, the Playground's `Gui`) |
| MVU (Elm) | the program's one model | **yes** |

It is not `tiny_libs.gui`'s `Mvu` module either. That one runs its own
loop (`Mvu.step`), reads the mouse as a record per frame and keeps the
focus and the caret underneath the model. Here the Playground already
is the loop and delivers messages, so the pieces only need to be values
with a hit test and shapes.

What is in `libs/gui`, and what is still drawn in `Window_view`:

| Piece | Where | Why |
|---|---|---|
| Text in cells, the status bubble | `Gui_text` | any chrome's |
| The strip of tabs | `Gui_tabs` | generic over what a tab is |
| Back, Forward, Reload, Stop | `Gui_toolbar` | a row of picture buttons |
| A menu opened at a point | `Gui_menu` | generic over what an item is |
| A line of text typed into | `Gui_field` | the omnibox's text and box |
| A scrollbar | `Gui_scrollbar` | generic over the unit scrolled; the grab of a drag is the model's |
| The desktop's scale | `Gui_scale` | any window on a screen of many dots |
| Colours, the box hit test | `Gui_kit` | shared by the pieces |
| What the right click's menu offers | `src/chrome/Browser_menu` | a browser's |
| The omnibox's two-tone address, the "JS" and zoom badges, the wrench | `Window_view` | specific to a browser |
| The developer tools' panel | `Window_view`, `Browser_devtools` | a browser's |

## Processes and threads

### mini-chrome: one process, one thread that matters

```
   one process
   +----------------------------------------------------------------+
   |  main thread                                                   |
   |    the window's events -> update -> view -> drawing            |
   |    every tab: HTML and CSS read, the cascade, layout,          |
   |    JavaScript, pictures decoded, http:// stepped (never        |
   |    blocking), the profile's file                               |
   |                                                                |
   |  Worker's pool: 4 threads (Fetch)                              |
   |    an https:// fetch, whole (TCP, our TLS, HTTP), blocking     |
   |    a host's name resolved (getaddrinfo)                        |
   |                                                                |
   |  a thread per async function stopped at an await               |
   |    (Js_coroutine): a stack kept aside, asleep; it runs only    |
   |    while the main thread waits for it                          |
   +----------------------------------------------------------------+
```

- **One process.** Every tab is a value in the same model, in the same
  heap. There is no sandbox and no message passing between tabs.
- **One main thread** does everything that is not waiting on the
  network: the events, `update`, `view`, the drawing (Cairo's, or the
  Playground's own rasterizer), and for every tab the parsing, the
  cascade, the layout, the scripts and the pictures' decoding.
- **A pool of four threads** (`Worker`, created by `Fetch.create`;
  `threads=off` removes it). An `https://` request runs whole on one of
  them, because our TLS client blocks; so does the resolution of a
  host's name. `http://` needs no thread: `Http_request` is a
  non-blocking state machine stepped on the main thread at each frame.
  The main thread polls the pool's jobs at each `Tick`.
- **A thread per async function waiting** (`Js_coroutine`). A script's
  `async` function that reaches an `await` must stop in its middle and
  go on later; the interpreter walks the tree by OCaml's calls, so
  that is a second stack, and OCaml 4.14 has none to set aside but a
  thread's. It is a coroutine, not concurrency: the main thread sleeps
  while the function's body runs, and the body sleeps the rest of the
  time, so the interpreter needs no lock. One that awaits a promise
  nobody settles sleeps until the program ends.
- **No domains, so one core.** Nothing calls `Domain.spawn`. With
  OCaml 4.14 all threads share the runtime's lock; with OCaml 5 they
  all live in one domain, which comes to the same: only one thread runs
  OCaml code at a time. The pool gives concurrency (the window stays
  alive while a request waits on the network), not parallelism. The
  part of an `https://` fetch that computes rather than waits (the TLS
  handshake's arithmetic, the decryption) does take the main thread's
  time.

What follows from that:

- A slow layout or a long script in any tab freezes the whole window.
- An exception anywhere ends the program, all tabs with it (the
  zero-width picture of Hacker News did exactly that).
- Only the shown tab's timers run (`Tick` advances its scripts alone);
  the fetches of every tab go on.
- A resize or a zoom lays out every tab again, on the main thread.

### Chrome: a process per site, many threads in each

Chrome's design since its first release (2008) is the opposite: the
browser is several operating system processes that talk by messages.

```
   browser process          the window, the tabs' strip, the omnibox, the
                            profile's files; it alone may touch the disk
                            and decide what the others may do
   renderer processes       one per site (roughly per tab at first, per
                            site since site isolation, 2018): HTML, CSS,
                            layout, JavaScript (V8), in a sandbox
   GPU process              what is drawn, composited on the graphics card
   network service          the sockets, TLS, HTTP, the cache, cookies
   utility processes        decoders and other risky work, sandboxed
```

and inside a renderer: a main thread (DOM, style, layout, JavaScript),
a compositor thread (scrolling and animations go on while the main
thread is busy), raster threads, an I/O thread for the messages.

### Side by side

| | mini-chrome | Chrome |
|---|---|---|
| Processes | 1 | browser, GPU, network, one renderer per site, utilities |
| Is each tab its own process? | no: a value in the model | yes (per site) |
| A tab crashes | the program ends | that tab shows "Aw, Snap!" |
| A tab's script loops | the window freezes | that tab freezes; the chrome and other tabs go on |
| Sandbox | none; capabilities (`Cap`) say in the types what code may reach | renderers cannot open files or sockets |
| Threads | main, and a pool of 4 for `https://` and names | dozens: main, compositor, raster, I/O, pools, per process |
| Cores used | 1 | as many as there are |
| Network | `http://` on the main thread, non-blocking; `https://` on the pool | its own process, asynchronous |
| Scrolling while a page is busy | waits | goes on (the compositor thread) |
| Between the parts | function calls, messages of the model | IPC (Mojo) |

Chrome pays for this in memory and in machinery (every page's data
crosses a process boundary). mini-chrome pays nothing and gets none of
the isolation.

### What could be done here

In rising order of work, none of it started:

1. **Decode pictures on the pool.** Little gained while there is one
   domain: it would not block a frame on a system call, but the decoding
   still takes the runtime lock.
2. **Domains (OCaml 5 only).** Lay out a background tab, decode a JPEG
   or run the TLS arithmetic on another core. The CI also builds with
   4.14, so it would need a fallback, and the shared tables (the parsed
   sheets, the styles' memo, the rendered icons) would need care.
3. **A process per tab.** The Chrome way: a renderer program that takes
   bytes and answers with shapes over a pipe, the main program keeping
   the window. It would give the crash isolation, and with it a real use
   for the capabilities (a renderer started with no `Cap.open_out`). It
   is a redesign of `Browser_tab` and of what crosses the boundary.

## Authority: capabilities

The program gets every capability once, from `Cap.main` in `main`, and
hands down only what each part needs:

```
   Cap.main
     |- Cap.network ................. Browser_tab -> Fetch -> Tcp, Http_request, Tls_client
     |- Cap.open_in, Cap.env ........ Browser_profile.load, .default_dir   (before the window is made)
     |- Cap.forkew, Cap.env ......... Gui_scale.desktop: xrdb, for the desktop's scale
     '- Cap.open_out ................ Browser_profile.save                 (update's Tick, and at exit)
```

A function's type says what it can reach. `Tls_client` predates this for
its two files (the roots, `/dev/urandom`).

## What is kept between runs

One file, `~/.config/mini-chrome/Preferences` (JSON, `Browser_profile`):
the window's size, the scale chosen (if one was) and each site's zoom. It is read in `main` before the
window is made, written a second after it changes and when the program
ends. Everything else (history, the sites whose scripts run, cookies,
which do not exist yet) lasts as long as the program.
