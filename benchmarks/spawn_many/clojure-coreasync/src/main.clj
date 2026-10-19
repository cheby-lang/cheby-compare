;; spawn_many: spawn `n` short go blocks in batches of 1000, join each batch through the go
;; blocks' result channels and print the sum.
(ns main
  (:gen-class)
  (:require [clojure.core.async :refer [<!! go]]))

(set! *warn-on-reflection* true)

(def ^:const batch 1000)
(def ^:const rounds 10)
(def ^:const modulus 2147483647) ; 2^31 - 1
(def ^:const multiplier 48271)   ; the MINSTD generator

(defn- work
  "The value of the task with this index: `rounds` steps of MINSTD from index + 1."
  ^long [^long index]
  (loop [r 0 x (inc index)]
    (if (< r rounds)
      (recur (inc r) (rem (* x multiplier) modulus))
      x)))

(defn- spawn-and-join
  "Starts one go block per index in start..start+cnt-1, takes each one's result and returns
  their sum."
  ^long [^long start ^long cnt]
  ;; mapv, not lazy map: every go block of the batch starts before the first take.
  (let [tasks (mapv (fn [i] (go (work i))) (range start (+ start cnt)))]
    (reduce (fn [^long sum task] (+ sum (long (<!! task)))) 0 tasks)))

(defn -main [& args]
  (let [n (Long/parseLong (first args))
        sum (loop [start 0 sum 0]
              (if (< start n)
                (recur (+ start batch) (+ sum (spawn-and-join start (min batch (- n start)))))
                sum))]
    (println (str "tasks: " n))
    (println (str "sum: " sum))))
