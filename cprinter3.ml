(* pretty printing for cast *)

open Globals 
open Lexing 
open Cast 
open Cformula
open Printf

module P = Cpure

type loc_mark = {loc_name:string;loc_offset:int}

let loc_mark_list = ref([]:loc_mark list)

let rec string_of_space (level:int) = 
        match level with
        |0 -> ""
        |_ -> "\t\t"^string_of_space (level - 1)
;;

(* function to print a list of strings *) 
let rec string_of_ident_list l c = match l with 
  | []               -> ""
  | h::[]            -> h 
  | h::t             -> h ^ c ^ (string_of_ident_list t c)
;;

(* pretty printing for primitive types *)
let string_of_prim_type = function 
  | Bool          -> "boolean"
  | Float         -> "float"
  | Int           -> "int"
  | Void          -> "void"
  | Bag           -> "multiset"
;;

(* pretty printing for types *)
let string_of_typ = function 
  | P.Prim t        -> string_of_prim_type t 
  | P.OType ot      -> if ((String.compare ot "") ==0) then "ptr" else ot
;;

let string_of_pos p = " "^(string_of_int p.start_pos.Lexing.pos_lnum)^":"^
				(string_of_int (p.start_pos.Lexing.pos_cnum - p.start_pos.Lexing.pos_bol));;



let string_of_constraint_relation m = match m with
  | Cpure.Unknown -> " ?  "
  | Cpure.Subsumed -> " <  "
  | Cpure.Subsuming -> " >  "
  | Cpure.Equal -> " =  "
  | Cpure.Contradicting -> "!= "
  
let string_of_spec_var sv = match sv with
  | P.SpecVar (_, v, p) -> v ^ (if p = Primed then "'" else "")

let rec string_of_h_formula h = match h with
  | Star ({h_formula_star_h1 = h1; h_formula_star_h2 = h2; h_formula_star_pos = pos}) -> 
      (string_of_h_formula h1) ^ " * " ^ (string_of_h_formula h2)
  | DataNode ({h_formula_data_node = sv; h_formula_data_name = c; h_formula_data_arguments = svs; h_formula_data_pos = pos})  ->
	  (string_of_spec_var sv) ^ "::" ^ c 
	  ^ "<" ^ (String.concat ", " (List.map string_of_spec_var svs)) ^ ">"
  | ViewNode ({h_formula_view_node = sv; 
			   h_formula_view_name = c; 
			   h_formula_view_arguments = svs; 
			   h_formula_view_origins = origins;
			   h_formula_view_pos = pos}) ->
	  (string_of_spec_var sv) ^ "::" ^ c 
	  ^ "<" ^ (String.concat ", " (List.map string_of_spec_var svs)) ^ ">" 
	  (*^ "origins: " ^ (String.concat ";" origins) ^ "--"*)
  | HTrue -> "true"
  | HFalse -> "false"

let need_parenthesis = function 
(*    | P.Null _ | P.Var _ | P.IConst _ | P.Max _ | P.Min _  -> false 
    | _                                                    -> true *)
	_ -> false
;; 

(* pretty printing for an expression for a formula *)
let rec string_of_formula_exp = function 
  | P.Null l -> "null"
  | P.Var (x, l) -> (match x with 
					   | P.SpecVar (t, id, p) -> id ^ (match p with 
														 | Primed    -> "'" 
														 | Unprimed  -> "" ))
  | P.IConst (i, l)           -> string_of_int i
  | P.Add (e1, e2, l)	      -> (match e1 with 
    | P.Null _ | P.Var _ | P.IConst _ | P.Max _ | P.Min _        -> (string_of_formula_exp e1) ^ "+"   			      
    | _                                                          -> "(" ^ (string_of_formula_exp e1) ^ ")+") ^ (match e2 with 
           | P.Null _ | P.Var _ | P.IConst _ | P.Max _ | P.Min _ -> string_of_formula_exp e2
	   | _                                                   -> "(" ^ (string_of_formula_exp e2) ^ ")")
  | P.Subtract (e1, e2, l)    -> if need_parenthesis e1
    then 
      if need_parenthesis e2
      then  "(" ^ (string_of_formula_exp e1) ^ ")-(" ^ (string_of_formula_exp e2) ^ ")"  			      
	  else "(" ^ (string_of_formula_exp e1) ^ ")-" ^ (string_of_formula_exp e2)
    else (string_of_formula_exp e1) ^ "-" ^ (string_of_formula_exp e2)										    | P.Mult (i, e, l)          -> (string_of_int i) ^ " * " ^ (if need_parenthesis e then "(" ^ (string_of_formula_exp e) ^ ")" else string_of_formula_exp e)
  | P.Max (e1, e2, l)         -> "max(" ^ (string_of_formula_exp e1) ^ "," ^ (string_of_formula_exp e2) ^ ")"
  | P.Min (e1, e2, l)         -> "min(" ^ (string_of_formula_exp e1) ^ "," ^ (string_of_formula_exp e2) ^ ")" 
  | P.Bag (elist, l) 					-> "{" ^ (string_of_formula_exp_list elist) ^ "}"
  | P.BagUnion ([], l) 				-> ""
  | P.BagUnion (e::[], l)			-> (string_of_formula_exp e) 
  | P.BagUnion (e::rest, l) 	-> "(" ^ (string_of_formula_exp e) ^ " union " ^ (string_of_formula_exp (P.BagUnion (rest, l))) ^ ")"
  | P.BagIntersect ([], l) 		-> ""
  | P.BagIntersect (e::[], l)	-> (string_of_formula_exp e) 
  | P.BagIntersect (e::rest, l)->(string_of_formula_exp e) ^ "<intersect>" ^ (string_of_formula_exp (P.BagIntersect (rest, l)))
  | P.BagDiff (e1, e2, l)     -> (string_of_formula_exp e1) ^ "-" ^ (string_of_formula_exp e2) 

  
