;; ping_pong: two virtual threads exchange `n` messages over two rendezvous channels.
(ns main
  (:gen-class)
  (:import (java.util.concurrent SynchronousQueue)))

(set! *warn-on-reflection* true)

(defn- echo
  "Task B: answers each of the `n` values from `ping` with the value plus one on `pong`."
  [^long n ^SynchronousQueue ping ^SynchronousQueue pong]
  (dotimes [_ n]
    (let [x (long (.take ping))]
      (.put pong (inc x)))))

(defn- play
  "Task A: sends 1..n on `ping` and adds up the answers from `pong`."
  ^long [^long n ^SynchronousQueue ping ^SynchronousQueue pong]
  (loop [i 1 sum 0]
    (if (> i n)
      sum
      (do (.put ping i)
          (recur (inc i) (+ sum (long (.take pong))))))))

(defn- start-virtual
  "Starts `f` on a new virtual thread."
  ^Thread [f]
  (.start (Thread/ofVirtual) ^Runnable f))

(defn -main [& args]
  (let [n (Long/parseLong (first args))
        ping (SynchronousQueue.)
        pong (SynchronousQueue.)
        ;; The JVM main thread is a platform thread, so A runs on a virtual thread like B.
        b (start-virtual #(echo n ping pong))
        result (promise)
        a (start-virtual #(deliver result (play n ping pong)))]
    (.join a)
    (let [sum @result]
      (.join b)
      (println n)
      (println sum))))
