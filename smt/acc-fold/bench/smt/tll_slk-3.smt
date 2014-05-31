(set-logic QF_S)

(declare-sort node 0)
(declare-fun parent () (Field node node))
(declare-fun left () (Field node node))
(declare-fun right () (Field node node))
(declare-fun next () (Field node node))

(define-fun tree ((?in node))
Space (tospace
(or
(exists ((?flted_11_35 node)) (tobool (pto ?in (sref (ref parent ?Anon_14) (ref left ?D1) (ref right ?flted_11_35) (ref next ?Anon_15) ))))
(and 
(distinct ?r nil)
(tobool (ssep 
(pto ?in (sref (ref parent ?Anon_16) (ref left ?l) (ref right ?r) (ref next ?D2) ))
(tree ?l)
(tree ?r)
) )
))))

(define-fun tll ((?in node) (?p node) (?ll node) (?lr node))
Space (tospace
(or
(exists ((?p_26 node)(?lr_27 node)(?flted_16_25 node)) (tobool (pto ?in (sref (ref parent ?p_26) (ref left ?D1) (ref right ?flted_16_25) (ref next ?lr_27) ))))
(exists ((?p_28 node)(?self_29 node)(?ll_30 node)(?self_31 node)(?z_32 node)(?lr_33 node)) (tobool (ssep (ssep (pto ?in (sref (ref parent ?p_28) (ref left ?l) (ref right ?r) (ref next ?D2) )) (tll ?l ?self_29 ?ll_30 ?z)) (tll ?r ?self_31 ?z_32 ?lr_33))))
)))











(declare-fun xprm () node)
(declare-fun pprm () node)
(declare-fun D1_1127 () node)
(declare-fun Anon_1128 () node)
(declare-fun flted_11_1125 () node)


(assert 
(and 
(= flted_11_1125 nil)
(tobool (ssep 
(pto xprm (sref (ref parent pprm) (ref left D1_1127) (ref right flted_11_1125) (ref next Anon_1128) ))
emp
) )
)
)

(assert (not 
(and 
(tobool (ssep 
(pto xprm (sref (ref parent parent_28_1069prm) (ref left left_28_1070prm) (ref right right_28_1071prm) (ref next next_28_1072prm) ))
emp
) )
)
))

(check-sat)