(* pretty printing for a list of pure formulae *)
and string_of_formula_exp_list l = match l with 
  | []                         -> ""
  | h::[]                      -> string_of_formula_exp h
  | h::t                       -> (string_of_formula_exp h) ^ ", " ^ (string_of_formula_exp_list t)
;;
  
(* pretty printing for boolean constraints *)
let string_of_b_formula = function 
  | P.BConst (b,l)              -> (*if b <> true then*) string_of_bool b (*else ""*)
  | P.BVar (x, l)               -> (match x with 
    | P.SpecVar (_, id, p) -> id ^ (match p with 
      | Primed    -> "'" 
      | Unprimed  -> "" ))
  | P.Lt (e1, e2, l)            -> if need_parenthesis e1 
                                   then if need_parenthesis e2 then "(" ^ (string_of_formula_exp e1) ^ ") < (" ^ (string_of_formula_exp e2) ^ ")"
                                                               else "(" ^ (string_of_formula_exp e1) ^ ") < " ^ (string_of_formula_exp e2)
                                   else (string_of_formula_exp e1) ^ " < " ^ (string_of_formula_exp e2)
  | P.Lte (e1, e2, l)           -> if need_parenthesis e1 
                                   then if need_parenthesis e2 then "(" ^ (string_of_formula_exp e1) ^ ") <= (" ^ (string_of_formula_exp e2) ^ ")"
                                                               else "(" ^ (string_of_formula_exp e1) ^ ") <= " ^ (string_of_formula_exp e2)
                                   else (string_of_formula_exp e1) ^ " <= " ^ (string_of_formula_exp e2)
  | P.Gt (e1, e2, l)            -> if need_parenthesis e1 
                                   then if need_parenthesis e2 then "(" ^ (string_of_formula_exp e1) ^ ") > (" ^ (string_of_formula_exp e2) ^ ")"
                                                               else "(" ^ (string_of_formula_exp e1) ^ ") > " ^ (string_of_formula_exp e2)
                                   else (string_of_formula_exp e1) ^ " > " ^ (string_of_formula_exp e2)
  | P.Gte (e1, e2, l)           -> if need_parenthesis e1 
                                   then if need_parenthesis e2 then "(" ^ (string_of_formula_exp e1) ^ ") >= (" ^ (string_of_formula_exp e2) ^ ")"
                                                               else "(" ^ (string_of_formula_exp e1) ^ ") >= " ^ (string_of_formula_exp e2)
                                   else (string_of_formula_exp e1) ^ " >= " ^ (string_of_formula_exp e2)
  | P.Eq (e1, e2, l)            -> if need_parenthesis e1 
                                   then if need_parenthesis e2 then "(" ^ (string_of_formula_exp e1) ^ ") = (" ^ (string_of_formula_exp e2) ^ ")"
                                                               else "(" ^ (string_of_formula_exp e1) ^ ") = " ^ (string_of_formula_exp e2)
                                   else (string_of_formula_exp e1) ^ " = " ^ (string_of_formula_exp e2)	
  | P.Neq (e1, e2, l)           -> if need_parenthesis e1 
                                   then if need_parenthesis e2 then "(" ^ (string_of_formula_exp e1) ^ ") != (" ^ (string_of_formula_exp e2) ^ ")"
                                                               else "(" ^ (string_of_formula_exp e1) ^ ") != " ^ (string_of_formula_exp e2)
                                   else (string_of_formula_exp e1) ^ " != " ^ (string_of_formula_exp e2)
  | P.EqMax (e1, e2, e3, l)     -> (string_of_formula_exp e1) ^" = max(" ^ (string_of_formula_exp e2) ^ "," ^ (string_of_formula_exp e3) ^ ")"
  | P.EqMin (e1, e2, e3, l)     -> (string_of_formula_exp e1) ^" = min(" ^ (string_of_formula_exp e2) ^ "," ^ (string_of_formula_exp e3) ^ ")"
	| P.BagIn (v, e, l)					-> (string_of_spec_var v) ^ " <in> " ^ (string_of_formula_exp e)
	| P.BagNotIn (v, e, l)			-> (string_of_spec_var v) ^ " <notin> " ^ (string_of_formula_exp e)
  | P.BagSub (e1, e2, l)			-> (string_of_formula_exp e1) ^ " <subset> " ^ (string_of_formula_exp e2)
	| P.BagMin (v1, v2, l)			-> (string_of_spec_var v1) ^ " = <min> (" ^ (string_of_spec_var v2) ^ ")"
	| P.BagMax (v1, v2, l)			-> (string_of_spec_var v1) ^ " = <max> (" ^ (string_of_spec_var v2) ^ ")"

;;

(* pretty printing for a list of pure formulas *)
let rec string_of_pure_formula_list l = match l with 
  | []               -> ""
  | h::t             -> (string_of_pure_formula h) ^ "\n" ^ (string_of_pure_formula_list t)

(* pretty printing for a pure formula *)
and string_of_pure_formula = function 
  | P.BForm bf                    -> string_of_b_formula bf 
  | P.And (f1, f2, l)             -> (string_of_pure_formula f1) ^ " & " ^ (string_of_pure_formula f2)
  | P.Or (f1, f2, l)              -> "((" ^ (string_of_pure_formula f1) ^ ") | (" ^ (string_of_pure_formula f2) ^ "))"
  | P.Not (f, l)                  -> "!(" ^ (string_of_pure_formula f) ^ ")"
  | P.Forall (x, f, l)            -> "(all " ^ (match x with P.SpecVar (_, id, p) -> id ^ (match p with 
    | Primed    -> "'"
    | Unprimed  -> "")) ^ ". " ^ (string_of_pure_formula f) ^ ")"
  | P.Exists (x, f, l)            -> "(ex " ^ (match x with P.SpecVar (_, id, p) -> id ^ (match p with 
    | Primed    -> "'"
    | Unprimed  -> "")) ^ ". " ^ (string_of_pure_formula f) ^ ")"

