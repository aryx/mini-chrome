(* A sound decoded as it plays, not before.

   A compressed sound is a list of packets, each a few hundredths of a
   second, and a decoder that must be given them in order (Vorbis and
   Opus overlap each block with the one before: Mdct.mli). To decode
   them all when the file is opened is the simple way, and a song of
   four minutes then makes the page wait a quarter of a minute before
   its first note, and holds every sample of it from then on.

   Here the sound is there at once, whole in its length and silent:
   two arrays of samples at the browser's rate (Signal.stereo), as
   long as the file says the sound is. A stream fills them from the
   front, a packet at a time, when asked to be [ahead] of where the
   player is; the player reads the arrays as it reads any sound's, and
   knows nothing of this.

     the file's packets   p0 p1 p2 p3 p4 p5 ...        (next: one more decoded)
     at the file's rate   ################......       (filled)
     at ours              ##############........       (ready)
                              ^ the player       ^ ahead of it: three seconds

   The file's rate is not always ours (Opus is at 48,000 samples a
   second always, the browser's sounds at Signal.rate): each of our
   samples is read between the file's (Resample.read, a cubic through
   four of them), as soon as those it needs are decoded -- the same
   numbers as the whole sound resampled at once, with no seam between
   two packets.

   Its length is the one the file says (an Ogg file's last page);
   decoded whole, a sound is as long as its packets gave, which can be
   a few hundredths of a second less: silence here.

   What is not done: going back to the start gives what was decoded
   (nothing is forgotten, so the memory is the simple way's in the
   end), and a jump ahead decodes all that is between, the decoders
   having no other way in.

   modern:
   A browser decodes on a thread of its own, some seconds ahead of the
   sound card, and forgets what was played; it can start in the middle
   of a file (an Ogg page says its time, and the codec forgets the
   packets before within a few of them), which is what lets a radio
   be listened to. Media Source Extensions (2013) gave the page's
   script the feeding itself, a piece of file at a time. *)

type t

(* [create ~rate ~length ~skip ~next]: a sound of [length] samples a
 * channel at [rate] a second, after the first [skip] decoded are
 * dropped (Opus's pre-skip); [next ()] decodes one more packet, its
 * channels' samples (one channel, or two and more: the first two are
 * kept), None at the end *)
val create : rate:int -> length:int -> skip:int -> next:(unit -> float array array option) -> t

(* the sound, whole in its length, silent where it is not decoded yet *)
val samples : t -> Signal.stereo

(* how many of its samples (at our rate) are decoded *)
val ready : t -> int

(* packets decoded until [ready] is at least that, or the end *)
val ahead : t -> int -> unit
