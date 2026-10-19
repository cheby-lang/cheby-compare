;; Mandelbrot set on an N x N grid: count the points inside, sum iterations, checksum.
(ns main
  (:gen-class))

(set! *warn-on-reflection* true)

(def ^:const max-iter 50)

(defn escape-time
  "The number of iterations before the point (cr, ci) escapes, or max-iter."
  ^long [^double cr ^double ci]
  (loop [zr 0.0, zi 0.0, i 0]
    (if (< i max-iter)
      (let [zr2 (* zr zr)
            zi2 (* zi zi)]
        (if (> (+ zr2 zi2) 4.0)
          i
          ;; recur evaluates both updates with the old zr and zi
          (recur (+ (- zr2 zi2) cr)
                 (+ (* (* 2.0 zr) zi) ci)
                 (inc i))))
      i)))

(defn -main [& args]
  (let [n (Long/parseLong (first args))
        nf (double n)]
    (loop [y 0, inside 0, iterations 0, checksum 0]
      (if (< y n)
        (let [ci (- (/ (* 2.0 (double y)) nf) 1.0)
              [inside iterations checksum]
              (loop [x 0, inside inside, iterations iterations, checksum checksum]
                (if (< x n)
                  (let [cr (- (/ (* 2.0 (double x)) nf) 1.5)
                        i (escape-time cr ci)]
                    (if (== i max-iter)
                      (recur (inc x) (inc inside) (+ iterations i) (+ checksum (+ (* y n) x)))
                      (recur (inc x) inside (+ iterations i) checksum)))
                  [inside iterations checksum]))]
          (recur (inc y) (long inside) (long iterations) (long checksum)))
        (do
          (println (str "inside " inside))
          (println (str "iterations " iterations))
          (println (str "checksum " (mod checksum 4294967296))))))))
