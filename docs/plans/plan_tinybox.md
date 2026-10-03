# Plan: tinybox in mini-chrome

## Context

mini-chrome stands on the Playground, and the Playground has a web
platform: a program compiled by js_of_ocaml whose every frame is an
`<svg>` patched in the page. Its menu, tinybox, is at
https://aryx.github.io/ocaml-elm-playground/tinybox.html. To open that
page in mini-chrome is the full circle: the Playground drawing a
browser that runs the Playground.

It was tried on 2026-10-03, on `Tinybox_web.bc.js` (538 KB, js_of_ocaml
6.4.1) served by `mini-httpd`. This plan says what was found, what to
change and in what order. The aim, in three marks:

1. **a picture**: the menu as Chrome shows it, in the README's table;
2. **a menu that answers**: arrows and the mouse move the selection,
   a few frames a second at least;
3. **a game played**: Enter opens a program's page (TinyPong first)
   and it can be played.

## What was measured

**Two things stopped the script, both fixed (not committed yet).** The
lexer refused `0o7777` (`0o` and `0b` literals); and the program
starts on `window.onload = f`, which nothing called (only
`addEventListener("load")`'s listeners were). With those the script
runs with no error and builds the menu: 48 KB of `<svg>` in the body,
made of `svg`, `g`, `rect`, `text` and `image`.

**The engine is the obstacle** (`Page_scripts.exe`, timed by hand):

| What | Time |
|---|---|
| the program started (`run_scripts`) | 6.8 s |
| one animation frame of the menu | 0.87 s |
| 3M iterations of `s = (s + i) \| 0`, at the top level | 4.8 s (1.6 µs each) |
| 3M calls of `f(a, b)` | 8.1 s (2.7 µs each; Node: 6 ms) |

A frame of the menu is then some 300,000 calls. No profiler on this
machine (`perf` is not installed), so the cause below is read in the
code, not measured: step 0 is to measure it.

**The picture.** The menu's svg saved as a static page and opened: the
background, the tiles' frames and the panels are drawn; no `<text>`
(`Svg` draws none), no `<image>` (not drawn, not fetched). In the real
page the svg is `position: fixed` with `width="100%"`: it is then a
positioned box, not a picture, and its texts are set as words. And an
inline svg wider than its line is not drawn at all (a bug).

**The events.** A page's scripts are told of `keydown` on the body and
of clicks. The platform listens on `window`, capturing, for `keydown`,
`keyup`, `mousemove`, `mousedown`, `mouseup`, `wheel`, `dblclick`,
`blur`, and turns a mouse's position into the svg's with
`createSVGPoint`, `getScreenCTM().inverse()` and `matrixTransform`.
`requestAnimationFrame`'s function is given no time (the program says
`rate: nan Hz`).

## Where the time should be going

Read in `Js_eval` and `Js_value`:

1. **A scope is a `Hashtbl` of names**, one made for each block, each
   loop's turn, each call (`new_scope`: `Hashtbl.create 8`), and a
   name is looked up by hashing its string in each table up to the
   globals (`lookup`). js_of_ocaml's code is all local variables and
   calls: every one of them pays this.
2. **An object's properties are a list** (`props`), searched in order,
   then its prototype's. The runtime's functions are globals, and the
   program's blocks are arrays (`items`, already an array): this should
   matter less than 1.
3. **A call**: the arguments bound by name, `arguments` made, the marks
   (`%strict`, `%module`, `%home`) looked up through the chain.

## The steps

Each ends with the numbers measured again and the tests passing; the
engine's changes follow `CLAUDE.md`'s rule for optimizations (the
simple function kept as `xxx_simple`, `opti=off`, a test that the two
agree, a comment `opti:` with the numbers).

**0. Measure.** `scripts/perf/Js_bench.exe`: the small loops above, and
tinybox's start and frame (the bundle fetched once into a scratch
directory, not kept in the repository). Counters in the engine under a
flag (scopes made, lookups and their depth, property reads and the
length walked) to say which of the three causes above is the one.
The two fixes committed with their tests. *Not in the budget.*

