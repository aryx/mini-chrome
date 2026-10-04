# Plan: the sites people use

## Context

`docs/sites.md` follows sixteen sites, most of them documents: a page
of HTML and its style, read. This plan is about the other web, the
one made of applications -- GitHub, Gmail, ChatGPT, YouTube,
discuss.ocaml.org, 9fans.topicbox.com, chess.com, Amazon -- and asks
of each: what stops it today, at which level (the network, HTML, CSS,
the JavaScript language, the web APIs, speed), and whether there is a
way.

Each was loaded on 2026-10-04 in the real program, twice: as the
browser is by default (its scripts not run), then with the site's
scripts allowed (`scripts=<host>`), the console read (`-v`) and the
window dumped. What follows is what was seen, not what is supposed.

## What was seen

| Site | Its scripts not run | Its scripts run | What it is |
|---|---|---|---|
| **GitHub** (a repository) | readable: the files' names, the About column, the tabs. Not right: no top bar, the buttons one over the other, the files' table without its columns and borders | 141 requests, 108 scripts, 4.9 MB of JavaScript; three errors, each in a file of GitHub's own (`code-view`: "e is not a function"; `github-elements`: `appendChild` of undefined; `behaviors`: `requestErrored` of null). Too slow to reach its 300th frame in 150 s | HTML made on the server (445 KB, React's, with CSS modules), 2.2 MB of CSS in twenty sheets, scripts that add behaviour to a page already whole |
| **discuss.ocaml.org** | right: the topics, their tags and counts, as links. Discourse gives a browser it does not know its page for crawlers | the same: that page has no script | an Ember application; its page without scripts is a courtesy, to read, not to post |
| **9fans.topicbox.com** | "your browser does not support the technologies needed" | blank: `Bad Router.baseUrl`; `xhr.upload.removeEventListener` is not a function; "Maximum call stack size exceeded" | an application whole in JavaScript (a page of 3 KB and its bundles; 7 requests) |
| **chess.com** | its side menu; the rest dark | 57 requests; `Object.defineProperty called on non-object`; `byteLength` of undefined (bytes: an ArrayBuffer); a bundle that does not parse ("expected an expression, not '.'"); Cloudflare's Turnstile | a Vue application; the board is a canvas, a game a WebSocket |
| **Amazon** | a page of 3.7 KB, right: "Click the button below to continue shopping" | the same | pages made on the server, behind a check for robots that a form's button passes |
| **YouTube** | grey boxes: the page's skeleton, 934 KB of HTML that is mostly data for its scripts | `NodeFilter is not defined`, `CSSStyleSheet is not defined`, its configuration object missing | megabytes of JavaScript (custom elements), and video by Media Source Extensions in VP9, AV1 or H.264 with AAC or Opus |
| **ChatGPT** | 403: "Enable JavaScript and cookies to continue" | "Browser not supported": Cloudflare's check of the browser | an application behind a challenge made to tell a known browser from anything else |
| **Gmail** | sent to Google's sign-in: "Couldn't sign you in: the browser you're using doesn't support JavaScript" | the sign-in form is drawn (the address's field, Next) | Google's sign-in, then megabytes of JavaScript; its page in plain HTML was retired in 2024 |

Two numbers frame the rest. **GitHub's style is 2.2 MB** for the light
theme alone, and uses what a component library of the 2020s uses:

