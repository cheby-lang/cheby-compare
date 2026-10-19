(* json_roundtrip: parses a JSON array of records, transforms it and *)
(* serializes it again. *)

let fnv_offset = 2166136261
let fnv_prime = 16777619

type address = { street : string; city : string; zip : int }
type entry = { day : int; amount : int }

type record = {
  id : int;
  name : string;
  active : bool;
  score : int;
  tags : string list;
  address : address;
  history : entry list;
}

open Yojson.Safe.Util

let address_of_json j =
  {
    street = j |> member "street" |> to_string;
    city = j |> member "city" |> to_string;
    zip = j |> member "zip" |> to_int;
  }

let entry_of_json j =
  { day = j |> member "day" |> to_int; amount = j |> member "amount" |> to_int }

let record_of_json j =
  {
    id = j |> member "id" |> to_int;
    name = j |> member "name" |> to_string;
    active = j |> member "active" |> to_bool;
    score = j |> member "score" |> to_int;
    tags = j |> member "tags" |> to_list |> List.map to_string;
    address = j |> member "address" |> address_of_json;
    history = j |> member "history" |> to_list |> List.map entry_of_json;
  }

let address_to_json a : Yojson.Safe.t =
  `Assoc
    [
      ("street", `String a.street);
      ("city", `String a.city);
      ("zip", `Int a.zip);
    ]

let entry_to_json e : Yojson.Safe.t =
  `Assoc [ ("day", `Int e.day); ("amount", `Int e.amount) ]

(* A kept record as it is written: [active] is gone, [score] changed and *)
(* [total] added. *)
let output_to_json r total : Yojson.Safe.t =
  `Assoc
    [
      ("id", `Int r.id);
      ("name", `String r.name);
      ("score", `Int (r.score + (100 * List.length r.tags)));
      ("tags", `List (List.map (fun t -> `String t) r.tags));
      ("address", address_to_json r.address);
      ("history", `List (List.map entry_to_json r.history));
      ("total", `Int total);
    ]

let fnv1a h s =
  String.fold_left
    (fun h c -> ((h lxor Char.code c) * fnv_prime) land 0xFFFF_FFFF)
    h s

let () =
  let text = In_channel.with_open_bin Sys.argv.(1) In_channel.input_all in
  let reps = int_of_string Sys.argv.(2) in
  let records_n = ref 0 and active_n = ref 0 and score_sum = ref 0 in
  let tags_n = ref 0 and history_n = ref 0 and amount_sum = ref 0 in
  let output_bytes = ref 0 and hash = ref fnv_offset in
  for rep = 0 to reps - 1 do
    let records =
      Yojson.Safe.from_string text |> to_list |> List.map record_of_json
    in
    let kept =
      List.fold_left
        (fun kept r ->
          let total = List.fold_left (fun s e -> s + e.amount) 0 r.history in
          incr records_n;
          score_sum := !score_sum + r.score;
          tags_n := !tags_n + List.length r.tags;
          history_n := !history_n + List.length r.history;
          amount_sum := !amount_sum + total;
          if r.active then begin
            incr active_n;
            output_to_json r total :: kept
          end
          else kept)
        [] records
    in
    let out = Yojson.Safe.to_string (`List (List.rev kept)) in
    output_bytes := !output_bytes + String.length out;
    if rep = reps - 1 then hash := fnv1a fnv_offset out
  done;
  Printf.printf "records %d\n" !records_n;
  Printf.printf "active %d\n" !active_n;
  Printf.printf "score_sum %d\n" !score_sum;
  Printf.printf "tags %d\n" !tags_n;
  Printf.printf "history %d\n" !history_n;
  Printf.printf "amount_sum %d\n" !amount_sum;
  Printf.printf "output_bytes %d\n" !output_bytes;
  Printf.printf "output_fnv1a %d\n" !hash
