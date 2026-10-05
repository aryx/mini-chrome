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

## What was done (2026-10-04)

Step 0, then what its counts pointed at; all in `Js_compile`, with
two lines in `Js_scope`, `Js_frame` and the lexer. `Js_eval` has
three more names in its interface and no line changed.

| | before | now | Node, `--jitless` |
|---|---|---|---|
| a menu frame | 172 ms | 130 ms | |
| the same, in instructions (callgrind) | 773 M | 553 M | |
| the menu started | 1.69 s | 1.31 s | |
| a loop, 3M turns | 640 ms | 515 | 108 |
| calls, 1M | 450 | 350 | 61 |
| properties, 1M | 320 | 280 | 59 |
| arrays, 1M | 240 | 175 | 47 |

**What a frame of the menu asks** (counters put in `Js_compile` for a
day, then taken out): 1,000,000 names read (553,000 the function's
own, 222,000 one scope up, the rest two to five), 307,000 operators,
144,000 items of arrays, 125,000 calls of closures (one or two
arguments, frames of under eight names), 62,000 of the host's (an
array's `pop` and `push`, a string's `charCodeAt`, `Array.isArray`, a
regexp's `test`), 116,000 scopes made for blocks, 28,000 arrays made,
and, left to the evaluator: 34,000 `typeof x`, 16,000 `instanceof`,
6,500 regexps read from their text again.

**What was taken**, by what the counts said:

- the names: the function's own and the one around's read where they
  are asked, by the slot, with no call (step 2's subject, taken
  another way);
- no scope for a body that declares nothing (an `if` without braces,
  a `switch`, a `try`): step 2;
- `typeof x`, `instanceof`, a regexp's text read once: no longer the
  evaluator's;
- the operators a program is made of, each its own closure; `true`
  and `false` made once (step 4, the part that paid: a table of small
  numbers would cost more to look into than a number costs to make);
- an array's item, an array's and a string's `length`, read at once;
  a built-in method (`push`, `charCodeAt`) found once at the place
  that calls it (step 3; an object's own properties were 1,100 reads
  a frame: no subject, and so no step 7);
- a call's small frame written out with no call to the runtime, and
  its own name looked for once (step 1's cheap half);
- an integer written as text without `printf` (step 6); the lexer's
  keywords in a table (the start).

**Not taken**: the arguments evaluated straight into the callee's
frame (step 1's other half). It needs the evaluator's call written a
second time in `Js_compile` (the depth, `this`, strict mode, the
line), for some 5%: the one step whose price is a second copy of
rules that must stay the same. And step 5 beyond the operators.

**Where it leaves us**: a frame at 130 ms, eight a second. Node's
interpreter is three to five times faster on the loops; the menu
would be near 30 ms a frame there. The rest of the way is the
decision of the last section.

## What the big engines do, and what of it is cheap here (2026-10-04)

Asked while Discourse was being brought up (`plan_sites.md`): its
start is 13 s of script where Chrome takes one. The famous techniques,
each with what it would be in this engine:

| Technique (who) | What it is | Here |
|---|---|---|
| **Lazy compilation** (every engine) | a function is compiled when first called: most of a bundle never runs | done: `Js_compile` compiles a body at its first call. Reading is eager, and cheap: 0.7 s for a bundle of 3.8 MB (`Js_bench.exe read=FILE`) |
| **A code cache** (V8) | what was read of a script kept for the next time | done for one load: a module's text is parsed once (`Js_module.parse`; it was parsed to list its imports, then again to run: a tenth of the start). Not kept between two loads |
| **Dictionary mode** (V8, for objects used as tables) | an object of many properties is a hash table | done: `Js_value.find`, a table beside the list past eight properties. A prototype of thirty methods was a list walked at each call: 30% of a loop of method calls |
| **Hidden classes and inline caches** (Self, 1989; V8) | objects made alike share a shape; a place in the code remembers the shape it saw and the slot it found | not done: the next tier (step 7 below), 300 to 500 lines in `Js_value`. The names of scopes have it (`Js_scope`'s places) |
| **Small integers unboxed** (V8's Smi) | a number that is a small integer is not allocated | not here: a `Number of float` is a block for OCaml; a second kind of number would be every operator written twice |
| **Interned names** | a property's key compared by its address | half done: the lexer shares a name written many times, and `Js_scope` compares addresses first |
| **A generational collector, tuned** | young objects die young | OCaml's is one. More room before a major pass (`space_overhead` 200): 4% for 50 MB more, set in the main |
| **Ropes** (V8's strings) | `a + b` is a node, flattened when read | not done; no profile has asked for it yet |
| **A JIT** | machine code for what is hot | never here |

So the cheap ones are taken, and they were not where the time was
expected: Discourse's start went from 56 s to 13 mostly by removing
lists where tables were wanted, in the engine's library and in the
DOM (`changes.txt`), not by a faster evaluator. What is left in its
profile is flat: property reads, the collector, the calls themselves.

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