**1. Variables resolved once.** After parsing, a pass gives each name
its place: how many scopes up, which slot (`Js_resolve`, a new module:
the classic of *Crafting Interpreters*' resolver, and of every
engine since). A scope is then an array; a block with no declaration
of its own makes none. What cannot be resolved stays by name: `with`,
a direct `eval`, the globals (a table, as today). *About 400 to 500
lines.* The hope is ten times; the mark to reach before going on is a
frame of the menu under 100 ms. If step 0 says otherwise, this step
changes.

**2. What the counters still show.** In the order they say: a call's
frame made without a table (the parameters' slots), the marks kept in
the closure instead of looked up, properties in a table past a
dozen. *100 to 200 lines.* To stop when a frame is near 30 ms: a
bytecode is another project.

**3. The picture** (mark 1, and it does not wait for steps 1 and 2: a
dump at frame N only needs patience).
- `Svg`: `<text>` (`font-size`, `text-anchor`, `dominant-baseline`,
  the transform) in the stroke font the page's letters use, and
  `<image href>` through a function the caller gives
  (`~picture:(string -> Rgba_image.t option)`).
- the page: an svg's `<image>` asked for as an `<img>`'s is, and the
  svg drawn again when it comes.
- layout: a positioned svg is a picture too (`position: fixed`,
  `100%` of the window), and one wider than its line is drawn.
- `aryx.github.io` in `Window_tabs.default_allowed`; a card or a link
  on `about:chrome`; the README's table and `docs/sites.md`.
*About 250 lines.*

**4. A frame at the right time.** `requestAnimationFrame` given the
time; one turn of it a frame of ours and no catching up when a turn
is long; and what a turn costs outside the script measured: the tree
frozen, the page laid out, the svg drawn at 1100 by 620. If that is
too much, the Playground's shapes made straight from the svg's
elements (a `rect` a rectangle, a `text` words, an `image` a picture:
what `Web_render` wrote, read back) instead of a picture of it: the
circle closed at the level of shapes. *50 lines, or 200 with the
shapes.*

**5. The events** (mark 2). `Browser_script` tells `window`'s
listeners, capturing ones first: keys down and up with `key`,
`ctrlKey` and the others; the mouse moved, pressed and released with
`clientX`, `clientY`, `button`, `movementX`; the wheel. The three SVG
members the platform asks, for an svg that fills the window (a
translation and a scale). `preventDefault` on a key keeps it from the
browser (Tab, the F keys). *About 200 lines, most in
`data/prelude/web.js`, which is not in the budget.*

**6. A program opened** (mark 3). `history.replaceState`,
`location.href = ...` leaving the page, Back coming back to
`?chosen=`; TinyPong's page, then two or three others, each with what
it stops on (`Page_scripts.exe`). The menu's 17 MB of sources asked
only when the code map is. *About 100 lines.*

**Later, or never:** sound (`AudioContext`: our decoders are there,
the mixing is not), touch, the code map's canvas, WebGL (the 3D
programs).

## Where it stands (2026-10-03, the same day)

The three marks are reached, slowly: the menu is drawn as Chrome draws
it (`docs/screenshots/tinybox.png`), it answers to the keys and to the
mouse, and Enter on TinyInvaders opens the game's page, which is
played with the arrows and space (`invaders.png`). 802 lines of the
budget (33,530 of 40,000), 205 of them to keep the parser's tree
plain and the calls' frames in a module of their own.

| | before | now |
|---|---|---|
| the menu started | 6.8 s | 2.0 s |
| one frame of the menu | 870 ms | 206 ms |
| 3M turns of a loop | 5.9 s | 1.0 s |
| 1M calls | 3.7 s | 0.67 s |

What each step became:

- **0, measured.** `scripts/perf/Js_bench.exe`; no counters: valgrind
  was there (`--tool=callgrind`, then `callgrind_annotate`), and said
  it at once -- two thirds of a call's 17,000 instructions were
  hashing names, comparing them and making tables.
- **1, the names.** Not a pass before the program runs: each name in
  the tree remembers where it was found, and checks it
  (`Js_scope.mli` says why that is enough, and the one program where
  it differs). Scopes as arrays, a call's frame made at once
  (`Js_frame.opti`). The parser's tree is left as it is: the places
  are in a copy made before the run (`Js_quicken`), in nodes the
  simple evaluator never meets. The simple way kept, `opti=off`, and
  `tests/js` run on both.
