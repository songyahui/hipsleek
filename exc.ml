open Gen
open Globals

type constant_flow = ident (* identifier for flows *)

type nflow = (int*int)(*numeric representation of flow*)

type nflow_n = nflow * (nflow list) (* orig_exc, current list *)

let empty_flow : nflow = (-1,-2)

let is_empty_flow ((a,b):nflow) = a<0 || (a>b)

let is_subset_flow (((s1,b1):nflow) as f1) (((s2,b2):nflow) as f2) =
      if is_empty_flow(f1) then true
      else if is_empty_flow(f2) then false
      else s2<=s1 && b1<=b2

let is_overlap_flow (((s1,b1):nflow) as f1) (((s2,b2):nflow) as f2) =
      if is_empty_flow(f1) || is_empty_flow(f2) then false
      else (s2<=s1 && s1<=b2) ||  (s2<=b1 && b1<=b2)

let is_next_flow (((s1,b1):nflow) as f1) (((s2,b2):nflow) as f2) =
      s2==b1+1

let is_eq_flow (((s1,b1):nflow)) (((s2,b2):nflow)) =
      s1==b1 && s2==b2

let union_flow (((s1,b1):nflow) as f1) (((s2,b2):nflow) as f2) =
      if (is_empty_flow f1) || (is_empty_flow f2) then empty_flow
      else ((min s1 s2),(max b1 b2))

let minus (s1,b1) (s2,b2) = 
  let r1 = if (s1==s2) then [] else [(s1,s2-1)] in
  let r2 = if (b1==b2) then [] else [(b2+1,b1)] in
  r1@r2
    
let subtract_flow (((s1,b1):nflow) as f1) (((s2,b2):nflow) as f2) =
      if is_empty_flow(f1) || is_empty_flow(f2) then []
      else if (is_subset_flow f1 f2) then minus f2 f1
      else if is_subset_flow f2 f1 then minus f1 f2
      else if not(is_overlap_flow f1 f2) then [f1]
      else if s2<=b1 then [(s1,s2-1)]
      else [(s2,s1-1)]


let subtract (f1:nflow_n) (n:nflow) : nflow_n =
      if (is_empty_flow n) then f1
      else f1 (* TODO *)



(*  WN/Khanh: TODO  *)
(*  (i) add notion of exact type *)
(*  (ii) add holes in nflow type *)
(*
           subtype  exact
   __Exc    12-16    16
     |
     e1     12-15    15
     |
     e2     12-14    14
   /    \
  e3    e4
  12    13
   
  (e1,__Exc,(12,15)),
  (e2,e1,(12,14)),
  (e4,e2,(13,13)),
  (e3,e2,(12,12)),

*)


(* global constants *)

let flow = "flow"
let top_flow = "__flow"
(*let any_flow = "__Any"*)
let n_flow = "__norm"
let cont_top = "__Cont_top"
let brk_top = "__Brk_top"
let c_flow = "__c-flow"
let raisable_class = "__Exc"
let ret_flow = "__Ret"
let spec_flow = "__Spec"
let false_flow = "__false"
let abnormal_flow = "__abnormal"
let stub_flow = "__stub"
let error_flow = "__Error"

let n_flow_int = ref ((-1,-1):nflow)
let ret_flow_int = ref ((-1,-1):nflow)
let spec_flow_int = ref ((-1,-1):nflow)
let top_flow_int = ref ((-2,-2):nflow)
let exc_flow_int = ref ((-2,-2):nflow) (*abnormal flow*)
let error_flow_int  = ref ((-2,-2):nflow) (*must error*)
(* let may_error_flow_int = ref ((-2,-2):nflow) (\*norm or error*\) *)
let false_flow_int = (0,0)
let stub_flow_int = (-3,-3)


  (*hairy stuff for exception numbering*)
  (* TODO : should be changed to use Ocaml graph *)

type flow_entry = string * string * nflow 

let exc_list = ref ([]:flow_entry list)

let clear_exc_list () =
  n_flow_int := (-1,-1);
  ret_flow_int := (-1,-1);
  spec_flow_int := (-1,-1);
  top_flow_int := (-2,-2);
  exc_flow_int := (-2,-2);
  exc_list := []

let remove_dups1 (n:flow_entry list) = Gen.BList.remove_dups_eq (fun (a,b,_) (c,d,_) -> a=c) n

let clean_duplicates ()= 
  exc_list := remove_dups1 !exc_list

let exc_cnt = new counter 0

let reset_exc_hierarchy () =
  let _ = clean_duplicates () in
  let _ = exc_cnt # reset in
  let el = List.fold_left (fun acc (a,b,_) -> 
      if a="" then acc else (a,b,(0,0))::acc) [] !exc_list in
  exc_list := el

let string_of_exc_list (i:int) =
  let x = !exc_list in
  let el = pr_list (pr_triple pr_id pr_id (pr_pair string_of_int string_of_int)) (List.map (fun (a,e,p) -> (a,e,p)) x) in
  "Exception List "^(string_of_int i)^": "^(string_of_int (List.length x))^"members \n"^el


let get_hash_of_exc (f:string): nflow = 
  if ((String.compare f stub_flow)==0) then 
	Error.report_error {Error.error_loc = no_pos; Error.error_text = ("Error found stub flow")}
  else
	let rec get (lst:(string*string*nflow)list):nflow = match lst with
	  | [] -> false_flow_int
	  | (a,_,(b,c))::rst -> if (String.compare f a)==0 then (b,c)
		else get rst in
    (get !exc_list)

