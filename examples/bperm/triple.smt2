;DELARE INTEGER TRIPLE
(declare-datatypes () ((int-triple (mk-triple (first Int) (second Int) (third Int)))))

;DELARE TRIPLE VARIABLE
(declare-fun p1 () int-triple)
(declare-fun p2 () int-triple)

(assert (= 1 1))
;SAT
(check-sat)

; TRIPLE ASSIGNMENT
(assert (= p1 (mk-triple 2 2 2)))
(assert (= p2 (mk-triple 1 2 3)))
;(assert (= p1 p2))
;UNSAT
;(check-sat)

; TRIPLE's COMPONENT-WISE OPERATION
;(assert (= (first p1) (first p2)))
;UNSAT
;(check-sat)

;(assert (= (second p1) (second p2)))
;SAT
;(check-sat)

;(assert (= (third p1) (third p2)))
;UNSAT
;(check-sat)

(declare-fun x () Int)
(assert (= x 3))
;(assert (> (third p1) x))
;SAT
;(check-sat)

(declare-fun y () Int)
(assert (= y 2))

(declare-fun z () Int)
(assert (= z 1))
(declare-fun p3 () int-triple)
(declare-fun p4 () int-triple)

;TRIPLE of VARIABLES
(assert (= p3 (mk-triple z y x)))
(assert (= p3 p4))
(assert (= p3 p2))
;SAT
(check-sat)

(declare-fun p5 () int-triple)
(declare-fun p6 () int-triple)
(declare-fun x11 () Int)
(declare-fun x12 () Int)
(declare-fun x13 () Int)
(declare-fun x21 () Int)
(declare-fun x22 () Int)
(declare-fun x23 () Int)
(assert (= p5 (mk-triple x11 x12 x13)))
(assert (= p6 (mk-triple x21 x22 x23)))
(assert (= p5 p6))
(assert (not (= x11 x21)))
;UNSAT
(check-sat)
