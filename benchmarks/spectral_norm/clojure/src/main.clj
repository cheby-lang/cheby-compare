;; Spectral norm: the benchmarks-game power method on the matrix
;; A(i, j) = 1 / ((i + j)(i + j + 1) / 2 + i + 1), cut to n by n.
;;
;; Vectors are persistent vectors: each product walks its input with reduce-kv and builds a new
;; vector with mapv.
(ns main
  (:gen-class))

(set! *warn-on-reflection* true)

(defn entry
  "The entry A(i, j) of the matrix."
  ^double [^long i ^long j]
  (/ 1.0 (double (+ (quot (* (+ i j) (+ i j 1)) 2) i 1))))

(defn times-a
  "A times x."
  [x]
  (mapv (fn [^long i]
          (reduce-kv (fn [^double s ^long j ^double xj] (+ s (* (entry i j) xj))) 0.0 x))
        (range (count x))))

(defn times-at
  "A transposed times x."
  [x]
  (mapv (fn [^long i]
          (reduce-kv (fn [^double s ^long j ^double xj] (+ s (* (entry j i) xj))) 0.0 x))
        (range (count x))))

(defn times-ata [x]
  (times-at (times-a x)))

(defn -main [& args]
  (let [n (Long/parseLong (first args))
        [u v] (loop [round 0, u (vec (repeat n 1.0)), v []]
                (if (< round 10)
                  (let [v (times-ata u)]
                    (recur (inc round) (times-ata v) v))
                  [u v]))
        [vbv vv] (loop [i 0, vbv 0.0, vv 0.0]
                   (if (< i n)
                     (let [ui (double (nth u i))
                           vi (double (nth v i))]
                       (recur (inc i) (+ vbv (* ui vi)) (+ vv (* vi vi))))
                     [vbv vv]))
        vv (double vv)]
    (println (if (== vv 0.0)
               0
               (let [x (* (Math/sqrt (/ (double vbv) vv)) 1.0e9)]
                 (if (neg? x) (- (Math/round (- x))) (Math/round x)))))))
