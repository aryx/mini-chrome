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
- `sites/`: the real web (`docs/sites.md`)
  - `dump_sites.sh`: each site of the list loaded without a screen and
    dumped as a PNG, its requests and failures said: to look at, and
    bring `docs/sites.md` up to date
- `js/`: what real scripts ask of the JavaScript engine
  - `Js_survey.exe`: each script given parsed, then run in an empty
    page; its first mistake, and the mistakes counted; a library then
    used in a small page (`Js_survey.mli`)
  - `Page_scripts.exe`: a saved page's scripts run with no window:
    their console, the requests they make, the cookies they set, and
    a question asked of the page at the end (`Page_scripts.mli`;
    `mini-curl -o page.html URL`, then
    `./_build/default/scripts/js/Page_scripts.exe page.html URL "typeof jQuery"`)
- `perf/`: how fast (`docs/plan_performance.md`)
  - `Page_bench.exe`: where a page's load goes: the network, then each
    stage of the pipeline timed on the page fetched (`Page_bench.mli`;
    `dune build scripts/perf/Page_bench.exe`, then
    `./_build/default/scripts/perf/Page_bench.exe [URL] [WxH] [opti=off]`)
  - `load_timeline.sh`: the real program's load without a screen, a
    time before each line of `-v`, then the clock's time against the
    CPU's (`FRAMES=n` for the frame to stop at)
