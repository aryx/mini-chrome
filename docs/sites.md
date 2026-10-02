# The sites MiniChrome shows, and what each still lacks

A table to see at a glance where the browser stands on the real web,
and to watch it move: a row a site, a column a part of the browser,
each cell a colour and, when it is not green, what is missing.

| | |
|---|---|
| 🟢 | right, or close enough that a reader would not notice |
| 🟡 | usable: the content is there and readable, something is off |
| 🔴 | broken or missing: the page cannot be used for what it is for |
| ⚪ | the site asks nothing of that part |

**Checked on 2026-10-02**, each site loaded once in a window 1000 by
700, its scripts not run unless said (they run on the built-in pages
and on Hacker News only: `scripts=`), and its dump looked at: the top
of the page, what a person sees first. A colour is a judgment of that
picture, not a measure. To check again: `scripts/sites/dump_sites.sh`,
then look at the pictures and correct the rows.

## Summary

| | Sites | |
|---|---|---|
| 🟢 | 8 of 16 | the web of the 1990s, the text-only sites, Hacker News, Google's home |
| 🟡 | 4 of 16 | Wikipedia, DuckDuckGo, Lobsters, GitHub: readable, not right |
| 🔴 | 4 of 16 | two that do not load (Brotli, a TLS handshake), two whose page is unusable |

By part, what holds the most sites back, the worst first:

1. **JavaScript**: 8 sites have scripts that are not run. None of the
   🟢 ones needs them to be read; every modern site does to be *used*.
2. **CSS**: 5 sites laid out wrong, in places or wholly.
3. **Text**: letters beyond ASCII are a `?` (accents, curly quotes):
   seen on 3 sites.
4. **Network**: 2 sites do not load at all.

## The sites

Oldest web first, then by how much they ask.

| Site | Overall | Network | HTML | CSS | Text | JavaScript |
|---|---|---|---|---|---|---|
| **info.cern.ch** (the first web page, 1991) | 🟢 | 🟢 http | 🟢 | ⚪ | 🟢 | ⚪ |
| **Space Jam** (1996, kept as it was) | 🟢 | 🟢 14 requests | 🟢 tables, image links | ⚪ attributes only | 🟢 | ⚪ a date in the footer |
| **Berkshire Hathaway** (a page of the 1990s, still) | 🔴 does not load | 🔴 answers in Brotli (`br`) though only gzip is asked for | ? | ? | ? | ⚪ |
| **example.com** | 🟢 | 🟢 | 🟢 | 🟢 grid, `light-dark()`, `100vh` | 🟢 | 🔴 its script is not run (spread, a `/u` regexp): no icon, no translations |
| **Hacker News** | 🟢 | 🟢 | 🟢 tables, attributes | 🟢 | 🟢 | 🟢 `hn.js` runs (folding, votes not tried) |
| **Lobsters** | 🟡 | 🟢 29 requests | 🟢 | 🟡 a story's second line is cut in two, its "caches" link on a line of its own | 🟢 | 🔴 not run |
| **text.npr.org** | 🟢 | 🟢 | 🟢 | 🟢 | 🟢 | ⚪ |
| **CNN Lite** | 🟢 | 🟢 | 🟢 | 🟢 | 🟡 curly quotes and accents are `?` | ⚪ |
| **Craigslist** | 🔴 does not load | 🔴 the connection closes during the TLS handshake (why: not known) | ? | ? | ? | ? |
| **Project Gutenberg** | 🟢 | 🟢 30 requests | 🟢 | 🟢 the top of the page | 🟢 | 🟡 not run: its menus do not open |
| **Wikipedia** (an article) | 🟡 | 🟢 gzip, 21 requests | 🟢 | 🟢 its columns are a grid (from 1120 wide) | 🔴 every accented letter and phonetic sign is `?` | 🔴 not run: its startup script parses, then stops (`NORLQ is not defined`) |
| **DuckDuckGo** (the HTML results) | 🟡 | 🟢 | 🟢 | 🟡 the header's logo, field and filters overlap; the results are readable | 🟡 `?` in the snippets | ⚪ |
| **Google** (the home page) | 🟢 | 🟢 | 🟢 | 🟢 flexbox | 🟢 | 🔴 not run (a search's results: not tried) |
| **old.reddit.com** | 🔴 a blank page | 🟡 redirected to a sign-in page | ? | 🔴 nothing shows | ? | 🔴 not run |
| **GitHub** (a repository) | 🟡 | 🟢 24 requests | 🟢 | 🟡 the files are listed, bare: wide gaps, no table of them, the branch button a grey bar | 🟢 | 🔴 not run |
| **BBC News** | 🔴 | 🟢 23 requests | 🟢 | 🔴 the menu is a column of links, headlines overlap, columns too narrow | 🟢 | 🔴 not run; its pictures are loaded by scripts: broken frames |

`?` in a cell: could not be told, the page did not get that far.

## What the scripts of the web ask of the engine

The other measure, for JavaScript alone: twelve real scripts given to
the engine (`scripts/js/Js_survey.exe`), each stopping at its first
mistake. 🟢 runs to its end in an empty page; 🟡 parses, then stops
running; 🔴 does not parse.

| Script | | Where it stops (2026-10-02) |
|---|---|---|
| Hacker News' `hn.js` | 🟢 | |
| Preact 10 (minified) | 🟢 | |
| jQuery 3.7 | 🟡 | a regular expression with a lookahead `(?=...)` |
| jQuery 3.7 slim (minified) | 🟡 | the same |
| Mithril 2 | 🟡 | a regular expression with a backreference `\5` |
| Underscore 1.13 | 🟡 | `isFinite` is not defined |
| Wikipedia's startup module | 🟡 | `NORLQ is not defined` |
| React 18 (minified) | 🔴 | a getter in an object: `{ get now() { ... } }` |
| example.com's `s.js` | 🔴 | spread: `[...p.children]` |
| Alpine 3 | 🔴 | template literals: `` `...${x}...` `` |
| htmx 1.9 | 🔴 | template literals |
| Vue 3 (minified) | 🔴 | template literals |

Before the same day's work on the language of 1999 (the comma
operator, `in` and for-in, the bits, `switch`, `do`, labels,
`finally`): one 🟢, eleven 🔴.

## Next, by what it would turn green

- **Text beyond ASCII**: Wikipedia, CNN Lite, DuckDuckGo, and every
  page not in English.
- **Template literals, spread, getters, the regular expressions'
  lookaheads and backreferences**: the six 🔴 and 🟡 scripts above;
  then the sites' own scripts can be tried (`scripts=`).
- **Brotli**: Berkshire Hathaway (and a server that will not send
  gzip).
- **The TLS handshake Craigslist refuses**: to look into.
