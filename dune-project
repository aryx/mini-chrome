(lang dune 3.0)

(name mini-chrome)

(generate_opam_files true)

(license "LGPL-2.1-only")

(authors
   "Yoann Padioleau <yoann.padioleau@gmail.com>"
)

(maintainers
   "Yoann Padioleau <yoann.padioleau@gmail.com>"
)

(version "0.1.0")

(source (github aryx/mini-chrome))
(homepage "https://github.com/aryx/mini-chrome")
(bug_reports "https://github.com/aryx/mini-chrome/issues")

;; claude: one package, the browser; the libraries of languages/, libs/
;; and src/ are private (see README.md). It stands on elm-playground's
;; packages: the Playground for its window and drawing, tiny_libs for the
;; pictures, sound and video decoders and the cryptography; its
;; networking is its own (libs/network).
(package (name mini-chrome)
  (synopsis "A web browser from scratch in OCaml, after Google Chrome")
  (description "\
  A small web browser written from scratch in OCaml: HTML, CSS (the
  cascade, the box model, flexbox), a JavaScript engine, SVG, pictures,
  <video> and <audio>, tabs, an omnibox and developer tools. It started
  as elm-playground's TinyChrome.
")
  (depends
    (ocaml (>= "4.14.0"))
    (caps (>= "0.1.0"))
    ; claude: 0.3.1, the first with run_app ~screen_follows_window (the
    ; window resized, the page laid out again at its width)
    (tiny_libs (>= "0.3.1"))
    (elm_playground (>= "0.3.1"))
    ; claude: the software platform, SDL only: mini-chrome-software
    (elm_playground_software (>= "0.3.1"))
    (testo :with-test)
    (alcotest :with-test)
    ; claude: the openssl program, the server tests/network_unix's TLS
    ; tests talk to
    (conf-openssl :with-test)
  )
  ; claude: the native platform, SDL and Cairo: mini-chrome, built when
  ; it is installed (src/main/dune's (optional))
  (depopts
    elm_playground_native)
)
