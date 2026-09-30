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
;; packages: the Playground for its window and drawing, tiny_libs for
;; what is not a browser's own yet (networking, pictures, sound).
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
    (tiny_libs (>= "0.3.0"))
    (elm_playground (>= "0.3.0"))
    (elm_playground_native (>= "0.3.0"))
    (testo :with-test)
    (alcotest :with-test)
  )
)
