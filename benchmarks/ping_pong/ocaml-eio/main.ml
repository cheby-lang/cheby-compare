(* ping_pong: two Eio fibers exchange n messages over two rendezvous streams (capacity 0). *)
open Eio.Std

(* Task B: answers each of the n values from ping with the value plus one on pong. *)
let echo n ping pong =
  for _ = 1 to n do
    let x = Eio.Stream.take ping in
    Eio.Stream.add pong (x + 1)
  done

(* Task A: sends 1 .. n on ping and adds up the answers from pong. *)
let play n ping pong =
  let sum = ref 0 in
  for i = 1 to n do
    Eio.Stream.add ping i;
    sum := !sum + Eio.Stream.take pong
  done;
  !sum

let () =
  let n = int_of_string Sys.argv.(1) in
  (* A is Eio's main fiber; B is forked into a switch, whose end joins it. *)
  let sum =
    Eio_main.run @@ fun _env ->
    let ping = Eio.Stream.create 0 in
    let pong = Eio.Stream.create 0 in
    Switch.run @@ fun sw ->
    Fiber.fork ~sw (fun () -> echo n ping pong);
    play n ping pong
  in
  Printf.printf "%d\n%d\n" n sum
