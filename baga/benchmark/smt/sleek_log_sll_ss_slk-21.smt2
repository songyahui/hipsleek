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

(define-fun sll ((?in node) (?n Int) (?sm NUM) (?lg Int))
Space (tospace
(or
(and 
(= ?in nil)
(= ?n 0)
(<= ?sm ?lg)

)(exists ((?flted_16_26 Int)(?qs_27 Int)(?ql_28 Int))(and 
(= (+ ?flted_16_26 1) ?n)
(<= ?qmin ?qs_27)
(<= ?ql_28 ?lg)
(<= ?sm ?qmin)
(tobool (ssep 
(pto ?in (sref (ref val ?qmin) (ref next ?q) ))
(sll ?q ?flted_16_26 ?qs_27 ?ql_28)
) )
)))))

(define-fun ll ((?in node) (?n Int))
Space (tospace
(or
(and 
(= ?in nil)
(= ?n 0)

)(exists ((?flted_11_30 Int))(and 
(= (+ ?flted_11_30 1) ?n)
(tobool (ssep 
(pto ?in (sref (ref val ?Anon_12) (ref next ?q) ))
(ll ?q ?flted_11_30)
) )
)))))










































































(declare-fun v7prm () node)
(declare-fun q1 () node)
(declare-fun x () node)
(declare-fun v () Int)
(declare-fun xprm () node)
(declare-fun ql1 () Int)
(declare-fun qs1 () Int)
(declare-fun flted1 () Int)
(declare-fun qmin1 () Int)
(declare-fun vprm () Int)
(declare-fun res () node)
(declare-fun xs () Int)
(declare-fun xl () Int)
(declare-fun n () Int)


(assert 
(and 
;lexvar(= res v7prm)
(= v7prm q1)
(= vprm qmin1)
(= xprm x)
(= vprm v)
(distinct xprm nil)
(<= xs qmin1)
(<= ql1 xl)
(<= qmin1 qs1)
(= (+ flted1 1) n)
(<= qmin1 vprm)
(tobool (ssep 
(pto xprm (sref (ref val qmin1) (ref next q1) ))
(sll q1 flted1 qs1 ql1)
) )
)
)

(assert (not 
(exists ((sres1 Int)(lres1 Int)(nres1 Int))(and 
(<= nres1 n)
(<= n (+ nres1 1))
(<= lres1 xl)
(<= xs sres1)
(<= xs xl)
(<= 0 n)
(tobool  
(sll res nres1 sres1 lres1)
 )
))
))

(check-sat)