# data/

What the browser is built with and that is not OCaml: files embedded
as strings at build time, so that the program needs none of them at
run time. Each is copied by the dune file of the library that embeds
it (`copy_files`), and becomes a generated module there.

| Here | What it is | Embedded as | By |
|---|---|---|---|
| `about/` | the built-in site: the `about:` pages (`home.html`, `chrome.html`, the pages of the browsers before...), their style sheets and scripts, and one picture in each format the browser reads | `Site_pages`, `Site_pictures` | `src/about` |
| `tube/` | `about:tube`'s files made elsewhere, by ffmpeg: an MPEG-1 video and its WebM twin (VP8 by libvpx, the `.mpg`'s sound again as Vorbis by libvorbis); two chirps as an MP3 (LAME), and from it as Opus (libopus, in its own file and in a WebM), Vorbis and MP2 | `Tube_files` | `src/about` |
| `css/ua.css` | the browser's own style sheet: what an element looks like before the page says anything (CSS 2.1's appendix D, grown) | `Ua_sheet` | `languages/css` |
| `prelude/library.js` | the JavaScript standard library's later additions (ES2016 to ES2024, `Date`, `JSON.stringify`), written in JavaScript and run in every engine before any script | `Js_prelude` | `languages/javascript` |
| `prelude/web.js` | small web APIs (`AbortController`, `TextEncoder`, `structuredClone`, `Headers`, `Intl`...) written in JavaScript and run in every page before its scripts | `Script_prelude` | `src/dom` |

Why here and not beside the code: a source directory holds one
language. The `.mli` of each generated module (`Js_prelude.mli`,
`Script_prelude.mli`, `Site.mli`) says what its file is for.

Two things follow from their being text and not OCaml:

- they are not in the budget (`make loc` counts OCaml), which is why
  what can be written in the page's own languages is: a method of
  `Array` in JavaScript, a default look in CSS;
- a change to one is a rebuild, not a run-time choice: nothing reads
  these files once the program is built.

A new built-in page needs its file in `about/`, an entry in the
`Site_pages.ml` rule of `src/about/dune` (both `deps` and the
`echo`/`cat` pair), and a case in `Site.ml`.

Test data is not here: each suite has its own (`tests/images/data`,
`tests/images/pngsuite`, `tests/compression/data`).
