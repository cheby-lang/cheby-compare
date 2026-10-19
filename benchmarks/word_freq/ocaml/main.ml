(* word_freq: counts the words of a file and prints the 20 most frequent. *)

let top = 20

let () =
  let path = Sys.argv.(1) in
  let text = In_channel.with_open_bin path In_channel.input_all in
  let counts : (string, int) Hashtbl.t = Hashtbl.create 16 in
  let total = ref 0 in
  let count word =
    if word <> "" then begin
      (match Hashtbl.find_opt counts word with
      | Some c -> Hashtbl.replace counts word (c + 1)
      | None -> Hashtbl.add counts word 1);
      incr total
    end
  in
  List.iter
    (fun line -> List.iter count (String.split_on_char ' ' line))
    (String.split_on_char '\n' text);
  let ranked = Hashtbl.fold (fun word c acc -> (word, c) :: acc) counts [] in
  let ranked =
    List.sort
      (fun (w1, c1) (w2, c2) ->
        let by_count = Int.compare c2 c1 in
        if by_count <> 0 then by_count else String.compare w1 w2)
      ranked
  in
  Printf.printf "total %d\n" !total;
  Printf.printf "distinct %d\n" (Hashtbl.length counts);
  List.iter
    (fun (word, c) -> Printf.printf "%d %s\n" c word)
    (List.take top ranked)