and string_of_pure_formula_branches (f, l) =
  match l with
  | [] -> string_of_pure_formula f
  | _ -> string_of_pure_formula f ^ " & [" ^ (String.concat "; " (List.map (fun (l, f) -> "\"" ^ l ^ "\" : " ^ string_of_pure_formula f) l)) ^ "]"
;;

(* pretty printing for a cformula *)                                                         (*NOT DONE*)

let string_of_flow_store l = (String.concat " " (List.map (fun h-> (h.formula_store_name^"= "^
						(let rr = h.formula_store_value.formula_flow_interval in
							(string_of_int (fst rr))^"-"^(string_of_int (snd rr)))^" ")) l))

let rec string_of_flow_formula f c = 
	"{"^f^",("^(string_of_int (fst c.formula_flow_interval))^","^(string_of_int (snd c.formula_flow_interval))^
	")="^(Util.get_closest c.formula_flow_interval)^","^(match c.formula_flow_link with | None -> "" | Some e -> e)^"}"
	


and string_of_t_formula = function
(* commented on 09.06.08
 | TypeExact ({t_formula_sub_type_var = v;
				t_formula_sub_type_type = c}) -> 
	  (string_of_spec_var v) ^ " = " ^ c
  | TypeSub ({t_formula_sub_type_var = v;
			  t_formula_sub_type_type = c}) -> 
	  (string_of_spec_var v) ^ " <: " ^ c
  | TypeSuper ({t_formula_sub_type_var = v;
				t_formula_sub_type_type = c}) -> 
	  (string_of_spec_var v) ^ " > " ^ c*)
  | TypeAnd ({t_formula_and_f1 = f1;
			  t_formula_and_f2 = f2}) -> 
	  (string_of_t_formula f1) ^ " & " ^ (string_of_t_formula f2)
  | TypeTrue -> "TypeTrue"
  | TypeFalse -> "TypeFalse"

let rec string_of_formula = function 
  | Or ({formula_or_f1 = f1; formula_or_f2 = f2; formula_or_pos = pos}) -> 
      (string_of_formula f1) ^ "\nor " ^ (string_of_formula f2)
  | Base ({formula_base_heap = h; 
		   formula_base_pure = p; 
		   formula_base_branches = b; 
		   formula_base_type = t;
		   formula_base_flow = fl;
		   formula_base_pos = pos}) -> 
      (string_of_h_formula h) ^ " & " ^ (string_of_pure_formula_branches (p, b))^"&"^(string_of_flow_formula "FLOW" fl) (* ^ " & " ^ (string_of_t_formula t) *)
  | Exists ({formula_exists_qvars = svs; 
			 formula_exists_heap = h; 
			 formula_exists_pure = p; 
		     formula_exists_branches = b; 
			 formula_exists_type = t;
			 formula_exists_flow = fl;
			 formula_exists_pos = pos}) -> 
      "(EX " ^ (String.concat ", " (List.map string_of_spec_var svs)) 
      ^ " . " ^ (string_of_h_formula h) ^ " & " ^ (string_of_pure_formula_branches (p, b))^"&"^(string_of_flow_formula "FLOW" fl)
	  ^ (* " & " ^ (string_of_t_formula t)^ *) ")"

(* function to print a list of type F.formula * F.formula *)
let rec string_of_formulae_list l = match l with 
  | []               -> ""
  | (f1, f2)::[]     -> "\nrequires " ^ (string_of_formula f1) ^ "\nensures " ^ (string_of_formula f2)  
  | (f1, f2)::t      -> "\nrequires " ^ (string_of_formula f1) ^ "\nensures " ^ (string_of_formula f2) ^ (string_of_formulae_list t)
;;

let rec string_of_context (ctx: context) = match ctx with
  | Ctx es -> string_of_estate es
  | OCtx (c1, c2) -> (string_of_context c1) ^ "\nCtxOR\n" ^ (string_of_context c2)
  
and string_of_context_list ctx = String.concat "\n;\n" (List.map string_of_context ctx)

and string_of_taken_br c = match c with
  	| Then_taken c -> if c then "then_taken" else "else_taken"
	| Catch_taken c -> if c then "catch_taken" else "catch_not_taken"
	| Call_taken (c1,c2) -> "pre_"^(string_of_int c1)^" "^c2

and string_of_branch_trace c = 	"["^(String.concat ", " (List.map (fun (c1,c2) -> 
		(string_of_int c1)^"-"^(string_of_taken_br c2)) c))^"]"

and string_of_estate (es : entail_state) = 
  "es_formula: " ^ (string_of_formula es.es_formula)
  ^ "\nes_pure: " ^ (string_of_pure_formula_branches es.es_pure)
  ^ "\nes_heap: " ^ (string_of_h_formula es.es_heap)
 (* ^ "\nes_evars: " ^ (String.concat ", " (List.map string_of_spec_var es.es_evars))
  ^ "\nes_ivars: " ^ (String.concat ", " (List.map string_of_spec_var es.es_ivars))
  ^ "\nes_expl_vars: " ^ (String.concat ", " (List.map string_of_spec_var es.es_expl_vars))
  ^"\n es_gen_expl_vars:"^(String.concat ", " (List.map string_of_spec_var es.es_gen_expl_vars))
  ^"\n es_gen_impl_vars:"^(String.concat ", " (List.map string_of_spec_var es.es_gen_impl_vars))*)
  ^"\n es_label_list:"^(string_of_branch_trace es.es_label_list)
