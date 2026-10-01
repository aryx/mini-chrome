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
line sets it (to add to `flag_names`), and `OPTI=off` for `Page_bench`;
the optimized path is the default. Its `.mli` lists the code that
checks it, as elm-playground's `Opti.mli` does. (The Playground's own
`Opti.enabled`, its rasterizer's, is another switch: `opti=off` could
set both, to decide in step 1.)

With the switch come:

- **a test that the two paths agree** (the fragments and their
  positions for a layout, the shapes for a drawing), and a frame dumped
  with `opti=off` `cmp`-identical to the one with it on;
- **the numbers**: each step measured before and after with
  `Page_bench` and `load_timeline.sh`, said in the comment, in the
  table at the end of this plan, and in `changes.txt`.

The comments of all three kinds start `claude: opti:` (`grep -rn
"opti:"`).

## The steps

In the order of what each buys for what it costs. Each is its own
commit.

### 0. The tools (done)

`scripts/perf/Page_bench.exe` (the stages) and
`scripts/perf/load_timeline.sh` (the real program's load in time, the
clock against the CPU); `scripts/README.md`.

### 1. The switch

`libs/opti`: `Mini_opti.enabled`, its `.mli` the list of what checks
it. `opti=off` (MiniChrome's flags) and `OPTI=off` (`Page_bench`) set
it; whether `opti=off` also sets the Playground's `Opti.enabled` (the
rasterizer's) is decided here.

### 2. A line's shapes when it is shown

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
relayout is then 30 ms.

### 4. The frame at rest

Measure first: `FRAMES=600` and `FRAMES=1200` on about:blank, on
about:chrome and on the article, with `-uncapped` if the Playground's
cap hides it. Then, by what is found:

- the visible shapes built once and kept while the scroll, the zoom,
  the window and the page are the same (ours);
- nothing drawn when the model did not change (the Playground's: a
  change to its platforms, to present as a plan and agree on first, as
  CLAUDE.md says).

### 5. The cascade

257 ms, once a sheet that arrives. Count them in a load, and measure
where inside
(`Cascade.rules`, the selectors matched, `Computed.compute`) before
choosing: rules indexed by the last compound's tag, class or id, so
that an element tries only those that can match; the rules of a sheet
that has not changed kept while another arrives. `languages/css` reads
the same `Mini_opti.enabled`.

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
| | | | | |
