(* Opus: the sound of today's web -- what a WebM file, an .opus file
   and every WebRTC call carry; decoded here where it is music (its
   CELT half).

   A packet is one to 48 frames, and its first byte says how they are
   coded (the "TOC"):

     bits 7..3  the configuration, 0 to 31: which coder, how wide in
                frequency, how long a frame
                   0..11   SILK alone   speech: 4, 6 or 8 kHz wide,
                                        frames of 10 to 60 ms
                  12..15   hybrid       SILK under 8 kHz, CELT above
                  16..31   CELT alone   music: 4, 8, 12 or 20 kHz wide
                                        (a row of four each), frames of
                                        2.5, 5, 10 or 20 ms
     bit 2      two channels coded, or one
     bits 1..0  the frames: 0, one; 1, two of one size; 2, two of two
                sizes (the first's said); 3, a count in a second byte,
                of one size or each with its own, and padding

   The byte FC is 11111 1 00: CELT, 20 kHz wide, 20 ms; two channels;
   one frame -- what most music on the web is. A frame's size is one
   byte under 252, else two (the first, plus four times the second).

   Whatever the packet says, the sound comes out at 48,000 Hz, in the
   channels the stream's header asked for (a frame of one channel is
   played on both). A file starts with that header, "OpusHead": the
   channels, a gain, and how many samples at the start are the
   encoder's own warming up, to drop ([pre_skip]: 312 for libopus).

   Not decoded: SILK. A frame that is SILK's, alone or hybrid, is
   silence of its length -- speech at low rates, which is what a call
   is and not what a page plays. Nor: more than two channels, a lost
   packet concealed (it is silence), a redundant frame at a switch of
   coders.

   cs-history:
   Two codecs made one. SILK was Skype's, for speech (Koen Vos, 2009):
   linear prediction, as a telephone's codecs since the 1970s. CELT
   was Xiph.Org's (Jean-Marc Valin, from 2007, with Timothy Terriberry
   and Gregory Maxwell): a transform codec as Vorbis (Vorbis.mli), cut
   for delay -- frames of 2.5 to 20 ms where Vorbis has 46. The IETF's
   codec working group, asked for one codec for the Internet with no
   royalty, put them in one stream that can change from one to the
   other at each frame: RFC 6716, September 2012. WebRTC made it the
   codec every browser must have (RFC 7874); YouTube sends it in WebM;
   it replaced Vorbis in what is made now, and MP3 and AAC where
   nobody is owed anything.

   design:
   Why CELT alone, and first: it is the half that is a codec of music,
   the half whose ideas are new (Celt.mli), and what a file made for a
   page holds at 64 kbit/s and more. SILK is as much code again, of
   another kind.

   References: RFC 6716, Definition of the Opus Audio Codec (2012;
   section 3 for the packet, 4.3 for CELT; its appendix is the
   decoder, which is the standard: the text describes it); RFC 7845,
   Ogg Encapsulation for the Opus Audio Codec (2016), for "OpusHead";
   J.-M. Valin, G. Maxwell, T. Terriberry and K. Vos, High-Quality,
   Low-Delay Music Coding in the Opus Codec, AES 135th Convention,
   2013. *)

(* a decoder, and what it keeps from the frame before *)
type t

(* samples a second, always *)
val rate : int

(* from a stream's first packet, "OpusHead" (a WebM track's setup);
 * fails (Failure) on what is not one, or asks for more than two
 * channels *)
val create : head:string -> t

val channels : t -> int

(* samples to drop at the start *)
val pre_skip : t -> int

(* a packet cut: its configuration (0 to 31), whether it codes two
 * channels, its frames. Fails (Failure) on one cut short *)
val frames : string -> int * bool * string list

(* [decode t packet]: its samples, each channel's, from -1 to 1 *)
val decode : t -> string -> float array array

(* packets decoded one after the other, less [pre_skip] *)
val sound : t -> string list -> float array array

(* a stream's packets, its two headers first *)
val of_packets : string list -> t * float array array

(* an .opus file's sound, cut at the length it says *)
val of_ogg : string -> t * float array array
