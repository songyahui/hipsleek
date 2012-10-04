open Globals
open Gen

module DD = Debug
module Err = Error
module CP = Cpure
module CF = Cformula
module MCP = Mcpure
module CEQ = Checkeq
module TP = Tpdispatcher
module SAU = Sautility

(*temporal: name * hrel * definition body*)
type hp_rel_def = CP.rel_cat * CF.h_formula * CF.formula

(*hp_name * args * condition * lhs * rhs *)
type par_def_w_name =  CP.spec_var * CP.spec_var list * CF.formula * (CF.formula option) *
      (CF.formula option)

let string_of_par_def_w_name pd=
  let pr1 = !CP.print_sv in
  let pr4 = !CP.print_svl in
  let pr2 = Cprinter.prtt_string_of_formula in
  let pr3 = fun x -> match x with
    | None -> "None"
    | Some f -> pr2 f
  in
  let pr = pr_penta pr1 pr4 pr2 pr3 pr3 in
  pr pd

(**=================================**)

let rec elim_redundant_paras_lst_constr_x prog constrs =
  let drop_cands = List.concat (List.map (fun c -> check_dropable_paras_constr prog c) constrs) in
  let rec partition_cands_by_hp_name drops parts=
    match drops with
      | [] -> parts
      | (hp_name,ids)::xs ->
          let part,remains= List.partition (fun (hp_name1,_) -> CP.eq_spec_var hp_name1 hp_name) xs in
          partition_cands_by_hp_name remains (parts@[[(hp_name,ids)]@part])
  in
  let intersect_cand_one_hp ls=
    let hp_names,cands = List.split ls in
    (* let _ = Debug.info_pprint ("   hprel: " ^ (!CP.print_svl hp_names)) no_pos in *)
    (* let _ = Debug.info_pprint ("     cands: " ^ (let pr = pr_list Cprinter.string_of_list_int in pr cands)) no_pos in *)
    let locs = List.fold_left (fun ls1 ls2 -> Gen.BList.intersect_eq (=) ls1 ls2) (List.hd cands) (List.tl cands) in
    if locs = [] then []
    else [(List.hd hp_names, locs)]
  in
  let rec drop_invalid_group ls res=
    match ls with
      | [] -> res
      | (hp,locs)::ss -> if locs = [-1] then drop_invalid_group ss res
          else drop_invalid_group ss (res@[(hp,locs)])
  in
  (*group cands into each hp*)
  let groups = partition_cands_by_hp_name drop_cands [] in
  (*each hp, intersect all candidate drops*)
  let drop_hp_args = List.concat (List.map intersect_cand_one_hp groups) in
  let drop_hp_args = drop_invalid_group drop_hp_args [] in
  let _ = Debug.info_pprint ("  drops: " ^ (let pr = pr_list (pr_pair !CP.print_sv (pr_list string_of_int))
                                                         in pr drop_hp_args)) no_pos in
  let new_constrs = drop_process constrs drop_hp_args in
  (*find candidates in all assumes, if a case appears in all assmses => apply it*)
  new_constrs

and elim_redundant_paras_lst_constr prog hp_constrs =
  let pr = pr_list_ln Cprinter.string_of_hprel in
  Debug.no_1 "elim_redundant_paras_lst_constr" pr pr
      (fun _ ->  elim_redundant_paras_lst_constr_x prog hp_constrs) hp_constrs

(*each constraint, pick candidate args which can be droped in each hprel*)
and check_dropable_paras_constr prog constr:((CP.spec_var*int list) list) =
  Debug.ninfo_hprint (add_str "  assumption: " (Cprinter.string_of_hprel)) constr no_pos;
  let(lhs,rhs) = constr.CF.hprel_lhs,constr.CF.hprel_rhs in
  let _ = Debug.ninfo_pprint ("    RHS") no_pos in
  let l1 = check_dropable_paras_RHS prog rhs in
  let _ = Debug.ninfo_pprint ("    LHS") no_pos in
  let l2 = check_dropable_paras_LHS prog lhs rhs constr.CF.predef_svl in
  (l1@l2)

(*each hprel: check which arg is raw defined*)
and check_dropable_paras_RHS prog f:((CP.spec_var*int list) list)=
  (*RHS: dropable if para have just partial defined or more*)
  let def_vs_wo_args, _, _, hrs, _ = SAU.find_defined_pointers_raw prog f in
  let rec helper args res index=
    match args with
      | [] -> res
      | a::ass -> if (CP.mem_svl a def_vs_wo_args) then
            helper ass (res@[index]) (index+1)
          else helper ass res (index+1)
  in
  let check_dropable_each_pred hr =
    let (svar, exps,_) = hr in
    let _ = Debug.ninfo_pprint ("      hprel:  " ^ (CP.name_of_spec_var svar)) no_pos in
    let res = helper (List.concat (List.map CP.afv exps)) [] 0 in
    let _ = Debug.ninfo_pprint ("      cands: " ^ (Cprinter.string_of_list_int res)) no_pos in
    if res = [] then [(svar,[-1])] (*renturn -1 to indicate that none is allowed to drop*)
    else [(svar,res)]
  in
  List.concat (List.map check_dropable_each_pred hrs)

(*each hprel: check which arg is either defined or not-in-used*)
and check_dropable_paras_LHS prog f1 f2 predef :((CP.spec_var*int list) list)=
  let def_vs, hp_paras, _, _, _ = SAU.find_defined_pointers prog f1 predef in
  let rec helper args res index=
    match args with
      | [] -> res
      | a::ass -> if ((CP.mem_svl a (def_vs@predef)) || (is_not_used a (f1,f2))) then
            helper ass (res@[index]) (index+1)
          else helper ass res (index+1)
  in
  let check_dropable_each_hp (svar, args) =
    let _ = Debug.ninfo_pprint ("      hprel:  " ^ (CP.name_of_spec_var svar) ^ (!CP.print_svl args)) no_pos in
    let res = helper args [] 0 in
    let _ = Debug.ninfo_pprint ("      cands: " ^ (Cprinter.string_of_list_int res)) no_pos in
    if res = [] then [(svar,[-1])] (*renturn -1 to indicate that none is allowed to drop*)
    else [(svar, res)]
  in
  List.concat (List.map check_dropable_each_hp hp_paras)


and drop_process (constrs: CF.hprel list) (drlocs: (CP.spec_var* int list) list): ( CF.hprel list) =
  List.map (fun c -> drop_process_one_constr c drlocs) constrs

and drop_process_one_constr (constr: CF.hprel) drlocs: CF.hprel =
  {constr with
      CF.hprel_lhs = (filter_hp_rel_args_f constr.CF.hprel_lhs drlocs);
      CF.hprel_rhs = (filter_hp_rel_args_f constr.CF.hprel_rhs drlocs)}


and filter_hp_rel_args_f (f: CF.formula) (drlocs: (CP.spec_var* int list) list)=
  (* let rels, _ = List.split drlocs in *)
  let rec helper f drlocs = match f with
    | CF.Base fb -> CF.Base {fb with CF.formula_base_heap = filter_hp_rel_args fb.CF.formula_base_heap drlocs;}
    | CF.Or orf -> CF.Or {orf with CF.formula_or_f1 = helper orf.CF.formula_or_f1 drlocs;
                CF.formula_or_f2 = helper orf.CF.formula_or_f2 drlocs;}
    | CF.Exists fe -> CF.Exists {fe with CF.formula_exists_heap =  filter_hp_rel_args fe.CF.formula_exists_heap drlocs;}
  in 
  helper f drlocs

and filter_hp_rel_args (hf: CF.h_formula) (drlocs: (CP.spec_var* int list) list): CF.h_formula=
  (* let rels, _ = List.split drlocs in *)
  let rec look_up_drop_hp hp drops=
    match drops with
      | [] -> []
      | (hp1, locs)::ss -> if CP.eq_spec_var hp hp1 then locs
          else look_up_drop_hp hp ss
  in
  let rec helper hf0=
    match hf0 with
      | CF.Star {CF.h_formula_star_h1 = hf1;
                 CF.h_formula_star_h2 = hf2;
                 CF.h_formula_star_pos = pos} ->
          let n_hf1 = helper hf1 in
          let n_hf2 = helper hf2 in
          (match n_hf1,n_hf2 with
            | (CF.HEmp,CF.HEmp) -> CF.HEmp
            | (CF.HEmp,_) -> n_hf2
            | (_,CF.HEmp) -> n_hf1
            | _ -> CF.Star {CF.h_formula_star_h1 = n_hf1;
			                CF.h_formula_star_h2 = n_hf2;
			                CF.h_formula_star_pos = pos}
          )
      | CF.Conj { CF.h_formula_conj_h1 = hf1;
		          CF.h_formula_conj_h2 = hf2;
		          CF.h_formula_conj_pos = pos} ->
          let n_hf1 = helper hf1 in
          let n_hf2 = helper hf2 in
          CF.Conj { CF.h_formula_conj_h1 = n_hf1;
		            CF.h_formula_conj_h2 = n_hf2;
		            CF.h_formula_conj_pos = pos}
      | CF.Phase { CF.h_formula_phase_rd = hf1;
		           CF.h_formula_phase_rw = hf2;
		           CF.h_formula_phase_pos = pos} ->
          let n_hf1 = helper hf1 in
          let n_hf2 = helper hf2 in
          CF.Phase { CF.h_formula_phase_rd = n_hf1;
		             CF.h_formula_phase_rw = n_hf2;
		             CF.h_formula_phase_pos = pos}
      | CF.DataNode hd -> hf0
      | CF.ViewNode hv -> hf0
      | CF.HRel (sv, args, l) ->
	            let locs =  look_up_drop_hp sv drlocs in
                if locs = [] then hf0
                else
                  begin
                    let rec filter_args args new_args index=
                      match args with
                        | [] -> new_args
                        | a::ss -> if List.exists (fun id -> id = index) locs then
                              filter_args ss new_args (index+1)
                            else filter_args ss (new_args@[a]) (index+1)
                    in
	                let new_args = filter_args args [] 0 in
	                if((List.length new_args) == 0) then CF.HEmp
	                else (CF.HRel (sv, new_args, l))
	              end
      | CF.Hole _
      | CF.HTrue
      | CF.HFalse
      | CF.HEmp -> hf0
  in
  helper hf

