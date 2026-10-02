(* Claude Code
 *
 * Copyright (C) 2026 Yoann Padioleau
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public License
 * (LGPL) as published by the Free Software Foundation; either version
 * 2 of the License, or (at your option) any later version.
 *)

(* See Grid_layout.mli *)

(*****************************************************************************)
(* Placement *)
(*****************************************************************************)

type cell = { row : int; column : int; rows : int; columns : int }

(* the rectangle a name draws in the areas, if it is there *)
let area_of (areas : string list list) (name : string) : cell option =
  let found = ref None in
  List.iteri
    (fun r row ->
      List.iteri
        (fun c n ->
          if n = name then
            found := Some (match !found with None -> (r, c, r, c) | Some (r0, c0, r1, c1) -> (min r0 r, min c0 c, max r1 r, max c1 c)))
        row)
    areas;
  Option.map (fun (r0, c0, r1, c1) -> { row = r0; column = c0; rows = r1 - r0 + 1; columns = c1 - c0 + 1 }) !found

(* an item along one axis of [n] tracks said: its first track if it
 * says one (from 0), and how many it takes *)
let along (n : int) ((first, last) : Css_grid.line * Css_grid.line) : int option * int =
  (* a line as an index: 1 is before track 0; -1 after the last *)
  let index k = if k > 0 then k - 1 else max 0 (n + 1 + k) in
  match (first, last) with
  | Line a, Line b -> let a = index a and b = index b in (Some (min a b), max 1 (abs (b - a)))
  | Line a, Span k -> (Some (index a), k)
  | Line a, Auto -> (Some (index a), 1)
  | Span k, Line b -> (Some (max 0 (index b - k)), k)
  | Auto, Line b -> (Some (max 0 (index b - 1)), 1)
  | (Span k, _ | Auto, Span k) -> (None, k)
  | Auto, Auto -> (None, 1)

let place ~(rows : int) ~(columns : int) ~(areas : string list list) (placements : Css_grid.placement list) : cell list * int * int =
  let said_rows = max rows (List.length areas) in
  let columns = List.fold_left (fun m row -> max m (List.length row)) (max 1 columns) areas in
  (* what an item says: its first row and column if it says them, and
   * how many of each; a name that no area has says nothing *)
  let said (p : Css_grid.placement) : int option * int * int option * int =
    match p with
    | Area name -> ( match area_of areas name with Some c -> (Some c.row, c.rows, Some c.column, c.columns) | None -> (None, 1, None, 1))
    | Lines { row; column } ->
        let r, rs = along said_rows row and c, cs = along columns column in
        (r, rs, c, cs)
    | Auto_placed -> (None, 1, None, 1)
  in
  let wanted = List.map said placements in
  (* as many columns as the widest item needs *)
  let columns = List.fold_left (fun m (_, _, c, cs) -> max m (Option.value c ~default:0 + cs)) columns wanted in
  let taken : (int * int, unit) Hashtbl.t = Hashtbl.create 16 in
  let take (c : cell) = for r = c.row to c.row + c.rows - 1 do for k = c.column to c.column + c.columns - 1 do Hashtbl.replace taken (r, k) () done done in
  let free r c rs cs =
    c + cs <= columns
    && (let ok = ref true in
        for i = r to r + rs - 1 do for k = c to c + cs - 1 do if Hashtbl.mem taken (i, k) then ok := false done done;
        !ok)
  in
  (* those that say both first: the others go round them *)
  List.iter (fun w -> match w with Some r, rs, Some c, cs -> take { row = r; column = c; rows = rs; columns = cs } | _ -> ()) wanted;
  (* the others, in order: the next place that is free, row by row from
   * where the last one went *)
  let cursor = ref 0 in
  let cells =
    List.map
      (fun (w : int option * int * int option * int) ->
        match w with
        | Some r, rs, Some c, cs -> { row = r; column = c; rows = rs; columns = cs }
        | r, rs, c, cs ->
            let rec find (at : int) : cell =
              let row = at / columns and column = at mod columns in
              let row_ok = match r with Some r -> row = r | None -> true and column_ok = match c with Some c -> column = c | None -> true in
              if row_ok && column_ok && free row column rs cs then { row; column; rows = rs; columns = cs }
              (* a row said and no room left in it: at its end, the grid wider *)
              else if (match r with Some r -> row > r | None -> false) then { row = Option.get r; column = columns; rows = rs; columns = cs }
              else find (at + 1)
            in
            let cell = find (match r with Some r -> r * columns | None -> !cursor) in
            if r = None then cursor := (cell.row * columns) + cell.column;
            take cell;
            cell)
      wanted
  in
  let rows = List.fold_left (fun m (c : cell) -> max m (c.row + c.rows)) said_rows cells in
  let columns = List.fold_left (fun m (c : cell) -> max m (c.column + c.columns)) columns cells in
  (cells, rows, columns)