(*
  ^ "\nes_pp_subst: " ^ (String.concat ", " (List.map (fun (fr, t) -> "(" ^ (string_of_spec_var fr) 
														 ^ ", " ^ (string_of_spec_var t) ^ ")") es.es_pp_subst))
  ^ "\nes_pres_subst: " ^ (String.concat ", " (List.map (fun (fr, t) -> "(" ^ (string_of_spec_var fr) 
														 ^ ", " ^ (Presburger.string_of_aExp t) ^ ")") es.es_pres_subst))*
*)

(*(Hashtbl.iter (fun id (v_pre, v_exc, v_post, fail_trace) -> 
		(*(prerr_endline (sprintf "id:%s;" id));*)
		let id_int = (Int32.to_int (Int32.of_string (String.sub id 0 ((String.length id)-1)))) in
		 if (List.length fail_trace = 0) then (highlight_poscon (-1) struc_formula buffer "pink_highlight")
		 else (highlight_poscon id_int struc_formula buffer "red_highlight")) label)
*)
and string_of_label_map (t:label_map) (id:int):string = if (id == -1) then begin
	"["^(Hashtbl.fold (fun e (v_pre,v_exc, v_post,fail_trace) a -> 
		let fts = "["^(String.concat "," (List.map (fun (c1,c2)->
				(if c2 then "new fail" else "old fail")^ 
				(string_of_branch_trace c1)) fail_trace))^"]" in	
		(e^" pre:\n"^ (string_of_context_list v_pre)^
		"\n escaping input: "^(string_of_context_list v_exc)^
		"\n post: "^ (string_of_context_list v_post)^
		"\n fail_trace: "^fts^"\n"^a) ) t "")^"]\n" end
	else begin
		"["^(Hashtbl.fold (fun e (v_pre,v_exc, v_post,fail_trace) a -> 
		let prepost_id = (Int32.to_int (Int32.of_string (String.sub e 0 ((String.length e)-1)))) in
		if (prepost_id = id) then begin
		let fts = "["^(String.concat "," (List.map (fun (c1,c2)->
				(if c2 then "new fail" else "old fail")^ 
				(string_of_branch_trace c1)) fail_trace))^"]" in
			
		(e^" pre:\n"^ (string_of_context_list v_pre)^
		"\n escaping input: "^(string_of_context_list v_exc)^
		"\n post: "^ (string_of_context_list v_post)^
		"\n fail_trace: "^fts^"\n"^a) end else (a)) t "")^"]\n" 
	end
;;


(* pretty printing for a spec_var *)
let string_of_spec_var = function 
  | P.SpecVar (_, id, p) -> id ^ (match p with 
    | Primed   -> "'"
    | Unprimed -> "")

(* pretty printing for a spec_var list *)
let rec string_of_spec_var_list l = match l with 
  | []               -> ""
  | h::[]            -> string_of_spec_var h 
  | h::t             -> (string_of_spec_var h) ^ "," ^ (string_of_spec_var_list t)
;;


let rec string_of_ext_formula = function
	| ECase {
			formula_case_exists =ee;
			formula_case_branches  =  case_list ;
		} -> 
			let l3 = List.fold_left (fun a c -> a^" "^ (string_of_spec_var c)) "" ee in
			let impl = List.fold_left (fun a (c1,c2) -> a^"\n\t "^(string_of_pure_formula c1)^"->"^ 		
		( List.fold_left  (fun a c -> a ^" "^(string_of_ext_formula c )) "" c2)^"\n") "" case_list in
			("case ex.["^l3^"]{"^impl^"}")
	|EBase {
		 	formula_ext_implicit_inst = ii;
			formula_ext_explicit_inst = ei;
			formula_ext_exists = ee;
		 	formula_ext_base = fb;
		 	formula_ext_continuation = cont;	
		} -> 
				let l1 = List.fold_left (fun a c -> a^" "^ (string_of_spec_var c)) "" ii in
				let l2 = List.fold_left (fun a c -> a^" "^ (string_of_spec_var c)) "" ei in
				let l3 = List.fold_left (fun a c -> a^" "^ (string_of_spec_var c)) "" ee in
				let b = string_of_formula fb in
				let c = (List.fold_left (fun a d -> a^"\n"^(string_of_ext_formula d)) "{" cont)^"}" in
				"ex.["^l3^"]["^l1^"]["^l2^"]"^b^" "^c
	| EAssume (x,b,(c1,c2))-> "EAssume"^(string_of_int c1)^" "^ c2^" ref["^(string_of_spec_var_list x)^"] "^(string_of_formula b)
;;

let string_of_struc_formula d =  List.fold_left  (fun a c -> a ^"\n "^(string_of_ext_formula c )) "" d 
;;

(*
let rec string_of_spec = function
	| SCase {scase_branches= br;} ->
		 (List.fold_left (fun a (c1,c2)->a^"\n"^(string_of_pure_formula c1)^"-> "^
		( List.fold_left  (fun a c -> a ^"\n "^(string_of_spec c )) "" c2)) "case { " br)^"}\n"
	| SRequires 	{
			srequires_implicit_inst = ii;
			srequires_explicit_inst = ei;
			srequires_base = fb;
			srequires_continuation = cont;
			}	 ->
				let l2 = List.fold_left (fun a c -> a^ " " ^(string_of_spec_var c)) "" ei in
				let l1 = List.fold_left (fun a c -> a^ " " ^(string_of_spec_var c)) "" ii in
				let b = string_of_formula fb in				
				"requires ["^l1^"]["^l2^"]"^b^" "^((List.fold_left (fun a d -> a^"\n"^(string_of_spec d)) "{" cont)^"}")
	| SEnsure{ sensures_base = fb } -> ("ensures "^(string_of_formula fb))
;;


let string_of_specs d =  List.fold_left  (fun a c -> a ^" "^(string_of_spec c )) "" d 
;;*)


