all:
	dune build
test:
	dune runtest -f
clean:
	dune clean
# the two programs, bin/mini-chrome (Cairo when its platform is
# installed, else the software one) and bin/mini-chrome-software (the
# Playground's own rasterizer, always): see src/main/dune
run:
	dune exec mini-chrome
run-software:
	dune exec mini-chrome-software

# the lines of OCaml, and how much of the budget (30,000 for
# languages/, libs/ and src/; not the tests, nor the interfaces'
# opening comments) they are; -v: a library a
# line, and the largest files
loc:
	scripts/stats/loc.py
loc-v:
	scripts/stats/loc.py -v

#coupling: see also .github/workflows/docker.yml
build-docker:
	docker build -t "mini-chrome" .
build-docker-ocaml5:
	docker build -t "mini-chrome" --build-arg OCAML_VERSION=5.5.1 .

.PHONY: all test clean run run-software loc loc-v build-docker build-docker-ocaml5
