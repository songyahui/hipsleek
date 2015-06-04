(set-logic QF_S)
(set-info :source |  Sleek solver
  http://loris-7.ddns.comp.nus.edu.sg/~project/s2/beta/
|)

(set-info :smt-lib-version 2.0)
(set-info :category "crafted")
(set-info :status unsat)


(declare-sort node 0)
(declare-fun val () (Field node Int))
(declare-fun next () (Field node node))

(define-fun sll ((?in node) (?n Int) (?sm Int) (?lg Int))
Space (tospace
(or
(exists ((?sm_26 Int)(?flted_12_24 node))(and 
(= ?flted_12_24 nil)
(= ?sm ?lg)
(= ?n 1)
(= ?sm_26 ?sm)
(tobool  
(pto ?in (sref (ref val ?sm_26) (ref next ?flted_12_24) ))
 )
))(exists ((?sm_27 Int)(?lg_28 Int)(?flted_13_25 Int))(and 
(= (+ ?flted_13_25 1) ?n)
(distinct ?q nil)
(<= ?sm ?qs)
(= ?sm_27 ?sm)
(= ?lg_28 ?lg)
(tobool (ssep 
(pto ?in (sref (ref val ?sm_27) (ref next ?q) ))
(sll ?q ?flted_13_25 ?qs ?lg_28)
) )
)))))

(define-fun bnd1 ((?in node) (?n Int) (?sm NUM) (?bg Int) (?mi NUM))
Space (tospace
(or
(exists ((?mi_33 Int)(?flted_8_31 node))(and 
(= ?flted_8_31 nil)
(<= ?sm ?mi)
(< ?mi ?bg)
(= ?n 1)
(= ?mi_33 ?mi)
(tobool  
(pto ?in (sref (ref val ?mi_33) (ref next ?flted_8_31) ))
 )
))(exists ((?sm_34 Int)(?bg_35 Int)(?flted_9_32 Int))(and 
(= (+ ?flted_9_32 1) ?n)
(<= ?sm ?d)
(< ?d ?bg)
;eqmin(<= ?sm ?mi)
(< ?mi ?bg)
(= ?sm_34 ?sm)
(= ?bg_35 ?bg)
(tobool (ssep 
(pto ?in (sref (ref val ?d) (ref next ?p) ))
(bnd1 ?p ?flted_9_32 ?sm_34 ?bg_35 ?tmi)
) )
)))))




















































(declare-fun v10prm () node)
(declare-fun tmp1_2230 () node)
(declare-fun n4 () Int)
(declare-fun s () Int)
(declare-fun mi10 () Int)
(declare-fun l () Int)
(declare-fun n5 () Int)
(declare-fun s5 () Int)
(declare-fun mi11 () Int)
(declare-fun l5 () Int)
(declare-fun res () node)
(declare-fun xprm () node)
(declare-fun x () node)
(declare-fun lg () Int)
(declare-fun sm () Int)
(declare-fun mi () Int)
(declare-fun n () Int)


(assert 
(exists ((tmp1prm node))(and 
;lexvar(= res v10prm)
(= tmp1prm nil)
(= n4 n)
(= s sm)
(= l lg)
(= mi10 mi)
(<= 1 n)
(<= sm mi)
(< mi lg)
(= n5 n4)
(= s5 s)
(= l5 l)
(= mi11 mi10)
(<= 1 n4)
(<= s mi10)
(< mi10 l)
(= n5 1)
(<= 1 n5)
(<= s5 mi11)
(< mi11 l5)
(distinct x nil)
(= xprm nil)
(tobool  
(pto v10prm (sref (ref val mi10) (ref next tmp1prm) ))
 )
))
)

(assert (not 
(exists ((n7 Int)(mi15 Int)(l6 Int))(and 
(= mi15 mi)
(= n7 n)
(= xprm nil)
(< l6 lg)
(distinct x nil)
(< mi lg)
(<= sm mi)
(<= 1 n)
(tobool  
(sll res n7 mi15 l6)
 )
))
))

(check-sat)