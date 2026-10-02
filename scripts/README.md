# scripts/

Support programs for developing and debugging the browser, run from the
repository's root. Each one's header says what it does, why, and how to
use it; the techniques behind them are in
`docs/notes_debugging_techniques.txt`.

- `stats/`: numbers about the repository
  - `loc.py`: lines of OCaml (code, comments, blank), a part a line,
    and how much of the budget they are: 30,000 lines for the browser
    (`languages/`, `libs/`, `src/`), its tests and tools not counted
    (`make loc`, `make loc-v`)
- `js/`: what real scripts ask of the JavaScript engine
  - `Js_survey.exe`: each script given parsed, then run in an empty
    page; its first mistake, and the mistakes counted (`Js_survey.mli`)
- `perf/`: how fast (`docs/plan_performance.md`)
  - `Page_bench.exe`: where a page's load goes: the network, then each
    stage of the pipeline timed on the page fetched (`Page_bench.mli`;
    `dune build scripts/perf/Page_bench.exe`, then
    `./_build/default/scripts/perf/Page_bench.exe [URL] [WxH] [opti=off]`)
  - `load_timeline.sh`: the real program's load without a screen, a
    time before each line of `-v`, then the clock's time against the
    CPU's (`FRAMES=n` for the frame to stop at)
