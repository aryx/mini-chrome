#!/bin/bash
# The clips of tests/video: each a WebM file written by libvpx (through
# ffmpeg), and the MD5 of every frame as ffmpeg's own VP8 decoder gives
# it (raw I420: the luma, then the two chromas) -- the answer our
# decoder must give, to the byte. Run once, by hand, in this
# directory; its outputs are kept in the repository.
#
#   plain    frames predicted from the one before, nothing else
#   motion   more of it: new vectors, split macroblocks, quarter pixels
#   odd      a size that is not a multiple of 16
#   life     noise that moves: many split macroblocks
#   keys     a key frame every 7, four partitions of coefficients
#   prof1    the format's version 1: two-pixel filter, simple loop filter
#   prof3    version 3: whole-pixel chroma vectors
set -e
clip() {
  name=$1; shift
  ffmpeg -hide_banner -loglevel error -y "$@" -auto-alt-ref 0 $name.webm
  ffmpeg -hide_banner -loglevel error -y -i $name.webm -pix_fmt yuv420p -f rawvideo $name.yuv
  python3 - $name <<'PY'
import hashlib, subprocess, sys, json
name = sys.argv[1]
info = json.loads(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "stream=width,height", "-of", "json", name + ".webm"]))["streams"][0]
w, h = info["width"], info["height"]
size = w * h + 2 * ((w + 1) // 2) * ((h + 1) // 2)
yuv = open(name + ".yuv", "rb").read()
open(name + ".md5", "w").write("".join(hashlib.md5(yuv[i:i + size]).hexdigest() + "\n" for i in range(0, len(yuv), size)))
PY
  rm $name.yuv
}
clip plain  -f lavfi -i "testsrc=size=96x64:rate=10"      -frames:v 24 -c:v libvpx -b:v 120k
clip motion -f lavfi -i "testsrc2=size=160x120:rate=15"   -frames:v 30 -c:v libvpx -b:v 150k
clip odd    -f lavfi -i "mandelbrot=size=70x50:rate=10"   -frames:v 20 -c:v libvpx -b:v 80k
clip life   -f lavfi -i "life=size=96x80:rate=10:mold=10:ratio=0.3:death_color=#102030:life_color=#ffe0a0" -frames:v 25 -c:v libvpx -b:v 200k
clip keys   -f lavfi -i "testsrc2=size=96x64:rate=10"     -frames:v 30 -c:v libvpx -b:v 100k -g 7 -slices 4
clip prof1  -f lavfi -i "testsrc2=size=96x64:rate=10"     -frames:v 16 -c:v libvpx -b:v 100k -profile:v 1
clip prof3  -f lavfi -i "testsrc2=size=96x64:rate=10"     -frames:v 16 -c:v libvpx -b:v 100k -profile:v 3

# A sound alone, Vorbis (libvorbis), two channels at 22,050 Hz: a
# falling chirp on the left, a rising one on the right. The same
# packets in WebM and in Ogg, and what libvorbis decodes from them
# (16-bit samples, the two channels in turn): our decoder's answer, a
# rounding apart.
plain="-map_metadata -1 -fflags +bitexact -flags:a +bitexact"
ffmpeg -hide_banner -loglevel error -y -f lavfi \
  -i "aevalsrc=0.6*sin(2*PI*(900-800*t)*t)|0.6*sin(2*PI*(200+1500*t)*t):s=22050:d=0.5" \
  -c:a libvorbis -q:a 2 $plain sound.webm
ffmpeg -hide_banner -loglevel error -y -i sound.webm -c:a copy $plain sound.ogg
ffmpeg -hide_banner -loglevel error -y -c:a libvorbis -i sound.ogg -f s16le $plain sound.s16
