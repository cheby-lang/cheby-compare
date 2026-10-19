(* Mandelbrot set on an N x N grid: count the points inside, sum iterations, checksum. *)

let max_iter = 50

(* The number of iterations before the point (cr, ci) escapes, or max_iter. *)
(* The products are bound before their sums: ocamlopt on arm64 fuses an inline a *. b +. c into an *)
(* fmadd, and no flag turns that off. Bound, it emits no fused instruction (checked with -S). *)
let escape_time cr ci =
  let zr = ref 0.0 and zi = ref 0.0 and i = ref 0 and escaped = ref false in
  while (not !escaped) && !i < max_iter do
    let zr2 = !zr *. !zr in
    let zi2 = !zi *. !zi in
    if zr2 +. zi2 > 4.0 then escaped := true
    else begin
      let t = 2.0 *. !zr *. !zi in
      zi := t +. ci;
      zr := zr2 -. zi2 +. cr;
      incr i
    end
  done;
  !i

let () =
  let n = int_of_string Sys.argv.(1) in
  let nf = float_of_int n in
  let inside = ref 0 and iterations = ref 0 and checksum = ref 0 in
  for y = 0 to n - 1 do
    let ci = (2.0 *. float_of_int y /. nf) -. 1.0 in
    for x = 0 to n - 1 do
      let cr = (2.0 *. float_of_int x /. nf) -. 1.5 in
      let i = escape_time cr ci in
      iterations := !iterations + i;
      if i = max_iter then begin
        incr inside;
        checksum := !checksum + ((y * n) + x)
      end
    done
  done;
  Printf.printf "inside %d\n" !inside;
  Printf.printf "iterations %d\n" !iterations;
  Printf.printf "checksum %d\n" (!checksum land 0xFFFF_FFFF)
