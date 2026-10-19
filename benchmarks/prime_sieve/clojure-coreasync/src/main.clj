;; prime_sieve: the concurrent prime sieve, one go block per stage, connected by unbuffered
;; core.async channels. Prints n, the n-th prime and the sum of the first n primes.
(ns main
  (:gen-class)
  (:require [clojure.core.async :refer [<! <!! >! chan go-loop]]))

(set! *warn-on-reflection* true)

(defn- generate
  "Sends 2, 3, 4 and so on to `out`, forever."
  [out]
  (go-loop [i 2]
    (>! out i)
    (recur (inc i))))

(defn- sieve-filter
  "Passes on the numbers from `in` that `prime` does not divide, forever."
  [in out prime]
  (go-loop []
    (let [m (long (<! in))]
      (when-not (zero? (rem m (long prime)))
        (>! out m))
      (recur))))

(defn -main [& args]
  (let [n (Long/parseLong (first args))
        first-ch (chan)]
    (generate first-ch)
    (loop [k 0 ch first-ch last-prime 0 sum 0]
      (if (< k n)
        (let [prime (long (<!! ch))
              next-ch (chan)]
          (sieve-filter ch next-ch prime)
          (recur (inc k) next-ch prime (+ sum prime)))
        ;; core.async's go-block threads are daemon threads: returning from -main ends the JVM
        ;; with every stage still parked (SPEC, "Shut down", option 1).
        (do (println (str "primes: " n))
            (println (str "last: " last-prime))
            (println (str "sum: " sum)))))))