(* functions to decide if an expression needs parenthesis *)
let need_parenthesis e = match e with 
  | BConst _ | Bind _ | FConst _ | IConst _ | Unit _ | Var _ -> false 
  | _                                                        -> true
;;

let string_of_sharp st = match st with
	| Sharp_ct t -> string_of_flow_formula "" t
	| Sharp_v  f -> "flow_var "^f
(* pretty printing for expressions *)
let rec string_of_exp e level =match e with 
  | Java ({exp_java_code = code}) -> code
  | CheckRef _ -> ""
  | Assert ({exp_assert_asserted_formula = f1o; 
			 exp_assert_assumed_formula = f2o; 
			 exp_assert_pos = l;
			 exp_assert_label =  lbl;}) -> 
      begin
	  let str1 = 
		match f1o with
		  | None -> ""
		  | Some f1 -> (string_of_space level)^"assert " ^ (string_of_struc_formula f1) in
	  let str2 =
		match f2o with
		  | None -> ""
		  | Some f2 -> (string_of_space level)^"assume " ^ (string_of_formula f2) in
		lbl^": "^str1 ^ " " ^ str2
      end
  | Assign ({exp_assign_lhs = id; exp_assign_rhs = e; exp_assign_pos = l}) -> 
		(string_of_space level)^id ^ " = " ^(match e with
					   |Bind ({exp_bind_type = _; 
	   					exp_bind_bound_var = (_, id); 
	   					exp_bind_fields = idl;
	   					exp_bind_body = eb;
	   					exp_bind_pos = l})->(string_of_exp e level)
					   |_ ->(string_of_exp e 0))(*^
		"\n{"^ (string_of_label_map l.state) ^"} \n"^"assign loc:"^(string_of_full_loc l.pos)^"\n"*)
  | BConst ({exp_bconst_val = b; exp_bconst_pos = l}) -> 
      string_of_bool b 
  | Bind ({exp_bind_type = _; 
	   exp_bind_bound_var = (_, id); 
	   exp_bind_fields = idl;
	   exp_bind_body = e;
	   exp_bind_pos = l}) -> 
	   "bind " ^ id ^ " to (" ^ (string_of_ident_list (snd (List.split idl)) ",") ^ ") in \n"^(string_of_space level)^"{\n" ^ (string_of_exp e (level+1)) ^ "\n"^(string_of_space level)^"}"
  | Block ({exp_block_type = _;
	    exp_block_body = e;
	    exp_block_local_vars = _;
	    exp_block_pos = _}) -> (string_of_space level)^"{\n" ^ (string_of_exp e (level+1)) ^ "\n"^(string_of_space level)^"}\n"
  | ICall ({exp_icall_type = _;
	   exp_icall_receiver = r;
	   exp_icall_method_name = id;
	   exp_icall_arguments = idl;
	   exp_icall_visible_names = _;
	   exp_icall_pos = l}) -> 
	   (string_of_space level)^r ^ "." ^ id ^ "(" ^ (string_of_ident_list idl ",") ^ ")" 
  | Cast ({exp_cast_target_type = t;
		   exp_cast_body = body}) -> begin
	  (string_of_space level)^"(" ^ (string_of_typ t) ^ " )" ^ (string_of_exp body level)
	end
  | Cond ({exp_cond_type = _;
	   exp_cond_condition = id;
	   exp_cond_then_arm = e1;
	   exp_cond_else_arm = e2;
	   exp_cond_pos = l;
	   exp_cond_id = br_id}) -> 
	   (string_of_space level)^"if (" ^ id ^ ")\n " ^(string_of_exp e1 (level+1)) ^ "\n"^(string_of_space level)^"else \n" ^ (string_of_exp e2 (level+1)) ^ "\n" 
  | Debug ({exp_debug_flag = b; exp_debug_pos = l}) -> if b then (string_of_space level)^"debug" else ""
  | Dprint _                   -> (string_of_space level)^"dprint"
  | FConst ({exp_fconst_val = f; exp_fconst_pos = l}) -> string_of_float f 
  (*| FieldRead (_, (v, _), (f, _), _) -> v ^ "." ^ f*)
  (*| FieldWrite ((v, _), (f, _), r, _) -> v ^ "." ^ f ^ " = " ^ r*)
  | IConst ({exp_iconst_val = i; exp_iconst_pos = l}) -> string_of_int i 
  | New ({exp_new_class_name = id;
	  exp_new_arguments = idl;
	  exp_new_pos = l}) -> 
	  "new" ^ id ^ "(" ^ (string_of_ident_list (snd (List.split idl)) ",") ^ ")"
  | Null l -> "null"
  | Print (i, l)-> (string_of_space level)^"print " ^ (string_of_int i) 
  | Sharp ({exp_sharp_flow_type = st;
	     exp_sharp_val = eo;
	     exp_sharp_pos = l}) ->begin(string_of_space level)^(
		 match st with
		 | Sharp_ct f ->  if (Cformula.equal_flow_interval f.formula_flow_interval !ret_flow_int) then
									 (match eo with 
										|Sharp_prog_var e -> "return " ^ (snd e)
										| _   -> "return")
						 else  (match eo with 
					| Sharp_prog_var e -> "throw " ^ (snd e)
					| Sharp_finally e -> "throw " ^ e ^":"^(string_of_sharp st)
					| _   -> "throw "^(string_of_sharp st))
		 | _ -> (match eo with 
					| Sharp_prog_var e -> "throw " ^ (snd e)
					| Sharp_finally e -> "throw " ^ e ^":" ^(string_of_sharp st)
					| _   -> "throw "^(string_of_sharp st)))end 
  | SCall ({exp_scall_type = _;
	   exp_scall_method_name = id;
	   exp_scall_arguments = idl;
	   exp_scall_visible_names = _;
	   exp_scall_pos = l;
	   exp_scall_id = scall_id}) -> 
	   (string_of_space level)^(string_of_int scall_id)^" "^ id ^ "(" ^ (string_of_ident_list idl ",") ^ ")" 
  | Seq ({exp_seq_type = _;
	  exp_seq_exp1 = e1;
	  exp_seq_exp2 = e2;
	  exp_seq_pos = l}) -> 
	  (string_of_exp e1 level) ^ ";\n" ^ (string_of_exp e2 level)(*^
	  "\n{"^(string_of_space level)^ (string_of_label_map l.state) ^"} \n"^"seq loc:"^(string_of_full_loc l.pos)^"\n"*)
  | This _ -> (string_of_space level)^"this"
  | Var ({exp_var_type = _;
	  exp_var_name = id;
	  exp_var_pos = l}) -> (string_of_space level)^id 
  | VarDecl ({exp_var_decl_type = t;
	      exp_var_decl_name = id;
	      exp_var_decl_pos = _}) -> 
	      (string_of_space level)^(string_of_typ t) ^" "^ id (*^ (string_of_exp e1) ^ ";\n" ^ (string_of_exp e2)*)
  | Unit l                     -> ""
  | While ({exp_while_condition = id;
	    exp_while_body = e;
	    exp_while_spec = fl;
	    exp_while_pos = l})  -> 
	    "while " ^ id ^ (string_of_struc_formula fl) ^ "\n"^(string_of_space level)^"{\n" ^ (string_of_exp e (level+1)) ^ "\n}\n"
  | Unfold ({exp_unfold_var = sv}) -> (string_of_space level)^"unfold " ^ (string_of_spec_var sv)
  | Try b -> 
	let c = b.exp_catch_clause.exp_catch_flow_type in
	(string_of_space level)^"try \n"^(string_of_exp b.exp_try_body (level+1))^"\n"^(string_of_space level)^"catch ("^ (string_of_int (fst c))^","^(string_of_int (snd c))^")="^(Util.get_closest c)^ 
				(match b.exp_catch_clause.exp_catch_flow_var with 
					| Some c -> (" @"^c^" ")
					| _ -> " ")^
				 (match b.exp_catch_clause.exp_catch_var with 
					| Some (a,b) -> ((string_of_typ a)^":"^b^" ")
					| _ -> " ")^") \n\t"^(string_of_exp b.exp_catch_clause.exp_catch_body level)