(*t1 is a subtype of t2*)
let exc_sub_type (t1 : constant_flow) (t2 : constant_flow): bool = 
  let r11,r12 = get_hash_of_exc t1 in
  if ((r11==0) && (r12==0)) then false
  else
	let r21,r22 = get_hash_of_exc t2 in
	if ((r21==0) && (r22==0)) then true
	else
	  ((r11>=r21)&&(r12<=r22))

(* TODO : to determine subtype based on intervals *)
let flow_sub_type (t1 : nflow) (t2 : nflow): bool 
      = false

(* TODO : to determine overlap based on intervals *)
let flow_overlap (t1 : nflow) (t2 : nflow): bool 
      = false

(*let exc_int_sub_type ((t11,t12):nflow)	((t21,t22):nflow):bool = if (t11==0 && t12==0) then true else ((t11>=t21)&&(t12<=t22))*)

(* TODO : below can be improved by keeping only supertype & choosing the closest *)
(* Given (min,max) and closest found (cmin,cmax), such that cmin<=min<=max<=cmax
     (i) exact      min=max=cmax      id#
     (ii) full       min=min & max    id
     (ii) partial    otherwise        id_
*)
let get_closest ((min,max):nflow):(string) = 
  let rec get (lst:(string*string*nflow) list):string*nflow = 
    match lst  with
	  | [] -> (false_flow,false_flow_int)
	  | (a,b,(c,d)):: rest-> 
            if (c==min && d==max) then (a,(c,d)) (*a fits perfect*)
	        else 
              let r,(minr,maxr) = (get rest) in
	          if (minr==c && maxr==d)||(c>min)||(d<max) then (r,(minr,maxr)) (*the rest fits perfect or a is incompatible*)
	          else if (minr>min)||(maxr<max) then (a,(c,d)) (*the rest is incompatible*)
	          else if ((min-minr)<=(min-c) && (maxr-max)<=(d-max)) then (r,(minr,maxr))
	          else (a,(c,d)) in
  let r,_ = (get !exc_list) in r

let add_edge(n1:string)(n2:string):bool =
  let _ =  exc_list := !exc_list@ [(n1,n2,false_flow_int)] in
  true

let add_edge(n1:string)(n2:string):bool =
  Debug.no_2 "add_edge" pr_id pr_id string_of_bool add_edge n1 n2

(*constructs the mapping between class/data def names and interval
  types*)
(* FISHY : cannot be called multiple times, lead to segmentation problem in lrr proc *)
let compute_hierarchy () =
  let rec lrr (f1:string)(f2:string):(((string*string*nflow) list)*nflow) =
	let l1 = List.find_all (fun (_,b1,_)-> ((String.compare b1 f1)==0)) !exc_list in
	if ((List.length l1)==0) then 
      let i = exc_cnt # inc_and_get 
        (* let j = (Globals.fresh_int()) in  *)
      in ([(f1,f2,(i,i))],(i,i))
	else 
      let ll,(mn,mx) = List.fold_left 
        (fun (t,(o_min,o_max)) (a,b,(c,d)) -> 
            let temp_l,(n_min, n_max) = (lrr a b) 
            in (temp_l@t
                ,( (if ((o_min== -1)||(n_min<o_min)) then n_min else o_min)
                    ,(if (o_max<n_max) then n_max else o_max)))) 
        ([],(-1,-1)) 
        l1 
      in let _ = exc_cnt # inc in  (* to account for internal node *)      
      ( ((f1,f2,(mn,mx+1))::ll) ,(mn,mx+1)) 
  in
  (* let r,_ = (lrr top_flow "") in *)
  (* why did lrr below cause segmentation problem for sleek? *)
  let _ = reset_exc_hierarchy () in
  (* let _ = print_flush "c-h 1" in *)
  let r,_ = (lrr "" "") in
  (* let _ = print_flush "c-h 2" in *)
  let _ = exc_list := r in
  n_flow_int := (get_hash_of_exc n_flow);
  ret_flow_int := (get_hash_of_exc ret_flow);
  spec_flow_int := (get_hash_of_exc spec_flow);
  top_flow_int := (get_hash_of_exc top_flow);
  exc_flow_int := (get_hash_of_exc abnormal_flow);
  error_flow_int := (get_hash_of_exc error_flow)
    (* ; Globals.sleek_mustbug_flow_int := (get_hash_of_exc Globals.sleek_mustbug_flow) *)
    (* ;Globals.sleek_maybug_flow_int := (get_hash_of_exc Globals.sleek_maybug_flow) *)
    (* ;let _ = print_string ((List.fold_left (fun a (c1,c2,(c3,c4))-> a ^ " (" ^ c1 ^ " : " ^ c2 ^ "="^"["^(string_of_int c3)^","^(string_of_int c4)^"])\n") "" r)) in ()*)

let compute_hierarchy i () =
  let pr () = string_of_exc_list 0 in
  Debug.no_1_num i "compute_hierarchy" pr pr (fun _ -> compute_hierarchy()) ()


  (* TODO : use a graph module here! *)
let has_cycles ():bool =
  let rec cc (crt:string)(visited:string list):bool = 
	let sons = List.fold_left (fun a (d1,d2,_)->if ((String.compare d2 crt)==0) then d1::a else a) [] !exc_list in
	if (List.exists (fun c-> (List.exists (fun d->((String.compare c d)==0)) visited)) sons) then true
	else (List.exists (fun c-> (cc c (c::visited))) sons) in	
  (cc top_flow [top_flow])

