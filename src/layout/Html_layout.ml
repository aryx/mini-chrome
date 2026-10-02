(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Html_layout.mli *)

type metrics = Looks.t -> string -> float
type picture = { src : string; height : float; middle : bool }
type control = { element : Dom.element; control_height : float }

type fragment = {
  text : string;
  look : Looks.t;
  x : float;
  width : float;
  baseline : float;
  picture : picture option;
  control : control option;
  element : Dom.element;
}

type line = { top : float; height : float; baseline : float; fragments : fragment list; anchors : string list }
type kind = Block of Dom.element | Anonymous | Rule of Dom.element
type marker = Bullet | Number of int

type box = {
  kind : kind;
  x : float;
  y : float;
  width : float;
  height : float;
  children : box list;
  lines : line list;
  floats : fragment list;
  marker : marker option;
  background : Looks.color option;
}

type unit_ = { space : float; width : float }
type breaker = measure:float -> unit_ array -> (int * int) list

(*****************************************************************************)
(* Breaking lines *)
(*****************************************************************************)

(* Linebreak.greedy's rule, with each unit's own space (a page's words
 * are in several looks, their spaces of several widths) *)
let greedy : breaker =
 fun ~measure units ->
  let n = Array.length units in
  let rec go start acc =
    if start >= n then List.rev acc
    else
      (* the line from [start], as long as the next unit still fits *)
      let rec extend j w =
        if j + 1 < n && w +. units.(j + 1).space +. units.(j + 1).width <= measure then
          extend (j + 1) (w +. units.(j + 1).space +. units.(j + 1).width)
        else j
      in
      let j = extend start units.(start).width in
      go (j + 1) ((start, j) :: acc)
  in
  go 0 []

(*****************************************************************************)
(* What every layout asks *)
(*****************************************************************************)

(* a form's control's size, in the look it is in, by its kind; none for
 * a hidden one, or what is not a control *)
let control_size (metrics : metrics) (l : Looks.t) (e : Dom.element) : (float * float) option =
  let number name default =
    match Option.bind (Dom.attribute name e) int_of_string_opt with Some n when n > 0 -> float_of_int n | _ -> default
  in
  (* a fixed-width character's cell: a field's text is set on one *)
  let cell = 0.6 *. l.size in
  let button label = Some (metrics l label +. (1.4 *. l.size), 1.7 *. l.size) in
  match Forms.control e with
  | None -> None
  | Some c -> (
      match c.kind with
      | Hidden -> None
      | Text | Password -> Some ((number "size" 20. *. cell) +. 8., 1.6 *. l.size)
      | Checkbox | Radio -> Some (0.9 *. l.size, 0.9 *. l.size)
      | Submit | Reset | Button -> button (Forms.label c)
      | Select opts ->
          let widest = List.fold_left (fun w (label, _) -> Float.max w (metrics l label)) 0. opts in
          Some (widest +. (2.2 *. l.size), 1.7 *. l.size)
      | Textarea -> Some ((number "cols" 20. *. cell) +. 8., (number "rows" 2. *. Looks.leading *. l.size) +. 8.))

let rec fragments (b : box) : fragment list =
  List.concat_map (fun (l : line) -> l.fragments) b.lines @ b.floats @ List.concat_map fragments b.children


let rec first_baseline (b : box) : float option =
  match b.lines with
  | l :: _ -> Some l.baseline
  | [] -> List.fold_left (fun found c -> match found with Some _ -> found | None -> first_baseline c) None b.children