and is_not_used sv constr=
  let lhs, rhs = constr in
  (is_not_used_RHS sv rhs) && (is_not_connect_LHS sv rhs lhs)

and is_not_used_RHS (v: CP.spec_var)(f: CF.formula): bool = 
  let hds, hvs, hrs = CF.get_hp_rel_formula f in
  let eqNulls = match f with
    |CF.Base  ({CF.formula_base_pure = p1})
    |CF.Exists ({ CF.formula_exists_pure = p1}) -> (
      let eqNull1, eqNull2 =  List.split (MCP.ptr_equations_with_null p1) in
      CP.remove_dups_svl (eqNull1@eqNull2)
    )
    |CF.Or f  -> report_error no_pos "not handle yet"
  in
  let rhs_vs = (eqNulls) @ (List.map (fun hd -> hd.CF.h_formula_data_node) hds) @ (List.map (fun hv -> hv.CF.h_formula_view_node) hvs)  in
  let get_svars el = List.concat (List.map (fun c -> [CP.exp_to_spec_var c] ) el) in
  let rel_args =List.concat ( List.map (fun (_,el,_) -> get_svars el) hrs) in
  let rhs_vs = rhs_vs@rel_args in
  let str = List.fold_left (fun a b ->  (CP.name_of_spec_var b ^ "," ^ a )) "" rhs_vs in
  let _ = Debug.ninfo_pprint ("RHS vars " ^ str) no_pos in
  let b = List.exists (fun c-> if(CP.eq_spec_var v c) then true else false) rhs_vs in
  if(b) then false 
  else true

and is_not_connect_LHS (v: CP.spec_var)(f: CF.formula)(f2:CF.formula): bool = 
  let hds, hvs, hrs = CF.get_hp_rel_formula f in
  let hds = List.filter (fun c -> not(is_not_used_RHS c.CF.h_formula_data_node f2)) hds in
  let hvs = List.filter (fun c -> not(is_not_used_RHS c.CF.h_formula_view_node f2)) hvs in
  let node_args = (List.concat (List.map (fun hd -> hd.CF.h_formula_data_arguments) hds)) @ (List.concat(List.map (fun hv -> hv.CF.h_formula_view_arguments) hvs)) in
  let node_args = List.filter (fun c -> CP.is_node_typ c) node_args in
  let b = List.exists (fun c-> if(CP.eq_spec_var v c) then true else false) node_args in
  if(b) then false
  else true

(*analysis unknown information*)
let rec analize_unk_one prog constr =
  let _ = Debug.info_pprint ("   hrel: " ^ (Cprinter.string_of_hprel constr)) no_pos in
 (*remove hrel and returns hprel_args*)
  (*lhs*)
  let lhs1,lhrels = SAU.drop_get_hrel constr.CF.hprel_lhs in
  (*rhs*)
  let rhs1,rhrels = SAU.drop_get_hrel constr.CF.hprel_rhs in
(*find fv of lhs + rhs wo hrels*)
  let lsvl = SAU.get_raw_defined_w_pure prog lhs1 in
  let rsvl = SAU.get_raw_defined_w_pure prog rhs1 in
  (*find diff for each hrel*)
  let rec helper args res index all=
    match args with
      | [] -> res
      | a::ass -> if (CP.mem_svl a all) then
            helper ass res (index+1) all
          else helper ass (res@[index]) (index+1) all
  in
  let get_unk_ptr all_ptrs (hp_name, args)=
    (* if all_ptrs = [] then [(hp_name,[-1])] (\*[] mean dont have any information*\) *)
    (* else *)
      begin
          let res = helper args [] 0 all_ptrs in
          if res = [] then [(hp_name,[-1])] (*renturn -1 to indicate that none is allowed to drop*)
          else [(hp_name, res)]
      end
  in
  (*return*)
  List.concat (List.map (get_unk_ptr (lsvl@rsvl)) (lhrels@rhrels))

(*this method has the same structure with elim_redundant_paras_lst_constr_x,
should use higher-order when stab.*)
and analize_unk prog constrs =
  let unk_cands = List.concat (List.map (analize_unk_one prog) constrs) in
  let rec partition_cands_by_hp_name unks parts=
    match unks with
      | [] -> parts
      | (hp_name,ids)::xs ->
          let part,remains= List.partition (fun (hp_name1,_) -> CP.eq_spec_var hp_name1 hp_name) xs in
          partition_cands_by_hp_name remains (parts@[[(hp_name,ids)]@part])
  in
  let intersect_cand_one_hp ls=
    let hp_names,cands = List.split ls in
    (* let _ = Debug.info_pprint ("   hprel: " ^ (!CP.print_svl hp_names)) no_pos in *)
    (* let _ = Debug.info_pprint ("     cands: " ^ (let pr = pr_list Cprinter.string_of_list_int in pr cands)) no_pos in *)
    let locs = List.fold_left (fun ls1 ls2 -> Gen.BList.intersect_eq (=) ls1 ls2) (List.hd cands) (List.tl cands) in
    if locs = [] then []
    else [(List.hd hp_names, locs)]
  in
  let rec drop_invalid_group ls res=
    match ls with
      | [] -> res
      | (hp,locs)::ss -> if locs = [-1] then drop_invalid_group ss res
          else drop_invalid_group ss (res@[(hp,locs)])
  in
  (*group cands into each hp*)
  let groups = partition_cands_by_hp_name unk_cands [] in
  (*each hp, intersect all candidate unks*)
  let unk_hp_args1 = List.concat (List.map intersect_cand_one_hp groups) in
  let unk_hp_args2 = drop_invalid_group unk_hp_args1 [] in
  (* let _ = Debug.info_pprint ("  unks: " ^ (let pr = pr_list (pr_pair !CP.print_sv (pr_list string_of_int)) *)
  (*  in pr unk_hp_args2)) no_pos *)
  (* in *)
  List.map (update_unk_one_constr unk_hp_args2) constrs

and update_unk_one_constr unk_hp_locs constr=
  let lhprels = CF. get_HRels_f constr.CF.hprel_lhs in
  let rhprels = CF. get_HRels_f constr.CF.hprel_rhs in
  let rec retrieve_args_one_hp ls (hp,args)=
    match ls with
      | [] -> []
      | (hp1,locs)::ss -> if CP.eq_spec_var hp hp1 then
            SAU.retrieve_args_from_locs args locs 0 []
          else retrieve_args_one_hp ss (hp,args)
  in
  let unk_svl = List.concat (List.map
              (retrieve_args_one_hp unk_hp_locs) (lhprels@rhprels)) in
  let new_constr ={constr
     with CF.unk_svl = CP.remove_dups_svl (constr.CF.unk_svl@unk_svl)}
  in
  let _ = Debug.info_pprint ("   new hrel: " ^
              (Cprinter.string_of_hprel new_constr)) no_pos in
  new_constr

(*END first step*)
(*=======================*)
(*should we mkAnd f1 f2*)
let rec find_defined_pointers_two_formulas_x prog f1 f2 predef_ptrs=
  let (def_vs1, hds1, hvs1, hrs1, eqs1) = SAU.find_defined_pointers_raw prog f1 in
  let (def_vs2, hds2, hvs2, hrs2, eqs2) = SAU.find_defined_pointers_raw prog f2 in
  SAU.find_defined_pointers_after_preprocess prog (def_vs1@def_vs2) (hds1@hds2) (hvs1@hvs2)
      (hrs2) (eqs1@eqs2) predef_ptrs

and find_defined_pointers_two_formulas prog f1 f2 predef_ptrs=
  let pr1 = !CP.print_svl in
  let pr2 = pr_list_ln (pr_pair !CP.print_sv pr1) in
  (* let pr3 = fun x -> Cprinter.string_of_h_formula (CF.HRel x) in *)
  let pr4 = fun (a1, a2, _, _, _) ->
      let pr = pr_pair pr1 pr2 in pr (a1,a2)
  in
  Debug.no_3 "find_defined_pointers_two_formulas" Cprinter.prtt_string_of_formula Cprinter.prtt_string_of_formula pr1 pr4
      (fun _ _ _ -> find_defined_pointers_two_formulas_x prog f1 f2 predef_ptrs) f1 f2 predef_ptrs

(*unilities for computing partial def*)
let rec lookup_undef_args args undef_args def_ptrs=
  match args with
    | [] -> undef_args
    | a::ax -> if CP.mem_svl a def_ptrs then (*defined: omit*)
          lookup_undef_args ax undef_args def_ptrs
        else (*undefined *)
          lookup_undef_args ax (undef_args@[a]) def_ptrs

(*END unilities for computing partial def*)

(*check_partial_def_eq: to remove duplicate and identify terminating condition*)
let check_partial_def_eq (hp1, args1, cond1, olhs1, orhs1) (hp2, args2, cond2, olhs2, orhs2)=
  if (CP.eq_spec_var hp1 hp2) then (*if not the same hp, fast return*)
  (*form a subst*)
    let subst = List.combine args1 args2 in
    let checkeq_w_option of1 of2=
      match of1, of2 with
        | None,None -> true
        | Some _, None -> false
        | None, Some _ -> false
        | Some f1, Some f2 ->
          (*subs*)
            let f1_subst = CF.subst subst f1 in
	    let hvars = List.map (fun c -> CP.full_name_of_spec_var c) (CF.get_hp_rel_name_formula f1_subst @ CF.get_hp_rel_name_formula f2) in
            let r,_ (*map*) =  CEQ.checkeq_formulas hvars f1_subst f2 in
            r
    in
    (checkeq_w_option olhs1 olhs2) &&
        (checkeq_w_option orhs1 orhs2)
  else false

