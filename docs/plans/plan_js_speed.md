# Plan: a faster JavaScript, the clear engine left as it is

## Context

The Playground's menu and games run in the browser
(`plan_tinybox.md`) at six frames a second: a frame of the menu is
172 ms where 16 are wanted. Two rounds were made, each kept apart
from the evaluator and switchable:

| | a menu frame | what |
|---|---|---|
| 2026-10-02 | 870 ms | the evaluator, tables of names |
| 2026-10-03 | 206 | `Js_scope`'s places, `Js_frame`, numbers and items (`opti=off`) |
| 2026-10-04 | 172 | `Js_compile`: bodies made closures (`js=walk`) |

The first round was four times, the second a quarter where three to
five times were hoped. This plan is written from that: what is left
to take, what it can give, and how to take it without touching what
makes the engine readable.

**What stays as it is.** `Js_eval` is the definition: the tree
walked, a case a construct, the language's rules in the order the
standard says them. With `Js_scope`'s simple way under it
(`opti=off`) it is the engine to read. Nothing below edits its cases
or puts a fast path in them; what is fast is beside it, in modules
of its own, reached by a reference or a kind of node it never makes
(as `Js_compile` and `Js_quicken` are), and `tests/js` runs every
way on the same expectations.

## What was measured

The menu's start and four frames under callgrind
(`notes_debugging_techniques.txt`, session 4), compiled, by kind of
cost:

| | |
|---|---|
| the engine itself: closures called, calls made, arguments | 35% |
| scopes and frames: a name found, a frame made | 17% |
| memory: values made, the collector | 15% |
| properties, strings compared, operators | 15% |
| strings made, numbers written | 4% |
| reading the script (once) | 2% |
| the page: the DOM a script changes | 2% |
| the rest (the runtime's own, below 0.5% each) | 10% |

No line is above 7%. Three things follow:

1. **There is no next "scopes' tables".** The first round removed one
   cause that was two thirds of the time. What is left is many causes
   of a few percent each.
2. **A resolver would give little.** A name is already found by a
   count of scopes and a slot (`Js_scope.at`); a pass that fixed
   those before the run would save the check of the slot's name, a
   part of the 17%, and cost the node-by-node fall back to `Js_eval`
   that keeps `Js_compile` short (a scope must stay findable by
   name for it).
3. **The work itself is large.** A frame of the menu is a view of
   five hundred shapes built, made a tree of SVG, compared with the
   frame before, by OCaml compiled to JavaScript: every call of an
   unknown function goes through the runtime's `caml_call`. That is
   what Chrome compiles to machine code and runs in a millisecond or
   two. An interpreter written in OCaml, its numbers allocated and
   its objects lists of properties, does not get there: this plan's
   honest end is a frame at 60 to 90 ms, twelve to sixteen a second,
   not sixty.

So two kinds of step: the engine's, each small; and what makes the
slowness not matter, outside the engine.

## Outside the engine: what the slowness costs

These are cheap, and the first two are felt more than any 20%.

**A. A key tapped is never lost.** The Playground reads the keys
held at each tick; a key down and up between two frames of 170 ms is
not seen. The browser tells a page's script of the key going down at
once (`Window_update.told`) and of its going up -- but can hold the
"up" until one animation frame of the page has run since the "down".
Same for a click (down and up in one frame). **Done**:
`Window_update.update` keeps what was let go too soon (`late`) and
tells it after the page's frame; `step` is the plain way.

**B. Sound that does not cut: nothing to do.** The fear was that at
170 ms a frame the platform's schedule (300 ms ahead at most) runs
dry. Measured (2026-10-04) on TinyMissileCommand's script with a
clock that moves 170 ms a frame: six gaps in the first second, while
its schedule grows from 50 ms ahead to 200, then none -- 7.8 s of
sound in 8.5 s of clock, back to back. The Playground's own jitter
buffer does it, and a clock that stopped when the queue is empty, as
was planned here, would have had it schedule 50 ms a frame: the sound
three times too slow. Gaps come back above 300 ms a frame.

**C. A frame not drawn again when it is the same** is the
Playground's to do, not ours: its web platform builds and compares
the whole view sixty times a second whatever happened. A menu
nobody touches would then cost nothing (here and in Chrome: the
fan). To propose in elm-playground, as `skip_same_view` was for the
native platforms; not counted in this plan's numbers.

## The engine: steps, by what the profile says they can give

Each is its own change with its numbers before and after
(`scripts/perf/Js_bench.exe`, the loops and the menu), in
`Js_compile` or a module beside it, off with `js=walk`. An estimate
is a share of the profile, not a promise; a step that gives under 3%
on the menu is put back.

| | Step | Where the time is | Hope |
|---|---|---|---|
| 1 | **A call without a list.** The arguments evaluated straight into the callee's frame (its layout is known: `Js_ast.frame`) when it is a closure with plain parameters; today a list is made, then walked into the cells, and a `this` checked three ways | calls, arguments, `bind_params`, `set`: 8% | 5% |
| 2 | **Blocks without scopes.** A block's `let` that no function made in it keeps (read in the text) lives in the function's frame: no scope a turn of a loop, fewer scopes to go up | `nested`, `up`, `at`: 9% | 5% |
| 3 | **A property where it was.** A place in the compiled code that reads `o.k` remembers the object's list of properties and the cell found (an inline cache, as a name's); a function's `length` and `l` (what `caml_call` asks at each call), an array's and a string's `length`, read without a search | `property`, `get`, strings compared: 10% | 6% |
| 4 | **Numbers that are there.** The small integers as values made once (a table of the first thousand, both signs), `true` and `false` too: a loop's counter and a comparison's answer allocate nothing | allocation, the collector: 15% | 4% |
| 5 | **The same code specialized.** `caml_apply` between closures is the price of closures; fewer of them: a statement that is an expression's call compiled as one closure, an `if` whose test is a comparison of two names as one | closures called: 9% | 4% |
| 6 | **Strings.** A number written as text by the short way first (an integer: no `printf`, no reading back); `a + b` of two strings in a loop is what it is | 4% | 2% |

