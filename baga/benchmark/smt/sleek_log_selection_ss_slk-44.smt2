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




















































(declare-fun x () __Exc)
(declare-fun xprm () __Exc)
(declare-fun mi11 () NUM)
(declare-fun l5 () NUM)
(declare-fun s5 () NUM)
(declare-fun n5 () Int)
(declare-fun minimumprm () NUM)
(declare-fun mi10 () NUM)
(declare-fun mi () NUM)
(declare-fun l () NUM)
(declare-fun lg () NUM)
(declare-fun s () NUM)
(declare-fun sm () NUM)
(declare-fun n4 () Int)
(declare-fun n () Int)
(declare-fun tmp1prm () __Exc)


(assert 
(and 
;lexvar(distinct x nil)
(< mi11 l5)
(<= s5 mi11)
(<= 1 n5)
(= n5 1)
(= xprm nil)
(< mi10 l)
(<= s mi10)
(<= 1 n4)
(= mi11 mi10)
(= l5 l)
(= s5 s)
(= n5 n4)
(= minimumprm mi10)
(< mi lg)
(<= sm mi)
(<= 1 n)
(= mi10 mi)
(= l lg)
(= s sm)
(= n4 n)
(= tmp1prm nil)

)
)

(assert (not 
(and 
(tobool  
(htrue )
 )
)
))

(check-sat)