(*collect partial def ---> hp*)
let rec collect_par_defs_one_side_one_hp_x prog lhs rhs (hrel, args) def_ptrs
      rhrels eq hd_nodes hv_nodes=
  begin
      (*old code*)
      let undef_args = lookup_undef_args args [] def_ptrs in
      let test1= (List.length undef_args) = 0 in
        (*case 1*)
        (*this hp is well defined, synthesize partial def*)
      let keep_ptrs = SAU.loop_up_closed_ptr_args prog hd_nodes hv_nodes args in
      let r = CF.drop_data_view_hrel_nodes lhs SAU.check_nbelongsto_dnode SAU.check_nbelongsto_vnode SAU.check_neq_hrelnode keep_ptrs keep_ptrs []
      in
      let test2 = (not (SAU.is_empty_f r)) && test1 in
      if test2 then
        let r = (hrel, args, r, Some r, None) in
        let _ =  DD.info_pprint ("  partial defs - one side: \n" ^
          (let pr =  string_of_par_def_w_name in pr r) ) no_pos in
        [r]
        (* let closed_args = loop_up_ptr_args prog hd_nodes hv_nodes args in *)
      (* (\*for debugging*\) *)
      (* Debug.info_hprint (add_str "closed args: " (!CP.print_svl)) closed_args no_pos; *)
      (* (\*END*\) *)
      (* let diff = Gen.BList.difference_eq CP.eq_spec_var closed_args (def_ptrs@args) in *)
      (*   if (List.length diff) = 0 then *)
      (*     let r = CF.drop_data_view_hrel_nodes lhs check_nbelongsto_dnode check_nbelongsto_vnode *)
      (*       check_neq_hrelnode closed_args closed_args [] *)
      (*     in *)
      (*     [(hrel, args, r, Some r, None)] *)
      else
    (*CASE2: hp1(x1,x2,x3) --> h2(x1,x2,x3)* formula: hp such that have the same set of args in both sides*)
          collect_par_defs_two_side_one_hp prog lhs rhs (hrel, args) rhrels hd_nodes hv_nodes
end

and collect_par_defs_one_side_one_hp prog lhs rhs (hrel, args) def_ptrs
      rhrels eq hd_nodes hv_nodes=
  let pr1 = pr_pair !CP.print_sv !CP.print_svl in
  let pr2 = Cprinter.prtt_string_of_formula in
  let pr3 = pr_list_ln string_of_par_def_w_name in
   Debug.no_2 "collect_par_defs_one_side_one_hp" pr1 pr2 pr3
       (fun _ _ -> collect_par_defs_one_side_one_hp_x prog lhs rhs (hrel, args) def_ptrs
       rhrels eq hd_nodes hv_nodes) (hrel, args) lhs

(*collect hp1(x1,x2,x3) ---> hp2(x1,x2,x3) * F  partial def *)
(*todo: more general form: collect hp1(x1,x2,x3) ---> hp2(x1,x2) * F:
 x3 is defined/unknown/predef  partial def *)
and collect_par_defs_two_side_one_hp_x prog lhs rhs (hrel, args) rhs_hrels hd_nodes hv_nodes=
  let args0 = CP.remove_dups_svl args in
  let rec find_hrel_w_same_args ls r=
    match ls with
      | [] -> r
      | (hp, args1)::ss ->
          let args11 = CP.remove_dups_svl args1 in
          let diff = Gen.BList.difference_eq CP.eq_spec_var args11 args0 in
          if diff = [] then
            (*todo: find condition. for implication*)
            (*currently just check there exists conditions contain args1*)
           (
               let _, mf, _, _, _ = CF.split_components lhs in
               let svl = CP.fv (MCP.pure_of_mix mf) in
               if(List.exists (fun v ->  CP.mem_svl v svl) args1) then
            (*exist*) find_hrel_w_same_args ss r
               else
                 find_hrel_w_same_args ss (r@[hp]) (*collect it*)
           )
          else find_hrel_w_same_args ss r
  in
    (*find all hrel in rhs such that cover the same set of args*)
  let r_selected_hrels = find_hrel_w_same_args rhs_hrels [] in
  let keep_ptrs = SAU.loop_up_closed_ptr_args prog hd_nodes hv_nodes args in
  let build_par_def hp=
    let r = CF.drop_data_view_hrel_nodes rhs SAU.check_nbelongsto_dnode SAU.check_nbelongsto_vnode SAU.check_neq_hrelnode keep_ptrs keep_ptrs [hp] in
    (hrel, args, r, None, Some r)
  in
  let r = List.map build_par_def r_selected_hrels in
  let _ =  DD.info_pprint ("  partial defs - two side: \n" ^
          (let pr = pr_list_ln string_of_par_def_w_name in pr r) ) no_pos in
  r

and collect_par_defs_two_side_one_hp prog lhs rhs (hrel, args) rhs_hrels hd_nodes hv_nodes=
  let pr1 = pr_pair !CP.print_sv !CP.print_svl in
  let pr2 =  pr_list_ln pr1 in
  let pr3 = pr_list_ln string_of_par_def_w_name in
  Debug.no_2 "collect_par_defs_two_side_one_hp" pr1 pr2 pr3
      (fun _ _ -> collect_par_defs_two_side_one_hp_x prog lhs rhs (hrel, args) rhs_hrels hd_nodes hv_nodes)
      (hrel, args) rhs_hrels

let collect_par_defs_recursive_hp_x prog lhs rhs (hrel, args) rec_args def_ptrs hrel_vars eq hd_nodes hv_nodes dir=
  let build_partial_def ()=
    let keep_ptrs = SAU.loop_up_closed_ptr_args prog hd_nodes hv_nodes
      (CP.remove_dups_svl (args@rec_args)) in
    let plhs = CF.drop_data_view_hrel_nodes lhs SAU.check_nbelongsto_dnode SAU.check_nbelongsto_vnode SAU.check_neq_hrelnode keep_ptrs keep_ptrs [hrel] in
     let prhs = CF.drop_data_view_hrel_nodes rhs SAU.check_nbelongsto_dnode SAU.check_nbelongsto_vnode SAU.check_neq_hrelnode keep_ptrs keep_ptrs [hrel] in
     (*find which formula contains root args*)
     let _ = Debug.ninfo_pprint ("lpdef: " ^ (Cprinter.prtt_string_of_formula plhs)) no_pos in
     let _ = Debug.ninfo_pprint ("rpdef: " ^ (Cprinter.prtt_string_of_formula prhs)) no_pos in
     let _ = Debug.ninfo_pprint ("args: " ^ (!CP.print_svl args)) no_pos in
     let _ = Debug.ninfo_pprint ("rec_args: " ^ (!CP.print_svl rec_args)) no_pos in
     if dir then (*args in lhs*)
         begin
         let ptrs1, _,_, _,_ = SAU.find_defined_pointers_raw prog plhs in
         if CP.mem_svl (List.hd args) ptrs1 then
           [(hrel , args ,plhs, Some prhs, Some plhs) ]
         else
           [(hrel , rec_args ,plhs, Some plhs, Some prhs) ]
         end
     else
       let ptrs1, _,_, _,_ = SAU.find_defined_pointers_raw prog prhs in
        if CP.mem_svl (List.hd args) ptrs1 then
           [(hrel , args ,plhs, Some plhs, Some prhs) ]
         else
           [(hrel , rec_args ,plhs, Some prhs, Some plhs) ]
  in
  let undef_args = lookup_undef_args args [] (def_ptrs) in
  if undef_args = [] then (build_partial_def())
  else []

let collect_par_defs_recursive_hp prog lhs rhs (hrel, args) args2 def_ptrs hrel_vars eq hd_nodes hv_nodes dir=
  let pr1 = !CP.print_svl in
  let pr2 = (pr_pair !CP.print_sv pr1) in
  let pr3 = pr_list_ln string_of_par_def_w_name in
  Debug.no_2 "collect_par_defs_recursive_hp" pr2 pr1 pr3
      (fun  _ _ -> collect_par_defs_recursive_hp_x prog lhs rhs (hrel, args)
        args2 def_ptrs hrel_vars eq hd_nodes hv_nodes dir) (hrel, args) def_ptrs

