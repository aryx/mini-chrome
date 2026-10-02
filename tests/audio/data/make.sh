#!/bin/sh
# The clips of tests/audio: Ogg Vorbis files written by others'
# encoders (through ffmpeg), and what libvorbis, the reference,
# decodes from each (16-bit WAV) -- the answer our decoder must give,
# a rounding apart. Run once, by hand, in this directory; its outputs
# are kept in the repository.
#
#   bell     one channel, libvorbis: a bell (three partials dying away)
#   stereo   two channels coupled, libvorbis: the bell on the left, the
#            bell and chirps on the right -- alike but not the same, and
#            attacks (short blocks)
#   low      the same at 22,050 Hz and the lowest quality: smaller blocks
#   native   ffmpeg's own encoder, whose setup is not libvorbis's:
#            other codebooks, floors and modes. (ffmpeg's own decoder
#            gives another right channel for it than libvorbis does:
#            hence libvorbis's, asked for by name, for all four.)
set -e
ff="ffmpeg -hide_banner -loglevel error -y"
plain="-map_metadata -1 -fflags +bitexact -flags:a +bitexact"
bell="0.5*exp(-4*t)*(sin(2*PI*440*t)+0.5*sin(2*PI*1108*t)+0.25*sin(2*PI*2217*t))/1.75"
chirp="0.3*exp(-30*mod(t\,0.125))*sin(2*PI*(300+3000*mod(t\,0.125))*t)"
mono="-f lavfi -i aevalsrc=$bell:s=44100:d=0.5"
two="-f lavfi -i aevalsrc=$bell|$bell+$chirp:s=44100:d=0.5"
$ff $mono -c:a libvorbis -q:a 3 $plain bell.ogg
$ff $two -c:a libvorbis -q:a 4 $plain stereo.ogg
$ff $two -ar 22050 -c:a libvorbis -q:a 0 $plain low.ogg
$ff $two -c:a vorbis -strict experimental -b:a 96k $plain native.ogg
for f in bell stereo low native; do
  $ff -c:a libvorbis -i $f.ogg -c:a pcm_s16le $plain $f.expected.wav
done
