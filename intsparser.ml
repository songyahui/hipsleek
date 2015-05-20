#include "xdebug.cppo"
open VarGen
open Globals
open Gen.Basic
open Iexp 

module I = Iast
module IF = Iformula

let rec partition_by_key key_of key_eq ls = 
  match ls with
  | [] -> []
  | e::es ->
    let ke = key_of e in 
    let same_es, other_es = List.partition (fun e -> key_eq ke (key_of e)) es in
    (ke, e::same_es)::(partition_by_key key_of key_eq other_es)

let ints_loc_prefix = "ints_method_"

let name_of_ints_loc lbl = 
  match lbl with
  | NumLoc (i, _) -> ints_loc_prefix ^ (string_of_int i)
  | NameLoc (s, _) -> s

let pos_of_ints_loc lbl = 
  match lbl with
  | NumLoc (_, p)
  | NameLoc (_, p) -> p

let eq_ints_loc lbl1 lbl2 =
  (String.compare (name_of_ints_loc lbl1) (name_of_ints_loc lbl2)) == 0

let rec trans_ints_exp_lst (exps: ints_exp list) (last_exp: I.exp): I.exp = 
  match exps with
  | [] -> last_exp
  | e::es ->
    let cont_exp = trans_ints_exp_lst es last_exp in
    match e with
    | Assign asg ->
      let asg_pos = asg.ints_exp_assign_pos in
      let asg_exp = I.mkAssign I.OpAssign asg.ints_exp_assign_lhs asg.ints_exp_assign_rhs 
                      (fresh_branch_point_id "") asg_pos in
      I.mkSeq asg_exp cont_exp asg_pos
    | Assume asm ->
      let asm_pos = asm.ints_exp_assume_pos in
      I.mkCond asm.ints_exp_assume_formula cont_exp (I.Empty asm_pos) None asm_pos

let trans_ints_block (blk: ints_block): I.exp =
  let exps = blk.ints_block_commands in
  let fr = blk.ints_block_from in
  let t = blk.ints_block_to in
  let pos = blk.ints_block_pos in
  (* Translate to_label to a method call *)
  let to_exp = I.mkCallNRecv (name_of_ints_loc t) None [] None (fresh_branch_point_id "") (pos_of_ints_loc t) in
  (* Translate ints_exp list *)
  trans_ints_exp_lst exps to_exp

let trans_ints_block_lst fn (fr_lbl: ints_loc) (blks: ints_block list): I.proc_decl =
  let pos = pos_of_ints_loc fr_lbl in
  let proc_name = name_of_ints_loc fr_lbl in
  let proc_body = List.fold_left (fun acc blk -> I.mkSeq acc (trans_ints_block blk) (I.get_exp_pos acc)) (I.Empty pos) blks in
  I.mkProc fn proc_name [] "" None false [] [] I.void_type None (IF.EList []) (IF.mkEFalseF ()) pos (Some proc_body)

