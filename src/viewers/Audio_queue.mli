(* The sounds a page's scripts scheduled (AudioContext), mixed into
 * what the browser plays: each a pair of channels and the sample of
 * the output's clock it starts at. [mix] is the sound card's side,
 * called for each block it asks (Browser_media's fill, on the audio
 * thread): the clock moves by the block, what is due in it is added,
 * what is over is dropped. *)

(* the clock: seconds of sound played since the program began *)
val now : unit -> float

(* samples at [rate] a second, to start at [at] seconds of that clock
 * (now, if it is past); made the output's rate *)
val play : at:float -> rate:int -> float array -> float array -> unit

(* the block [out] being filled: what is scheduled in it added to what
 * it has, and the clock moved past it *)
val mix : Signal.stereo -> unit