let rec collect_par_defs_one_constr_new_x prog constr =
  let lhs, rhs = constr.CF.hprel_lhs, constr.CF.hprel_rhs in
  DD.info_pprint ">>>>>> collect partial def for hp_rel <<<<<<" no_pos;
  DD.info_pprint (" hp_rel: " ^ (Cprinter.prtt_string_of_formula lhs) ^ " ==> " ^
  (Cprinter.prtt_string_of_formula rhs)) no_pos;
  let rec get_rec_pair_hps ls (hrel1, arg1)=
    match ls with
      | [] -> []
      | (hrel2, arg2)::ss -> if CP.eq_spec_var hrel1 hrel2 then [((hrel1, arg1), (hrel2, arg2))]
          else get_rec_pair_hps ss (hrel1, arg1)
  in
  let cs_predef_ptrs = constr.CF.predef_svl@constr.CF.unk_svl in
  (*find all defined pointer (null, nodes) and recursive defined parameters (HP, arg)*)
  let l_def_ptrs, l_hp_args_name,l_dnodes, l_vnodes,leqs = SAU.find_defined_pointers prog lhs cs_predef_ptrs in
  (*should mkAnd lhs*rhs?*)
  let r_def_ptrs, r_hp_args_name, r_dnodes, r_vnodes, reqs = find_defined_pointers_two_formulas prog lhs rhs cs_predef_ptrs in
  (*CASE 1: formula --> hp*)
  (*remove dup hp needs to be process*)
  let check_hp_arg_eq (hp1, args1) (hp2, args2)=
    let rec eq_spec_var_list l1 l2=
      match l1,l2 with
        |[],[] -> true
        | v1::ls1,v2::ls2 ->
            if CP.eq_spec_var v1 v2 then
              eq_spec_var_list ls1 ls2
            else false
        | _ -> false
    in
    ((CP.eq_spec_var hp1 hp2) && (eq_spec_var_list args1 args2))
  in
  let lhps = (Gen.BList.remove_dups_eq check_hp_arg_eq (l_hp_args_name)) in
  let rhps = (Gen.BList.remove_dups_eq check_hp_arg_eq (r_hp_args_name)) in
  let total_hps = (Gen.BList.remove_dups_eq check_hp_arg_eq (lhps@rhps)) in
  let lpdefs = List.concat (List.map (fun hrel ->
      collect_par_defs_one_side_one_hp prog lhs rhs hrel
          (l_def_ptrs@cs_predef_ptrs) r_hp_args_name leqs l_dnodes l_vnodes)
                                lhps) in
  let rpdefs = List.concat (List.map (fun hrel ->
      collect_par_defs_one_side_one_hp prog lhs rhs hrel
          (l_def_ptrs@cs_predef_ptrs) [] (*pass [] to not exam case 2*)
          leqs l_dnodes l_vnodes)
                                rhps) in
  (*CASE2: hp1(x1,x2,x3) --> h2(x1,x2,x3)* formula: hp such that have the same set of args in both sides - call in side lhs*)
  (*CASE 3: recursive contraints*)
  let rec_pair_hps = List.concat (List.map (get_rec_pair_hps l_hp_args_name) r_hp_args_name) in
   (*for debugging*)
  (* let pr1 = (pr_pair !CP.print_sv !CP.print_svl) in *)
  (* let pr2 = pr_list_ln (pr_pair pr1 pr1) in *)
  (* Debug.info_hprint (add_str "  recursive pair: " (pr2)) rec_pair_hps no_pos; *)
  (*END for debugging*)
  let new_constrs, rec_pdefs =
    if rec_pair_hps = [] then
     (*drop constraints that have one hp after collect partial def*)
      let new_constrs=
        if (List.length total_hps) <= 1 then []
        else [constr]
      in (new_constrs, [])
    else
      let helper ((hp1,args1),(hp2,args2))=
        (*recompute defined ptrs*)
         let l_def_ptrs, _,_, _,_ = SAU.find_defined_pointers prog lhs (args2@cs_predef_ptrs) in
         (*should mkAnd lhs*rhs?*)
         let r_def_ptrs, _, _, _, _ = find_defined_pointers_two_formulas prog lhs rhs (args2@cs_predef_ptrs) in
        let r1 = collect_par_defs_recursive_hp prog lhs rhs (hp1,args1) args2
          (l_def_ptrs@r_def_ptrs@args2@cs_predef_ptrs) (l_hp_args_name@r_hp_args_name) (leqs@reqs)
          (l_dnodes@r_dnodes) (l_vnodes@r_vnodes) true in
        if r1 = [] then
          (*recompute defined ptrs*)
          let l_def_ptrs, _,_, _,_ = SAU.find_defined_pointers prog lhs (args1@cs_predef_ptrs) in
         (*should mkAnd lhs*rhs?*)
          let r_def_ptrs, _, _, _, _ = find_defined_pointers_two_formulas prog lhs rhs (args1@cs_predef_ptrs) in
          collect_par_defs_recursive_hp prog lhs rhs (hp2,args2) args1
              (l_def_ptrs@r_def_ptrs@args1@cs_predef_ptrs) (l_hp_args_name@r_hp_args_name) (leqs@reqs)
              (l_dnodes@r_dnodes) (l_vnodes@r_vnodes) false
        else r1
      in
      let rec_pdefs = List.concat (List.map helper rec_pair_hps) in
      (*drop constraints that have one hp after collect partial def*)
      let new_constrs=
        let num_hp = (List.length total_hps) in
        let num_pair_rec_hp = (List.length rec_pair_hps) in
        if (num_hp - num_pair_rec_hp) <= 1 then []
        else [constr]
      in (new_constrs, rec_pdefs)
  in
  (* DD.info_pprint ("  partial defs: \n" ^ *)
  (* (let pr = pr_list_ln string_of_par_def_w_name in pr (lpdefs @ rpdefs)) ) no_pos; *)
  DD.info_pprint ("  rec partial defs: \n" ^
  (let pr = pr_list_ln string_of_par_def_w_name in pr (rec_pdefs)) ) no_pos;
  (new_constrs,(lpdefs @ rpdefs @ rec_pdefs))

and collect_par_defs_one_constr_new prog constr =
  let pr1 = Cprinter.string_of_hprel in
  let pr2 = pr_list_ln string_of_par_def_w_name in
  let pr4 = pr_list_ln pr1 in
  let pr3 = (pr_pair pr4 pr2) in
  Debug.no_1 "collect_par_defs_one_constr_new" pr1 pr3
      (fun _ -> collect_par_defs_one_constr_new_x prog constr) constr

(* - collect partial def
  - simplify: remove constaints which have <= 1 hp
*)
let rec collect_partial_definitions_x prog constrs: (CF.hprel list * par_def_w_name list) =
  let simpl_constrs, par_defs = List.split (List.map (collect_par_defs_one_constr_new prog) constrs) in
  (List.concat simpl_constrs, List.concat par_defs)

and collect_partial_definitions prog constrs: (CF.hprel list * par_def_w_name list) =
  let pr1 = pr_list_ln Cprinter.string_of_hprel in
  let pr2 =  pr_list_ln string_of_par_def_w_name in
   Debug.no_1 "collect_partial_definitions" pr1 (pr_pair pr1 pr2)
 (fun _ -> collect_partial_definitions_x prog constrs) constrs


(* and get_def_by_substitute_constrs (constrs: (CF.formula * CF.formula) list): (par_def list) =  *)
(*   if(List.length constrs < 2) then [] *)
(*   else ( *)
(*     let defs_head = List.concat (List.map (fun c -> get_def_by_substitute_two_constr c (List.hd constrs)) (List.tl constrs)) in *)
(*     defs_head @ (get_def_by_substitute_constrs (List.tl constrs)) *)
(*   ) *)

(* and get_def_by_substitute_two_constr  (constr1: CF.formula * CF.formula)  (constr2: CF.formula * CF.formula): (par_def list) = *)
(*   let f11, f12 = constr1 in *)
(*   let f21, f22 = constr2 in *)
(*   Debug.ninfo_hprint (add_str "Test equiv formulae: " ( Cprinter.string_of_hprel_lhs_rhs)) (f11,f22) no_pos; *)
(*   let b1, mt1 = CEQ.checkeq_formulas [] f11 f22 in *)
(*   Debug.ninfo_hprint (add_str "Test equiv formulae: " ( Cprinter.string_of_hprel_lhs_rhs)) (f12,f21) no_pos; *)
(*   let b2, mt2 = CEQ.checkeq_formulas [] f12 f21 in *)
(*   let defs1 = if(b1) then ( *)
(*     let f_1 = CEQ.subst_with_mt (List.hd mt1) f12 in  *)
(* (\*change vars*\) *)
(*     (\*let f_2 = CEQ.subst_with_mt (List.hd mt1) f21 in *\) (\*not sound, should check if both var occur*\) *)
(*     Debug.ninfo_hprint (add_str "NEW ASSUME AFTER CHANGE VARS: " ( Cprinter.string_of_hprel_lhs_rhs)) (f_1,f21) no_pos; *)
(*     let (a, b) =  collect_par_defs_one_constr(f_1,f21) in  *)
(*     b *)
(*   ) *)
(*     else [] *)
(*   in *)
(*   let defs2 = if(b2) then  ( *)
(*     let f_1 = CEQ.subst_with_mt (List.hd mt1) f11 in  *)
(*     Debug.ninfo_hprint (add_str "NEW ASSUME AFTER CHANGE VAR: " ( Cprinter.string_of_hprel_lhs_rhs)) (f_1,f22) no_pos; *)
(*     let (a,b) = collect_par_defs_one_constr (f_1,f22) in *)
(*     b *)
(*   ) *)
(*     else [] *)
(*   in *)
(*   (defs1@defs2) *)

(*====================*)
let rec simplify_one_constr prog constr=
  let (lhs, rhs) = constr.CF.hprel_lhs,constr.CF.hprel_rhs in
  match lhs,rhs with
    | CF.Base lhs_b, CF.Base rhs_b ->
        let l,r,matched = simplify_one_constr_b prog lhs_b rhs_b in
        {constr with CF.predef_svl = constr.CF.predef_svl@matched;
            CF.hprel_lhs = CF.Base l;
            CF.hprel_rhs = CF.Base r;
        }
    | _ -> report_error no_pos "sa.simplify_one_constr"

and simplify_one_constr_b_x prog lhs_b rhs_b=
  (*return subst of args and add in lhs*)
  let check_eq_data_node dn1 dn2=
    CP.eq_spec_var dn1.CF.h_formula_data_node dn2.CF.h_formula_data_node
  in
  let check_eq_view_node vn1 vn2=
    (*return subst of args and add in lhs*)
    CP.eq_spec_var vn1.CF.h_formula_view_node vn2.CF.h_formula_view_node
  in
  let l_hds, l_hvs, l_hrs = CF.get_hp_rel_bformula lhs_b in
  let r_hds, r_hvs, r_hrs = CF.get_hp_rel_bformula rhs_b in
  DD.info_pprint (" input: " ^(Cprinter.prtt_string_of_formula_base lhs_b) ^ " ==> " ^
  (Cprinter.prtt_string_of_formula_base rhs_b)) no_pos;
  (*drop unused pointers in LHS*)
  DD.info_pprint "  drop not-in-used pointers" no_pos;
  let keep_hrels,keep_ptrs = List.split (List.map
    (fun (hrel, eargs, _) -> (hrel, List.concat (List.map CP.afv eargs)))
    (l_hrs@r_hrs) )
  in
  let lhs_b1 = SAU.keep_data_view_hrel_nodes_fb prog lhs_b (l_hds@r_hds) (l_hvs@r_hvs)
    (List.concat keep_ptrs) keep_hrels in
  (*pointers/hps matching LHS-RHS*)
  (*data nodes, view nodes, rel*)
  DD.info_pprint "  matching LHS-RHS" no_pos;
  let matched_data_nodes = Gen.BList.intersect_eq check_eq_data_node l_hds r_hds in
  let matched_view_nodes = Gen.BList.intersect_eq check_eq_view_node l_hvs r_hvs in
  let matched_hrel_nodes = Gen.BList.intersect_eq CF.check_eq_hrel_node l_hrs r_hrs in
  let hrels = List.map (fun (id,_,_) -> id) matched_hrel_nodes in
  let dnode_names = List.map (fun hd -> hd.CF.h_formula_data_node) matched_data_nodes in
  let vnode_names = List.map (fun hv -> hv.CF.h_formula_view_node) matched_view_nodes in
  Debug.info_pprint ("    Matching found: " ^ (!CP.print_svl (dnode_names@vnode_names@hrels))) no_pos;
  let lhs_nhf2,rhs_nhf2=
    if (dnode_names@vnode_names@hrels)=[] then lhs_b1.CF.formula_base_heap,rhs_b.CF.formula_base_heap
    else
      let lhs_nhf = CF.drop_data_view_hrel_nodes_hf lhs_b1.CF.formula_base_heap
        SAU.select_dnode SAU.select_vnode SAU.select_hrel dnode_names vnode_names hrels in
      let rhs_nhf = CF.drop_data_view_hrel_nodes_hf rhs_b.CF.formula_base_heap
        SAU.select_dnode SAU.select_vnode SAU.select_hrel dnode_names vnode_names hrels in
      (lhs_nhf,rhs_nhf)
  in
  (*remove duplicate pure formulas*)
  let lhs_nmf2 = CP.remove_redundant (MCP.pure_of_mix lhs_b1.CF.formula_base_pure) in
  let rhs_nmf2 = CP.remove_redundant (MCP.pure_of_mix rhs_b.CF.formula_base_pure) in
  let lhs_b2 = {lhs_b1 with CF.formula_base_heap = lhs_nhf2;
      CF.formula_base_pure = MCP.mix_of_pure lhs_nmf2
               } in
  let rhs_b2 = {rhs_b with CF.formula_base_heap = rhs_nhf2;
               CF.formula_base_pure = MCP.mix_of_pure rhs_nmf2} in
 (*pure subformulas matching LHS-RHS: drop RHS*)
  DD.info_pprint (" output: " ^(Cprinter.prtt_string_of_formula_base lhs_b2) ^ " ==> " ^
  (Cprinter.prtt_string_of_formula_base rhs_b2)) no_pos;