let trans_ints_prog fn (iprog: ints_prog): I.prog_decl =
  let main_proc =
    let start_lbl = iprog.ints_prog_start in
    let pos = pos_of_ints_loc start_lbl in
    let start_exp = I.mkCallNRecv (name_of_ints_loc start_lbl) None [] None (fresh_branch_point_id "") pos in
    I.mkProc fn "main" [] "" None false [] [] I.void_type None (IF.EList []) (IF.mkEFalseF ()) pos (Some start_exp)
  in
  let from_lbls = List.map (fun blk -> blk.ints_block_from) iprog.ints_prog_blocks in
  let to_lbls = List.map (fun blk -> blk.ints_block_to) iprog.ints_prog_blocks in
  let abandoned_to_lbls = Gen.BList.remove_dups_eq eq_ints_loc (Gen.BList.difference_eq eq_ints_loc to_lbls from_lbls) in
  let abandoned_procs = List.map (fun lbl ->
      let pos = pos_of_ints_loc lbl in
      let ret_exp = I.mkReturn None None pos in
      I.mkProc fn (name_of_ints_loc lbl) [] "" None false [] [] I.void_type None (IF.EList []) (IF.mkEFalseF ()) pos (Some ret_exp)
    ) abandoned_to_lbls in
  
  let proc_blks = partition_by_key (fun blk -> blk.ints_block_from) eq_ints_loc iprog.ints_prog_blocks in
  let proc_decls = 
    [main_proc] @ 
    (List.map (fun (fr, blks) -> trans_ints_block_lst fn fr blks) proc_blks) @
    abandoned_procs 
  in
  let global_vars =
    let f e =
      match e with
      | I.Var v -> Some [(v.I.exp_var_name, v.I.exp_var_pos)]
      | _ -> None
    in
    let all_vars = List.concat (List.map (fun pd ->
        match pd.I.proc_body with
        | None -> []
        | Some b -> I.fold_exp b f (List.concat) [])
      proc_decls) in
    Gen.BList.remove_dups_eq (fun (s1, _) (s2, _) -> String.compare s1 s2 == 0) all_vars
  in
  let () = x_binfo_hp (add_str "global_vars" (pr_list fst)) global_vars no_pos in
  let global_var_decls = List.map (fun (d, p) -> I.mkGlobalVarDecl Int [(d, None, p)] p) global_vars in 
  (* Inline Iast procedure if body is only a call to another procedure *)
  let proc_decls =
      let rec inline_body pd proc_names =
        (match pd.I.proc_body with
        | Some (CallNRecv { exp_call_nrecv_method = cnr_method }) ->
                let called_proc = (List.find
                  (fun pd -> cnr_method = pd.I.proc_name)
                  proc_decls) in
                (* If we're not trying to inline it, then recurse (+ this name) *)
                if not (List.mem called_proc.I.proc_name proc_names) then
                  let called_proc = inline_body called_proc (pd.I.proc_name::proc_names) in
                  { pd with I.proc_body = called_proc.I.proc_body }
                else
                  pd
        | _ -> pd) in
      (List.map (fun pd -> inline_body pd []) proc_decls) in
  let called_proc_names =
    let f caller_name e =
      match e with
      (* Don't consider calls where the proc name is the caller name. *)
      | I.CallNRecv { exp_call_nrecv_method = cnr_method } when cnr_method <> caller_name ->
        Some [cnr_method]
      | _ -> None
    in
    let all_calls = "main" :: List.concat (List.map (fun pd ->
        match pd.I.proc_body with
        | None -> []
        | Some b -> I.fold_exp b (f pd.I.proc_name) (List.concat) [])
    proc_decls) in
    Gen.BList.remove_dups_eq (fun s1 s2 -> String.compare s1 s2 == 0) all_calls
  in
  let () = x_binfo_hp (add_str "called_proc_names" (pr_list (fun x->x))) called_proc_names no_pos in
  (* remove procedures which aren't called *)
  let proc_decls =
    List.filter (fun pd -> List.mem pd.I.proc_name called_proc_names) proc_decls
  in
  { prog_include_decls = [];
    prog_data_decls = [];
    prog_global_var_decls = global_var_decls;
    prog_logical_var_decls = [];
    prog_enum_decls = [];
    prog_view_decls = [];
    prog_func_decls = [];
    prog_rel_decls = [];
    prog_rel_ids = [];
    prog_templ_decls = [];
    prog_ut_decls = [];
    prog_hp_decls = [];
    prog_hp_ids = [];
    prog_axiom_decls = [];
    prog_proc_decls = proc_decls;
    prog_coercion_decls = [];
    prog_hopred_decls = [];
    prog_barrier_decls = [];
    prog_test_comps = []; }

let parse_ints (file_name: string): I.prog_decl =
  let in_chnl = open_in file_name in
  let lexbuf = Lexing.from_channel in_chnl in
  let iprog = 
    try
      let p = Iparser.program Ilexer.tokenizer lexbuf in
      let () = close_in in_chnl in
      p
    with e ->
      let () = close_in in_chnl in
      match e with
      | Parsing.Parse_error ->
        let curr = lexbuf.Lexing.lex_curr_p in
        let err_pos = { start_pos = curr; mid_pos = curr; end_pos = curr; } in
        (* let line = curr.Lexing.pos_lnum in                       *)
        (* let cnum = curr.Lexing.pos_cnum - curr.Lexing.pos_bol in *)
        let token = Lexing.lexeme lexbuf in
        Gen.report_error err_pos ("Intsparser: Unexpected token " ^ token)
      | _ -> raise e
  in 
  trans_ints_prog file_name iprog
