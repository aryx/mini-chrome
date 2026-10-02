(* Webm: a WebM file's frames found -- the box a web video comes in.

   A video file is not its codec: the compressed frames (Vp8_video's)
   are packets, and a container says what they are, when each is
   shown, and keeps the sound's packets beside the picture's. WebM is
   Matroska's syntax with a short list of what may be inside: at
   first VP8 and Vorbis, since then VP9, AV1 and Opus.

   The syntax is EBML, "binary XML": elements in elements, each

     name     1 to 4 bytes        0x1A45DFA3 is the file's first
     size     1 to 8 bytes        how many bytes of content follow
     content                      elements, a number, a text, bytes

   The name and the size are numbers whose length is in their own
   first byte, UTF-8's idea: the count of zeros before the first 1 is
   how many bytes follow ([vint]). 0x81 is one byte, the number 1;
   0x40 0x02 two bytes, the number 2.

   What is read, of all that Matroska has:

     Segment                          the file's one body
       Info                           TimecodeScale: the unit of every
                                      time, in ns (a millisecond
                                      unless said); Duration
       Tracks
         TrackEntry                   TrackNumber, TrackType (1:
                                      video), CodecID ("V_VP8")
           Video                      PixelWidth, PixelHeight
       Cluster                        a stretch of the file: its time,
         SimpleBlock                  then blocks, each a track's
         BlockGroup > Block           number, its time after the
                                      cluster's (16 bits), a byte of
                                      flags, one frame

   An element not known is skipped by its size: how a format of 2002
   took AV1 and HDR without a new version. A size of all ones is "to
   the end", for a file written while it is recorded.

   Not read: the index (Cues: where the key frames are, to jump
   there), several frames laced in one block, chapters, tags,
   attachments. A sound's track is found and its packets kept, not
   decoded here: Vorbis is libs/audio's (Vorbis.mli; Media gives it the
   track's [setup] and its packets), Opus is not decoded yet.

   cs-history:
   Matroska -- the Russian doll, boxes in boxes -- was started in
   December 2002 by Steve Lhomme and others, out of an earlier
   project (MCF), to be a container nobody owned, holding anything:
   AVI (Microsoft's RIFF, 1992) could not say when a frame was shown
   but by counting them, QuickTime's and MP4's were Apple's and
   MPEG's. It became the .mkv of films passed round the net. In May
   2010 Google, opening VP8, needed a free container to go with it
   and took Matroska with a list of allowed contents: WebM, the file
   of HTML5's <video> that nobody had to pay for. EBML and Matroska
   were made RFCs only in 2020 and 2024 (8794, 9559).

   others:
   MP4 (ISO base media file format, 2001, after QuickTime's of 1991):
   boxes too, a size then four letters, and the same job -- H.264's
   and AAC's usual box, and what most of the web's video is in. Ogg
   (Xiph.Org): pages, made to be streamed, Theora's and Vorbis's.

   Reference: RFC 8794 (EBML), RFC 9559 (Matroska); the WebM
   container guidelines (webmproject.org). *)

(* a track: its number (which its packets say), whether it is a
 * video's, its codec's name ("V_VP8", "A_VORBIS"), a video's size, a
 * sound's samples a second and channels (0 for a video), and what its
 * codec must be told before the first packet (Vorbis's three headers,
 * [laced]; nothing for VP8) *)
type track = { number : int; video : bool; codec : string; width : int; height : int; rate : float; channels : int; setup : string }

(* the tracks, and every packet in the file's order: its track, its
 * time in seconds, its bytes; how long the file says it is *)
type t = { tracks : track list; frames : (int * float * string) list; duration : float }

(* whether these bytes are an EBML file (Matroska, WebM): 1A 45 DF A3 *)
val sniff : string -> bool

(* the file read. Raises [Failure] or [Invalid_argument] on bytes
 * that are not one *)
val parse : string -> t

(* the first video track and its frames, each with its time *)
val video : t -> (track * (float * string) list) option

(* the first sound track and its packets *)
val audio : t -> (track * (float * string) list) option

(* several packets in one string, as Xiph laces them (Matroska's way
 * to keep Vorbis's three headers in a track's [setup]): a byte, their
 * count less one; the size of each but the last, as bytes to add up,
 * the last of them under 255 (so 255 3 is 258, and 255 0 is 255);
 * then the packets. "\002\003\001abcde" is "abc", "d", "e".
 * Raises [Invalid_argument] on a string cut short *)
val laced : string -> string list
