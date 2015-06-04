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




















































(declare-fun v7prm () Int)
(declare-fun mi7 () Int)
(declare-fun xprm () node)
(declare-fun flted8 () node)
(declare-fun res () Int)
(declare-fun x () node)
(declare-fun l () NUM)
(declare-fun s () NUM)
(declare-fun mi () NUM)
(declare-fun n () Int)


(assert 
(and 
;lexvar(= res v7prm)
(= v7prm mi7)
(<= s mi)
(< mi l)
(= n 1)
(= mi7 mi)
(= xprm x)
(< 0 n)
(= flted8 nil)
(tobool  
(pto xprm (sref (ref val mi7) (ref next flted8) ))
 )
)
)

(assert (not 
(exists ((n3 Int)(s4 Int)(l4 Int)(mi9 Int))(and 
(= mi9 mi)
(= l4 l)
(= s4 s)
(= n3 n)
(= res mi)
(distinct x nil)
(< mi l)
(<= s mi)
(<= 1 n)
(tobool  
(bnd1 x n3 s4 l4 mi9)
 )
))
))

(check-sat)