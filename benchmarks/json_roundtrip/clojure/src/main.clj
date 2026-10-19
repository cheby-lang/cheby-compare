;; json_roundtrip: parses a JSON array of records, transforms it and serializes it again.
(ns main
  (:require [clojure.data.json :as json])
  (:import (java.nio.charset StandardCharsets))
  (:gen-class))

(set! *warn-on-reflection* true)

(def ^:const fnv-offset 2166136261)
(def ^:const fnv-prime 16777619)

(defn- fnv1a
  "FNV-1a 32-bit over `data`, starting from `h`."
  ^long [^long h ^bytes data]
  (areduce data i h h
           (bit-and (* (bit-xor h (bit-and (aget data i) 0xff)) fnv-prime) 0xffffffff)))

(defn- transform
  "The output record for a kept record: `active` dropped, `score` changed, `total` added."
  [r total]
  (array-map :id (:id r)
             :name (:name r)
             :score (+ (:score r) (* 100 (count (:tags r))))
             :tags (:tags r)
             :address (:address r)
             :history (:history r)
             :total total))

(defn- step
  "Adds record `r` to the counters and, when it is active, its output record to `kept`."
  [[stats kept] r]
  (let [total (reduce + 0 (map :amount (:history r)))
        stats (-> stats
                  (update :records inc)
                  (update :score-sum + (:score r))
                  (update :tags + (count (:tags r)))
                  (update :history + (count (:history r)))
                  (update :amount-sum + total))]
    (if (:active r)
      [(update stats :active inc) (conj! kept (transform r total))]
      [stats kept])))

(defn- round-trip
  "One repetition: parse, aggregate and serialize. Returns the counters and the output bytes."
  [stats ^String text]
  (let [records (json/read-str text :key-fn keyword)
        [stats kept] (reduce step [stats (transient [])] records)
        out ^String (json/write-str (persistent! kept))]
    [stats (.getBytes out StandardCharsets/UTF_8)]))

(defn -main [path reps-arg & _]
  (let [text (slurp path)
        reps (Long/parseLong reps-arg)
        zero {:records 0 :active 0 :score-sum 0 :tags 0
              :history 0 :amount-sum 0 :output-bytes 0}
        [stats h] (reduce (fn [[stats h] rep]
                            (let [[stats ^bytes out] (round-trip stats text)
                                  stats (update stats :output-bytes + (alength out))]
                              [stats (if (= rep (dec reps)) (fnv1a fnv-offset out) h)]))
                          [zero fnv-offset]
                          (range reps))]
    (println "records" (:records stats))
    (println "active" (:active stats))
    (println "score_sum" (:score-sum stats))
    (println "tags" (:tags stats))
    (println "history" (:history stats))
    (println "amount_sum" (:amount-sum stats))
    (println "output_bytes" (:output-bytes stats))
    (println "output_fnv1a" h)))
