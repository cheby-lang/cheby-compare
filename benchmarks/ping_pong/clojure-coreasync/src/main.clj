;; ping_pong: two go blocks exchange `n` messages over two unbuffered core.async channels.
(ns main
  (:gen-class)
  (:require [clojure.core.async :refer [<! <!! >! chan go]]))

(set! *warn-on-reflection* true)

(defn- echo
  "Task B: answers each of the `n` values from `ping` with the value plus one on `pong`.
  Returns the go block's result channel, which closes when B is done."
  [^long n ping pong]
  (go
    (dotimes [_ n]
      (>! pong (inc (long (<! ping)))))))

(defn- play
  "Task A: sends 1..n on `ping` and adds up the answers from `pong`. Returns the go block's
  result channel, which yields the sum."
  [^long n ping pong]
  (go
    (loop [i 1 sum 0]
      (if (> i (long n))
        sum
        (do (>! ping i)
            (recur (inc i) (+ sum (long (<! pong)))))))))

(defn -main [& args]
  (let [n (Long/parseLong (first args))
        ping (chan)
        pong (chan)
        ;; The JVM main thread is not a go block, so A runs in a go block like B; main only waits
        ;; for their result channels.
        b (echo n ping pong)
        a (play n ping pong)
        sum (<!! a)]
    (<!! b)
    (println n)
    (println sum)))
