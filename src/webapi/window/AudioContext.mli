(* AudioContext: sound made by a page's script, a buffer of samples at
   a time (the Web Audio API).

   <audio> plays a file. A game, a synthesizer, a tracker compute
   their sound as they run, and need the other way: here are the next
   samples, play them at that instant.

     const ctx = new AudioContext()
     const buffer = ctx.createBuffer(2, n, 44100)       two channels of n samples
     buffer.getChannelData(0)[i] = ...                  written by the script
     const source = ctx.createBufferSource()
     source.buffer = buffer
     source.connect(ctx.destination)
     source.start(ctx.currentTime + 0.05)               on the context's clock, in seconds

   The clock ([currentTime]) is the sound card's, not the page's: it
   moves by the samples really played, so a buffer started right at
   the end of the one before plays with no gap, however late the frame
   that made it. A script that keeps a little sound scheduled ahead
   (a tenth of a second) and tops it up at each frame has continuous
   sound: what the Playground's web platform does with the samples of
   its own mixer (its Web_audio), and how its games are heard in this
   browser (docs/plans/plan_tinybox.md).

   What is here is that much and no more: a context, its clock, a
   buffer, a buffer's source started at a time and connected to the
   destination. The class is written in JavaScript
   (data/prelude/web.js); this module is the two things it cannot do
   itself, the clock and the samples handed to who plays them
   ([output], which the browser sets: Audio_queue). No graph of nodes:
   no gain, no oscillator, no filter, no decoding of a file
   (decodeAudioData), and the context is "running" from the start,
   where a browser waits for a click or a key.

   cs-history:
   Sound on the web was a plug-in's (Flash) until <audio> (HTML5).
   Mozilla tried samples written to an <audio> element (the Audio Data
   API, 2010); Chris Rogers, at Google, proposed a graph of nodes that
   a native thread runs -- sources, gains, filters, wired by connect --
   so that timing would not depend on JavaScript's (the Web Audio API,
   in Chrome in 2011, a W3C Recommendation in 2021). A buffer source
   wired straight to the destination, as here, is its smallest graph.

   modern:
   The graph is run on an audio thread, 128 samples at a time; a
   script's own processing runs there too, in an AudioWorklet (2018),
   which replaced the ScriptProcessorNode, whose callback on the main
   thread stuttered whenever the page was busy. *)

(* who plays: the clock, in seconds since it began; and samples (left,
 * right, at [rate] a second) to be heard from the instant [at] of
 * that clock, or from now if it is past *)
type output = { now : unit -> float; play : at:float -> rate:int -> float array -> float array -> unit }

(* nobody at first: a clock that stays at 0, samples dropped. The
 * browser sets it (Window_update, to Audio_queue's) *)
val output : output ref

(* the global __audio the prelude's AudioContext is written over: now()
 * and play(left, right, rate, at) *)
val install : (string -> Js_value.value -> unit) -> unit
