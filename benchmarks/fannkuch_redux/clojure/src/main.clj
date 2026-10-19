;; Fannkuch-redux: flips over every permutation of 0..n, in the order the counting algorithm
;; generates them. Prints the alternating checksum and the maximum flip count.
;;
;; perm1 and count are persistent vectors, updated by index with nth and assoc.
(ns main
  (:gen-class))

(set! *warn-on-reflection* true)

(defn flip
  "perm with its first k + 1 elements reversed."
  [perm ^long k]
  (loop [p perm, i 0, j k]
    (if (< i j)
      (recur (assoc p i (nth p j) j (nth p i)) (inc i) (dec j))
      p)))

(defn count-flips
  "The number of flips that bring 0 to the front of perm."
  ^long [perm]
  (loop [p perm, flips 0]
    (let [k (long (nth p 0))]
      (if (zero? k)
        flips
        (recur (flip p k) (inc flips))))))

(defn rotate
  "perm with its first r + 1 elements rotated left by one."
  [perm ^long r]
  (let [first (nth perm 0)]
    (loop [p perm, i 0]
      (if (< i r)
        (recur (assoc p i (nth p (inc i))) (inc i))
        (assoc p r first)))))

(defn next-perm
  "Step 3: advances perm1 to the next permutation. Returns [perm1 count r], or nil after the
  last permutation."
  [perm1 cnt ^long r ^long n]
  (loop [perm1 perm1, cnt cnt, r r]
    (when (< r n)
      (let [perm1 (rotate perm1 r)
            c (dec (long (nth cnt r)))
            cnt (assoc cnt r c)]
        (if (pos? c)
          [perm1 cnt r]
          (recur perm1 cnt (inc r)))))))

(defn fannkuch
  "[checksum max-flips] over all permutations of 0..n, n >= 1."
  [^long n]
  (loop [perm1 (vec (range n)), cnt (vec (repeat n 0)), r n
         max-flips 0, checksum 0, perm-index 0]
    ;; 1. Reset the counters below r; the loop leaves r at 1.
    (let [[cnt r] (loop [cnt cnt, r r]
                    (if (not= r 1)
                      (recur (assoc cnt (dec r) r) (dec r))
                      [cnt r]))
          ;; 2. Count the flips; perm1 is immutable, so it is its own copy.
          flips (count-flips perm1)
          max-flips (max max-flips flips)
          checksum (if (even? perm-index) (+ checksum flips) (- checksum flips))]
      ;; 3. Advance perm1.
      (if-some [[perm1 cnt r] (next-perm perm1 cnt r n)]
        (recur perm1 cnt (long r) max-flips checksum (inc perm-index))
        [checksum max-flips]))))

(defn -main [& args]
  (let [n (Long/parseLong (first args))
        [checksum max-flips] (fannkuch (max n 1))]
    (println checksum)
    (println (str "Pfannkuchen(" n ") = " max-flips))))
