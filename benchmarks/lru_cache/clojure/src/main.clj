;; lru_cache: a capacity-bounded LRU cache under a skewed pseudo-random key stream.
;;
;; Shape C of the SPEC: `entries` is a hash map from key to [value tick], `by-tick` a sorted map
;; from each live tick to its key, so its first entry is the least recently used key.
(ns main
  (:gen-class))

(set! *warn-on-reflection* true)

(def ^:const modulus 1000000007)
(def ^:const lehmer-m 2147483647)
(def ^:const lehmer-a 48271)
(def ^:const seed 42)
(def ^:const hot-percent 80)

(defn- pick-key
  "The key for generator state `state`: hot (0 .. hot-1) or cold (hot .. 16*hot-1)."
  ^long [^long state ^long hot ^long cold]
  (let [draw (quot state 100)]
    (if (< (rem state 100) hot-percent)
      (rem draw hot)
      (+ hot (rem draw cold)))))

(defn- checksum
  "Sum of position * key over the cache from least to most recently used, mod MODULUS."
  ^long [by-tick]
  (loop [ks (vals by-tick), position 1, sum 0]
    (if-let [s (seq ks)]
      (recur (rest s) (inc position) (rem (+ sum (* position (long (first s)))) modulus))
      sum)))

(defn -main [capacity-arg ops-arg & _]
  (let [capacity (Long/parseLong capacity-arg)
        ops (Long/parseLong ops-arg)
        hot capacity
        cold (* capacity 15)]
    (loop [i 0, state seed, clock 0
           entries {}, by-tick (sorted-map)
           hits 0, misses 0, values 0]
      (if (< i ops)
        (let [state (rem (* state lehmer-a) lehmer-m)
              key (pick-key state hot cold)]
          (if-let [[value old] (get entries key)]
            ;; A hit: the key takes the newest tick.
            (recur (inc i) state (inc clock)
                   (assoc entries key [value clock])
                   (-> by-tick (dissoc old) (assoc clock key))
                   (inc hits) misses (rem (+ values (long value)) modulus))
            ;; A miss: evict the oldest tick when full, then insert.
            (let [[entries by-tick] (if (= (count entries) capacity)
                                      (let [[t k] (first by-tick)]
                                        [(dissoc entries k) (dissoc by-tick t)])
                                      [entries by-tick])]
              (recur (inc i) state (inc clock)
                     (assoc entries key [(inc (* key 2)) clock])
                     (assoc by-tick clock key)
                     hits (inc misses) values))))
        (do
          (println "hits" hits)
          (println "misses" misses)
          (println "values" values)
          (println "checksum" (checksum by-tick)))))))
