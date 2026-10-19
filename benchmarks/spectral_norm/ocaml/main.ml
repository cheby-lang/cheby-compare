(* Spectral norm: the benchmarks-game power method on the matrix *)
(* A(i, j) = 1 / ((i + j)(i + j + 1) / 2 + i + 1), cut to n by n. *)

(* The entry A(i, j) of the matrix. Without [@inline], ocamlopt (no flambda) keeps it a call *)
(* that returns a boxed float, one allocation per entry. *)
let[@inline] entry i j = 1.0 /. float_of_int ((((i + j) * (i + j + 1)) / 2) + i + 1)

(* Writes A times x into out. *)
let times_a x out =
  let n = Array.length x in
  for i = 0 to n - 1 do
    let sum = ref 0.0 in
    for j = 0 to n - 1 do
      sum := !sum +. (entry i j *. x.(j))
    done;
    out.(i) <- !sum
  done

(* Writes A transposed times x into out. *)
let times_at x out =
  let n = Array.length x in
  for i = 0 to n - 1 do
    let sum = ref 0.0 in
    for j = 0 to n - 1 do
      sum := !sum +. (entry j i *. x.(j))
    done;
    out.(i) <- !sum
  done

(* Writes A transposed times A times x into out, using tmp. *)
let times_ata x tmp out =
  times_a x tmp;
  times_at tmp out

let dot x y =
  let sum = ref 0.0 in
  for i = 0 to Array.length x - 1 do
    sum := !sum +. (x.(i) *. y.(i))
  done;
  !sum

let () =
  let n = int_of_string Sys.argv.(1) in
  let u = Array.make n 1.0 in
  let v = Array.make n 0.0 in
  let tmp = Array.make n 0.0 in
  for _ = 1 to 10 do
    times_ata u tmp v;
    times_ata v tmp u
  done;
  let vv = dot v v in
  let result =
    if vv = 0.0 then 0 else Float.to_int (Float.round (sqrt (dot u v /. vv) *. 1e9))
  in
  Printf.printf "%d\n" result
