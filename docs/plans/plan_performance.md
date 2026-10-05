# Plan: a page shown faster

## Context

`docs/history.md` listed "speed: a Wikipedia article is slow to lay
out, and a resize lays every tab out again. Measure first." It was
measured on 2026-10-01 (how: `notes_debugging_techniques.txt`, session
2), on Wikipedia's article on OCaml: 354 KB of HTML, 3,904 elements,
two style sheets at first (217 KB and 7 KB), 24 requests in all, a page
16,000 pixels high in a window showing 713 of them.

The page takes about 15 s to settle, and then a core for as long as it
is shown. This plan says where the time goes, what to change and in
what order, and the way the changes are made.

## What was measured

**The program computes, it does not wait.** To frame 400: 27.2 s of the
clock, 26.5 s of CPU. So nothing here is about the network: gzip (done)
and keep-alive make fewer bytes and handshakes, not a faster page.

**The stages** (`scripts/perf/Page_bench.exe`, the best of 3 runs; the
first measure of that day in brackets, on a busier machine):

| Stage | ms |
|---|---|
| Charset, `Html_lexer`, `Html_tree` | 5 + 17 + 21 |
| `Css_syntax.parse_stylesheet`, 217 KB | 17 |
| `Computed.styles` (cascade + computed) | 257 (290) |
| `Box_layout.layout` | 22 (33) |
| `Browser_boxes.draw`, the page's shapes | 452 (557) |
| `Browser_page.read`, no sheet yet | 763 |
| `Browser_page.laid_out`, the sheets come (cascade run) | 954 |
| `Browser_page.laid_out` again (styles memoized) | 543 (520) |
| the page over TLS, gzip | 400 (curl: 310) |

**The load in time** (`scripts/perf/load_timeline.sh`): the page's
bytes are there at 0.7 s, its sheets and first pictures asked for at
1.6 s, and the answers then come in bursts one to 2.6 s apart until
14.8 s. `Fetch.step` hands a frame's answers together and each lays the
page out again (`Browser_tab.with_arrived`, `with_sheet`): a burst of
four answers is four relayouts in one frame.

**The page at rest**: 600 frames take 33.6 s, 1,200 take 51.8 s: 30 ms
of CPU a frame for a page nobody touches. Not looked into yet.

## Where the time goes

1. **The shapes of the whole page are built at each relayout.**
   `Browser_boxes.draw` makes, for every letter of the page, a
   rectangle for each segment of each stroke and a dot at each point
   (`Stroke_text.glyph`; the round pen doubled the count), with a
   `sqrt` and an `atan2` each. `Window_view.page_shapes` then keeps the
   lines between the scroll and the window's bottom: about 4% of them
   here. The layout proper is 22 ms of a relayout of 543.
   (elm-playground's `notes_opti_ocaml.md`, section 11, had found it
   at 0.25 s and named it "the next thing to make lazy".)
2. **A relayout per answer**, when one per frame would show the same:
   24 answers, 24 relayouts, most of the 14 s.
3. **The cascade, 257 ms**, runs again each time a sheet arrives (how
   many times in this load was not counted: at least for the page with
   no sheet, then for each of the two first ones). It is memoized for
   a picture's arrival already.
4. **A frame at rest, 30 ms**: unknown. The view builds the visible
   shapes again and the platform draws them, though nothing changed.
5. **A resize lays every tab out** (`Window_tabs.relaid_all`), and so
   now does the panel opened or closed (`with_panel`: 100vh).

## The way: the simple code can still be read

A matter of judgment, not a hard rule. What is being protected is the
reader: someone should be able to read the simple code first, to
understand the browser, and the optimized one only later, to learn the
trick. As in elm-playground's `libs/` (`notes_opti_ocaml.md`, section
18, and its `Opti.mli`), three cases:

- **A small optimization** (a test moved first, `Int.max` for `max`, a
  value computed once outside a loop): just made. The old line is not
  worth keeping.
- **A few simple lines replaced by a few others**, where the old ones
  say the idea better: the old code in a comment beside the new, no
  switch.
- **A few simple lines replaced by an algorithm** (a memo, a laziness,
  an index): the switch. The simple function is kept, runnable, as
  `xxx_simple`, the fast one is `xxx_opti`, and `xxx` chooses:

  ```ocaml
  let draw_simple ~visited ~picture_of b = (* every shape, at once *) ...
  let draw_opti ~visited ~picture_of b = (* a line's shapes when asked *) ...
  let draw ~visited ~picture_of b =
    if !Mini_opti.enabled then draw_opti ~visited ~picture_of b else draw_simple ~visited ~picture_of b
  ```

