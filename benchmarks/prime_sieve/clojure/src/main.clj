;; prime_sieve: the concurrent prime sieve, one virtual thread per stage, connected by rendezvous
;; channels. Prints n, the n-th prime and the sum of the first n primes.
(ns main
  (:gen-class)
  (:import (java.util.concurrent SynchronousQueue)))

(set! *warn-on-reflection* true)

(defn- generate
  "Sends 2, 3, 4 and so on to `out`, forever."
  [^SynchronousQueue out]
  (loop [i 2]
    (.put out i)
    (recur (inc i))))

(defn- sieve-filter
  "Passes on the numbers from `in` that `prime` does not divide, forever."
  [^SynchronousQueue in ^SynchronousQueue out ^long prime]
  (loop []
    (let [m (long (.take in))]
      (when-not (zero? (rem m prime))
        (.put out m))
      (recur))))

(defn- start-virtual
  "Starts `f` on a new virtual thread."
  ^Thread [f]
  (.start (Thread/ofVirtual) ^Runnable f))

(defn -main [& args]
  (let [n (Long/parseLong (first args))
        first-ch (SynchronousQueue.)]
    (start-virtual #(generate first-ch))
    (loop [k 0 ^SynchronousQueue ch first-ch last-prime 0 sum 0]
      (if (< k n)
        (let [prime (long (.take ch))
              next-ch (SynchronousQueue.)]
          (start-virtual #(sieve-filter ch next-ch prime))
          (recur (inc k) next-ch prime (+ sum prime)))
        ;; Virtual threads are daemon threads: returning from -main ends the JVM with every stage
        ;; still blocked (SPEC, "Shut down", option 1).
        (do (println (str "primes: " n))
            (println (str "last: " last-prime))
            (println (str "sum: " sum)))))))