- **2, the rest.** Two numbers added with no conversion, an array's
  item by its number (it was written as a string and read back), an
  object's keys compared as strings, no scope where nothing is
  declared. Four times in all, not ten: the profile is flat now (the
  tree walked, an operator found by its name each time), and the next
  factor is another engine -- the tree compiled to closures, or to a
  bytecode. **That is the step left**: at five frames a second a key
  tapped between two frames is not seen by the program, which reads
  the keys held at each tick.
- **3, the picture.** Not text and pictures added to `Svg`: an svg
  made of the Playground's shapes is drawn as those shapes
  (`Svg_shapes`), what step 4 kept as a fallback -- the first frame
  showed that a rasterizer for icons is not for a window's picture
  sixty times a second. A fixed svg is laid out as a picture. Not
  done: an svg wider than its line still is not drawn in the flow
  (the bug found on the way), and no card on `about:chrome`.
- **4, the frame.** The time given; nothing else needed: one turn a
  frame was already so.
- **5, the events.** `Browser_script.window_event`, told from
  `Window_update.told` when a script listens. Not done: a double
  click, a right click, a capital typed (the key is the platform's
  name, "a" with Shift held).
- **6, a program opened.** Nothing to do: `location.href = ...` was
  there.

What stopped the program on the way, each found by its first error
(`-v`): a typed array's `subarray`; then `canvas.getContext`, which
ended the animation's loop -- the keys and clicks after it looked
ignored. A canvas is now a stand-in that draws nothing, and a request
for bytes (`responseType = "arraybuffer"`, the menu's 17 MB of
sources) fails at once: the code panel says "no answer".

A way to test the engine found on the way: a small OCaml program
compiled by js_of_ocaml, run by Node and by `mini-node`, the two
outputs compared (`js_of_ocaml t.byte`; equalities, `compare`,
`Hashtbl`, `Printf`, `Int64`: the same here).

Since (2026-10-04):

- **the engine again**: function bodies compiled to closures
  (`Js_compile`, apart from the evaluator, `js=walk` to compare). A
  quarter, not the three to five times hoped: a menu frame 195 ms to
  172. The profile says why (`Js_compile.mli`): what is left is a
  frame made at each call, the arguments as a list, a number a new
  value, a name some scopes up -- not the tree's dispatch.
- **sound**: `AudioContext` (a buffer's source started at a time) and
  `Audio_queue`: TinyMissileCommand's script schedules its 4.8 s of
  sound in 5 s of play (counted without a sound card; to be heard by
  ears). At six frames a second the platform's schedule (300 ms ahead
  at most) has gaps: the sound is there, cut.
- the animation's time, the menu's sources failing at once: as above.

Next, in the order of what is felt:

1. **the engine, differently**: to sixty frames a second is a factor
   of ten, and no more of it is in the tree: variables in registers
   (no scope made at a call), arguments passed without a list,
   properties by a shape and a slot. A compiler with its own idea of
   a function, beside the evaluator as `Js_compile` is.
2. **a canvas and bytes**: typed arrays as bytes and not as arrays of
   numbers, `putImageData` and `toDataURL` kept as a picture the page
   can show: the code map, and every program that draws a bitmap.
4. the Playground's label (the window's size and frame rate) drawn
   over the page: an option of the platform's.

## Cost

900 to 1,300 lines of the budget (32,728 of 40,000 today), half of it
the engine's steps 1 and 2 -- which every site with scripts gains
from: `docs/sites.md`'s rows are to be run again after step 1.

## Risks

- **The resolver against the language's corners**: closures made in a
  loop (a `let` each turn), hoisted functions, `arguments`, generators
  and async functions (`Js_coroutine` keeps scopes alive), modules'
  live bindings, the host's `define`. The tests of `tests/js` and
  `Js_survey`'s twelve libraries are the net; `opti=off` the way back.
- **Ten times may not be enough.** At 90 ms a frame the menu answers
  but nothing is played; mark 3 then waits for step 2, or stops at
  the turn-based programs.
- **The whole page laid out each frame** may cost as much as the
  script once the script is fast: step 4 measures before it builds.
