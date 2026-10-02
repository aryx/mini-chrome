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
# The sites of docs/sites.md, each loaded without a screen and its
# window dumped as a PNG, with what -v said of its requests: how many,
# how many failed, and the first failure. Then the pictures are to be
# looked at, one by one, and docs/sites.md brought up to date: a site's
# colour is a person's (or Claude's) judgment of its picture, not a
# number this script can give.
#
# Usage, from the repository's root, after a make:
#   scripts/sites/dump_sites.sh [DIR]         (DIR: /tmp/mini-chrome-sites)
#   [FRAMES=n] [SIZE=WxH] scripts/sites/dump_sites.sh DIR [flag ...]
#
# Examples:
#   scripts/sites/dump_sites.sh
#   scripts/sites/dump_sites.sh /tmp/with-scripts scripts=example.com,en.wikipedia.org
#
# The sites are the list below: add one there, and its row in
# docs/sites.md.

set -uo pipefail

DIR=${1:-/tmp/mini-chrome-sites}
shift || true
FRAMES=${FRAMES:-420}
SIZE=${SIZE:-1000x700}
mkdir -p "$DIR"

SITES="
http://info.cern.ch/hypertext/WWW/TheProject.html
https://www.spacejam.com/1996/
https://www.berkshirehathaway.com
https://example.com
https://news.ycombinator.com
https://lobste.rs
https://text.npr.org
https://lite.cnn.com
https://www.craigslist.org
https://www.gutenberg.org
https://en.wikipedia.org/wiki/Web_browser
https://html.duckduckgo.com/html/?q=ocaml
https://www.google.com
https://old.reddit.com
https://github.com/aryx/mini-chrome
https://www.bbc.com/news
"

export SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy
i=0
for url in $SITES; do
  i=$((i + 1))
  n=$(printf "%02d" $i)
  out=$(timeout 120 ./bin/mini-chrome -v -size "$SIZE" -dump-frame "$FRAMES" "$DIR/$n.png" "url=$url" profile=off "$@" 2>&1)
  requests=$(echo "$out" | grep -c ' GET ')
  failed=$(echo "$out" | grep -c 'failed ')
  first=$(echo "$out" | grep -m1 'failed ' | sed 's/.*failed //' | cut -c1-100)
  echo "$n.png  $url  requests $requests, failed $failed${first:+  ($first)}"
done
echo
echo "the pictures are in $DIR"