(lhs_b2, rhs_b2, dnode_names@vnode_names@hrels)

and simplify_one_constr_b prog lhs_b rhs_b=
  let pr = Cprinter.prtt_string_of_formula_base in
  Debug.no_2 "simplify_one_constr_b" pr pr (pr_triple pr pr !CP.print_svl)
      (fun _ _ -> simplify_one_constr_b_x prog lhs_b rhs_b) lhs_b rhs_b

let simplify_constrs_x prog constrs=
  List.map (simplify_one_constr prog) constrs

let simplify_constrs prog constrs=
   let pr = pr_list_ln (Cprinter.string_of_hprel) in
  Debug.no_1 "simplify_constrs" pr pr
      (fun _ -> simplify_constrs_x prog constrs) constrs


and get_only_hrel f = match f with 
  |CF.Base {CF.formula_base_heap = hf} -> (match hf with
      | CF.HRel hr -> hr
      | _ -> raise Not_found
  )
  |CF.Exists {CF.formula_exists_heap = hf} -> (match hf with
      | CF.HRel hr -> hr
      | _ -> raise Not_found
  )
  | CF.Or f  -> report_error no_pos "not handle yet"

(*todo: rhs is only hp with more than 1 param*)
let get_hp_split_cands_x constrs =
  let helper (lhs,rhs)=
    (*try(
        let sv,el,l = get_only_hrel rhs in
        if(List.length el >= 2) then [(CF.HRel (sv,el,l))]
        else []
    )
    with _ -> []*)
(*split all*)
    let hn, hv, hr = CF.get_hp_rel_formula lhs in
    let hn1, hv1, hr1 = CF.get_hp_rel_formula rhs in
    let cands = hr1 @ hr in
    let cands =  Gen.BList.remove_dups_eq (fun (hp1,_,_)  (hp2,_,_) ->
      CP.eq_spec_var hp1 hp2) cands in
    let cands = List.filter (fun (sv,el,l) ->  (List.length el) >= 2) cands in
    let cands = List.map (fun (sv,el,l) -> (CF.HRel (sv,el,l))) cands in
    cands 
  in
  (*remove duplicate*)
  let cands = (List.concat (List.map helper constrs)) in
  Gen.BList.remove_dups_eq (fun (CF.HRel (hp1,_,_)) (CF.HRel (hp2,_,_)) ->
      CP.eq_spec_var hp1 hp2) cands

let get_hp_split_cands constrs =
  let pr1 = pr_list_ln (pr_pair Cprinter.prtt_string_of_formula Cprinter.prtt_string_of_formula) in
  let pr2 = pr_list_ln (Cprinter.string_of_hrel_formula) in
  Debug.no_1 "get_hp_split_cands" pr1 pr2
  (fun _ -> get_hp_split_cands_x constrs) constrs

(*split one hp -> mutiple hp and produce corresponding heap formulas for substitution*)
let hp_split_x hps =
  (*each arg, create new hp and its corresponding HRel formula*)
  let helper1 l arg =
    let new_hp_name = Globals.hp_default_prefix_name ^ (string_of_int (Globals.fresh_int())) in
    let new_hp_sv = CP.SpecVar (HpT,new_hp_name, Unprimed) in
    (*should refresh arg*)
    (new_hp_sv, CF.HRel (new_hp_sv, [arg], l))
  in
  (*rhs is only hp with more than 1 parameter*)
  (*for each hp*)
  let helper hf =
    match hf with
      | (CF.HRel (sv,el,l)) ->
          let hps = List.map (helper1 l) el in
          let new_hp_names,new_hrel_fs = List.split hps in
          let new_hrels_comb = List.fold_left (fun hf1 hf2 -> CF.mkStarH hf1 hf2 l) (List.hd new_hrel_fs) (List.tl new_hrel_fs) in
          ((sv,new_hp_names),(sv, CF.HRel (sv,el,l), new_hrels_comb))
      | _ -> report_error no_pos "sa.hp_split_x: can not happen"
  in
  let res = List.map helper hps in
  List.split res

let hp_split hps =
  let pr1 = !CP.print_sv in
  let pr2 = !CP.print_svl in
  let pr3 = (pr_list (pr_pair pr1 pr2)) in
  let pr4 = Cprinter.string_of_h_formula in
  let pr5 = pr_list pr4 in
  let pr6 = pr_list (pr_triple pr1 pr4 pr4) in
   Debug.no_1 "hp_split" pr5 (pr_pair pr3 pr6)
       (fun _ -> hp_split_x hps) hps

let subst_constr_with_new_hps_x hp_constrs hprel_subst=
  let elim_first_arg (a1,a2,a3)= (a2,a3) in
  let new_hprel_subst = List.map elim_first_arg hprel_subst in
  let helper (l_constr, r_constr)=
    (CF.subst_hrel_f l_constr new_hprel_subst, CF.subst_hrel_f r_constr new_hprel_subst)
  in
  List.map helper hp_constrs

let subst_constr_with_new_hps hp_constrs hprel_subst=
  let pr1= pr_list_ln (pr_pair Cprinter.prtt_string_of_formula Cprinter.prtt_string_of_formula) in
  let pr2 = Cprinter.string_of_h_formula in
  let pr3 = fun (a1,a2,a3) -> let pr =pr_pair pr2 pr2 in pr (a2,a3) in
  let pr4 = pr_list_ln pr3 in
  Debug.no_2 "subst_constr_with_new_hps" pr1 pr4 pr1
      (fun _ _ -> subst_constr_with_new_hps_x hp_constrs hprel_subst) hp_constrs hprel_subst

(*return new contraints and hp split map *)
let split_hp_x (hp_constrs: (CF.formula * CF.formula) list): ((CF.formula * CF.formula) list *
          (CP.spec_var*CP.spec_var list) list * (CP.spec_var * CF.h_formula*CF.h_formula) list) =
  (*get hp candidates*)
  let split_cands = get_hp_split_cands hp_constrs in
  (*split  and get map*)
  let split_map,hprel_subst =  hp_split split_cands in
  (*subs old hrel by new hrels*)
  let new_constrs = subst_constr_with_new_hps hp_constrs hprel_subst in
  (new_constrs, split_map, hprel_subst)

let split_hp (hp_constrs: (CF.formula * CF.formula) list):((CF.formula * CF.formula) list *
 (CP.spec_var*CP.spec_var list) list * (CP.spec_var *CF.h_formula*CF.h_formula) list) =
  let pr1 =  pr_list_ln (pr_pair Cprinter.prtt_string_of_formula Cprinter.prtt_string_of_formula) in
  let pr2 = !CP.print_sv in
  let pr3 = !CP.print_svl in
  let pr4 = fun (a1,a2,_) -> (*ignore a3*)
      let pr = pr_pair pr1 (pr_list (pr_pair pr2 pr3)) in
      pr (a1, a2)
  in
  Debug.no_1 "split_hp" pr1 pr4
      (fun _ -> split_hp_x hp_constrs) hp_constrs

(*========subst==============*)
let rec check_unsat_x f=
  match f with
    | CF.Base fb -> check_inconsistency fb.CF.formula_base_heap fb.CF.formula_base_pure
    | CF.Or orf -> (check_unsat orf.CF.formula_or_f1) || (check_unsat orf.CF.formula_or_f2)
    | CF.Exists fe ->
        (*may not correct*)
        check_inconsistency fe.CF.formula_exists_heap fe.CF.formula_exists_pure

and check_unsat f=
  let pr1 = Cprinter.prtt_string_of_formula in
  let pr2 = string_of_bool in
  Debug.no_1 "check_unsat" pr1 pr2
      (fun _ -> check_unsat_x f) f

and check_inconsistency hf mixf=
  let hds, _, _ (*hvs, hrs*) =  CF.get_hp_rel_h_formula hf in
  (*currently we just work with data nodes*)
  let neqNulls = List.map (fun dn -> CP.mkNeqNull dn.CF.h_formula_data_node dn.CF.h_formula_data_pos) hds in
  let new_mf = MCP.mix_of_pure (CP.join_conjunctions neqNulls) in
  let cmb_mf = MCP.merge_mems mixf new_mf true in
  not (TP.is_sat_raw cmb_mf)