(*****************************************************************************)
(* The tracks' sizes *)
(*****************************************************************************)

type content = { least : float; most : float }

let flexible (t : Css_grid.track) : bool = match t.max with Fr _ -> true | _ -> false

(* a track's least, and its most (infinity for an fr) *)
let least ~(base : float) (t : Css_grid.track) (c : content) : float =
  match t.min with Length l -> Css_values.resolve l base | Max_content -> c.most | Min_content | Auto | Fr _ -> c.least

let most ~(base : float) (t : Css_grid.track) (c : content) : float =
  match t.max with Length l -> Css_values.resolve l base | Min_content -> c.least | Max_content | Auto -> c.most | Fr _ -> infinity

let contents ~(base : float) ~(gap : float) (tracks : Css_grid.track array) (items : (int * int * content) list) : content array =
  let cs = Array.make (Array.length tracks) { least = 0.; most = 0. } in
  let add i (c : content) = cs.(i) <- { least = Float.max cs.(i).least c.least; most = Float.max cs.(i).most c.most } in
  (* the items of one track first, then those that span *)
  List.iter (fun (first, span, c) -> if span = 1 && first < Array.length cs then add first c) items;
  List.iter
    (fun (first, span, (c : content)) ->
      let last = first + span - 1 in
      if span > 1 && last < Array.length cs && not (Array.exists flexible (Array.sub tracks first span)) then begin
        (* what the others hold already, taken off: the rest to the last *)
        let others (pick : Css_grid.track -> content -> float) : float =
          let sum = ref (gap *. float_of_int (span - 1)) in
          for i = first to last - 1 do
            sum := !sum +. pick tracks.(i) cs.(i)
          done;
          !sum
        in
        (* a track's widest: its most, if it has one; else its content's *)
        let widest t k = let m = most ~base t k in if m = infinity then k.most else Float.max m (least ~base t k) in
        add last { least = Float.max 0. (c.least -. others (least ~base)); most = Float.max 0. (c.most -. others widest) }
      end)
    items;
  cs

let sizes ~(room : float option) ~(base : float) ~(gap : float) ~(stretch : bool) (tracks : Css_grid.track array) (cs : content array) : float array =
  let n = Array.length tracks in
  let low = Array.init n (fun i -> least ~base tracks.(i) cs.(i)) in
  let high = Array.init n (fun i -> Float.max low.(i) (most ~base tracks.(i) cs.(i))) in
  match room with
  | None ->
      (* nothing to share: each its most, an fr its content *)
      Array.init n (fun i -> if flexible tracks.(i) then Float.max low.(i) cs.(i).most else high.(i))
  | Some room ->
      let size = Array.copy low in
      let gaps = gap *. float_of_int (max 0 (n - 1)) in
      let left () = room -. gaps -. Array.fold_left ( +. ) 0. size in
      (* the room left to the tracks below their most, equally, each up
       * to it: again until none is left, or none can grow *)
      let rec grow () =
        let growing = List.filter (fun i -> (not (flexible tracks.(i))) && size.(i) < high.(i)) (List.init n Fun.id) in
        let free = left () in
        if free > 0.01 && growing <> [] then begin
          let share = free /. float_of_int (List.length growing) in
          List.iter (fun i -> size.(i) <- Float.min high.(i) (size.(i) +. share)) growing;
          grow ()
        end
      in
      grow ();
      (* then to the fr tracks, by their shares; one whose least is more
       * than its share keeps its least, and the others share again *)
      let rec share (flex : int list) =
        if flex <> [] then begin
          let fixed = Array.fold_left ( +. ) 0. (Array.mapi (fun i s -> if List.mem i flex then 0. else s) size) in
          let fr i = match tracks.(i).max with Fr f -> f | _ -> 0. in
          let unit = Float.max 0. (room -. gaps -. fixed) /. Float.max 1. (List.fold_left (fun s i -> s +. fr i) 0. flex) in
          match List.filter (fun i -> low.(i) > fr i *. unit) flex with
          | [] -> List.iter (fun i -> size.(i) <- fr i *. unit) flex
          | frozen ->
              List.iter (fun i -> size.(i) <- low.(i)) frozen;
              share (List.filter (fun i -> not (List.mem i frozen)) flex)
        end
      in
      let flex = List.filter (fun i -> flexible tracks.(i)) (List.init n Fun.id) in
      share flex;
      (* no fr: the auto tracks stretched over what is left *)
      (if stretch && flex = [] then
         let autos = List.filter (fun i -> tracks.(i).max = Css_grid.Auto) (List.init n Fun.id) in
         let free = left () in
         if free > 0. && autos <> [] then List.iter (fun i -> size.(i) <- size.(i) +. (free /. float_of_int (List.length autos))) autos);
      size

(*****************************************************************************)
(* Where each starts *)
(*****************************************************************************)

let starts ~(align : Computed.align) ~(room : float) ~(gap : float) (sizes : float array) : float array =
  let n = Array.length sizes in
  let free = Float.max 0. (room -. Array.fold_left ( +. ) 0. sizes -. (gap *. float_of_int (max 0 (n - 1)))) in
  let fn = float_of_int n in
  (* before the first, and added to each gap *)
  let before, between =
    match align with
    | End -> (free, 0.)
    | Center -> (free /. 2., 0.)
    | Space_between when n > 1 -> (0., free /. (fn -. 1.))
    | Space_around when n > 0 -> (free /. fn /. 2., free /. fn)
    | Space_evenly -> (free /. (fn +. 1.), free /. (fn +. 1.))
    | _ -> (0., 0.)
  in
  let at = ref before in
  Array.map
    (fun s ->
      let start = !at in
      at := !at +. s +. gap +. between;
      start)
    sizes
