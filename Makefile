all:
	dune build
test:
	dune runtest -f
clean:
	dune clean
# claude: the two programs, bin/mini-chrome (Cairo when its platform is
# installed, else the software one) and bin/mini-chrome-software (the
# Playground's own rasterizer, always): see src/main/dune
run:
	dune exec mini-chrome
run-software:
	dune exec mini-chrome-software

#coupling: see also .github/workflows/docker.yml
build-docker:
	docker build -t "mini-chrome" .
build-docker-ocaml5:
	docker build -t "mini-chrome" --build-arg OCAML_VERSION=5.5.1 .

.PHONY: all test clean run run-software build-docker build-docker-ocaml5
