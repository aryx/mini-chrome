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
# What a page's load looks like in time, on the real program: it is run
# without a screen (SDL's dummy driver) up to a frame, -v saying each
# request and each answer, and a time is put before each line. Then the
# clock's time against the CPU's: nearly the same means the program
# computes, it does not wait for the network.
#
# What to read in it (docs/dev/notes_debugging_techniques.txt, session 2):
# answers that come in bursts seconds apart are frames that long (a
# page laid out again for each answer of the burst); and two runs to
# different frames (FRAMES=600, FRAMES=1200) give what a frame costs
# once the page is shown.
#
# Usage, from the repository's root, after a make:
#   [FRAMES=n] [SIZE=WxH] scripts/perf/load_timeline.sh [URL] [flag ...]
#
# Examples:
#   scripts/perf/load_timeline.sh                       # Wikipedia's article on OCaml, 400 frames
#   scripts/perf/load_timeline.sh https://news.ycombinator.com
#   FRAMES=1200 scripts/perf/load_timeline.sh           # the frames after the load
#   scripts/perf/load_timeline.sh about:tube threads=off

set -euo pipefail

URL=${1:-https://en.wikipedia.org/wiki/OCaml}
shift || true
FRAMES=${FRAMES:-400}
SIZE=${SIZE:-1400x800}
OUT=$(mktemp --suffix=.png)
trap 'rm -f "$OUT"' EXIT

# a time before each line; an address shortened to fit
stamp() {
  python3 -u -c '
import sys, time
t0 = time.time()
for line in sys.stdin:
    line = line.rstrip().replace("mini-chrome: [INFO] ", "")
    print("%7.2f  %s" % (time.time() - t0, line[:110]))
'
}

export SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy
TIMEFORMAT=$'\nclock %R s, CPU %U s (user) + %S s (system), to frame '"$FRAMES"
time (./bin/mini-chrome -v -size "$SIZE" -dump-frame "$FRAMES" "$OUT" "url=$URL" profile=off "$@" 2>&1 | stamp)
