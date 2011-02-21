open Globals

  type stree =
    | Leaf of bool (*false-> empty*)
    | Node of stree * stree
    
  let top = Leaf true
  let bot = Leaf false
  let leftTree = Node ((Leaf true), (Leaf false))  
  let rightTree = Node ((Leaf false), (Leaf true))
  
  let mkNode l r = match l,r with
    | Leaf b1, Leaf b2 when b1==b2 -> Leaf b1
    | _ -> Node(l,r)
    
  let rec empty = function
    | Leaf b -> not b 
    | Node (s0, s1) -> (empty s0)&&(empty s1)
  
  let rec full = function
    | Leaf b -> b
    | Node (s0, s1) -> (full s0)&&(full s1)
    
  let rec stree_eq t1 t2 = match t1,t2 with
    | Leaf b1,Leaf b2  -> b1==b2
    | Node (l1, r1), Node (l2,r2) -> (stree_eq l1 l2)&&(stree_eq r1 r2)
    | _ -> false
        
  let rec can_join x y = match x,y with
    | _ , Leaf false
    | Leaf false, _ -> true
    | Node(l1,r1),Node(l2,r2) -> (can_join l1 l2) && (can_join r1 r2)
    | _ -> false
            
  (*returns the largest share, the smallest tree *)
  let join x y =
    let rec helper x y= match x with
      | Leaf b -> if b then Leaf true else y
      | Node (l1, r1) -> match y with
        | Leaf b -> if b then Leaf true else x
        | Node (l2, r2) -> mkNode (helper l1 l2) (helper r1 r2) in
    if (can_join x y) then helper x y else bot
  
  (*returns the smallest share contained in both, the largest tree*)
  let rec intersect x y = match x with
      | Leaf b -> if b then y else x
      | Node (l1, r1) -> match y with
        | Leaf b -> if b then x else y
        | Node (l2, r2) -> mkNode (intersect l1 l2) (intersect r1 r2) 
   
  let rec neg_tree = function
    | Leaf b -> Leaf (not b)
    | Node (l, r) -> mkNode (neg_tree l) (neg_tree r)
        
  let rec multiply t1 t2= match t1 with
      | Leaf b -> if b then t2 else t1
      | Node (l, r) -> mkNode (multiply l t2) (multiply r t2)
      
  let split x =(multiply x leftTree),(multiply x rightTree)

  let rec string_of_tree_share ts = match ts with
    | Leaf true -> "T"
    | Leaf false -> ""
    | Node (t1,t2) -> "("^(string_of_tree_share t1)^","^(string_of_tree_share t2)^")"
         
  let rec can_divide x y = 
    if stree_eq x y then true
    else match x with
      | Leaf _ -> false
      | Node (l,r) -> (can_divide l y)&&(can_divide r y)
    
  let rec divide x y = 
    if stree_eq x y then top
      else match x with
        | Leaf _ -> report_error no_pos "perm division by non subtree"
        | Node (l,r) -> mkNode (divide l y) (divide r y)
  
  (*can_subtract*)
  let rec contains x y = match x,y with
    | Leaf true, _ ->  true
    | _, Leaf false -> true
    | Leaf false, _ -> false
    | Node(l1,r1), Node(l2,r2) -> (contains l1 l2)&&(contains r1 r2)
    | Node _, Leaf true -> false
    
  let subtract x y = 
    let rec helper x y = match x,y with
      | Leaf true, _ -> neg_tree y
      | Leaf false, _ -> y
      | Node(l1,r1), Node(l2,r2) -> mkNode (helper l1 l2) (helper r1 r2) 
      | Node _ , Leaf false -> x
      | Node _ , Leaf true -> report_error no_pos "missmatch in contains" in      
   if contains x y then helper x y else bot