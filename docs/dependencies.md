# What mini-chrome stands on

Everything the browser uses that is not in this repository, by kind:
the Playground, the libraries written with it (`tiny_libs`), the opam
packages, the C libraries, what the machine must have when it runs,
and what was used once to make a file kept here. And, at the end,
what is *not* a dependency: what was taken from elsewhere and is now
this repository's own.

The rule for which side of the line a thing is on (2026-10-02): what
was born of the web, or for it, is written or kept here and told here
(`CLAUDE.md`, Conventions); what is general computer science -- a
compression, a cipher, a picture format older than the web, a
rasterizer -- stays in elm-playground and is used from its packages.
Keep this file true when a library is added to a `dune` file.

## 1. The Playground: the program's frame

`elm_playground` (opam, from `../ocaml-elm-playground`) is the runtime
the whole program is written against (`docs/architecture.md`).

| What | From it |
|---|---|
| The Elm architecture | `init`, `update`, `view`, `subscriptions`; `Cmd`, `Sub`; the loop that calls them (`Playground_platform.run_app`) |
| Drawing | the shapes a `view` returns (`rectangle`, `words`, `image`, `group`, `move`...), colours |
| The window and its events | size, keys, text typed, the pointer, the wheel, resizing, the frame clock |
| The command line | `key=value` flags; `-size`, `-dump-frame`, `-script`, `-v` |
| Two platforms, one chosen at build time | `elm_playground_native`: SDL2 and Cairo; `elm_playground_software`: SDL2 and its own rasterizer (`mini-chrome-software`, and every test) |

Not used: the Playground's own `Http` and networking commands (the
browser has its own, `libs/network` and `Fetch`), its 3D platforms,
its game kits.

## 2. `tiny_libs`: the libraries under the Playground

Pure OCaml, written in elm-playground, one opam package of many
libraries. By what they are, with the modules the browser names:

### Pictures and drawing

| Library | Modules | Used for | By |
|---|---|---|---|
| `graphics_rgba` | `Rgba_image` | the pixels every decoder gives back | `libs/images`, `libs/video`, `src/display`, `src/viewers` |
| `graphics_gif` | `Gif` | GIF pictures, animated ones | `src/display`, `src/viewers` |
| `graphics_jpeg` | `Jpeg` | JPEG pictures | `src/display`, `src/viewers`, `libs/pdf` |
| `graphics_xpm` | `Xpm` | X pixmaps (a media file) | `src/viewers` |
| `graphics_core` | `Framebuffer` | the pixels an SVG is painted into | `libs/images`, `src/about` |
| `graphics_2d` | `Fill`, `Stroke` | polygons filled with smooth edges, a stroke's outline: SVG | `libs/images`, `src/about` |
| `graphics_2d_geometry` | `Curve`, `Affine` | Bezier curves made lines, transforms composed: SVG | `libs/images` |
| `graphics_font` | `Hershey` | the letters: A. V. Hershey's strokes (1967), the browser's one font | `src/display`, `libs/pdf`, `src/viewers` |

### Video and sound (what `<video>` and `<audio>` play, and `about:tube`)

| Library | Modules | Used for | By |
|---|---|---|---|
| `graphics_movie` | `Movie` | a video as a player sees it: frames with times | `src/viewers` |
| `graphics_mpeg1`, `graphics_mpeg_system` | `Mpeg1`, `Mpeg_system` | MPEG-1 video, the `.mpg` stream | `src/viewers`, `src/about` |
| `graphics_avi`, `graphics_fli`, `graphics_y4m` | `Avi`, `Fli`, `Y4m` | AVI (Motion JPEG), FLC, raw video | `src/viewers`, `src/about` |
| `audio`, `audio_signal` | `Audio`, `Signal`, `Resample` | the mixer a sound is played through; samples, their rate changed | `src/viewers`, `src/about` |
| `audio_mpeg` | `Mpeg_audio` | MP2 and MP3 | `src/viewers` |
| `audio_wav`, `audio_midi`, `audio_mod`, `audio_abc` | `Wav`, `Midi`, `Mod`, `Mod_player`, `Abc`, `Doremi` | the other sounds a media file may be; `about:tube`'s tune written in each | `src/viewers`, `src/about` |

### Compression

| Library | Modules | Used for | By |
|---|---|---|---|
| `compression` | `Gzip`, `Zstd` | a body with `Content-Encoding: gzip`, `zstd` | `libs/network` |
| | `Zlib`, `Inflate`, `Crc32` | PNG's pixels and its checksums | `libs/images` |
| | `Huffman` | the prefix codes of Brotli and of lossless WebP | `libs/compression`, `libs/images` |

### Cryptography (all of it for TLS 1.3, 1.2 and their certificates, but one)

| Library | Modules | Used for | By |
|---|---|---|---|
| `crypto` | `X25519` | the key exchange | `libs/network` |
| | `Hkdf`, `Hmac`, `Sha256`, `Sha512` | the key schedule, the transcript's hash | `libs/network` |
| | `Chacha20_poly1305`, `Gcm` (AES) | the records' encryption | `libs/network` |
| | `Rsa`, `Ecdsa`, `Bignum` | a certificate's signature checked | `libs/network` |
| | `Sha1` | WebSocket's handshake proof | `libs/network` |

### Small things

| Library | Modules | Used for | By |
|---|---|---|---|
| `core` | `Base64` | PEM certificates, WebSocket's key | `libs/network` |
| | `Civil`, `Clock` | a certificate's dates, the time now | `libs/network` |
| `gui` | `Text` | a string's characters, for the chrome's text in cells | `libs/gui` |
| `random` | `Lehmer` | `Math.random`, seeded: a page run twice does the same | `languages/javascript` |