| In GitHub's sheets | Times | Here |
|---|---|---|
| `var(--x)` | 18,912 | yes |
| `:where()`, `:is()`, `:not()` | 911, 181, 777 | yes |
| `@media` with a range (`width >= 768px`) | 745 | yes |
| logical properties (`margin-block-start`, `padding-inline`...) | about 1,600 | **yes, since today** (`Css_logical`) |
| `:has()` | 92 | no |
| `order` (flex) | 78 | no |
| `clip-path` (what hides a screen reader's text) | 57 | no |
| `text-overflow` | 52 | no |
| `@container` | 23 | no |
| `color-mix()` | 21 | no |

**And an application's scripts are megabytes**, run at each load. Our
engine starts a program of 931 KB in 1.3 s and is three to five times
slower than Node's interpreter, which is itself many times slower
than what these sites are written for (`plan_js_speed.md`).

## What can be hoped, site by site

**Within reach** -- the page comes whole from the server; what is
missing is ours to add, a property and a bug at a time:

- **GitHub, read**: a repository, a file, an issue, drawn as Chrome
  draws them, scripts off. The work is CSS and layout (below).
- **discuss.ocaml.org, read**: there already. To check: a topic's
  page, the next page of a list.
- **Amazon, browsed**: the button of the first page is a form; what
  comes after is HTML made on the server, large and old-fashioned
  (tables, floats, sprites), and cookies. To try before saying more.

**Far, but a road** -- an application of moderate size whose errors
are things we lack, each nameable:

- **9fans.topicbox.com**: the smallest of the applications here
  (seven requests), and the first to try to bring up whole: a router
  over `history`, requests, a list drawn by scripts. Its three errors
  are a week's work, and there will be others behind them.
- **GitHub with its scripts**: behaviour over a page already there
  (menus, the file tree, the search). Three errors and its speed.
- **discuss.ocaml.org as an application**, **chess.com's pages**
  (not the board): frameworks (Ember, Vue) whose first errors are the
  bytes and objects of the language's library.

**Not by this browser** -- and the reason is not a missing feature:

- **ChatGPT**: Cloudflare's challenge is written to refuse what is
  not one of the browsers it knows, by what the engine is (the order
  of its properties, its timings, its TLS handshake's shape). Passing
  it is pretending to be Chrome to a program made to detect that; not
  a thing to build here.
- **Gmail**: Google's sign-in refuses browsers it does not recognise
  as secure, by policy; behind it, an application of the size of
  YouTube's. Mail is IMAP's, in another program.
- **YouTube**: the application could one day run, slowly; the video
  cannot be shown without Media Source Extensions and a decoder of
  VP9 or AV1 (tens of thousands of lines each; H.264 and AAC are
  patented besides). `about:tube` plays what this browser decodes.
- **chess.com, a game played**: the board is drawn on a canvas at
  sixty frames a second over megabytes of scripts.

## The work, by level

Each level has a way to find what is missing that does not need the
site to work: a census of what the site asks, against what we have.

**1. CSS and layout: GitHub drawn right** (the first target).
- *A census tool* (`scripts/css/Css_census.exe`): a site's sheets
  read by our own parser and cascade, and said: the properties we
  drop and how often, the selectors we do not match, the at-rules we
  skip. The table above was made by hand with regular expressions;
  the tool makes it from what the engine really refuses, for any
  site, and `docs/sites.md` gets a column from it.
- Then, in the order the census and the picture say: `order`,
  `:has()`, `clip-path` and the ways a page hides text meant for a
  screen reader, `text-overflow`, `position: sticky`, `@container`,
  `color-mix()`; the table of files (its columns, its borders); the
  top bar that does not show; the buttons that overlap.
- The method of `notes_debugging_techniques.txt`, session 1: one
  thing wrong in the picture, the element found in the page, its
  rules read, a page of ten lines that shows the same.

**2. HTML.** Little is wrong at this level: the pages parse. To
check: `<template>` and what custom elements expect to find,
`hidden`, `<dialog>`, `inert`, and what the server sends a browser
it does not know (Discourse's crawler page, Amazon's check).

**3. The JavaScript language.** The method that brought twelve
libraries up (`scripts/js/Js_survey.exe`): each site's bundles saved,
parsed, run in an empty page, the first error fixed, again. Seen
today: a bundle that does not parse (chess.com's Sentry), a stack too
shallow for a router's recursion (the limit of 2,000 calls), 
`Object.defineProperty` on what we do not call an object.

**4. The web APIs.** By the errors, then by a census of the names a
bundle reads on `window`, `document` and an element that we do not
define: `NodeFilter` and tree walkers, `CSSStyleSheet` and adopted
sheets, an `XMLHttpRequest`'s `upload`, bytes (an `ArrayBuffer` that
is one, typed arrays over it, `TextEncoder`), custom elements and
shadow roots, observers that observe (`MutationObserver`,
`IntersectionObserver`), `history.pushState` and a router's idea of
the address, `crypto`, `structuredClone`, `Intl`. Each a module of
its name in `src/webapi`, as `Cors` and `AudioContext` are.

**5. Speed.** An application's megabytes parsed and run at each
load, then at each click. `plan_js_speed.md`'s end (a frame of a
compiled program in 130 ms) is where this starts: scripts kept
parsed between two visits, a function compiled only when called
(done), and the engine's next design if these sites become the aim.

**6. The network and who we say we are.** TLS 1.2 (Craigslist; some
of these sites' hosts), cookies' `SameSite`, the `User-Agent` and
what a site sends for it (`Browser_agent`'s table and its reasons).

## Order

1. **GitHub, read, drawn right**: the census tool, then its findings.
   Visible at each step, and what it adds (a component library's CSS)
   is what every site of the list is styled with.
2. **Amazon and discuss.ocaml.org, a second page each**: what a
   click gives, to know if "within reach" is true.
3. **9fans.topicbox.com brought up**: the first application run
   whole, chosen for its size; `Js_survey` and the APIs' census on
   its bundles.
4. **GitHub's scripts**, then the frameworks (Vue, Ember) by their
   first errors.

Not planned: ChatGPT, Gmail, YouTube's video, chess.com's board.

## Progress

**2026-10-04, step 1: GitHub's repository page is drawn right**,
scripts off (`docs/screenshots/github.png`). The census tool is
`scripts/css/Css_census.exe`; its second mode (`at=SELECTOR`: an
element's winning rules, and what its style and its ancestors' come
to) is what found each fault. None was a missing property:

- a custom property's name was put in lower case (`--bgColor-default`
  never found by `var(--bgColor-default)`): the top bar, the borders,
  the links' colour, the table;
- six faults of layout, each shown first on a page of ten lines
  (`changes.txt`): a float's fit to the last bit, a percent
  `max-width` asked of the item itself, percents inside what is being
  measured (a button, a field), an svg as a flex item, a colour's
  opacity, a flex item's minimum over its maximum.

The census's own list (`order`, `:has()`, `clip-path`,
`text-overflow`, `@container`, `color-mix()`) was not needed for this
page: to do when a page shows the lack. A saved copy of the page with
its sheets beside it, served by `mini-httpd`, is the bench: the real
site's sheets are refused to a page of another origin.

**2026-10-04, YouTube and Gmail, a first look with their scripts.**
Asked for as the aim, however far: two sites used by everybody are
the best bench a browser has. What was learned in an evening:

- *YouTube's page can be run without a window*: its nine scripts put
  in the page (12 MB, the main one 10.8 MB) are read and run by
  `scripts/js/Page_scripts.exe` in 5.4 s. The engine's speed is not
  what stops it first.
- *What stops it* is the first of a long chain, each found only once
  the one before is passed: `NodeFilter`, `CSSStyleSheet` and its
  `replaceSync`, then the polyfill of web components patching
  prototypes we do not have (`HTMLSlotElement`), then Polymer itself.
  Of the names its bundles use, 49 are not defined here; the ones
  that matter: `CustomElementRegistry`, `Request`, `Response`,
  `ReadableStream`, `MessageChannel`, `Worker`, `MediaSource`,
  `IntersectionObserverEntry`, `DOMException`, `History`.
- *The page is its custom elements*: `<ytd-app>` and hundreds under
  it, each a class given to `customElements.define`, with a shadow
  tree or Polymer's emulation of one. Without them nothing is drawn
  but the skeleton the server sends. So the road is, in order:
  **custom elements** (the registry, an element upgraded when its
  name is defined, its callbacks when it enters the page), **shadow
  trees** (`attachShadow`, slots, the tree the layout sees made of
  both), **templates** (`<template>`'s content, cloned), **observers
  that observe**. GitHub's own elements and 9fans.topicbox need the
  first three too: it is the same work, and the next one to do.
- *Then the video*, which is another matter (Media Source Extensions
  and a decoder of VP9 or AV1): the application drawn with its
  thumbnails and titles is the mark to aim at; the player is not.
- *Gmail*: Google's sign-in page is drawn with its scripts (the
  address's field, Next). What comes after an address is typed was
  not tried: it needs an account, and is where Google decides
  whether it knows the browser.

A way to work that does not cost the budget: what a web API is
that needs nothing of the engine's insides is written in JavaScript
(`data/prelude/web.js`, as `AudioContext`'s class is), and the
engine gets only the hooks (an element entering the tree, a shadow
root's place in the tree that is laid out).

**2026-10-04, later: 9fans.topicbox.com starts, and web components.**

- *9fans.topicbox.com* is not made of custom elements (said wrongly
  above): it is an application of one framework (Overture, FastMail's),
  whose every error was a small thing of ours, each found without
  the network -- its bundles and its server's answers saved once and
  given back (`Page_scripts.exe` with `FILES=DIR`), so that nothing is
  sent to its error tracker while it fails. Three were the language's
  (a function expression's own name, forEach's second argument, `new
  Number`), four the page's (`location.href`'s final `/`, an upload's
  `removeEventListener`, a parsed document's lookups, the root's
  `clientWidth`). It now draws its menu and its News Center, with its
  desktop layout. Not right yet: the content is under the side bar
  (its layout), and a group's topics were not tried.
- *Shadow trees and custom elements* are in (`Shadow_tree.mli`, a
  card on `about:chrome`): what GitHub's elements and YouTube's are
  made with. Not tried on them yet.
- *A progressive JPEG* was the red slash seen on some pages
  (dave.recoil.org): the decoder is the Playground's, which reads
  them since 2026-10-04 (`Jpeg_progressive`, elm-playground after
  0.3.6).

## Cost

The budget has 5,545 lines left of 40,000. Step 1 is 300 to 600
(CSS properties and selectors are small each; the tool is in
`scripts/`, not counted). Step 3 and 4 are web APIs, a hundred lines
each for a dozen of them: they do not fit with the rest, and reaching
them means deciding what the budget is for -- the plan to come back
to after step 2.
