#!/bin/bash
# Claude Code
#
# Copyright (C) 2026 Yoann Padioleau
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Library General Public License
# (LGPL) as published by the Free Software Foundation; either version
# 2 of the License, or (at your option) any later version.
#
# The README's screenshots (docs/screenshots/), taken again: the real
# program, without a screen, on real sites and on its own pages, each
# window dumped after 480 frames (FRAMES, for another count; SIZE and
# KEPT, for another window and what is kept of it) -- the page had, its style sheets and
# pictures come, laid out for the last time.
#
# Usage, from the repository's root, after a make (needs the network,
# and ImageMagick's convert):
#   scripts/sites/screenshots.sh
#
# The window is made 100 points taller than the picture kept, and its
# bottom cut off: the Playground's platforms write the window's size
# and frame rate at the bottom left, which is not the browser's.

set -uo pipefail

DIR=docs/screenshots
mkdir -p "$DIR"
export SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy

shot() {
  name=$1; url=$2; shift 2
  timeout 150 ./bin/mini-chrome -size "${SIZE:-1200x900}" -dump-frame "${FRAMES:-480}" "$DIR/$name.png" url="$url" profile=off "$@" > /dev/null 2>&1
  convert "$DIR/$name.png" -crop "${KEPT:-1200x800}+0+0" +repage "$DIR/$name.png"
  echo "$name: $(identify -format '%wx%h, %b' "$DIR/$name.png")"
}

shot hackernews https://news.ycombinator.com
shot wikipedia https://en.wikipedia.org/wiki/OCaml
shot github https://github.com/ocaml/ocaml
shot tube about:tube
shot pdf about:pdf
shot chrome about:chrome
# the Playground's menu, compiled to JavaScript by js_of_ocaml, run by
# our engine (docs/plans/plan_tinybox.md): a frame is long, so fewer
# of them. Its picture is 16 by 9: a window whose page is (675 points
# under the 87 of the tabs and the toolbar), kept whole -- the
# platform's words are dark on its dark ground
SIZE=1200x762 KEPT=1200x762 FRAMES=220 shot tinybox https://aryx.github.io/ocaml-elm-playground/tinybox.html
