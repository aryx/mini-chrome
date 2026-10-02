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
picture, not a measure -- and a picture is not enough: **Using it**
says whether the site does what it is for (a search engine searched, an
article read), as far as that was tried; Google's home page was green
by its picture when its field could not be typed into. To check again: `scripts/sites/dump_sites.sh`,
then look at the pictures and correct the rows.

## Summary

| | Sites | |
|---|---|---|
| 🟢 | 7 of 16 | the web of the 1990s, the text-only sites, Hacker News |
| 🟡 | 4 of 16 | Wikipedia, DuckDuckGo, Lobsters, GitHub: readable, not right |
| 🔴 | 5 of 16 | two that do not load (Brotli, a TLS handshake), two whose page is unusable, and Google: its page shows, a search does not |

By part, what holds the most sites back, the worst first:

1. **JavaScript**: 8 sites have scripts that are not run. None of the
   🟢 ones needs them to be read; every modern site does to be *used*,
   and Google will not search without.
2. **CSS**: 5 sites laid out wrong, in places or wholly.
3. **Text**: letters beyond ASCII are a `?` (accents, curly quotes):
   seen on 3 sites.
4. **Network**: 2 sites do not load at all.

## The sites

Oldest web first, then by how much they ask.

| Site | Overall | Using it | Network | HTML | CSS | Text | JavaScript |
|---|---|---|---|---|---|---|---|
| **info.cern.ch** (the first web page, 1991) | 🟢 | 🟢 read | 🟢 http | 🟢 | ⚪ | 🟢 | ⚪ |
| **Space Jam** (1996, kept as it was) | 🟢 | 🟢 looked at | 🟢 14 requests | 🟢 tables, image links | ⚪ attributes only | 🟢 | ⚪ a date in the footer |
| **Berkshire Hathaway** (a page of the 1990s, still) | 🔴 does not load | 🔴 | 🔴 answers in Brotli (`br`) though only gzip is asked for | ? | ? | ? | ⚪ |
| **example.com** | 🟢 | 🟢 read | 🟢 | 🟢 | 🟢 grid, `light-dark()`, `100vh` | 🟢 | 🔴 its script is not run (spread, a `/u` regexp): no icon, no translations |
| **Hacker News** | 🟢 | 🟢 read; signing in and voting not tried | 🟢 | 🟢 tables, attributes | 🟢 | 🟢 | 🟢 `hn.js` runs (folding, votes not tried) |
| **Lobsters** | 🟡 | 🟢 read | 🟢 29 requests | 🟢 | 🟡 a story's second line is cut in two, its "caches" link on a line of its own | 🟢 | 🔴 not run |
| **text.npr.org** | 🟢 | 🟢 read | 🟢 | 🟢 | 🟢 | 🟢 | ⚪ |
| **CNN Lite** | 🟢 | 🟢 read | 🟢 | 🟢 | 🟢 | 🟡 curly quotes and accents are `?` | ⚪ |
| **Craigslist** | 🔴 does not load | 🔴 | 🔴 the connection closes during the TLS handshake (why: not known) | ? | ? | ? | ? |
| **Project Gutenberg** | 🟢 | 🟡 read; its search and menus not tried | 🟢 30 requests | 🟢 | 🟢 the top of the page | 🟢 | 🟡 not run: its menus do not open |
| **Wikipedia** (an article) | 🟡 | 🟡 read, with holes in the words; its search not tried | 🟢 gzip, 21 requests | 🟢 | 🟢 its columns are a grid (from 1120 wide) | 🔴 every accented letter and phonetic sign is `?` | 🔴 not run: its startup script parses, then stops (`NORLQ is not defined`) |
| **DuckDuckGo** (the HTML results) | 🟡 | 🟢 searched from the omnibox; its own form not tried | 🟢 | 🟢 | 🟡 the header's logo, field and filters overlap; the results are readable | 🟡 `?` in the snippets | ⚪ |
| **Google** | 🔴 the home page shows, a search does not | 🔴 a query can be typed and sent, and the consent page answered (a form posted, its cookie kept); then "enable JavaScript to continue" | 🟢 | 🟢 | 🟢 flexbox | 🟢 | 🔴 not run: Google's results have needed scripts since 2025 |
| **old.reddit.com** | 🔴 a blank page | 🔴 | 🟡 redirected to a sign-in page | ? | 🔴 nothing shows | ? | 🔴 not run |
| **GitHub** (a repository) | 🟡 | 🟡 the files' names can be read and followed; the README not looked at | 🟢 24 requests | 🟢 | 🟡 the files are listed, bare: wide gaps, no table of them, the branch button a grey bar | 🟢 | 🔴 not run |
| **BBC News** | 🔴 | 🔴 headlines cannot be read in order | 🟢 23 requests | 🟢 | 🔴 the menu is a column of links, headlines overlap, columns too narrow | 🟢 | 🔴 not run; its pictures are loaded by scripts: broken frames |

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
| React 18 (minified) | 🟡 | `Symbol` is not defined |
| htmx 1.9 | 🟡 | `document.createEvent` is not a function |
| example.com's `s.js` | 🟡 | parses; in the survey's empty page it stops at the paragraph it expects |
| Alpine 3 | 🔴 | optional chaining: `a?.b` |
| Vue 3 (minified) | 🔴 | `class` |

How it moved, the same day:

| | 🟢 | 🟡 | 🔴 |
|---|---|---|---|
| at first | 1 | 0 | 11 |
| the language of 1999 (the comma operator, `in` and for-in, the bits, `switch`, `do`, labels, `finally`) | 2 | 5 | 5 |
| template literals, destructuring, default and rest parameters, spread, an object literal's short forms, getters and setters | 2 | 8 | 2 |

## Next, by what it would turn green

- **Text beyond ASCII**: Wikipedia, CNN Lite, DuckDuckGo, and every
  page not in English.
- **The regular expressions' lookaheads and backreferences, `class`,
  optional chaining, `Symbol` and a few globals**: the scripts above;
  then the sites' own scripts can be tried (`scripts=`).
- **Brotli**: Berkshire Hathaway (and a server that will not send
  gzip).
- **The TLS handshake Craigslist refuses**: to look into.