**The switch is our own: `Mini_opti.enabled`**, a library of one
module in `libs/opti` (`mini_opti`, as `libs/gui` is `mini_gui`), with
no dependency, so that `languages/` and `src/layout`, which link no
graphics library, can read it as `src/` does. Not named `Opti`:
`tiny_libs.graphics_core` has an unwrapped module of that name, linked
with the Playground, and two would not link. `opti=off` on the command
line sets it, and on `Page_bench`'s; the optimized path is the default.
Its `.mli` lists the code that checks it, as elm-playground's
`Opti.mli` does. The Playground's own `Opti.enabled`, its rasterizer's,
is another switch, which `opti=off` does not touch: what is measured
with and without is then our code alone.

With the switch come:

- **a test that the two paths agree** (the fragments and their
  positions for a layout, the shapes for a drawing), and a frame dumped
  with `opti=off` `cmp`-identical to the one with it on;
- **the numbers**: each step measured before and after with
  `Page_bench` and `load_timeline.sh`, said in the comment, in the
  table at the end of this plan, and in `changes.txt`.

The comments of all three kinds start `opti:` (`grep -rn
"opti:"`).

## The steps

In the order of what each buys for what it costs. Each is its own
commit.

### 0. The tools (done)

`scripts/perf/Page_bench.exe` (the stages) and
`scripts/perf/load_timeline.sh` (the real program's load in time, the
clock against the CPU); `scripts/README.md`. And, since step 7, in
the program itself: `timings=on` says when it ends where the time
went, a line a stage (`Stopwatch`, `libs/opti`).

### 1. The switch (done)

`libs/opti`: `Mini_opti.enabled`, its `.mli` the list of what checks
it (nothing yet). `opti=off` sets it, on mini-chrome's command line
(`-v` says so) and on `Page_bench`'s. It does not set the Playground's
`Opti.enabled`.

### 2. A line's shapes when it is shown (done)

Done as said below, but smaller: no `draw_simple` and `draw_opti`, one
helper, `Browser_draw.later`, a promise of a shape with the switch on
and the shape built at once with it off; `Browser_draw.between` is the
view's culling, and where a promise is asked for. The explanation and
its picture are in `Browser_draw.mli`. Measured on the same page:

| | opti=off | now |
|---|---|---|
| `laid_out` again (styles memoized) | 450 ms | 28 ms |
| `Browser_page.read`, no sheet yet | 796 ms | 239 ms |
| `laid_out`, the sheets come | 803 ms | 347 ms |
| the first window's shapes (`between`) | - | 6 ms, once |
| the load, to its last answer | 14.8 s | 6.2 s |
| to frame 400 (clock) | 28.0 s | 16.2 s |
| a frame at rest | 30 ms | 31 ms |

The program is still computing all the while (16.2 s of clock, 15.6 of
CPU): the frame at rest, step 4, is now most of it, 400 frames of 30
ms being 12 s.

What was planned:

`Browser_draw.drawn` is a list of (top, bottom, shape), one entry for
a line of text, a box's background, a marker. The entries are cheap
to list; the shapes of a line's letters are what costs. So: the same
list, the shape built when first asked for and kept (a `Lazy.t`, or a
function memoized), and the view forcing only the entries it shows.

- `draw_simple` builds every shape at once, as today; `draw_opti` the
  list of lazy ones. `drawn`'s type changes for both (the simple one
  gives values already forced), and with it its users:
  `Window_view.page_shapes`, `Browser_draw.controls_drawn` and
  `outlines`, `Browser_media.draw`.
- Kept from one frame to the next: a line scrolled away and back costs
  nothing; a relayout drops them all, as today.
- Expected: `laid_out` again from 543 ms to about 30 (the layout, and
  the list), plus the lines shown, once. `Browser_page.read` from 763
  to about 300. The 24 relayouts of the load then cost under a second
  together.
- To check: the dumps of about:tube, about:chrome and the article,
  with and without, `cmp`; a test forcing every entry of both paths.
- A risk: a shape kept holds its line's fragments alive; they are
  alive anyway, in the page's layout.

### 3. One relayout a frame

