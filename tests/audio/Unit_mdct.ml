(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Unit_mdct.mli *)

let close = Alcotest.(array (float 1e-3))

let tests =
  Testo.categorize "Mdct"
    [
      Testo.create "the worked example: two frequencies, four samples" (fun () ->
          Alcotest.check close "(1, 0)" [| 0.383; -0.383; -0.924; -0.924 |] (Mdct.imdct [| 1.; 0. |]));
      Testo.create "the samples are the definition's" (fun () ->
          List.iter
            (fun m ->
              let x = Array.init m (fun k -> sin (float_of_int k *. 0.7) +. (0.3 *. float_of_int (k mod 3))) in
              let direct =
                Array.init (2 * m) (fun n ->
                    let sum = ref 0. in
                    Array.iteri (fun k v -> sum := !sum +. (v *. cos (Float.pi /. float_of_int m *. (float_of_int n +. 0.5 +. (float_of_int m /. 2.)) *. (float_of_int k +. 0.5)))) x;
                    !sum)
              in
              Alcotest.check close (string_of_int m) direct (Mdct.imdct x))
            [ 2; 8; 30; 120 ]);
      Testo.create "the cosine transform, fast and by its definition (opti=off)" (fun () ->
          List.iter
            (fun m ->
              let x = Array.init m (fun i -> sin (float_of_int i *. 0.37) +. (0.5 *. cos (float_of_int (i * i) *. 0.01))) in
              let simple = Mdct.dct4_simple x and fast = Mdct.dct4_opti x in
              Array.iteri (fun i v -> if Float.abs (v -. fast.(i)) > 1e-9 *. float_of_int m then Alcotest.failf "m = %d, at %d: %g, not %g" m i fast.(i) v) simple)
            (* powers of two (Vorbis's), 15 times one (Opus's), others *)
            [ 4; 8; 32; 128; 1024; 6; 30; 120; 960; 14; 22 ]);
      Testo.create "the Fourier transform: a size that is no power of two" (fun () ->
          (* one turn of a cosine in 6 samples: all in frequencies 1 and 5 *)
          let re, im = Mdct.fft (Array.init 6 (fun n -> cos (2. *. Float.pi *. float_of_int n /. 6.))) (Array.make 6 0.) in
          Alcotest.check close "real" [| 0.; 3.; 0.; 0.; 0.; 3. |] re;
          Alcotest.check close "imaginary" (Array.make 6 0.) im;
          (* a prime: by the definition *)
          let re, _ = Mdct.fft (Array.make 7 1.) (Array.make 7 0.) in
          Alcotest.check close "seven ones" [| 7.; 0.; 0.; 0.; 0.; 0.; 0. |] re);
    ]