`tiny_libs.compression_brotli`, `graphics_png` and `graphics_svg`
exist there and are **not** linked: the browser has its own (section
6). The Playground links its own `Png` (a texture, a frame dumped),
which is why `libs/images` is wrapped.

## 3. opam packages

| Package | Used for |
|---|---|
| `caps` | capabilities: the authority to open a socket, a file, to run a program, handed down from `Cap.main` |
| `logs` | `-v`: each file and URL opened, said |
| `threads`, `unix` (OCaml's own) | the pool that waits for the network, an async function's coroutine; sockets, files, the clock |
| `dune` | the build |
| `testo`, `alcotest` | the tests |
| `conf-openssl` (tests only) | the `openssl` program: the TLS server `tests/network_unix` talks to |
| `tsdl`, `cairo2`, `ctypes` | not ours: what the Playground's platforms bind SDL and Cairo with |

Versions: OCaml 4.14 or 5; elm-playground after 0.3.5 (Brotli a
library apart there since 0.3.4; `set_cursor` and the clipboard after 0.3.5; progressive JPEGs after 0.3.6). `configure`'s pin and `dune-project`'s bound
still say 0.3.1: both are behind, and a fresh checkout does not build
until they are raised to a release that has it.

## 4. C libraries

| Library | Used for | Needed |
|---|---|---|
| SDL2 | the window, the keyboard and pointer, the sound's output | always |
| Cairo | drawing, on the native platform | not by `mini-chrome-software`, nor by the tests |

No other C: HTTP, TLS, the cryptography, every decoder, the fonts
and the JavaScript engine are OCaml.

## 5. The machine, when the program runs

| What | Used for | Without it |
|---|---|---|
| the resolver (`getaddrinfo`) and TCP sockets | every request | no network: the built-in pages only |
| `/dev/urandom` | TLS's secrets, WebSocket's keys and masks | no https |
| the root certificates (`/etc/ssl/certs/ca-certificates.crt`, or the three other usual places) | whom TLS trusts | every https site refused |
| `xrdb` (optional; not run on macOS, where it would start XQuartz) | the desktop's scale (`Xft.dpi`) | scale 1 |
| the helper programs of the profile's `Preferences` (optional, the person's choice: `mpv`, `gv`...) | what the browser does not show: a film of YouTube's, PostScript (`Browser_helpers`) | none is run |
| `~/.config/mini-chrome/` | the profile and the cookies | defaults; nothing saved |
| `~/.cache/mini-chrome/` | the answers kept (the HTTP cache) | every answer asked of the network |

## 6. What is not a dependency any more

Taken from elm-playground (where this browser began) and kept here to
grow, or written here; each is told in its `.mli`.

| Here | What | Came as |
|---|---|---|
| `languages/html`, `css`, `javascript`, `json` | the page's languages | a fork of its `languages/` and browser kit |
| `languages/xml`, `libs/dom` | XML's reader, the document's tree | out of its `Svg`, out of `languages/html` |
| `libs/network` | URLs, HTTP/1.1, cookies, TLS 1.3, TLS 1.2 (`Tls12`, with the P-256 exchange, `P256`, written here over `Bignum`), X.509, WebSocket | a copy of its `libs/networking` (wrapped: the Playground links the original) |
| `libs/compression` | Brotli and its dictionary | a copy; split out there so the two do not meet |
| `libs/images` | PNG, SVG | copies (wrapped: the Playground links its `Png`) |
| | WebP: `Webp`, `Vp8l`, `Vp8` | written here |
| `libs/video` | WebM, VP8's video | written here |
| `libs/pdf`, `libs/fonts` | a PDF file read and drawn; TrueType, CFF and Type 1 fonts | written here |
| `libs/audio` | Vorbis, Ogg's packets | a copy (its `audio_vorbis`, not linked here) |
| | Opus (CELT), the MDCT | written here |
| `libs/richtext`, `tools/typeset` | a look; Knuth and Plass's line breaking | copies of two of its app kits |
| `tools/mosaic`, `netscape`, `firefox` | the browsers before this one and the first layout engine | its `TinyMosaic`, `TinyNetscape`, `TinyFirefox` |

Others' data kept in the repository: Brotli's dictionary (Google, MIT
licence), PngSuite's pictures (Willem van Schaik's, their own
licence, in `tests/images/pngsuite`).

## 7. Used once, to make a file kept here

Not needed to build or to test: the outputs are in the repository,
each beside the script that says how it was made.

| Tool | Made |
|---|---|
| ffmpeg (libvpx, libvorbis, libopus, LAME) | `about:tube`'s `.mpg`, `.webm`, `.mp3`, `.opus`, `.ogg` and `.mp2`; the clips of `tests/video` and `tests/audio`, and what each must decode to |
| libwebp, through Python's Pillow | the pictures of `tests/images` and what each must decode to |
| Google's Brotli encoder (Python) | the streams of `tests/compression` |
| RFC 6386's text | `Vp8_tables`, taken from it by a program |
| RFC 6716's reference decoder (its appendix) | `Celt_tables`, taken from it by a program |
| Adobe's glyph list, the standard encoding (TeX Live's `8a.enc`), CFF's strings (Ghostscript's `gs_css_e.ps`) | `Glyph_names`, made by a program |
| Adobe's font metrics for Times and Helvetica (TeX Live's AFM files) | `Standard_widths`, made by a program |
| pdfTeX, cairo (Python), Chrome, LibreOffice; poppler's `pdftoppm` | the files of `tests/pdf` and the picture each page must be near; `about:pdf`'s sample |
