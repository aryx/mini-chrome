(* Webp: the web's own picture format -- a file's chunks found, and the
   picture in them decoded by the format it is in (Vp8, Vp8l).

   A WebP file is a box of chunks, and the box is older than the web:
   RIFF, each chunk four letters, a length of four bytes (the low byte
   first), then that many bytes, and one more of padding when the
   length is odd. The whole file is one chunk, RIFF, whose bytes start
   with the letters WEBP and go on with the chunks that matter:

     VP8     a lossy picture: one key frame of the VP8 video format
             (the fourth letter is a space)                 -> Vp8
     VP8L    a lossless picture                             -> Vp8l
     VP8X    the extended file: flags, and the size of the canvas;
             says that other chunks follow
     ALPH    the transparency of a lossy picture, which has none of
             its own: a byte a pixel, compressed as a lossless
             picture's green (Vp8l.plane), each byte first lessened
             by a neighbour (a filter, as PNG's)
     ANIM, ANMF   an animation and its frames, each a picture's chunks
                  after 16 bytes of where and how long
     ICCP, EXIF, XMP   a colour profile, the camera's notes: skipped

   So three kinds of file: the simple lossy one (RIFF, WEBP, VP8), the
   simple lossless one (RIFF, WEBP, VP8L), and the extended one (VP8X
   first, then whatever it announces). The smallest of the tests,
   data/lossless-1x1.webp, one transparent pixel, whole:

     52 49 46 46   R I F F
     1e 00 00 00   30: the bytes that follow, to the file's end
     57 45 42 50   W E B P
     56 50 38 4c   V P 8 L
     11 00 00 00   17: this chunk's bytes
     2f            the lossless format's signature
     00 00 00 00   14 bits of width - 1, 14 of height - 1 (1 by 1), a
                   bit for alpha, 3 of version
     07 50 8a ...  the picture (Vp8l.mli reads its first bits)
     00            17 is odd: a byte of padding

   12 + 8 + 17 + 1 = 38 bytes. And a lossy one's start, data/lossy-
   gradient.webp, 32 by 24:

     ... V P 8 space, 78 00 00 00 (120 bytes), then
     10 05 00      the frame's tag: a key frame, shown, whose first
                   part is 40 bytes (Vp8.mli)
     9d 01 2a      a key frame's start code
     20 00 18 00   its width and height, 14 bits each: 32, 24

   which is all [size] reads: a page is laid out around a picture
   whose pixels are not decoded yet.

   An animation is shown as its first frame, as an animated GIF is not
   (Browser_media plays those): the frames after the first are drawn
   over the canvas at their place, blended or not, which is not done
   here.

   cs-history:
   Where it came from. On2 Technologies, of New York (first The Duck
   Corporation, makers of the TrueMotion codecs for video games), sold
   video codecs through the 2000s: VP3, which it gave away in 2001 and
   which became Theora; VP6, which Flash played, and so YouTube at its
   start; VP8, announced in 2008. Google bought the company (the deal
   closed in February 2010) and on 19 May 2010 published VP8's source
   under a free licence as the WebM project: a video format for
   HTML5's <video> that nobody had to pay for, against H.264, which
   had patents and a licensing body (Browser_media.mli tells that
   quarrel). On 30 September 2010 it announced WebP: a VP8 key frame
   -- a frame coded without reference to another -- put in a RIFF box
   and called a picture. The codec was already written, tuned and
   in every copy of Chrome; and Google's measure was pictures 25 to
   34% smaller than JPEG's at the same quality, on a web where
   pictures were most of a page's bytes.

   cs-history:
   A lossy format alone could not replace PNG and GIF, so a second
   format, unrelated to VP8 but for its name, was announced in
   November 2011 (Vp8l.mli), and the extended file (VP8X, with alpha
   for lossy pictures and animation) made the three in 2012. The
   others were slow to follow -- a format of one vendor, read by one
   engine: Firefox read WebP in 2019, Safari in 2020, eight and ten
   years after Chrome. It was made an RFC only in 2024.

   cs-history:
   RIFF, the Resource Interchange File Format, is Microsoft's and
   IBM's (1991): the box of WAV sounds and AVI videos (elm-playground's
   Avi.mli). It is itself Electronic Arts' IFF (1985), the Amiga's box
   (elm-playground's Ilbm.mli), with the lengths' bytes turned round
   for Intel's processors. A picture format of 2010 in a box of 1985:
   a box needs no inventing.

   evolution:
   A video codec's still frame as a picture format is a pattern that
   came back twice: HEIC (2015), a frame of H.265, the iPhone's
   photographs since 2017; and AVIF (2019), a frame of AV1 -- the
   codec that descends from VP8 through VP9, made by an alliance of
   the companies that did not want to pay for H.265. Each time the
   reasoning is WebP's: the hard part, the codec, is there already.

   design:
   The cost of a format that every program must read from strangers.
   In September 2023 a WebP file made to that end was found being used
   against telephones: libwebp, the C library that every browser and
   much else links, built the tables of a lossless picture's prefix
   codes in a buffer sized for the codes a well-formed file can have,
   and a file could ask for more (CVE-2023-4863). Every browser, and
   every program with one inside, was patched in a week. A decoder of
   bytes from the network is the place where a language that checks
   an array's bounds pays for itself: here a file cut short or lying
   about its sizes ends in an exception, [Failure] or
   [Invalid_argument], and a broken picture's icon.

   others:
   Why here and not with elm-playground's GIF, PNG and JPEG
   (tiny_libs' graphics/images, which Browser_picture uses): those
   formats came to the web from outside, and a media player reads
   them too; this one was made by a browser's vendor for pages, and
   is told with the browser.

   References: RFC 9649, WebP Image Format (Zern, Massimino and
   Alakuijala, November 2024), which holds the container and the
   lossless format; RFC 6386 for the lossy one (Vp8.mli). The
   decoder is checked against libwebp's own output, pixel for pixel
   (tests/images, whose data/make.py made the files). *)

(* whether these bytes are a WebP file: RIFF, four bytes of length,
 * WEBP *)
val sniff : string -> bool

(* the picture: the lossless one, or the lossy one with its alpha if
 * it has some; an animation's first frame. Raises [Failure] or
 * [Invalid_argument] on bytes that are not one. *)
val decode : string -> Rgba_image.t

(* its width and height, from the first chunk's header alone *)
val size : string -> (int * int) option

(* [chunks s from until]: the chunks between two places of [s], each
 * its four letters and its bytes; a file's are [chunks s 12
 * (String.length s)] *)
val chunks : string -> int -> int -> (string * string) list