let subst_one_cs_w_one_partial_def f (hp_name, args, def_f)=
(*drop hrel and get current args*)
  let newf, argsl = CF.drop_hrel_f f [hp_name] in
  match argsl with
    | [] -> f
    | [eargs] ->
        begin
            (*to subst*)
        (*generate a susbst*)
        let args2= (List.fold_left List.append [] (List.map CP.afv eargs)) in
        DD.info_pprint ("   subst " ^ (Cprinter.prtt_string_of_formula def_f) ^ " ==> " ^ (!CP.print_sv hp_name)
                        ^ (!CP.print_svl args)) no_pos;
        (* DD.info_pprint ("   into " ^ (Cprinter.prtt_string_of_formula f)) no_pos; *)
        let subst = (List.combine args args2) in
        let def_f_subst = CF.subst subst def_f in
        (* DD.info_pprint ("   body after subst " ^ (Cprinter.prtt_string_of_formula def_f_subst)) no_pos; *)
        (*should remove duplicate*)
        let svl1 = CF.fv newf in
        let svl2 = CF.fv def_f_subst in
        let intersect = CP.intersect svl1 svl2 in
        (* DD.info_pprint ("   intersect: " ^ (!CP.print_svl intersect)) no_pos; *)
        let def_f1 =
          if intersect = [] then def_f_subst else
            (* let diff = Gen.BList.difference_eq CP.eq_spec_var svl2 svl1 in *)
            match def_f_subst with
              | CF.Base fb ->
                  CF.Base {fb with CF.formula_base_heap = CF.drop_data_view_hrel_nodes_hf fb.CF.formula_base_heap
                          SAU.select_dnode SAU.select_vnode
                          SAU.select_hrel intersect intersect intersect}
              | _ -> report_error no_pos "sa.subst_one_cs_w_one_partial_def"
        in
        (*combi def_f_subst into newf*)
        let newf1 = CF.mkStar newf def_f1 CF.Flow_combine (CF.pos_of_formula newf) in
        (*check contradiction*)
        let susbt_f=
          if check_unsat newf1 then
            let _ = DD.info_pprint ("     contradiction found after subst.") no_pos in
            f
          else newf1
        in
        (* DD.info_pprint ("   subst out: " ^ (Cprinter.prtt_string_of_formula susbt_f)) no_pos; *)
        susbt_f
      end
    | _ -> report_error no_pos "sa.subst_one_cs_w_one_partial_def: should be a singleton"

(*
each constraints, apply lhs and rhs. each partial def in one side ==> generate new constraint

 ldef --> hp: subst all hp in lhs with ldef
 hp --> rdef: subst all hp in rhs with rdef
*)
let subst_one_cs_w_partial_defs ldefs rdefs constr=
  let lhs,rhs = constr.CF.hprel_lhs,constr.CF.hprel_rhs in
  DD.info_pprint ("    input: " ^(Cprinter.prtt_string_of_formula lhs) ^ " ==> " ^
  (Cprinter.prtt_string_of_formula rhs)) no_pos;
  (*subst lhs*)
  DD.info_pprint "  subst lhs" no_pos;
  let lhs1 = List.fold_left subst_one_cs_w_one_partial_def lhs ldefs in
  (*subst rhs*)
  DD.info_pprint "  subst rhs" no_pos;
  let rhs1 = List.fold_left subst_one_cs_w_one_partial_def rhs rdefs in
  (*rhs contradict with lhs?*)
  let cmbf = CF.mkStar lhs1 rhs1 CF.Flow_combine no_pos in
  let lhs2,rhs2 =
    if check_unsat cmbf then
      let _ = DD.info_pprint ("      contradiction found between lhs and rhs") no_pos in
      (lhs,rhs)
    else (lhs1,rhs1)
  in
  let _ = DD.info_pprint ("    out: " ^(Cprinter.prtt_string_of_formula lhs2) ^ " ==> " ^
                                 (Cprinter.prtt_string_of_formula rhs2)) no_pos in
  {constr with CF.hprel_lhs = lhs2;
      CF.hprel_rhs = rhs2}

let subst_cs_w_partial_defs_x hp_constrs par_defs=
  (*partition non-recursive partial defs: lhs set and rhs set*)
  let rec partition_par_defs pdefs lpdefs rpdefs=
    match pdefs with
      | [] -> (lpdefs, rpdefs)
      | (hp_name, hp_args, _, oldef, ordef)::ps ->
          (
              match oldef, ordef with
                | Some _ ,Some _ -> (*recursive par def -->currently omit*)
                    partition_par_defs ps lpdefs rpdefs
                | Some f1, None -> (*lhs case*)
                    partition_par_defs ps (lpdefs@[(hp_name, hp_args, f1)]) rpdefs
                | None, Some f2 -> (*rhs case*)
                    partition_par_defs ps lpdefs (rpdefs@[(hp_name, hp_args, f2)])
                | None, None -> (*can not happen*)
                    report_error no_pos "sa.partition_par_defs: can not happen"
          )
  in
  let (ldefs, rdefs) = partition_par_defs par_defs [] [] in
  List.map (subst_one_cs_w_partial_defs ldefs rdefs) hp_constrs

let subst_cs_w_partial_defs hp_constrs par_defs=
  let pr1 = pr_list_ln Cprinter.string_of_hprel in
  let pr2 = pr_list_ln string_of_par_def_w_name in
  Debug.no_2 "subst_cs_w_partial_defs" pr1 pr2 pr1
      (fun _ _ -> subst_cs_w_partial_defs_x hp_constrs par_defs) hp_constrs par_defs

(*
sth ====> A*HP1*HPn
substituted by HP1*HPn ====> b
(currently we only support HP1*HPn, we can enhance with
more general formula and use imply )
result is sth ====> A*b
*)
let subst_cs_w_other_cs_x constrs=
  (* find all constraints which have lhs is a HP1*HPn ====> b *)
  let check_lhs_hps_only constr=
    let lhs = constr.CF.hprel_lhs in
    let rhs = constr.CF.hprel_rhs in
    DD.ninfo_pprint ("      LHS: " ^ (Cprinter.prtt_string_of_formula lhs)) no_pos;
    match lhs with
      | CF.Base fb -> if (CP.isConstTrue (MCP.pure_of_mix fb.CF.formula_base_pure)) then
            let r = (CF.get_HRel fb.CF.formula_base_heap) in
            (match r with
              | None -> []
              | Some (hp, args) -> [(hp, args, rhs)]
            )
          else []
      | _ -> report_error no_pos "sa.subst_cs_w_other_cs: not handle yet"
  in
  let cs_substs = List.concat (List.map check_lhs_hps_only constrs) in
  (* let _ = if cs_substs = [] then DD.info_pprint ("      EMPTY") no_pos else *)
  (*       DD.info_pprint ("      NOT EMPTY") no_pos *)
  (* in *)
  List.map (subst_one_cs_w_partial_defs [] cs_substs) constrs

let rec subst_cs_w_other_cs constrs=
  let pr1 = pr_list_ln Cprinter.string_of_hprel in
   Debug.no_1 "subst_cs_w_other_cs" pr1 pr1
       (fun _ -> subst_cs_w_other_cs_x constrs) constrs

(* looking for constrs with the form
 sth ====> A*HP1*HPn *)
and subst_one_cs_w_hps subst_hps constr=
  let lhs,rhs = constr.CF.hprel_lhs,constr.CF.hprel_rhs in
  let get_rhs_hps f=
    match f with
      | CF.Base fb -> if (CP.isConstTrue (MCP.pure_of_mix fb.CF.formula_base_pure)) then
            let r = (CF.get_HRels fb.CF.formula_base_heap) in
            r
          else []
      | _ -> report_error no_pos "sa.subst_cs_w_other_cs: not handle yet"
  in
  let sort_hps hps = List.sort (fun (CP.SpecVar (_, id1,_),_)
      (CP.SpecVar (_, id2, _),_)-> String.compare id1 id2) hps
  in
  (*precondition: ls1 and ls2 are sorted*)
  let rec checkeq ls1 ls2 subst=
    match ls1,ls2 with
      | [],[] -> (true,subst)
      | (id1, args1)::ss1,(id2, args2)::ss2 ->
          if CP.eq_spec_var id1 id2 then checkeq ss1 ss2
            (subst@(List.combine args1 args2))
          else (false,[])
      | _ -> (false,[])
  in
  let rhs_hps =  get_rhs_hps rhs in
  let sorted_rhs_hps = sort_hps rhs_hps in
  let find_and_susbt (hps, f)=
    let sorted_subst_hps = sort_hps hps in
    let res,subst = checkeq sorted_subst_hps sorted_rhs_hps [] in
    let l,r=
      if res then
        let hps,_ = List.split hps in
      (*drop hrels and ignore args*)
        let new_rhs, _ = CF.drop_hrel_f rhs hps in
        let subst_f = CF.subst subst f in
      (*combi subst_f into new_rhs*)
        let rhs2 = CF.mkStar new_rhs subst_f CF.Flow_combine (CF.pos_of_formula new_rhs) in
        (lhs,rhs2)
      else (lhs,rhs)
    in {constr with CF.hprel_lhs = l;
        CF.hprel_rhs = r;}
  in
  (List.map find_and_susbt subst_hps)

(*======================*)
(*
each lhs1, check rhs2 of other cs:
 - remove irrelevant svl of rhs2 (wrt. lhs1)
 - checkeq lhs1,rhs2: if yes
  - get susbt
  - form new cs (after subst): lhs2 -> rhs1
*)

(*input in fb
 output: true,susbs: can subst
*)

(*
dn is current node, it is one node of ldns
ss: subst from ldns -> rdns
*)
and get_closed_ptrs_one rdn ldns rdns lcur_match ss=
  let _ =  DD.info_pprint ("    rdn: " ^ (!CP.print_sv rdn) ) no_pos in
  let rec find_args_subst largs rargs lm rm=
    match largs, rargs with
      | [],[] -> (lm,rm)
      | la::ls,ra::rs -> if CP.mem_svl ra lcur_match then (*matched already*)
            find_args_subst ls rs lm rm
          else find_args_subst ls rs (lm@[la]) (rm@[ra])
      | _ -> report_error no_pos "sa.get_closed_ptrs: 1"
  in
  let ldn_match = List.filter (fun (_,vs1, _) ->
      (* let _ =  DD.ninfo_pprint ("    ldn: " ^ (!CP.print_sv vs1) ) no_pos in *)
      let vs2 = (CP.subs_one ss vs1) in
      (* let _ =  DD.ninfo_pprint ("    ldn2: " ^ (!CP.print_sv vs2) ) no_pos in *)
      CP.eq_spec_var vs2 rdn
  ) ldns in
  let rdn_match = List.filter (fun (_,vs1, _) -> CP.eq_spec_var vs1 rdn) rdns in
  if ldn_match = [] || rdn_match = [] then
    ([],[]) (*either lhs1 or rhs2 does not have any node*)
  else
    begin
        let (ld_name, lsv, largs) = List.hd ldn_match in
        let (rd_name, rsv, rargs) = List.hd rdn_match in
        if ld_name = rd_name then (*same type*)
          let lm,rm = find_args_subst largs rargs [] [] in
            (lm, List.combine rm lm)
        else
          ([],[])
    end