Together, if each gives what is hoped: a quarter to a third, a frame
at 115 to 130 ms. To go under 90 needs the seventh, which is not a
step but a decision:

**7. Objects by shape.** An object's properties as an array of
values and a shape shared by the objects made alike (the hidden
classes of Self and V8), instead of a list of pairs. It is the one
change that is not beside the engine: `Js_value.obj` is everybody's
(the evaluator, the built-ins, the DOM's host objects). It can be
kept behind `Js_value`'s own functions (`get_own`, `set_own`,
`keys`, which most of the code already goes through) with the list
as the simple way -- but it is 300 to 500 lines in the middle of the
engine, and the question to answer first is whether the menu's time
is in its objects at all: js_of_ocaml's values are arrays, and its
objects few. **To measure before deciding** (step 0), and likely not
worth it for this program; a site made of objects (a framework's
virtual DOM) would say otherwise.

## Step 0: what to count first

A day of measure before any of the above, kept in
`scripts/perf/`:

- **What a frame is made of**: counters in `Js_compile`, under a
  flag, by kind -- calls (to closures, to the host), names read by
  how many scopes up, properties read by the kind of object (array,
  function, plain) and where found (own, a prototype), numbers made,
  scopes made. The table above is where the instructions go; this is
  what the program asks, and it says which of steps 1 to 7 has a
  subject.
- **A reference**: the same frame's count of operations, and the
  loops, in Node with its compiler off (`node --jitless`, an
  interpreter of bytecode written in C++): what an interpreter can
  do, to know how far the hope is from the possible.
- **Smaller programs than the menu**, compiled by js_of_ocaml and
  kept in `tests/js/data`: a sort, a table filled and read, a tree
  built and folded, strings joined -- each run by Node and by
  `mini-node`, their outputs compared (a test), their times a line
  of `Js_bench`.

## How it is kept true

- `tests/js` on every way (`dune`: compiled, walked, `opti=off`), and
  a fourth if a step has its own switch.
- The js_of_ocaml programs above against Node: the engine against a
  real compiler's output, which found nothing wrong in October but
  will when a call's frame is made another way.
- `scripts/js/Js_survey.exe`'s twelve libraries, and the sites'
  dumps (`docs/sites.md`), after each step.
- A step's comment starts `opti:` and gives its numbers; what it
  replaces stays runnable (`_simple`, or the evaluator itself).

## Cost

Step A: 20 lines (done: `Window_update.update`); B: none. Steps 1 to 6: 400 to 600 lines of the
5,792 left, none in `Js_eval`. Step 7, if ever: 300 to 500, in
`Js_value`.

## What this plan is not

Not a bytecode and its machine, and not a compiler to registers: on
this profile they would move the 35% of "the engine itself" and
leave the rest, for a second engine as long as the first. If sixty
frames a second in the browser's own JavaScript becomes the aim, that
is the plan to write then, with step 0's numbers to start from.
