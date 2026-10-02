#!/bin/sh
# The clips of tests/audio: Ogg Vorbis and Opus files written by
# others' encoders (through ffmpeg), and what the references, libvorbis
# and libopus, decode from each (16-bit samples: a WAV, or raw at
# 48,000 Hz for Opus) -- the answer our decoders must give, a rounding
# apart. Run once, by hand, in this directory; its outputs
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

# Opus, by libopus; "lowdelay" is CELT alone.
#
#   music    two channels, 20 ms frames: attacks (short blocks, the
#            anti-collapse), a pitched bell (the post-filter), the two
#            channels as mid and side, as one and a sign, and apart
#   thin     the same at 24 kbit/s: bands with no bit, folded
#   short    frames of 2.5 ms, one channel
#   packed   three frames of 20 ms a packet (the packet's code 3)
#   narrow   4 kHz wide, frames of 10 ms
#   speech   12 kbit/s for a voice: SILK, which we do not decode --
#            silence of its length (no answer kept)
noise="0.2*(random(0)-0.5)*gt(mod(t\,0.25)\,0.2)"
two48="-f lavfi -i aevalsrc=$bell+$noise|$bell+$chirp:s=48000:d=0.5"
mono48="-f lavfi -i aevalsrc=$bell+$chirp+$noise:s=48000:d=0.5"
celt="-c:a libopus -application lowdelay"
$ff $two48 $celt -b:a 96k $plain music.opus
$ff $two48 $celt -b:a 24k $plain thin.opus
$ff $mono48 $celt -b:a 64k -frame_duration 2.5 $plain short.opus
$ff $mono48 $celt -b:a 48k -frame_duration 60 $plain packed.opus
$ff $mono48 $celt -b:a 32k -frame_duration 10 -cutoff 4000 $plain narrow.opus
$ff $mono48 -c:a libopus -application voip -b:a 12k $plain speech.opus
for f in music thin short packed narrow; do
  $ff -c:a libopus -i $f.opus -f s16le $plain $f.s16
done