and get_closed_matched_ptrs ldns rdns lcur_match ss=
  let rec helper old_m old_ss inc_m=
  let r = List.map (fun m -> get_closed_ptrs_one m ldns rdns old_m old_ss) inc_m in
  let incr_match, incr_ss = List.split r in
  if incr_match = [] then
    old_m, old_ss
  else
    let n_incr_m = (List.concat incr_match) in
    helper (old_m@n_incr_m) (old_ss@(List.concat incr_ss)) n_incr_m
  in
  helper lcur_match ss lcur_match

(*
 lhs1 ==> rhs1
find all constraints lhs2 ==> rhs2 such that
 rhs2 |- lhs1 --> l,r.
Note
- rhs2 may have more hps + hnode than lhs1
- should return a subst from lhs1 to rhs2 since at the end
we have to combine rhs1 into r to form a new cs:
      lhs2*l ===> r*subst(rhs1)
*)
and find_imply lhs1 rhs1 lhs2 rhs2=
   (* let _ = Debug.info_pprint ("    lhs1: " ^ (Cprinter.prtt_string_of_formula_base lhs1)) no_pos in *)
   (* let _ = Debug.info_pprint ("    rhs2: " ^ (Cprinter.prtt_string_of_formula_base rhs2)) no_pos in *)
  let sort_hps_x hps = List.sort (fun (CP.SpecVar (_, id1,_),_)
      (CP.SpecVar (_, id2, _),_)-> String.compare id1 id2) hps
  in
  let sort_hps hps=
    let pr1 = pr_list_ln (pr_pair !CP.print_sv !CP.print_svl) in
    Debug.no_1 "sort_hps" pr1 pr1
        (fun _ ->  sort_hps_x hps) hps
  in
  (*precondition: ls1 and ls2 are sorted*)
  (*we may enhance here, ls1, ls2 are not necessary the same: ls2 >= ls1*)
  let rec check_hrels_imply ls1 ls2 subst matched args=
    match ls1,ls2 with
      | [],[] -> (subst,matched,args)
      | (id1, args1)::ss1,(id2, args2)::ss2 ->
          if CP.eq_spec_var id1 id2 then
            check_hrels_imply ss1 ss2
            (subst@(List.combine args1 args2)) (matched@[id2]) (args@args2)
          else check_hrels_imply ls1 ss2 subst matched args
      | [], _ -> (subst,matched,args)
      | _ -> ([],[],[])
  in
  let transform_hrel (hp,eargs,_)= (hp, List.concat (List.map CP.afv eargs)) in
  let transform_dn dn= (dn.CF.h_formula_data_name, dn.CF.h_formula_data_node,
                        List.filter (fun (CP.SpecVar (t,_,_)) -> is_pointer t ) dn.CF. h_formula_data_arguments) in
  (*matching hprels and return subst*)
  let ldns,_,lhrels = CF.get_hp_rel_bformula lhs1 in
  let rdns,_,rhrels = CF.get_hp_rel_bformula rhs2 in
  let l_rhrels = sort_hps (List.map transform_hrel lhrels) in
  let r_rhrels = sort_hps (List.map transform_hrel rhrels) in
  let subst,matched_hps, m_args = check_hrels_imply l_rhrels r_rhrels [] [] [] in
  let r=
    if matched_hps = [] then None
    else
      begin
      (*matching hnodes (in matched_hps) and return subst*)
          let lhns1 = List.map transform_dn ldns in
          let rhns1 = List.map transform_dn rdns in
          let rm,subst1 =  get_closed_matched_ptrs lhns1 rhns1 m_args subst in
      (*subst in lhs1*)
          let n_lhs1 = CF.subst_b subst1 lhs1 in
      (*check pure implication*)
          let lmf = CP.filter_var (MCP.pure_of_mix n_lhs1.CF.formula_base_pure) rm in
          let b,_,_ = TP.imply (MCP.pure_of_mix rhs2.CF.formula_base_pure) lmf "sa:check_hrels_imply" true None in
          if b then
        (*drop hps and matched svl in n_rhs2*)
            let l_res = {n_lhs1 with
                CF.formula_base_heap = CF.drop_data_view_hrel_nodes_hf
                    n_lhs1.CF.formula_base_heap SAU.select_dnode
                    SAU.select_vnode SAU.select_hrel rm rm matched_hps}
            in
            let r_res = {rhs2 with
                CF.formula_base_heap = CF.drop_data_view_hrel_nodes_hf
                    rhs2.CF.formula_base_heap SAU.select_dnode
                    SAU.select_vnode SAU.select_hrel rm rm matched_hps;
                CF.formula_base_pure = MCP.mix_of_pure
                    (CP.filter_var
                         (MCP.pure_of_mix rhs2.CF.formula_base_pure) rm)}
            in
        (*combine l_res into lhs2*)
            let l =  CF.mkStar lhs2 (CF.Base l_res) CF.Flow_combine (CF.pos_of_formula lhs2) in
            let n_rhs1 = CF.subst subst1 rhs1 in
            let r = CF.mkStar n_rhs1 (CF.Base r_res) CF.Flow_combine (CF.pos_of_formula n_rhs1) in
            (Some (l, r))
          else None
      end
  in
  r

and find_imply_subst constrs=
  let find_imply_one cs1 cs2=
    let _ = Debug.ninfo_pprint ("    cs1: " ^ (Cprinter.string_of_hprel cs1)) no_pos in
    let _ = Debug.ninfo_pprint ("    cs2: " ^ (Cprinter.string_of_hprel cs2)) no_pos in
    match cs1.CF.hprel_lhs,cs2.CF.hprel_rhs with
      | CF.Base lhs1, CF.Base rhs2 ->
          let r = find_imply lhs1 cs1.CF.hprel_rhs cs2.CF.hprel_lhs rhs2 in
          begin
              match r with
                | Some (l,r) ->
                    let new_cs = {cs1 with
                        CF.predef_svl = CP.remove_dups_svl (cs1.CF.predef_svl@cs2.CF.predef_svl);
                        CF.unk_svl = CP.remove_dups_svl (cs1.CF.unk_svl@cs2.CF.unk_svl);
                        CF.hprel_lhs = l;
                        CF.hprel_rhs = r;
                    }
                    in
                    let _ = Debug.ninfo_pprint ("    new cs: " ^ (Cprinter.string_of_hprel new_cs)) no_pos in
                    [new_cs]
                | None -> []
          end
      | _ -> report_error no_pos "sa.find_imply_one"
  in
  let rec helper don rest res=
    match rest with
      | [] -> res
      | cs::ss -> let r = List.concat (List.map (find_imply_one cs) (don@rest)) in
                  helper (don@[cs]) ss (res@r)
  in
  helper [List.hd constrs] (List.tl constrs) []

and subst_cs_w_other_cs_new_x constrs=
  let is_non_recursive_cs constr=
    let lhrel_svl = CF.get_hp_rel_name_formula constr.CF.hprel_lhs in
    let rhrel_svl = CF.get_hp_rel_name_formula constr.CF.hprel_rhs in
    ((CP.intersect lhrel_svl rhrel_svl) = [])
  in
  (* (\* find all constraints which have lhs is a HP1*HPn ====> b *\) *)
  (* let check_lhs_hps_only constr= *)
  (*   let lhs,rhs = constr.CF.hprel_lhs,constr.CF.hprel_rhs in *)
  (*   match lhs with *)
  (*     | CF.Base fb -> if (CP.isConstTrue (MCP.pure_of_mix fb.CF.formula_base_pure)) then *)
  (*           let r = (CF.get_HRels fb.CF.formula_base_heap) in *)
  (*           [(r,rhs)] *)
  (*         else [] *)
  (*     | _ -> report_error no_pos "sa.subst_cs_w_other_cs: not handle yet" *)
  (* in *)
  (*remove recursive cs*)
  let constrs1 = List.filter is_non_recursive_cs constrs in
  (* let cs_susbsts = List.concat (List.map check_lhs_hps_only constrs) in *)
  (* List.concat (List.map (subst_one_cs_w_hps cs_susbsts) constrs) *)
  find_imply_subst constrs1
(*=========END============*)

let rec subst_cs_w_other_cs_new constrs=
  let pr1 = pr_list_ln Cprinter.string_of_hprel in
   Debug.no_1 "subst_cs_w_other_cs_new" pr1 pr1
       (fun _ -> subst_cs_w_other_cs_new_x constrs) constrs

let subst_cs_x hp_constrs par_defs=
(*subst by partial defs*)
  DD.info_pprint " subst with partial defs" no_pos;
  let constrs1 = subst_cs_w_partial_defs hp_constrs par_defs in
(*subst by constrs*)
  DD.info_pprint " subst with other assumptions" no_pos;
  let new_cs =
    if (List.length constrs1) > 1 then
      subst_cs_w_other_cs_new constrs1
    else []
  in
    (constrs1@new_cs)

let subst_cs hp_constrs par_defs=
  let pr1 = pr_list_ln Cprinter.string_of_hprel in
  let pr2 = pr_list_ln string_of_par_def_w_name in
  Debug.no_2 "subst_cs" pr1 pr2 pr1
      (fun _ _ -> subst_cs_x hp_constrs par_defs) hp_constrs par_defs

