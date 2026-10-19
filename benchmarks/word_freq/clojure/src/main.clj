;; word_freq: counts the words of a file and prints the 20 most frequent.
(ns main
  (:require [clojure.string :as str])
  (:gen-class))

(set! *warn-on-reflection* true)

(def ^:const top 20)

(defn- words
  "The words of `text`: maximal runs of non-space, non-newline characters."
  [^String text]
  (let [parts (str/split text #"\s+")]
    ;; split keeps a leading empty part (and gives [""] for an empty text).
    (if (= "" (first parts)) (rest parts) parts)))

(defn- by-frequency
  "Orders [word count] entries by count descending, then by word (ordinal)."
  [[w1 c1] [w2 c2]]
  (let [c (compare c2 c1)]
    (if (zero? c) (compare w1 w2) c)))

(defn -main [path & _]
  (let [counts (frequencies (words (slurp path)))
        ranked (sort by-frequency counts)
        total (reduce + 0 (vals counts))]
    (println "total" total)
    (println "distinct" (count counts))
    (doseq [[word n] (take top ranked)]
      (println n word))))
