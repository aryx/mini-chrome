#!/bin/bash
# The three older browsers of tools/ (mini-mosaic, mini-netscape,
# mini-firefox) on the built-in pages, each dumped to a PNG in the
# directory given: no display needed (SDL's dummy drivers). Run before
# and after a change to what they share with the browser (Html_layout's
# types, Looks.t, Browser_draw, Browser_page, Browser_tab) and compare
# the two directories with cmp: nothing of theirs should move.
#
#   scripts/tools/dump_old_browsers.sh /tmp/before
#   ... the change, dune build ...
#   scripts/tools/dump_old_browsers.sh /tmp/after
#   for f in /tmp/before/*.png; do cmp $f /tmp/after/$(basename $f); done
out=${1:?a directory for the pictures}
mkdir -p "$out"
cd "$(dirname "$0")/../.."
export SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy
dump() { timeout 60 "$@" >/dev/null 2>&1 || echo "FAILED: $*"; }
for page in home history form netscape; do
  dump ./bin/mini-mosaic -size 900x900 -dump-frame 30 "$out/mosaic-$page.png" url=about:$page
done
dump ./bin/mini-mosaic -size 900x900 -dump-frame 30 "$out/mosaic-pretty.png" url=about:history wrap=pretty width=600
for page in netscape css home form history; do
  dump ./bin/mini-netscape -size 900x900 -dump-frame 40 "$out/netscape-$page.png" url=about:$page
done
dump ./bin/mini-netscape -size 900x900 -dump-frame 40 "$out/netscape-nocss.png" url=about:css css=off
for page in firefox css counter todo netscape; do
  dump ./bin/mini-firefox -size 900x900 -dump-frame 40 "$out/firefox-$page.png" url=about:$page
done
ls "$out" | wc -l