;;
(*
let rec string_of_exp2 e level num=match e with 
  | Java ({exp_java_code = code}) -> code
  | CheckRef _ -> ""
  | Assert ({exp_assert_asserted_formula = f1o; 
			 exp_assert_assumed_formula = f2o; 
			 exp_assert_pos = l;
			 exp_assert_label =  lbl;}) -> 
      begin
	  let str1 = 
		match f1o with
		  | None -> ""
		  | Some f1 -> (string_of_space level)^"assert " ^ (string_of_struc_formula f1) in
	  let str2 =
		match f2o with
		  | None -> ""
		  | Some f2 -> "assert:"^(string_of_int num)^(string_of_space level)^"assume " ^ (string_of_formula f2) in
		lbl^": "^str1 ^ " " ^ str2
      end
  | Assign ({exp_assign_lhs = id; exp_assign_rhs = e; exp_assign_pos = l}) -> 
		(string_of_space level)^id ^ " = " ^(match e with
					   |Bind ({exp_bind_type = _; 
	   					exp_bind_bound_var = (_, id); 
	   					exp_bind_fields = idl;
	   					exp_bind_body = eb;
	   					exp_bind_pos = l})->"assign:"^(string_of_int num)^(string_of_exp2 e level (num+1))
					   |_ ->"assign:"^(string_of_int num)^(string_of_exp2 e 0 (num+1)))^
		"\n{"^ (string_of_label_map l.state) ^"} \n"^"assign loc:"^(string_of_full_loc l.pos)^"\n"
  | BConst ({exp_bconst_val = b; exp_bconst_pos = l}) -> 
      "bconst"^(string_of_int num)^string_of_bool b 
  | Bind ({exp_bind_type = _; 
	   exp_bind_bound_var = (_, id); 
	   exp_bind_fields = idl;
	   exp_bind_body = e;
	   exp_bind_pos = l}) -> 
	   "bind"^(string_of_int num)^"bind " ^ id ^ " to (" ^ (string_of_ident_list (snd (List.split idl)) ",") ^ ") in \n"^(string_of_space level)^"{\n" ^ (string_of_exp2 e (level+1) (num+1)) ^ "\n"^(string_of_space level)^"}"
  | Block ({exp_block_type = _;
	    exp_block_body = e;
	    exp_block_local_vars = _;
	    exp_block_pos = _}) -> "block"^(string_of_int num)^(string_of_space level)^"{\n" ^ (string_of_exp2 e (level+1) (num+1)) ^ "\n"^(string_of_space level)^"}\n"
  | ICall ({exp_icall_type = _;
	   exp_icall_receiver = r;
	   exp_icall_method_name = id;
	   exp_icall_arguments = idl;
	   exp_icall_visible_names = _;
	   exp_icall_pos = l}) -> 
	   "icall"^(string_of_int num)^(string_of_space level)^r ^ "." ^ id ^ "(" ^ (string_of_ident_list idl ",") ^ ")" 
  | Cast ({exp_cast_target_type = t;
		   exp_cast_body = body}) -> begin
	  "cast"^(string_of_int num)^(string_of_space level)^"(" ^ (string_of_typ t) ^ " )" ^ (string_of_exp2 body level (num+1))
	end
  | Cond ({exp_cond_type = _;
	   exp_cond_condition = id;
	   exp_cond_then_arm = e1;
	   exp_cond_else_arm = e2;
	   exp_cond_pos = l;
	   exp_cond_id = br_id}) -> 
	   "cond"^(string_of_int num)^(string_of_space level)^"if (" ^ id ^ ")\n " ^(string_of_exp2 e1 (level+1) (num+1)) ^ "\n"^(string_of_space level)^"else \n" ^ (string_of_exp2 e2 (level+1) (num+1)) ^ "\n" 
  | Debug ({exp_debug_flag = b; exp_debug_pos = l}) -> if b then "debug:"^(string_of_int num)^(string_of_space level)^"debug" else ""
  | Dprint _                   -> (string_of_int num)^(string_of_space level)^"dprint"
  | FConst ({exp_fconst_val = f; exp_fconst_pos = l}) -> "fconst"^(string_of_int num)^string_of_float f 
  (*| FieldRead (_, (v, _), (f, _), _) -> v ^ "." ^ f*)
  (*| FieldWrite ((v, _), (f, _), r, _) -> v ^ "." ^ f ^ " = " ^ r*)
  | IConst ({exp_iconst_val = i; exp_iconst_pos = l}) -> "iconst"^(string_of_int num)^string_of_int i 
  | New ({exp_new_class_name = id;
	  exp_new_arguments = idl;
	  exp_new_pos = l}) -> 
	  "new"^(string_of_int num)^"new" ^ id ^ "(" ^ (string_of_ident_list (snd (List.split idl)) ",") ^ ")"
  | Null l -> (string_of_int num)^"null"
  | Print (i, l)-> (string_of_int num)^(string_of_space level)^"print " ^ (string_of_int i) 
  | Sharp ({exp_sharp_flow_type = st;
	     exp_sharp_val = eo;
	     exp_sharp_pos = l}) ->begin(string_of_space level)^(
		 match st with
		 | Sharp_ct f ->  if (Cformula.equal_flow_interval f.formula_flow_interval !ret_flow_int) then
									 (match eo with 
										|Sharp_prog_var e -> (string_of_int num)^"return " ^ (snd e)
										| _   -> (string_of_int num)^"return")
						 else  (match eo with 
					| Sharp_prog_var e -> (string_of_int num)^"throw " ^ (snd e)
					| Sharp_finally e -> (string_of_int num)^"throw " ^ e ^":"^(string_of_sharp st)
					| _   -> (string_of_int num)^"throw "^(string_of_sharp st))
		 | _ -> (match eo with 
					| Sharp_prog_var e -> (string_of_int num)^"throw " ^ (snd e)
					| Sharp_finally e ->(string_of_int num)^ "throw " ^ e ^":" ^(string_of_sharp st)
					| _   -> (string_of_int num)^"throw "^(string_of_sharp st)))end 
  | SCall ({exp_scall_type = _;
	   exp_scall_method_name = id;
	   exp_scall_arguments = idl;
	   exp_scall_visible_names = _;
	   exp_scall_pos = l;
	   exp_scall_id = scall_id}) -> 
	   "scall:"^(string_of_int num)^(string_of_space level)^(string_of_int scall_id)^" "^ id ^ "(" ^ (string_of_ident_list idl ",") ^ ")" 
  | Seq ({exp_seq_type = _;
	  exp_seq_exp1 = e1;
	  exp_seq_exp2 = e2;
	  exp_seq_pos = l}) -> 
	  "seq"^(string_of_int num)^(string_of_exp2 e1 level (num+1)) ^ ";\n" ^ (string_of_exp2 e2 level (num+1))^
	  "\n{"^(string_of_space level)^ (string_of_label_map l.state) ^"} \n"^"seq loc:"^(string_of_full_loc l.pos)^"\n"
  | This _ -> "this"^(string_of_int num)^(string_of_space level)^"this"
  | Var ({exp_var_type = _;
	  exp_var_name = id;
	  exp_var_pos = l}) -> "var:"^(string_of_int num)^(string_of_space level)^id 
  | VarDecl ({exp_var_decl_type = t;
	      exp_var_decl_name = id;
	      exp_var_decl_pos = _}) -> 
	      "vardecl:"^(string_of_int num)^(string_of_space level)^(string_of_typ t) ^" "^ id (*^ (string_of_exp e1) ^ ";\n" ^ (string_of_exp e2)*)
  | Unit l                     -> ""
  | While ({exp_while_condition = id;
	    exp_while_body = e;
	    exp_while_spec = fl;
	    exp_while_pos = l})  -> 
	    (string_of_int num)^"while " ^ id ^ (string_of_struc_formula fl) ^ "\n"^(string_of_space level)^"{\n" ^ (string_of_exp2 e (level+1) (num+1)) ^ "\n}\n"
  | Unfold ({exp_unfold_var = sv}) -> (string_of_int num)^(string_of_space level)^"unfold " ^ (string_of_spec_var sv)
  | Try b -> 
	let c = b.exp_catch_clause.exp_catch_flow_type in
	(string_of_int num)^(string_of_space level)^"try \n"^(string_of_exp2 b.exp_try_body (level+1) (num+1))^"\n"^(string_of_space level)^"catch ("^ (string_of_int (fst c))^","^(string_of_int (snd c))^")="^(Util.get_closest c)^ 
				(match b.exp_catch_clause.exp_catch_flow_var with 
					| Some c -> (" @"^c^" ")
					| _ -> " ")^
				 (match b.exp_catch_clause.exp_catch_var with 
					| Some (a,b) -> ((string_of_typ a)^":"^b^" ")
					| _ -> " ")^") \n\t"^(string_of_exp2 b.exp_catch_clause.exp_catch_body level (num+1))
;;
*)