The answers of one `Fetch.step` given to a tab, then the tab laid out
once: `with_arrived` and `with_sheet` only record what came, and a
relayout follows the last. Whether the old way is kept behind the
switch or in a comment depends on how much the new one adds: to judge
when it is written. After step 2 this buys less; measure before doing it, and drop it if a
relayout is then 30 ms. (It is 28: what a burst of four answers costs
is now 0.1 s. Likely dropped, unless the cascade's 270 ms run several
times a frame: to count, with step 5.)

### 4. The frame at rest

Measured (2026-10-01, after step 2). What a frame costs once the page
is shown and nothing moves, from two runs to frames 600 and 1,200:

| Page | Shapes in the window | Cairo | Software |
|---|---|---|---|
| about:blank (the chrome alone) | | 12 ms | 19 ms |
| Wikipedia's article on OCaml | 7,577 | 30 ms | 51 ms |
| about:history | 15,813 | 56 ms | 81 ms |
| about:chrome | 20,416 | 72 ms | 117 ms |

It is the drawing, not the view. `Window_view` asking for the window's
shapes again is 0.0 ms (they are kept, step 2); the Playground's loop
(`Native_loop_2d`) then draws every shape and presents the window, at
every frame, changed or not. `Page_bench` draws about:chrome's 20,416
shapes with the software rasterizer in 110 ms, which is the 117
measured on the program: about 5 microseconds a shape there, 3.5 with
Cairo (a save, a colour, a transform, a path, a fill and a restore
each).

And the shapes are the letters': ten to twenty a letter (a rectangle a
segment of a stroke and a dot a point, `Stroke_text.glyph`), so a
window of 1,400 letters is 20,000 shapes. Two different things follow,
and they do not replace each other:

**a. Nothing changed: nothing drawn.** For the page at rest (a core
busy for as long as a page is shown, the fan of a laptop). The platform
cannot know: the view gives it a new list each frame. So two halves:

- ours: `Window_view.view` gives back the same list (`==`) when what it
  reads of the model is the same. The model changes at every Tick (its
  `time`), so the view must say what it reads: not `time`, unless a
  video plays or a caret blinks.
- the Playground's: the loop skips the drawing and the present when
  the shapes are the list of the frame before (`==`). A few lines of
  `Native_loop_2d`, but a change of the platforms: to present as a
  plan and agree on first (CLAUDE.md).

Buys: the frame at rest from 12-72 ms to the view's check. Does
nothing for a frame that does change: a scroll, a pointer moved over a
link, a letter typed in the omnibox still draw everything, at 14
frames a second on about:chrome.

**b. Fewer shapes a letter.** For every frame. Three ways, the first
two ours alone:

- *a letter a picture*: each glyph (its character, size, weight,
  slant, colour) rasterized once into a small `Rgba_image` and drawn as
  one `Bitmap`, the Playground's existing shape: 15 times fewer shapes.
  But the letters are then pixels, made for one scale: the device's
  scale times the zoom has to reach `src/display`, and the frame is no
  longer the same pixel for pixel as the simple way's (the test becomes
  "looks the same"). Needs a rasterizer in `src/display`
  (`tiny_libs.graphics_2d` has the fills).
- *a line a picture*: the same with one `Bitmap` a line: fewer shapes
  still, more memory (a line of 1,400 by 22 is 123 KB; 700 lines kept
  would be 86 MB: an eviction to write).
- *a stroke a shape*, in the Playground: a new form, a pen's path with
  round ends and joints, one a glyph. Cairo draws that natively (one
  path, one stroke), the web's SVG too (`stroke-linecap: round`); the
  software rasterizer needs it written. The letters stay geometry, at
  any scale, and the same on every platform. A change of the
  Playground's interface and of its three 2D platforms: a plan of its
  own there, and a release.

Not measured: what Cairo makes of a stroked path against fifteen
filled shapes. A guess from the count of shapes alone: about:chrome's
72 ms to 10-15.

To decide: (a) first, small and sure, if the Playground's half is
agreed; then which of (b), after a trial of "a stroke a shape" on
Cairo alone to have its number.

**(a) is done.** Ours: `Window_view.view` keeps the last model drawn
and its shapes, and gives them back when the model is the same but
for its time (`same_but_time`: every field `==`) and the window does
not move by itself (`animated`: a tab loading, a page with a player);
`Window_tabs.on_tab` gives the model back when the tab did not change.
The Playground's: `skip_same_view` (a field of `Playground.window`,
given to `run_app ~window`), an option and not
the rule -- a program's picture may change without its view (an
animated GIF's frames are the platform's): the frame is skipped when
the view is the list drawn last and no event came to the window;
`-uncapped` and `-debug-keys` draw every frame. The explanation and
its picture are in `Window_view.mli`.

