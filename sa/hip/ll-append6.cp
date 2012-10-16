HeapPred HP_1(node a).
HeapPred HP_2(node a, node b).

append[
ass [H1,G2]:{ 	HP1(a,x) * x::node<_,y>&a=null & y=null -> G2(x,y),
			H1(x) -> x::node<_,b> * HP1(b,x),
			HP1(a,x)&a!=null -> H1(a),
			x::node<_,b> * G2(b,y)&b!=null & y=null -> G2(x,y) }

hpdefs [H1,G2]:{H1(x) -> x::node<_,p>*HP_1(p),
   HP_1(x) -> x=null or x::node<_,p1> * HP_1(p1),
   G2(x,y) -> x::node<_,p> *y::node<_,null> * HP_2(p,y),
   HP_2(x,p) -> x=p or x::node<_,p1> * HP_2(p1,p) * p::node<_,null>
 }
]