(* pretty printing for one data declaration*)
let string_of_decl d = match d with 
 | (t, id)             -> (string_of_typ t) ^ " " ^ id 
;;           

(* function to print a list of typed_ident *) 
let rec string_of_decl_list l c = match l with 
  | []               -> ""
  | h::[]            -> "  " ^ string_of_decl h 
  | h::t             -> "  " ^ (string_of_decl h) ^ c ^ (string_of_decl_list t c)
;;

(* pretty printing for a data declaration *)
let string_of_data_decl d = "data " ^ d.data_name ^ " {\n" ^ (string_of_decl_list d.data_fields "\n") ^ "\n}"
;;


(* pretty printing for a view *)
let string_of_view_decl v = "view " ^ v.view_name ^ "<" ^ (string_of_spec_var_list v.view_vars) ^ ">=" ^
                            (string_of_struc_formula v.view_formula) 
  ^ "\n\tinv " ^ (string_of_pure_formula (fst v.view_user_inv))
  ^ "\n\tunstruc_f" ^(string_of_formula v.view_un_struc_formula)
  ^ "\n\txform " ^ (string_of_pure_formula (fst v.view_x_formula))
  ^ "\n\t view_base_case: "^
  (match v.view_base_case with 
	| None -> "none " 
	|Some (s1,(s3,s2)) -> ((string_of_pure_formula s1)^"->"^(string_of_pure_formula_branches (s3, s2))))
    