A frame at rest, CPU (Cairo):

| Page | opti=off | now |
|---|---|---|
| about:blank | 12.0 ms | 0.2 ms |
| about:chrome | 70.5 ms | 0.3 ms |
| Wikipedia's article on OCaml | 26.7 ms | under 0.1 ms |
| about:tube (a player: always drawn) | 28 ms | 28 ms |

Checked: a test runs the program by hand (init, update, the commands'
messages) and finds the very list a Tick later, a new one after the
pointer moved or the page scrolled, equal to `view_simple`'s; and ten
scripted sessions (scroll, the panel, the pointer over a link, a
click, a zoom, the right click's menu, about:timer, about:counter,
about:tube, the elements' view) dump the same frame with opti=off.

Left of (a): a page with a player is drawn at each frame even paused
(about:tube); `animated` could ask the player.

**(b), the first way tried, and kept: a letter a picture**
(2026-10-02). Tried behind `letters=pictures`, then made the default
the same day (the scroll is far smoother): `Mini_opti.letters` is
`Pictures`, and `letters=segments` on the command line, or `opti=off`,
give the simple way back. In its
own module, `Glyph_picture` (its `.mli` says the why, with a picture);
`Stroke_text.glyph` chooses between `glyph_segments`, as it was, and
`glyph_picture`.

- No rasterizer was needed: a round pen is the points nearer to the
  strokes than half its width, so a pixel's opacity is read off its
  distance to the nearest segment. The same picture on every platform.
- The density (the window's scale times the page's zoom) is a
  reference the view sets (`Glyph_picture.density`), not an argument
  carried from the settings down to the letters. Right because a
  change of scale or zoom lays the page out again, and because every
  letter of the page is built in the view, after it is said: the lines
  shown, the controls' text, and a list item's number (which was built
  at the layout: made a promise as a line's are).
- A letter is moved to whole pixels (up to half a pixel) to stay sharp.

A frame drawn (`-uncapped`, which draws every frame), in ms:

| | Shapes in the window | Cairo | Software |
|---|---|---|---|
| about:chrome, the pen's segments | 20,416 | 74.3 | 116.3 |
| about:chrome, pictures | 1,007 (197 pictures kept) | 8.3 | 31.7 |
| about:history, the pen's segments | 15,813 | 55.9 | 79.6 |
| about:history, pictures | | 4.7 | 17.3 |

and a page's every shape, for someone who scrolls through all of it
(Wikipedia's article): 494 ms to 110.

Looked at, enlarged, side by side with the pen's: at scale 1, at
scale 2, zoomed and scrolled, the letters are the same to the eye
(not pixel for pixel: the joints of the pen's rectangles and dots
were a little darker). Not looked at: a real window, and the web
platform, where a picture is a PNG encoded each time.

Left as it is, to know: a page zoomed in steps makes pictures at each
density (the cache starts again past 4,096); the web's platform (a
picture is a PNG encoded) not tried.

**A Wikipedia article scrolled** (the same day: about:chrome was
smooth, the article sluggish). Measured by a script of 600 presses of
the arrows after the load, against the same run at rest: the CPU of a
step, the frame's view and its drawing (Cairo).

| | ms a step |
|---|---|
| opti=off | 139 |
| letters=segments | 97 |
| pictures, as first made the default | 340 |
| the platform keeping every picture it converted | 23 |
| the page's players and controls kept a layout | 15 |

Two causes, neither the letters' pictures themselves:

- **Cairo's platform converted most letters again at each frame.** It
  kept the surfaces of the last 32 bitmaps, in a list: enough for
  about:chrome, whose letters of one size and colour mostly were
  among the last 32 seen, not for an article's (links, bold, small
  print: more than 32 different ones in a line). Each miss is a
  Bigarray and a Cairo surface made. Now a table by the image (`==`),
  bounded by pixels (16 million), in elm-playground's
  `Image_native.surface_of_bitmap`. The lesson is the plan's own first
  one: what was "fast all the same" on one page had been left
  unexplained.
- **The view read the page's every fragment three times a frame** to
  find its players (twice) and its controls, 12,000 fragments each
  time, for a page with no player: 12 ms of a built view's 15 (found
  by a clock round each part of the view, in the real program, taken
  out again). Kept for the last layout asked about, as values of it
  (`Browser_media.players_of`, `Browser_draw.controls_of`).

