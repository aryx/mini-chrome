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
| 🟡 | 6 of 16 | Wikipedia, DuckDuckGo, Lobsters, GitHub, Berkshire Hathaway, BBC News: readable, not right |
| 🔴 | 3 of 16 | one that does not load (a TLS handshake), one whose page is unusable, and Google: its page shows, a search does not |

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
| **Berkshire Hathaway** (a page of the 1990s, still) | 🟡 readable, its links work; the heading is not as in Chrome | 🟢 | 🟢 answers in Brotli (`br`), whatever is asked | 🟡 the heading's first letter (a `<font size>` in a centred block) on a line of its own, the heading not centred; a table cell's small line over the link above it | 🟢 | 🟢 | ⚪ |
| **example.com** | 🟢 | 🟢 read | 🟢 | 🟢 | 🟢 grid, `light-dark()`, `100vh` | 🟢 | 🔴 its script is not run (spread, a `/u` regexp): no icon, no translations |
| **Hacker News** | 🟢 | 🟢 read; signing in and voting not tried | 🟢 | 🟢 tables, attributes | 🟢 | 🟢 | 🟢 `hn.js` runs (folding, votes not tried) |
| **Lobsters** | 🟡 | 🟢 read | 🟢 29 requests | 🟢 | 🟡 a story's second line is cut in two, its "caches" link on a line of its own | 🟢 | 🔴 not run |
| **text.npr.org** | 🟢 | 🟢 read | 🟢 | 🟢 | 🟢 | 🟢 | ⚪ |
| **CNN Lite** | 🟢 | 🟢 read | 🟢 | 🟢 | 🟢 | 🟡 curly quotes and accents are `?` | ⚪ |
| **Craigslist** | 🔴 does not load | 🔴 | 🔴 the connection closes during the TLS handshake (why: not known) | ? | ? | ? | ? |
| **Project Gutenberg** | 🟢 | 🟡 read; its search and menus not tried | 🟢 30 requests | 🟢 | 🟢 the top of the page | 🟢 | 🟡 not run: its menus do not open |
| **Wikipedia** (an article) | 🟡 | 🟡 read, with holes in the words; its search not tried | 🟢 gzip, 21 requests | 🟢 | 🟢 its columns are a grid (from 1120 wide) | 🔴 every accented letter and phonetic sign is `?` | 🔴 not run: its startup script parses, then stops (`NORLQ is not defined`) |
| **DuckDuckGo** (the HTML results) | 🟡 | 🟢 searched from the omnibox; its own form not tried | 🟢 | 🟢 | 🟡 the header's logo, field and filters overlap; the results are readable | 🟡 `?` in the snippets | ⚪ |
| **Google** | 🔴 the home page shows, a search does not | 🔴 a query can be typed and sent, and the consent page answered (a form posted, its cookie kept); then a page of script only | 🟢 | 🟢 | 🟢 flexbox | 🟢 | 🔴 a search answers our browser with a challenge: an obfuscated program (63 KB) that must compute a token before any result is sent. It loads and runs here without an error, and gives no token. To a browser it does not know Google sends that page; to an old Opera Mini's name, plain HTML results |
| **old.reddit.com** | 🔴 a blank page | 🔴 | 🟡 redirected to a sign-in page | ? | 🔴 nothing shows | ? | 🔴 not run |
| **GitHub** (a repository) | 🟡 | 🟢 the files, the About pane beside them, the tabs and the README can be read and followed | 🟢 24 requests | 🟢 | 🟡 the page's two columns are right (its `@media (width >= 48rem)`); the top bar is blank, the branch button an empty bar, the files have no icon, message or date | 🟢 | 🔴 not run: its scripts are modules (`<script type=module>`), and each file's last commit comes by them |
| **BBC News** | 🟡 | 🟢 the front page reads as one: the lead, the rows of stories, the side column, each a link | 🟢 23 requests | 🟢 | 🟡 its grid of twelve columns is right (`grid-column: 1 / span 4`), the menu folded (`<details>`); the "LIVE" badge is over its headline, the page not centred | 🟢 | 🟡 with `scripts=www.bbc.com,static.files.bbci.co.uk` its fifty files all parse and load (6 s of CPU), and React then fails to take the page over (styled-components wants a style sheet's object): nothing lost, the page came whole. Its pictures are WebP: no decoder, empty frames |

`?` in a cell: could not be told, the page did not get that far.

## What the scripts of the web ask of the engine

The other measure, for JavaScript alone: twelve real scripts given to
the engine (`scripts/js/Js_survey.exe`), each stopping at its first
mistake. A library is then *used*: asked for something in a small page
(jQuery to find, change and listen; Vue to mount a template; Preact
and Mithril to render), and its answer compared. 🟢 loads, and works
when used (or has no use to try: a site's own script); 🟡 loads, and
stops when used; 🔴 does not load.

| Script | | Where it stops (2026-10-02) |
|---|---|---|
| jQuery 3.7 | 🟢 | finds (`#l li`, `li:last`, `:contains`), changes (`text`, `addClass`, `appendTo`), listens and triggers a click |
| jQuery 3.7 slim (minified) | 🟢 | the same |
| Vue 3.4 (minified) | 🟢 | `createApp(...).mount()`: a template compiled, `{{ }}` and `v-for` rendered |
| Alpine 3 | 🟢 | `x-data` read, `x-text` set |
| Underscore 1.13 | 🟢 | `map`, `uniq`, `template` |
| Preact 10 (minified) | 🟢 | renders a tree into the page |
| Mithril 2 | 🟢 | renders a tree into the page |
| React 18 (minified) | 🟢 | makes elements (React alone: no react-dom here) |
| htmx 1.9 | 🟢 | finds, changes and processes elements; in the browser itself, `hx-get` asks its server and swaps the answer in |
| Hacker News' `hn.js` | 🟢 | |
| Wikipedia's startup module | 🟢 | |
| example.com's `s.js` | 🟡 | parses; in the survey's page it stops at the paragraph it expects. On example.com itself (`scripts=example.com`) it runs with no error said, and the page looks the same: not looked into |

jQuery, Vue and Alpine were also put on one page, served by
`mini-httpd` and opened in the browser itself (`scripts=127.0.0.1`):
each drew its part.

Loading was the measure until the libraries all loaded: a library
defined is not a library working, and the use says so.

How it moved, the same day:

| | 🟢 | 🟡 | 🔴 |
|---|---|---|---|
| at first | 1 | 0 | 11 |
| the language of 1999 (the comma operator, `in` and for-in, the bits, `switch`, `do`, labels, `finally`) | 2 | 5 | 5 |
| template literals, destructuring, default and rest parameters, spread, an object literal's short forms, getters and setters | 2 | 8 | 2 |
| regular expressions: lookaheads, lookbehinds, backreferences, named groups, the flags s, u, y | 3 | 7 | 2 |
| the globals libraries look for (`Symbol`, `Map`, `Set`, `Object.defineProperty`, `isFinite`...), an undeclared name assigned to | 6 | 4 | 2 |
| classes (`extends`, `super`, fields, statics), optional chaining | 6 | 5 | 1 |
| promises and their jobs, `async` functions and `await` | 6 | 6 | 0 |
| what a library asks of a page (the document as a node, an element's modern members, events of a script's own, `window`'s globals), a regular expression's `source`, typed arrays | 11 | 1 | 0 |

By the stricter measure, used and not only loaded: 6 🟢, 6 🟡, 0 🔴.

| | 🟢 | 🟡 | 🔴 |
|---|---|---|---|
| used: an array's methods on what is like one, `new Function`, `with`, `Proxy` and `Reflect`, a symbol as a value | 11 | 1 | 0 |

## Next, by what it would turn green

- **Text beyond ASCII**: Wikipedia, CNN Lite, DuckDuckGo, and every
  page not in English.
- **WebP** (a decoder, in elm-playground beside the others): the
  BBC's pictures, and most pictures of today's web.
- **Google's results**: not a matter of the engine any more. Either
  its challenge is studied until it gives a token (a program made to
  resist that), or the browser says it is one Google still sends plain
  results to, or searches go to DuckDuckGo (`search=duckduckgo`),
  which works.
- **Modules** (`<script type=module>`, import and export): GitHub's
  scripts, and most sites built since 2020.
- **`<details>` opened by a click, the layers of `@layer`, a style
  sheet as an object** (`style.sheet`, which React's styling
  libraries write their rules into).
- **The heading of Berkshire Hathaway** (a 1990s table and `<font>`),
  now that its Brotli is read.
- **The TLS handshake Craigslist refuses**: to look into.