(* pretty printing for a procedure *)
let string_of_proc_decl p level= 
  let locstr = (string_of_full_loc p.proc_loc)  
  in  (string_of_typ p.proc_return) ^ " " ^ p.proc_name ^ "(" ^ (string_of_decl_list p.proc_args ",") ^ ")\n" 
  ^ "static " ^ (string_of_struc_formula p.proc_static_specs) ^ "\n"
  ^ "dynamic " ^ (string_of_struc_formula p.proc_dynamic_specs) ^ "\n"
  ^ (if U.empty p.proc_by_name_params then "" 
	 else ("\nref " ^ (String.concat ", " (List.map string_of_spec_var p.proc_by_name_params)) ^ "\n"))
  ^ (match p.proc_body with 
       | Some e -> (string_of_exp e (level+1)) ^ "\n\n"
	   | None   -> "\n") ^ locstr
;; 

(* pretty printing for a list of data_decl *)
let rec string_of_data_decl_list l (buffer:GSourceView.source_buffer) = match l with 
 | []        -> buffer#insert ("")
 | h::[]     -> buffer#insert (string_of_data_decl h) 
 | h::t      -> buffer#insert ((string_of_data_decl h) ^ "\n");string_of_data_decl_list t buffer
;;

(* pretty printing for a list of proc_decl *)
let rec string_of_proc_decl_list l (buffer:GSourceView.source_buffer)= match l with 
 | []        -> buffer#insert ("")
 | h::t      -> let end_iter= buffer#get_iter `END in 
		let proc_name = h.proc_name in
		let mark1 = {loc_name=("pd_"^proc_name^"_st");loc_offset=end_iter#offset} in
			buffer#insert((string_of_proc_decl h 0)^"\n\n");loc_mark_list := mark1::!loc_mark_list;
			let cur_end_iter = buffer#get_iter `END in
			let mark2 = {loc_name=("pd_"^proc_name^"_en");loc_offset=cur_end_iter#offset} in 
				loc_mark_list := mark2::!loc_mark_list;
				(string_of_proc_decl_list t buffer)
;;

let rec search_mark_list (name:string) (marker_list:loc_mark list) = match marker_list with
	|[] -> raise Not_found
	|m::rest -> prerr_endline (sprintf "name:%s;offset:%i" m.loc_name m.loc_offset);if (m.loc_name = name) then m else search_mark_list name rest

(* pretty printing for a list of view_decl *)
let rec string_of_view_decl_list l (buffer:GSourceView.source_buffer)= match l with 
 | []        -> buffer#insert ("")
 | h::[]     -> buffer#insert (string_of_view_decl h) 
 | h::t      -> buffer#insert((string_of_view_decl h) ^ "\n");(string_of_view_decl_list t buffer)
;;

(* pretty printing for a program written in core language *)
(*let string_of_program p (buffer:GSourceView.source_buffer)= buffer#insert ("\n" ^ (string_of_data_decl_list p.prog_data_decls) ^ "\n\n" ^ 
                          (string_of_view_decl_list p.prog_view_decls) ^ "\n\n" ^ 
                          (string_of_proc_decl_list p.prog_proc_decls) ^ "\n")
;;*)

let string_of_program p (buffer:GSourceView.source_buffer)= buffer#set_text ""; buffer#insert ("\n");
				(string_of_data_decl_list p.prog_data_decls buffer);
				buffer#insert( "\n\n"); 
         	                (string_of_view_decl_list p.prog_view_decls buffer);
				buffer#insert ("\n\n");
                          	(string_of_proc_decl_list p.prog_proc_decls buffer); 
				buffer#insert ("\n")
;;



(*
  Created 22-Feb-2006

  Pretty printing fo the AST for the core language
*)