What is left of a step is the drawing. 15 ms is just inside a frame at
60 a second; the next gain would be there (fewer shapes: a line a
picture; or only the lines that came in drawn, the others moved).

Not tried, the letters being fast enough for now: a line a picture; a
stroke a shape, in the Playground.

### 5. The cascade

257 ms, once a sheet that arrives. Count them in a load, and measure
where inside
(`Cascade.rules`, the selectors matched, `Computed.compute`) before
choosing: rules indexed by the last compound's tag, class or id, so
that an element tries only those that can match; the rules of a sheet
that has not changed kept while another arrives. `languages/css` reads
the same `Mini_opti.enabled`.

### 7. A page restyled by its scripts (done, 2026-10-05)

GitHub's repository page with its scripts on took 58 s to its last
picture, and the JavaScript engine was the suspect. The same scripts
run offline (`Page_scripts.exe`) took 17 s: the rest was elsewhere.
Throw-away clocks around the stages of `Browser_page.lay_out` said
where -- and became the tool, `timings=on`:

    timings: 49.2 s of 85.9 measured
      styles      39 times   25.1 s
      scripts    259 times   13.5 s   (20.9 with what it calls)
      pictures    14 times    4.9 s
      boxes       39 times    4.2 s

The styles, computed again each time a script has changed the tree:
0.64 s a pass, for 1,823 elements and 25,273 rules. `Page_bench.exe`
on the page, under callgrind with `--toggle-collect` on
`Computed.styles` (the machine was loaded: a clock gave 594 ms, then
1067, for one binary), a pass in instructions:

| | a pass |
|---|---|
| as it was | 3.0 G |
| a class looked for in the attribute's text, not in a list of its words made each time (1.3 million lists, 61 million words) | |
| an attribute found with `String.equal`, not `List.assoc_opt`'s comparison of any two values (32 million calls) | |
| an element filed under its name and attributes, not `Hashtbl.hash` of all it holds (a script of 300 KB) | |
| rules with no id, class or name in their last part (`[data-kbd-chord]`, `:where(.label)`: 1,138 of them, tried on every element, two rules tried of three) filed under the attribute's name or what the `:where()` holds | 1.7 G |
| an element's declarations in a table, not a list turned round and searched for each of a hundred properties | 1.3 G |

In the program: the styles' 25.1 s are 6.1, the last picture comes at
45 s. Each was found the same way, the callers of the function at the
top of the profile (`callgrind_annotate --tree=caller`), and none is
GitHub's: Discourse and 9fans are styled by the same code.

What is left, by the same table: the scripts themselves (10 s), the
boxes (3.5 s for 39 layouts), the pictures (4.5 s for the README's
fourteen screenshots, decoded on the window's thread), and how many
passes there are -- a pass a change, where a real browser restyles
what the change touched (its invalidation sets). That one is an
algorithm, not a fix: the next step if a site needs it.

### 6. The tabs not shown

A resize, a zoom and the panel lay out the shown tab; the others are
marked stale and laid out when shown. Small, and only felt with many
tabs: last.

### Not in this plan

- **The network.** A request is 400 ms against curl's 310; keep-alive
  would save a handshake a request, and the pool's four threads share
  OCaml 4.14's one lock with the layout. Worth doing after the above,
  when the network is what is left: its own plan.
- **Incremental layout** (only what a picture moved laid out again):
  the layout is 22 ms.
- **`-O3`, flambda, `-unsafe`**: the code should be fast on the default
  compiler (elm-playground's "Not done, deliberately").

## Where the switch is checked

To fill as the steps are done (module, what the simple path does, what
the optimized one does, before and after):

| Module | Simple | Optimized | Before | After |
|---|---|---|---|---|
| `Browser_draw.later` | a line's shapes built at each relayout | built when the line is first shown, kept | a relayout 450 ms | 28 ms |
| `Window_view.view` | a new list of shapes and a frame drawn, sixty times a second | the list of the frame before for the same model: the platform draws nothing | a frame at rest 12-72 ms | 0.3 ms |
| `Stroke_text.glyph` | a letter its pen's strokes, ten to twenty shapes | one picture made once (`Glyph_picture`) | a frame of about:chrome drawn 74 ms | 8 ms |
| `Selectors.has_word`, `Cascade.key`, `Computed.compute` | a class's words listed at each selector tried; rules with no id, class or name tried on every element; declarations searched as a list | the attribute's text scanned; those rules under an attribute's name or a `:where()`'s class; a table | a style pass of GitHub's page 3.0 G instructions | 1.3 G |
