HeapPred HP_1(node a).
HeapPred HP_1a(node a).
HeapPred HP_2(node a, node b).

append[
ass [H1,G2]:{ 
  x::node<val_37_596,v_node_37_611> * G2(v_node_37_611,y) * 
    y::node<a,flted_34_587>&flted_34_587=null & v_node_37_611!=null --> G2(x,y)&true;
 y::node<a,flted_34_587> * HP_1a(v_node_37_605) * 
  x::node<val_37_594,y>&flted_34_587=null & v_node_37_605=null --> G2(x,y);
 HP_1a(v_node_37_611)& v_node_37_611!=null --> H1(v_node_37_611);
 H1(x) --> x::node<_, p> * HP_1a(p)}

hpdefs [H1,G2]:{H1(x) --> x::node<_,p>*HP_1(p);
   HP_1(x) --> x=null or x::node<_,p1> * HP_1(p1);
   G2(x,y) --> x::node<_,p> *y::node<_,p1> * HP_2(p,y) & p1=null;
   HP_2(x,p) --> x=p or x::node<_,p1> * HP_2(p1,p)
 }
]
