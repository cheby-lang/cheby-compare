(* Fannkuch-redux: flips over every permutation of 0..n, in the order the counting *)
(* algorithm generates them. Prints the alternating checksum and the maximum flip count. *)

(* Reverses a.(0..k), both ends included. *)
let reverse_prefix (a : int array) k =
  let i = ref 0 and j = ref k in
  while !i < !j do
    let t = a.(!i) in
    a.(!i) <- a.(!j);
    a.(!j) <- t;
    incr i;
    decr j
  done

(* Returns (checksum, max_flips) over all permutations of 0..n - 1, n >= 1. *)
let fannkuch n =
  let perm1 = Array.init n (fun i -> i) in
  let perm = Array.make n 0 in
  let count = Array.make n 0 in
  let max_flips = ref 0 and checksum = ref 0 in
  let r = ref n in
  (* Advances perm1 to the next permutation; false when every one has been visited. *)
  let rec next_permutation () =
    if !r = n then false
    else begin
      let first = perm1.(0) in
      for i = 0 to !r - 1 do
        perm1.(i) <- perm1.(i + 1)
      done;
      perm1.(!r) <- first;
      count.(!r) <- count.(!r) - 1;
      if count.(!r) > 0 then true
      else begin
        incr r;
        next_permutation ()
      end
    end
  in
  let rec loop perm_index =
    while !r <> 1 do
      count.(!r - 1) <- !r;
      decr r
    done;
    Array.blit perm1 0 perm 0 n;
    let flips = ref 0 in
    let k = ref perm.(0) in
    while !k <> 0 do
      reverse_prefix perm !k;
      incr flips;
      k := perm.(0)
    done;
    if !flips > !max_flips then max_flips := !flips;
    if perm_index land 1 = 0 then checksum := !checksum + !flips
    else checksum := !checksum - !flips;
    if next_permutation () then loop (perm_index + 1) else (!checksum, !max_flips)
  in
  loop 0

let () =
  let arg = int_of_string Sys.argv.(1) in
  let checksum, max_flips = fannkuch (max arg 1) in
  Printf.printf "%d\n" checksum;
  Printf.printf "Pfannkuchen(%d) = %d\n" arg max_flips
