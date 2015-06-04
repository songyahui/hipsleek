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




















































(declare-fun mi3 () NUM)
(declare-fun l1 () NUM)
(declare-fun s1 () NUM)
(declare-fun n1 () Int)
(declare-fun xnextprm () __Exc)
(declare-fun p1 () __Exc)
(declare-fun Anonprm () NUM)
(declare-fun flted3 () Int)
(declare-fun tmi1 () NUM)
(declare-fun sm2 () NUM)
(declare-fun s () NUM)
(declare-fun bg2 () NUM)
(declare-fun l () NUM)
(declare-fun xprm () __Exc)
(declare-fun x () __Exc)
(declare-fun n () Int)
(declare-fun a () NUM)
(declare-fun mi () NUM)
(declare-fun d1 () NUM)
(declare-fun aprm () NUM)


(assert 
(and 
;lexvar(= mi3 tmi1)
(= l1 bg2)
(= s1 sm2)
(= n1 flted3)
(= xnextprm p1)
(= Anonprm d1)
(= (+ flted3 1) n)
(<= s d1)
(< d1 l)
;eqmin(<= s mi)
(< mi l)
(= sm2 s)
(= bg2 l)
(= xprm x)
(= aprm a)
(<= 1 n)
(= a mi)
(distinct d1 aprm)

)
)

(assert (not 
;lexvar
))

(check-sat)