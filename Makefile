all:
	dune build
test:
	dune runtest -f
clean:
	dune clean
run:
	dune exec mini-chrome

#coupling: see also .github/workflows/docker.yml
build-docker:
	docker build -t "mini-chrome" .
build-docker-ocaml5:
	docker build -t "mini-chrome" --build-arg OCAML_VERSION=5.5.1 .

.PHONY: all test clean run build-docker build-docker-ocaml5