(*===========end subst============*)
(*========generalization==========*)
(*for par_defs*)
let generalize_one_hp prog par_defs=
  (*collect definition for each partial definition*)
  let obtain_and_norm_def args0 (a1,args,a3,olf,orf)=
    let f=
      match olf,orf with
        | Some f, None -> f
        | None, Some f -> f
        | Some f1, Some f2 -> f2
        | None, None -> report_error no_pos "sa.obtain_def: can't happen 2"
    in
    (*normalize args*)
    let subst = List.combine args args0 in
    (CF.subst subst f)
    in
    DD.info_pprint ">>>>>> generalize_one_hp: <<<<<<" no_pos;
    let hp, args, _,_,_ = (List.hd par_defs) in
    DD.info_pprint ((!CP.print_sv hp)^"(" ^(!CP.print_svl args) ^ ")") no_pos;
    let defs = List.map (obtain_and_norm_def args) par_defs in
  (*make disjunction*)
    let def = List.fold_left (fun f1 f2 -> CF.mkOr f1 f2 (CF.pos_of_formula f1))
      (List.hd defs) (List.tl defs) in
    DD.info_pprint (" =: " ^ (Cprinter.prtt_string_of_formula def) ) no_pos;
    (hp, (CP.HPRelDefn hp, (*CF.formula_of_heap*)
          (CF.HRel (hp, List.map (fun x -> CP.mkVar x no_pos) args, no_pos))
 (*no_pos*),
          def))

let generalize_hps_par_def prog par_defs=
  (*partition the set by hp_name*)
  let rec partition_pdefs_by_hp_name pdefs parts=
    match pdefs with
      | [] -> parts
      | (a1,a2,a3,a4,a5)::xs ->
          let part,remains= List.partition (fun (hp_name,_,_,_,_) -> CP.eq_spec_var a1 hp_name) xs in
          partition_pdefs_by_hp_name remains (parts@[[(a1,a2,a3,a4,a5)]@part])
  in
  let groups = partition_pdefs_by_hp_name par_defs [] in
  (*each group, do union partial definition*)
  (List.map (generalize_one_hp prog) groups)

let generalize_hps_cs hp_names cs=
  let rec look_up_hrel id ls=
    match ls with
      | [] -> report_error no_pos "sa.generalize_hps_cs: can not happen"
      | (id1, vars, p)::cs -> if CP.eq_spec_var id id1 then (id1, vars, p)
          else look_up_hrel id cs
  in
  let check_formula_hp_only f=
    match f with
      | CF.Base fb -> if (CP.isConstTrue (MCP.pure_of_mix fb.CF.formula_base_pure)) then
            let r = (CF.get_HRel fb.CF.formula_base_heap) in
            (match r with
              | None -> None
              | Some (hp, args) -> Some (hp, args)
            )
          else None
      | _ -> report_error no_pos "sa.subst_cs_w_other_cs: not handle yet"
  in
  let generalize_hps_one_cs constr=
    let lhs,rhs = constr.CF.hprel_lhs,constr.CF.hprel_rhs in
    let _,_,l_hp = CF.get_hp_rel_formula lhs in
    let _,_,r_hp = CF.get_hp_rel_formula rhs in
    let hps = List.map (fun (id, _, _) -> id) (l_hp@r_hp) in
    let diff = Gen.BList.difference_eq CP.eq_spec_var hps hp_names in
    match diff with
      | [] -> ([],[]) (*drop constraint, no new definition*)
      | [id] -> let (hp, args, p) = look_up_hrel id (l_hp@r_hp) in
                let ohp = check_formula_hp_only lhs in
                (match ohp with
                  | None ->
                       let ohp = check_formula_hp_only rhs in
                       ( match ohp with
                         | None -> ([constr],[]) (*keep constraint, no new definition*)
                         |  Some (hp, args) ->
                             ([],[(CP.HPRelDefn hp,(* CF.formula_of_heap*)
                                 (CF.HRel (hp, List.map (fun x -> CP.mkVar x no_pos) args, p)) (*p*), lhs)])
                       )
                  | Some (hp, args) ->
                    DD.info_pprint ">>>>>> generalize_one_cs_hp: <<<<<<" no_pos;
                     DD.info_pprint ((!CP.print_sv hp)^"(" ^(!CP.print_svl args) ^ ")=" ^
                         (Cprinter.prtt_string_of_formula rhs) ) no_pos;
                      ([],[(CP.HPRelDefn hp, (*CF.formula_of_heap*)
      (CF.HRel (hp, List.map (fun x -> CP.mkVar x no_pos) args, p)) , rhs)])
                )
      | _ -> ([constr],[]) (*keep constraint, no new definition*)
  in
  let r = List.map generalize_hps_one_cs cs in
  let cs1, hp_defs = List.split r in
  (List.concat cs1, List.concat hp_defs)

let generalize_hps_x prog cs par_defs=
  DD.info_pprint ">>>>>> step 6: generalization <<<<<<" no_pos;
(*general par_defs*)
  let pair_names_defs = generalize_hps_par_def prog par_defs in
  let hp_names,hp_defs = List.split pair_names_defs in
  
(*for each constraints, we may pick more definitions*)
  let remain_constr, hp_def1 = generalize_hps_cs hp_names cs in
(remain_constr, hp_defs@hp_def1)

let generalize_hps prog cs par_defs=
  let pr1 = pr_list_ln Cprinter.string_of_hprel in
  let pr2 = pr_list_ln string_of_par_def_w_name in
  let pr3 = pr_list Cprinter.string_of_hp_rel_def in
  Debug.no_2 "generalize_hp" pr1 pr2 (pr_pair pr1 pr3)
      (fun _ _ -> generalize_hps_x prog cs par_defs) cs par_defs

(*========END generalization==========*)
(*===========fix point==============*)
let infer_hps_fix prog (constrs: CF.hprel list) =
  let rec helper (constrs: CF.hprel list) par_defs =
    DD.info_pprint ">>>>>> step 3: simplification <<<<<<" no_pos;
    let constrs1 = simplify_constrs prog constrs in
     Debug.ninfo_hprint (add_str "constr each LOOP: " (pr_list_ln Cprinter.string_of_hprel)) constrs1 no_pos;
  (*step 3: pick partial definition*)
    DD.info_pprint ">>>>>> step 4: pick partial definitions <<<<<<" no_pos;
    let constrs2, new_par_defs = collect_partial_definitions prog constrs1 in
    let par_defs_diff = Gen.BList.difference_eq
      check_partial_def_eq new_par_defs par_defs in
    if par_defs_diff = [] then
 (*teminating condition*) 
      (constrs2, par_defs)  
    else
      begin
          (*step 4: pick complete def*)
          let constrs3 = constrs2 in
          DD.info_pprint ">>>>>> step 5: subst new partial def into constrs <<<<<<" no_pos;
          (*step 5: subst new partial def into constrs*)
          let constrs4 = subst_cs constrs3 (par_defs@par_defs_diff) in
          helper constrs4 (par_defs@par_defs_diff)
      end
  in
  helper constrs []

let generate_hp_def_from_split hp_defs_split=
  let helper (hp_name, ((CF.HRel (_,args,_)) as hrel), h_def)=
     DD.info_pprint ((!CP.print_sv hp_name)^"(" ^
        (let pr = pr_list !CP.print_exp in pr args) ^ ")=" ^
        (Cprinter.prtt_string_of_formula (CF.formula_of_heap h_def no_pos))) no_pos;
    (CP.HPRelDefn hp_name, hrel (*CF.formula_of_heap hrel no_pos*),
     CF.formula_of_heap h_def no_pos)
  in
   DD.info_pprint ">>>>>> equivalent hp: <<<<<<" no_pos;
  List.map helper hp_defs_split

(*
  input: constrs: (formula * formula) list
  output: definitions: (formula * formula) list
*)
let infer_hps_x prog (hp_constrs: CF.hprel list):(CF.hprel list * hp_rel_def list) =
  DD.info_pprint "\n\n>>>>>> norm_hp_rel <<<<<<" no_pos;
  DD.info_pprint ">>>>>> step 1a: drop arguments<<<<<<" no_pos;
  (* step 1: drop irr parameters *)
  let constrs = elim_redundant_paras_lst_constr prog hp_constrs in
  Debug.ninfo_hprint (add_str "   AFTER DROP: " (pr_list_ln Cprinter.string_of_hprel)) constrs no_pos;
  DD.info_pprint ">>>>>> step 1b: find unknown ptrs<<<<<<" no_pos;
  let constrs1 = analize_unk prog constrs in
   (* step 1': split HP *)
  DD.info_pprint ">>>>>> step 2: split arguments: currently omitted <<<<<<" no_pos;
  (* let constrs1, split_tb,hp_defs_split = split_hp constrs in *)
  (*for temporal*)
  let constrs2 = constrs1 in
  let hp_defs_split = [] in
  (*END for temporal*)
  let cs, par_defs = infer_hps_fix prog constrs2 in
  (*step 6: over-approximate to generate hp def*)
  let constr3, hp_defs = generalize_hps prog cs par_defs in
  let hp_def_from_split = generate_hp_def_from_split hp_defs_split in
  DD.info_pprint (" remains: " ^
     (let pr1 = pr_list_ln Cprinter.string_of_hprel in pr1 constr3) ) no_pos;
  (constr3, hp_defs@hp_def_from_split)
  (* loop 1 *)
  (*simplify constrs*)
  (* let constrs12 = simplify_constrs constrs1 in *)
  (* (\*step 3: pick partial definition*\) *)
  (* let constrs13, par_defs1 = collect_partial_definitions prog constrs12 in *)
  (* (\*step 4: pick complete def*\) *)
  (* (\*step 5: subst new partial def into constrs*\) *)
  (* let constrs14 = subst_cs constrs13 par_defs1 in *)
  (* (\*loop 2*\) *)
  (* (\*simplify constrs*\) *)
  (* let constrs22 = simplify_constrs constrs14 in *)
  (* (\*step 3: pick partial definition*\) *)
  (* let constrs23, par_defs2 = collect_partial_definitions prog constrs22 in *)
  (* let par_defs_diff = Gen.BList.difference_eq check_partial_def_eq par_defs2 par_defs1 in *)

(*(pr_pair Cprinter.prtt_string_of_formula Cprinter.prtt_string_of_formula)*)
let infer_hps prog (hp_constrs: CF.hprel list):
 (CF.hprel list * hp_rel_def list) =
  let pr1 = pr_list_ln Cprinter.string_of_hprel in
  let pr2 = pr_list_ln Cprinter.string_of_hp_rel_def in
  Debug.no_1 "infer_hp" pr1 (pr_pair pr1 pr2)
      (fun _ -> infer_hps_x prog hp_constrs) hp_constrs
