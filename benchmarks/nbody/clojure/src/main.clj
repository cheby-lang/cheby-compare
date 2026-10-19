;; n-body: five bodies of the outer solar system under gravity, advanced in fixed steps.
;; Prints the total energy before and after, as round(e * 10^9).
;;
;; Bodies are deftypes with mutable primitive double fields in a vector, the usual Clojure form
;; for numeric code that updates records in place.
(ns main
  (:gen-class))

(set! *warn-on-reflection* true)

(def ^:const solar-mass (* (* 4.0 Math/PI) Math/PI))
(def ^:const days-per-year 365.24)
(def ^:const dt 0.01)

(definterface IBody
  (^double x [])
  (^double y [])
  (^double z [])
  (^double vx [])
  (^double vy [])
  (^double vz [])
  (^double mass [])
  (setVelocity [^double vx ^double vy ^double vz])
  (addVelocity [^double dvx ^double dvy ^double dvz])
  (interact [other] "Applies one pair interaction of advance to this body and other.")
  (move [] "The position update of advance."))

(deftype Body [^:unsynchronized-mutable ^double x
               ^:unsynchronized-mutable ^double y
               ^:unsynchronized-mutable ^double z
               ^:unsynchronized-mutable ^double vx
               ^:unsynchronized-mutable ^double vy
               ^:unsynchronized-mutable ^double vz
               ^double mass]
  IBody
  (x [_] x)
  (y [_] y)
  (z [_] z)
  (vx [_] vx)
  (vy [_] vy)
  (vz [_] vz)
  (mass [_] mass)
  (setVelocity [this nvx nvy nvz]
    (set! vx nvx)
    (set! vy nvy)
    (set! vz nvz)
    this)
  (addVelocity [this dvx dvy dvz]
    (set! vx (+ vx dvx))
    (set! vy (+ vy dvy))
    (set! vz (+ vz dvz))
    this)
  (interact [this other]
    (let [^IBody b other
          dx (- x (.x b))
          dy (- y (.y b))
          dz (- z (.z b))
          d2 (+ (+ (* dx dx) (* dy dy)) (* dz dz))
          mag (/ dt (* d2 (Math/sqrt d2)))
          a-mag (* mass mag)
          b-mag (* (.mass b) mag)]
      (set! vx (- vx (* dx b-mag)))
      (set! vy (- vy (* dy b-mag)))
      (set! vz (- vz (* dz b-mag)))
      (.addVelocity b (* dx a-mag) (* dy a-mag) (* dz a-mag))
      this))
  (move [this]
    (set! x (+ x (* dt vx)))
    (set! y (+ y (* dt vy)))
    (set! z (+ z (* dt vz)))
    this))

(defn planet [[x y z] [vx vy vz] mass]
  (Body. x y z
         (* (double vx) days-per-year) (* (double vy) days-per-year) (* (double vz) days-per-year)
         (* (double mass) solar-mass)))

(defn initial-bodies []
  [(Body. 0.0 0.0 0.0 0.0 0.0 0.0 solar-mass)
   ;; Jupiter
   (planet [4.84143144246472090e+00 -1.16032004402742839e+00 -1.03622044471123109e-01]
           [1.66007664274403694e-03 7.69901118419740425e-03 -6.90460016972063023e-05]
           9.54791938424326609e-04)
   ;; Saturn
   (planet [8.34336671824457987e+00 4.12479856412430479e+00 -4.03523417114321381e-01]
           [-2.76742510726862411e-03 4.99852801234917238e-03 2.30417297573763929e-05]
           2.85885980666130812e-04)
   ;; Uranus
   (planet [1.28943695621391310e+01 -1.51111514016986312e+01 -2.23307578892655734e-01]
           [2.96460137564761618e-03 2.37847173959480950e-03 -2.96589568540237556e-05]
           4.36624404335156298e-05)
   ;; Neptune
   (planet [1.53796971148509165e+01 -2.59193146099879641e+01 1.79258772950371181e-01]
           [2.68067772490389322e-03 1.62824170038242295e-03 -9.51592254519715870e-05]
           5.15138902046611451e-05)])

(defn offset-momentum [bodies]
  (let [[px py pz] (reduce (fn [[^double px ^double py ^double pz] ^IBody b]
                             [(+ px (* (.vx b) (.mass b)))
                              (+ py (* (.vy b) (.mass b)))
                              (+ pz (* (.vz b) (.mass b)))])
                           [0.0 0.0 0.0]
                           bodies)]
    (.setVelocity ^IBody (nth bodies 0)
                  (/ (- (double px)) solar-mass)
                  (/ (- (double py)) solar-mass)
                  (/ (- (double pz)) solar-mass))))

(defn energy ^double [bodies]
  (let [n (count bodies)]
    (loop [i 0, e 0.0]
      (if (< i n)
        (let [^IBody b (nth bodies i)
              e (+ e (* (* 0.5 (.mass b))
                        (+ (+ (* (.vx b) (.vx b)) (* (.vy b) (.vy b))) (* (.vz b) (.vz b)))))
              e (double
                 (loop [j (inc i), e e]
                   (if (< j n)
                     (let [^IBody c (nth bodies j)
                           dx (- (.x b) (.x c))
                           dy (- (.y b) (.y c))
                           dz (- (.z b) (.z c))]
                       (recur (inc j)
                              (- e (/ (* (.mass b) (.mass c))
                                      (Math/sqrt (+ (+ (* dx dx) (* dy dy)) (* dz dz)))))))
                     e)))]
          (recur (inc i) e))
        e))))

(defn advance [bodies]
  (let [n (count bodies)]
    (dotimes [i n]
      (let [^IBody a (nth bodies i)]
        (loop [j (inc i)]
          (when (< j n)
            (.interact a (nth bodies j))
            (recur (inc j))))))
    (doseq [^IBody b bodies]
      (.move b))))

(defn scaled
  "round(e * 1e9), halves away from zero."
  ^long [^double e]
  (let [x (* e 1.0e9)]
    (if (neg? x) (- (Math/round (- x))) (Math/round x))))

(defn -main [& args]
  (let [steps (Long/parseLong (first args))
        bodies (initial-bodies)]
    (offset-momentum bodies)
    (println (scaled (energy bodies)))
    (dotimes [_ steps]
      (advance bodies))
    (println (scaled (energy bodies)))))
