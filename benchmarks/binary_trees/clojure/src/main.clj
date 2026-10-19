;; Binary-trees: allocates and walks many short-lived perfect binary trees.
;;
;; The first argument is the maximum depth n. The program checks a stretch tree of depth n + 1,
;; keeps a long-lived tree of depth n, and then builds and checks 2^(n - d + 4) trees of each
;; depth d = 4, 6, ..., n. A tree's check is its number of nodes.
(ns main
  (:gen-class))

(set! *warn-on-reflection* true)

(def ^:const min-depth 4)

;; A tree node with no payload; nil children are absent.
(deftype Node [left right])

(defn make
  "A perfect binary tree of depth d, which has 2^(d + 1) - 1 nodes."
  [^long d]
  (if (zero? d)
    (Node. nil nil)
    (Node. (make (dec d)) (make (dec d)))))

(defn check
  "The number of nodes of the tree, by walking it."
  ^long [^Node t]
  (+ 1
     (if-some [l (.-left t)] (check l) 0)
     (if-some [r (.-right t)] (check r) 0)))

(defn -main [& args]
  (let [n (Long/parseLong (first args))
        stretch-depth (inc n)]
    (println (str "stretch tree of depth " stretch-depth "\t check: " (check (make stretch-depth))))
    (let [long-lived (make n)]
      (loop [d min-depth]
        (when (<= d n)
          (let [iterations (bit-shift-left 1 (+ (- n d) min-depth))
                total (loop [i 0, total 0]
                        (if (< i iterations)
                          (recur (inc i) (+ total (check (make d))))
                          total))]
            (println (str iterations "\t trees of depth " d "\t check: " total))
            (recur (+ d 2)))))
      (println (str "long lived tree of depth " n "\t check: " (check long-lived))))))
