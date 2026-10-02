# Build and test mini-chrome with OCaml 4.14.4 via OPAM on Ubuntu.
# See also .github/workflows/docker.yml for its use in Github Actions (GHA).
# coupling: adapted from ~/github/ocaml-elm-playground/Dockerfile

# 24.04, not 22.04: tsdl calls SDL_RenderGetWindow, SDL 2.0.22's,
# and 22.04 has SDL 2.0.20
FROM ubuntu:24.04

# Setup a basic C dev environment
RUN apt-get update # needed otherwise can't find any package
RUN apt-get install -y build-essential autoconf automake pkgconf git

# Setup OPAM and OCaml
RUN apt-get install -y opam
# Initialize opam (disable sandboxing due to Docker)
RUN opam init --disable-sandboxing -y
ARG OCAML_VERSION=4.14.4
RUN opam switch create ${OCAML_VERSION} -v

# System deps of the Playground's native platform (SDL2 + cairo).
# coupling: elm_playground_native.opam (tsdl, cairo2)
RUN apt-get install -y pkg-config libsdl2-dev libcairo2-dev

WORKDIR /src

# Install dependencies (copy minimal files for Docker layer caching):
# ./configure pins elm-playground's packages while 0.3.1 is not on opam
COPY configure mini-chrome.opam ./
RUN eval $(opam env) && ./configure

# Now copy the full source and build
COPY . .
RUN eval $(opam env) && make

# Test
RUN eval $(opam env) && make test
