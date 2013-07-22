(*
  Choose with theorem prover to prove formula
*)

open Globals
open Others
open GlobProver
open Gen.Basic
open Mcpure
open Cpure
open Mcpure_D
open Log
open Printf

module CP = Cpure
module MCP = Mcpure



let test_db = false

let pure_tp = ref OmegaCalc
(* let tp = ref OZ *)
(* let tp = ref Redlog *)
(* let tp = ref AUTO *)
(* let tp = ref PARAHIP *)

let proof_no = ref 0
let provers_process = ref None

let next_proof_no () =
  let p_no = !proof_no + 1 in
  string_of_int p_no


type prove_type = Sat of CP.formula | Simplify of CP.formula | Imply of CP.formula * CP.formula
type result_type = Timeout | Result of string | Failure of string

let print_pure = ref (fun (c:CP.formula)-> Cprinter.string_of_pure_formula c(*" printing not initialized"*))

let prover_arg = ref "oc"
let external_prover = ref false
let tp_batch_mode = ref true
let external_host_ports = ref []
let webserver = ref false
let priority = ref 1
let decr_priority = ref false
let set_priority = ref false
let prio_list = ref []

  
 
let sat_cache = ref (Hashtbl.create 200)
let imply_cache = ref (Hashtbl.create 200)

(* An Hoa : Global variables to allow the prover interface to pass message to this interface *)

let generated_prover_input = ref "_input_not_set_"

let prover_original_output = ref "_output_not_set_"

let set_generated_prover_input inp =
	generated_prover_input := inp;;

let reset_generated_prover_input () = generated_prover_input := "_input_not_set_";;

let get_generated_prover_input () = !generated_prover_input;;
	
let set_prover_original_output oup = 
	prover_original_output := oup;;

let reset_prover_original_output () = prover_original_output := "_output_not_set_";;
	
let get_prover_original_output () = !prover_original_output;;

let suppress_imply_out = ref true;;

Smtsolver.set_generated_prover_input := set_generated_prover_input;;
Smtsolver.set_prover_original_output := set_prover_original_output;;
Omega.set_generated_prover_input := set_generated_prover_input;;
Omega.set_prover_original_output := set_prover_original_output;;

(* An Hoa : end *)

module Netprover = struct
  let debuglevel = 0 
  let trace f s = if debuglevel <= 1 then (prerr_string (Printf.sprintf "\n%d: %s: %s" (Unix.getpid ()) f s); flush stderr) else ()
  let show_info f s = if debuglevel <= 2 then (prerr_string (Printf.sprintf "\n%d: %s: %s" (Unix.getpid ()) f s); flush stderr) else ()
  
  (* server-setting (prover-setting) -> ()                                 *)
  (* proc_group(reqid,[[task]],timeout) -> [result]                        *)
  (* proc_group_async(reqid,[[task]]) -> groupid                           *)
  (* wait(groupid,[taskid::int],timeout) -> [result] timeout of -1 :       *)
  (* indefinite kill(groupid,[taskid])                                     *)
  (* wait_and_kill(groupid,[taskid::int],timeout) -> [result] timeout of   *)
  (* -1 : indefinite                                                       *)
  let use_pipe = ref false
  let in_ch = ref stdin
  let out_ch = ref stdout
  let default_pipe = "default"
  let default_timeout = 200.0
  let seq_number = ref 0 (* for asynch calls in the future *)
  let get_seq_no () = incr seq_number; !seq_number
  
  let start_prover_process () =
    (* let _ = print_string ("\n Tpdispatcher: start_prover_process \n") in *)
    let is_running cmd_args =
      let cmd = "ps -u$USER -f" in
      let ch = Unix.open_process_in cmd in
      try
        let re = Str.regexp_string cmd_args in
        while true do
          let s = input_line ch in
          try
            if Str.search_forward re s 0 >= 0 then raise Exit
          with Not_found -> ()
        done;
        false
      with Exit -> true
      | End_of_file -> false
      | e -> print_string "ho"; flush stdout; false
    in
    let cmd_args = "prover --pipe " ^ default_pipe in
    if not (is_running cmd_args) then begin
      print_string "\nLaunching default prover\n."; flush stdout;
      ignore(Unix.system cmd_args)
    end
  
  let set_use_pipe () =
    start_prover_process ();
    external_prover := true;
    use_pipe := true;
    let i, o = Net.Pipe.init_client default_pipe in
    in_ch := i; out_ch := o
  
  let set_use_socket host_port =
    external_prover := true ;
    use_pipe := false;
    let i, o = Net.Socket.init_client host_port in
    in_ch := i; out_ch := o
  
	let set_use_socket_map host_port =
		external_prover := true ;
		use_pipe := false;
		let i, o = Net.Socket.init_client host_port in
		in_ch := i; out_ch := o
		
	let set_use_socket_for_web host_port =
	    external_host_ports := [host_port];
	    external_prover := true;
	    use_pipe := false;
	    let i, o = Net.Socket.init_client host_port in
		in_ch := i; out_ch := o
		
	let set_prio_list str =
	  try
	    set_priority := true;
	    let lst = Str.split (Str.regexp ";") str in
	    prio_list := List.map (fun name_prio -> let l = Str.split (Str.regexp ":") name_prio in ((List.hd l),int_of_string(List.nth l 1))) lst
	  with e -> print_endline "set_prio_list error"; raise e
 
  let index_of elem lst =
    (** return the first index of [elem] in the list [lst] *)
    let rec find i elem lst =
      match lst with
      | [] -> (- 1)
      | hd:: tl -> if elem = hd then i else find (i + 1) elem tl
    in find 0 elem lst
  
  exception ServerTimeout
  exception ParStop
  
  type pmap_result = One of string | All of string list | Unknown
  
  let pmap (provers: string) (jobs: prove_type list) (stopper: result_type -> bool) : pmap_result =
    (* [pmap] sends the tuple of [provers] and [jobs] list to the server   *)
    (* and wait for results. When a result arrives, the [stopper] function *)
    (* is applied to the result. If [stopper] returns true, the function   *)
    (* exits with the result arrives. Otherwise it continues until all of  *)
    (* the results arrives and return the whole list of results.           *)
    
    let send_stop seqno = Net.IO.write !out_ch (Net.IO.msg_type_cancel_job, seqno) in
    (* send out job list to server *)
    let seqno = get_seq_no () in
    (* let stopper_closure = Marshal.to_string stopper [Marshal.Closures] in   *)
    (* trace "closure=" stopper_closure;                                       *)
    Net.IO.write_job_to_master !out_ch seqno default_timeout provers jobs "true";
    
    (* collect the results *)
    let num_jobs = List.length jobs in
    let result_arr = Array.make num_jobs "" in
    let time_start = Unix.gettimeofday () in
    try
      let num_results = ref 0 in
      let wait_fd = Unix.descr_of_in_channel !in_ch in
      while !num_results < num_jobs do
        let time_left = default_timeout -. ((Unix.gettimeofday ()) -. time_start) in
        if time_left < 0. then
          failwith "timeout" 
        else begin
          (* show_info "pmap" (Printf.sprintf "wait %d results" (num_jobs -          *)
          (* !num_results));                                                         *)
          let in_fds, _, _ = Gen.Basic.restart  (Unix.select [wait_fd] [] []) time_left in
          (* let in_fds, _, _ = Unix.select [wait_fd] [] [] time_left in *)
          if in_fds <> [] then begin
            incr num_results;
            let seqno, idx, result = Net.IO.read_result (Unix.in_channel_of_descr (List.hd in_fds)) in
            match result with
            | Result s ->
                if idx >= 0 then begin
                  (* trace "pmap" (Printf.sprintf "idx = %d" idx); *)
                  let res = Net.IO.from_string s in
                  Array.set result_arr idx s;
                  if stopper res then begin
                    show_info "pmap: discard others" "";
                    send_stop seqno;
                    Array.set result_arr 0 s; (* will return the first element only *)
                    raise ParStop
                  end
                end else
                  show_info "pmap result" "index is negative"
            | Timeout -> trace "pmap result" " timed out."
            | Failure s -> trace "pmap result" s
          end;
        end
      done;
      All (List.filter (fun s -> s <> "") (Array.to_list result_arr))
    with
    | ParStop -> trace "pmap" "\n by stoper."; (One result_arr.(0))
    | ServerTimeout -> trace "pmap" "\npmap timed out."; Unknown
    | e -> trace "pmap" (Printexc.to_string e); Unknown
  
  let call_prover ( f : prove_type) = 
    (** send message to external prover to get the result. *)
    try
      let ret = pmap !prover_arg [f] (fun _ -> false) in
      match ret with Unknown -> None 
      | One s ->   if s <> "" then Some (Net.IO.from_string s) else None
      | All results -> let s = (List.hd results) in
        if s <> "" then Some (Net.IO.from_string s) else None
    with e -> trace "pmap" (Printexc.to_string e); None
   
end

(* ##################################################################### *)

(* class used for keeping prover's functions needed for the incremental proving*)
class incremMethods : [CP.formula] incremMethodsType = object
  val push_no = ref 0 (*keeps track of the number of saved states of the current process*) 
  val process_context = ref [] (*variable used to archives all the assumptions send to the current process *)
  val declarations = ref [] (*variable used to archive all the declared variables in the current process context *) (* (stack_no * var_name * var_type) list*)
  val process = ref None (* prover process *)

  (*creates a new proving process *)
  method start_p () : prover_process_t =
    let proc = 
      match !pure_tp with
      | Cvc3 -> Cvc3.start()
      | _ -> Cvc3.start() (* to be completed for the rest of provers that support incremental proving *) 
    in 
    process := Some proc;
    proc

  (*stops the proving process*)
  method stop_p (process: prover_process_t): unit =
    match !pure_tp with
      | Cvc3 -> Cvc3.stop process
      | _ -> () (* to be completed for the rest of provers that support incremental proving *)

  (*saves the state of the process and its context *)
  method push (process: prover_process_t): unit = 
    push_no := !push_no + 1;
      match !pure_tp with
        | Cvc3 -> Cvc3.cvc3_push process
        | _ -> () (* to be completed for the rest of provers that support incremental proving *)

  (*returns the process to the state it was before the push call *)
  method pop (process: prover_process_t): unit = 
    match !pure_tp with
      | Cvc3 -> Cvc3.cvc3_pop process
      | _ -> () (* to be completed for the rest of provers that support incremental proving *)

  (*returns the process to the state it was before the push call on stack n *)
  method popto (process: prover_process_t) (n: int): unit = 
    let n = 
      if ( n > !push_no) then begin
        Debug.devel_zprint (lazy ("\nCannot pop to " ^ (string_of_int n) ^ ": no such stack. Will pop to stack no. " ^ (string_of_int !push_no))) no_pos;
        !push_no 
      end
      else n in
    match !pure_tp with
      | Cvc3 -> Cvc3.cvc3_popto process n
      | _ -> () (* to be completed for the rest of provers that support incremental proving *)

  method imply (process: (prover_process_t option * bool) option) (ante: CP.formula) (conseq: CP.formula) (imp_no: string): bool = true
    (* let _ = match proceess with  *)
    (*   | Some (Some proc, send_ante) -> if (send_ante) then  *)
    (*       else *)
    (*      imply process ante conseq imp_no *)

    (*adds active assumptions to the current process*)
    (* method private add_to_context assertion: unit = *)
    (*     process_context := [assertion]@(!process_context) *)

  method set_process (proc: prover_process_t) =
    process := Some proc

  method get_process () : prover_process_t option =
    !process 

end

let incremMethodsO = ref (new incremMethods)


(* ##################################################################### *)

let rec check_prover_existence prover_cmd_str =
  match prover_cmd_str with
    |[] -> ()
		| "log"::rest -> check_prover_existence rest
    | prover::rest -> 
        (* let exit_code = Sys.command ("which "^prover) in *)
        (*Do not display system info in the website*)
        let exit_code = Sys.command ("which "^prover^" > /dev/null 2>&1") in
        if exit_code > 0 then
          let _ = print_string ("WARNING : Command for starting the prover (" ^ prover ^ ") not found\n") in
          exit 0
        else check_prover_existence rest

let set_tp tp_str =
  prover_arg := tp_str;
  (******we allow normalization/simplification that may not hold
  in the presence of floating point constraints*)
  if tp_str = "parahip" || tp_str = "rm" then allow_norm := false else allow_norm:=true;
  (**********************************************)
  let prover_str = ref [] in
  (*else if tp_str = "omega" then
	(tp := OmegaCalc; prover_str := "oc"::!prover_str;)*)
  if (String.sub tp_str 0 2) = "oc" then
    (Omega.omegacalc := tp_str; pure_tp := OmegaCalc; prover_str := "oc"::!prover_str;)
  else if tp_str = "dp" then pure_tp := DP
  else if tp_str = "cvcl" then 
	(pure_tp := CvcLite; prover_str := "cvcl"::!prover_str;)
  else if tp_str = "cvc3" then 
	(pure_tp := Cvc3; prover_str := "cvc3"::!prover_str;)
  else if tp_str = "co" then
	(pure_tp := CO; prover_str := "cvc3"::!prover_str; 
     prover_str := "oc"::!prover_str;)
  else if tp_str = "isabelle" then
	(pure_tp := Isabelle; prover_str := "isabelle-process"::!prover_str;)
  else if tp_str = "mona" then
	(pure_tp := Mona; prover_str := "mona"::!prover_str;)
  else if tp_str = "monah" then
	(pure_tp := MonaH; prover_str := "mona"::!prover_str;)
  else if tp_str = "om" then
	(pure_tp := OM; prover_str := "oc"::!prover_str;
     prover_str := "mona"::!prover_str;)
  else if tp_str = "oi" then
	(pure_tp := OI; prover_str := "oc"::!prover_str;
     prover_str := "isabelle-process"::!prover_str;)
  else if tp_str = "set" then
    (pure_tp := SetMONA; prover_str := "mona"::!prover_str;)
  else if tp_str = "cm" then
	(pure_tp := CM; prover_str := "cvc3"::!prover_str;
     prover_str := "mona"::!prover_str;)
  else if tp_str = "coq" then
	(pure_tp := Coq; prover_str := "coqtop"::!prover_str;)
  (*else if tp_str = "z3" then 
	(pure_tp := Z3; prover_str := "z3"::!prover_str;)*)
   else if (String.sub tp_str 0 2) = "z3" then
	(Smtsolver.smtsolver_name := tp_str; pure_tp := Z3; prover_str := "z3"::!prover_str;)
  else if tp_str = "redlog" then
    (pure_tp := Redlog; prover_str := "redcsl"::!prover_str;)
  else if tp_str = "math" then
    (pure_tp := Mathematica; prover_str := "mathematica"::!prover_str;)
  else if tp_str = "rm" then
    pure_tp := RM
  else if tp_str = "parahip" then
    pure_tp := PARAHIP
  else if tp_str = "zm" then
    (pure_tp := ZM; 
    prover_str := "z3"::!prover_str;
    prover_str := "mona"::!prover_str;)
  else if tp_str = "auto" then
	(pure_tp := AUTO; prover_str := "oc"::!prover_str;
     prover_str := "z3"::!prover_str;
     prover_str := "mona"::!prover_str;
     prover_str := "coqtop"::!prover_str;
    )
  else if tp_str = "oz" then
	(pure_tp := AUTO; prover_str := "oc"::!prover_str;
     prover_str := "z3"::!prover_str;
    )
  else if tp_str = "prm" then
    (Redlog.is_presburger := true; pure_tp := RM)
  else if tp_str = "spass" then
    (pure_tp := SPASS; prover_str:= "SPASS-MOD"::!prover_str)
  else if tp_str = "minisat" then
    (pure_tp := MINISAT; prover_str := "z3"::!prover_str;)	
  else if tp_str = "log" then
    (pure_tp := LOG; prover_str := "log"::!prover_str)
  else
	();
  check_prover_existence !prover_str

let string_of_tp tp = match tp with
  | OmegaCalc -> "omega"
  | CvcLite -> "cvcl"
  | Cvc3 -> "cvc3"
  | CO -> "co"
  | Isabelle -> "isabelle"
  | Mona -> "mona"
  | MonaH -> "monah"
  | OM -> "om"
  | OI -> "oi"
  | SetMONA -> "set"
  | CM -> "cm"
  | Coq -> "coq"
  | Z3 -> "z3"
  | Redlog -> "redlog"
  | Mathematica -> "mathematica"
  | RM -> "rm"
  | PARAHIP -> "parahip"
  | ZM -> "zm"
  | OZ -> "oz"
  | AUTO -> "auto"
  | DP -> "dp"
  | SPASS -> "spass"
  | MINISAT -> "minisat"
  | LOG -> "log"

let name_of_tp tp = match tp with
  | OmegaCalc -> "Omega Calculator"
  | CvcLite -> "CVC Lite"
  | Cvc3 -> "CVC3"
  | CO -> "CVC Lite and Omega"
  | Isabelle -> "Isabelle"
  | Mona -> "Mona"
  | MonaH -> "MonaH"
  | OM -> "Omega and Mona"
  | OI -> "Omega and Isabelle"
  | SetMONA -> "Set Mona"
  | CM -> "CVC Lite and Mona"
  | Coq -> "Coq"
  | Z3 -> "Z3"
  | Redlog -> "Redlog"
  | Mathematica -> "Mathematica"
  | RM -> "Redlog and Mona"
  | PARAHIP -> "Redlog, Z3, and Mona"
  | ZM -> "Z3 and Mona"
  | OZ -> "Omega, Z3"
  | AUTO -> "Omega, Z3, Mona, Coq"
  | DP -> "DP"
  | SPASS -> "SPASS"
  | MINISAT -> "MINISAT"
  | LOG -> "LOG"

let log_file_of_tp tp = match tp with
  | OmegaCalc -> "allinput.oc"
  | Cvc3 -> "allinput.cvc3"
  | Isabelle -> "allinput.thy"
  | Mona -> "allinput.mona"
  | Coq -> "allinput.v"
  | Redlog -> "allinput.rl"
  | Mathematica -> "allinput.math"
  | Z3 -> "allinput.z3"
  | AUTO -> "allinput.auto"
  | OZ -> "allinput.oz"
  | SPASS -> "allinput.spass"
  | _ -> ""

let get_current_tp_name () = name_of_tp !pure_tp

let omega_count = ref 0

let start_prover () =
  match !pure_tp with
  | Coq -> Coq.start ();
  | Redlog | RM -> Redlog.start ();
  | Cvc3 -> (
      provers_process := Some (Cvc3.start ()); (* because of incremental *)
      let _ = match !provers_process with 
        |Some proc ->  !incremMethodsO#set_process proc
        | _ -> () in
      Omega.start ();
    )
  | Mona -> Mona.start()
  | Mathematica -> Mathematica.start()
  | Isabelle -> (
      Isabelle.start();
      Omega.start();
    )
  | OM -> (
      Mona.start();
      Omega.start();
    )
  | ZM -> (
      Mona.start();
      Smtsolver.start();
    )
  | DP -> Smtsolver.start();
  | Z3 -> Smtsolver.start();
  | SPASS -> Spass.start();
  | LOG -> file_to_proof_log !Globals.source_files
  | MINISAT -> Minisat.start ()
  | _ -> Omega.start()

let start_prover () =
  Gen.Profiling.do_1 "TP.start_prover" start_prover ()

let stop_prover () =
  match !pure_tp with
  | OmegaCalc -> (
      Omega.stop ();
      if !Redlog.is_reduce_running then Redlog.stop ();
    )
  | Coq -> Coq.stop ();
  | Redlog | RM -> (
      Redlog.stop();
      Omega.stop();
    )
  | Cvc3 -> (
      let _ = match !provers_process with
        |Some proc ->  Cvc3.stop proc;
        |_ -> () in
      Omega.stop();
    )
  | Isabelle -> (
      Isabelle.stop();
      Omega.stop();
    )
  | Mona -> Mona.stop();
  | Mathematica -> Mathematica.stop();
  | OM -> (
      Mona.stop();
      Omega.stop();
    )
  | ZM -> (
      Mona.stop();
      Smtsolver.stop();
    )
  | DP -> Smtsolver.stop()
  | Z3 -> Smtsolver.stop();
  | SPASS -> Spass.stop();
  | MINISAT -> Minisat.stop ();
  | _ -> Omega.stop();;

let stop_prover () =
  Gen.Profiling.do_1 "TP.stop_prover" stop_prover ()

(* Method checking whether a formula contains bag constraints or BagT vars *)

let is_bag_b_constraint (pf,_) = match pf with
    | CP.BConst _ 
    | CP.BVar _
    | CP.Lt _ 
    | CP.Lte _ 
    | CP.Gt _ 
    | CP.Gte _
    | CP.EqMax _ 
    | CP.EqMin _
    | CP.ListIn _ 
    | CP.ListNotIn _
    | CP.ListAllN _ 
    | CP.ListPerm _
        -> Some false
    | CP.BagIn _ 
    | CP.BagNotIn _
    | CP.BagMin _ 
    | CP.BagMax _
    | CP.BagSub _
        -> Some true
    | _ -> None

let is_bag_constraint (e: CP.formula) : bool =  
  let f_e e = match e with
    | CP.Bag _
    | CP.BagUnion _
    | CP.BagIntersect _
    | CP.BagDiff _ 
        -> Some true
    | CP.Var (CP.SpecVar (t, _, _), _) -> 
        (match t with
          | BagT _ -> Some true
          | _ -> Some false)
    | _ -> Some false
  in
  let or_list = List.fold_left (||) false in
  CP.fold_formula e (nonef, is_bag_b_constraint, f_e) or_list

let rec is_memo_bag_constraint (f:memo_pure): bool = 
  List.exists (fun c-> 
      (List.exists is_bag_constraint c.memo_group_slice)|| 
      (List.exists (fun c-> match is_bag_b_constraint c.memo_formula with | Some b-> b |_ -> false) c.memo_group_cons)
  ) f

(* TODO : make this work for expression *)
let rec is_array_exp e = match e with
  | CP.List _
  | CP.ListCons _
  | CP.ListHead _
  | CP.ListTail _
  | CP.ListLength _
  | CP.ListAppend _
  | CP.ListReverse _ ->
      Some false
  | CP.Add (e1,e2,_)
  | CP.Subtract (e1,e2,_)
  | CP.Mult (e1,e2,_)
  | CP.Div (e1,e2,_)
  | CP.Max (e1,e2,_)
  | CP.Min (e1,e2,_)
  | CP.BagDiff (e1,e2,_) -> (
      match (is_array_exp e1) with
      | Some true -> Some true
      | _ -> is_array_exp e2
    )
  | CP.Bag (el,_)
  | CP.BagUnion (el,_)
  | CP.BagIntersect (el,_) -> (
      List.fold_left (fun res exp -> match res with
                      | Some true -> Some true
                      | _ -> is_array_exp exp) (Some false) el
    )
  | CP.ArrayAt (_,_,_) -> Some true
  | CP.Func _ -> Some false
  | CP.TypeCast (_, e1, _) -> is_array_exp e1
  | CP.AConst _ | CP.FConst _ | CP.IConst _ | CP.Tsconst _ | CP.InfConst _ 
  | CP.Level _
  | CP.Var _ | CP.Null _ -> Some false

  (* Method checking whether a formula contains list constraints *)
let rec is_list_exp e = match e with
  | CP.List _
  | CP.ListCons _
  | CP.ListHead _
  | CP.ListTail _
  | CP.ListLength _
  | CP.ListAppend _
  | CP.ListReverse _ -> Some true
  | CP.Add (e1,e2,_)
  | CP.Subtract (e1,e2,_)
  | CP.Mult (e1,e2,_)
  | CP.Div (e1,e2,_)
  | CP.Max (e1,e2,_)
  | CP.Min (e1,e2,_)
  | CP.BagDiff (e1,e2,_) -> (
      match (is_list_exp e1) with
      | Some true -> Some true
      | _ -> is_list_exp e2
    )
  | CP.Bag (el,_)
  | CP.BagUnion (el,_)
  | CP.BagIntersect (el,_) -> (
      List.fold_left (fun res exp -> match res with
                      | Some true -> Some true
                      | _ -> is_list_exp exp) (Some false) el
    )
  | CP.TypeCast (_, e1, _) -> is_list_exp e1
  | CP.ArrayAt (_,_,_) | CP.Func _ -> Some false
  | CP.Null _ | CP.AConst _ | CP.Tsconst _ | CP.InfConst _
  | CP.Level _
  | CP.FConst _ | CP.IConst _ -> Some false
  | CP.Var(sv,_) -> if CP.is_list_var sv then Some true else Some false

(*let f_e e = Debug.no_1 "f_e" (Cprinter.string_of_formula_exp) (fun s -> match s with
	| Some ss -> string_of_bool ss
	| _ -> "") f_e_1 e
*)	

(* TODO : where are the array components *)
let is_array_b_formula (pf,_) = match pf with
    | CP.BConst _ | CP.XPure _ 
    | CP.BVar _
	| CP.BagMin _ 
    | CP.BagMax _
    | CP.SubAnn _
    | CP.LexVar _
		-> Some false    
    | CP.Lt (e1,e2,_) 
    | CP.Lte (e1,e2,_) 
    | CP.Gt (e1,e2,_)
    | CP.Gte (e1,e2,_)
	| CP.Eq (e1,e2,_)
	| CP.Neq (e1,e2,_)
	| CP.BagSub (e1,e2,_)
		-> (match (is_array_exp e1) with
						| Some true -> Some true
						| _ -> is_array_exp e2)
    | CP.EqMax (e1,e2,e3,_)
    | CP.EqMin (e1,e2,e3,_)
		-> (match (is_array_exp e1) with
						| Some true -> Some true
						| _ -> (match (is_array_exp e2) with
											| Some true -> Some true
											| _ -> is_array_exp e3))
    | CP.BagIn (_,e,_) 
    | CP.BagNotIn (_,e,_)
		-> is_array_exp e
    | CP.ListIn _ 
    | CP.ListNotIn _
    | CP.ListAllN _ 
    | CP.ListPerm _
        -> Some false
    | CP.RelForm _ -> Some true
    | CP.VarPerm _ -> Some false

let is_list_b_formula (pf,_) = match pf with
    | CP.BConst _ 
    | CP.BVar _
	| CP.BagMin _ 
    | CP.BagMax _
		-> Some false    
    | CP.Lt (e1,e2,_) 
    | CP.Lte (e1,e2,_) 
    | CP.Gt (e1,e2,_)
    | CP.Gte (e1,e2,_)
	| CP.Eq (e1,e2,_)
	| CP.Neq (e1,e2,_)
	| CP.BagSub (e1,e2,_)
		-> (match (is_list_exp e1) with
						| Some true -> Some true
						| _ -> is_list_exp e2)
    | CP.EqMax (e1,e2,e3,_)
    | CP.EqMin (e1,e2,e3,_)
		-> (match (is_list_exp e1) with
						| Some true -> Some true
						| _ -> (match (is_list_exp e2) with
											| Some true -> Some true
											| _ -> is_list_exp e3))
    | CP.BagIn (_,e,_) 
    | CP.BagNotIn (_,e,_)
		-> is_list_exp e
    | CP.ListIn _ 
    | CP.ListNotIn _
    | CP.ListAllN _ 
    | CP.ListPerm _
        -> Some true
    | _ -> Some false
 
let is_array_constraint (e: CP.formula) : bool =
 
  let or_list = List.fold_left (||) false in
  CP.fold_formula e (nonef, is_array_b_formula, is_array_exp) or_list

let is_relation_b_formula (pf,_) = match pf with
    | CP.RelForm _ -> Some true
    | _ -> Some false

let is_relation_constraint (e: CP.formula) : bool =
  let or_list = List.fold_left (||) false in
  CP.fold_formula e (nonef, is_relation_b_formula, nonef) or_list

let is_list_constraint (e: CP.formula) : bool =
 
  let or_list = List.fold_left (||) false in
  CP.fold_formula e (nonef, is_list_b_formula, is_list_exp) or_list

let is_list_constraint (e: CP.formula) : bool =
  (*Debug.no_1_opt "is_list_constraint" Cprinter.string_of_pure_formula string_of_bool (fun r -> not(r)) is_list_constraint e*)
  Debug.no_1 "is_list_constraint" Cprinter.string_of_pure_formula string_of_bool is_list_constraint e
  
let rec is_memo_list_constraint (f:memo_pure): bool = 
  List.exists (fun c-> 
      (List.exists is_list_constraint c.memo_group_slice)|| 
      (List.exists (fun c-> match is_list_b_formula c.memo_formula with | Some b-> b| _ -> false) c.memo_group_cons)
  ) f  
  
let is_mix_bag_constraint f = match f with
  | MCP.MemoF f -> is_memo_bag_constraint f
  | MCP.OnePF f -> is_bag_constraint f

let is_mix_list_constraint f = match f with
  | MCP.MemoF f -> is_memo_list_constraint f
  | MCP.OnePF f -> is_list_constraint f  
  
let elim_exists (f : CP.formula) : CP.formula =
  let ef = if !elim_exists_flag then CP.elim_exists f else f in
  ef
	
let elim_exists (f : CP.formula) : CP.formula =
  let pr = Cprinter.string_of_pure_formula in
  Debug.no_1 "elim_exists" pr pr elim_exists f
  

let sat_label_filter fct f =
  let pr = Cprinter.string_of_pure_formula in
  let test f1 = 
	if no_andl f1 then  fct f1 
	else report_error no_pos ("unexpected imbricated AndList in tpdispatcher sat: "^(pr f)) in
  let rec helper_x f = match f with 
		| AndList b -> 
			let lbls = Label_Pure.get_labels b in
                        let (comp,fil) = 
                          if false (* !Globals.label_aggressive_flag || !Globals.label_aggressive_sat *) 
                          then (Label_only.Lab_List.is_fully_compatible,fun fs -> fs)
                          else (Label_only.Lab_List.is_part_compatible,
                             List.filter (fun (l,_)-> not(Label_only.Lab_List.is_common l)) ) 
                        in
			let fs = List.map (fun l -> 
			    let lst = List.filter (fun (c,_)-> comp c l) b in
			    (l,List.fold_left (fun a c-> mkAnd a (snd c) no_pos) (mkTrue no_pos) lst)) lbls in
                        let _ = Debug.ninfo_hprint (add_str "fs" Label_Pure.string_of) fs no_pos in
                        (* let fs2 = List.filter (fun (l,_)-> l!=[]) fs in *)
                        let fs2 = fil fs in
                        let fs = if fs2==[] then fs else fs2 in
                        let _ = Debug.ninfo_hprint (add_str "label,fs" (pr_list (pr_pair (pr_list pr_id) pr)))  fs no_pos in
			List.for_all (fun (_,f) -> test f) fs
		| Or (f1,f2,_ ,_)-> (helper f1)||(helper f2)
		| _ -> test f 
  and helper f = Debug.no_1_loop "sat_label_filter_helper"  !print_formula string_of_bool helper_x f in
	helper f
	
let sat_label_filter fct f = 
	Gen.Profiling.do_1 "sat_label_filter" (sat_label_filter fct) f
  
let sat_label_filter fct f =  Debug.no_1 "sat_label_filter" !print_formula string_of_bool (fun _ -> sat_label_filter fct f) f
  
let imply_label_filter ante conseq = 
  (*let s = "unexpected imbricated AndList in tpdispatcher impl: "^(Cprinter.string_of_pure_formula ante)^"|-"^(Cprinter.string_of_pure_formula conseq)^"\n" in*)
  let comp = 
    if false (* !Globals.label_aggressive_flag *)
    then Label_only.Lab_List.is_fully_compatible
    else Label_only.Lab_List.is_part_compatible
  in
  match ante,conseq with
    | Or _,_  
    | _ , Or _ -> [(andl_to_and ante, andl_to_and conseq)]
    | AndList ba, AndList bc -> 
	  (*let fc = List.for_all (fun (_,c)-> no_andl c) in
	    (if fc ba && fc bc then () else print_string s;*)
	  List.map (fun (l, c)-> 
	      let lst = List.filter (fun (c,_)-> comp (* Label_only.Lab_List.is_part_compatible *) c l) ba in 
	      let fr1 = List.fold_left (fun a (_,c)-> mkAnd a c no_pos) (mkTrue no_pos) lst in
	      (*(andl_to_and fr1, andl_to_and c)*)
	      (fr1,c)) bc
    | AndList ba, _ -> [(andl_to_and ante,conseq)]
	  (*if (List.for_all (fun (_,c)-> no_andl c) ba)&& no_andl conseq then () else print_string s;*)
    | _ , AndList bc -> List.map (fun (_,c)-> (ante,c)) bc 
    | _ -> [ante,conseq]
	    (*if (no_andl ante && no_andl conseq) then [ante,conseq]
	      else 
	      (print_string s;
	      [(andl_to_and ante),(andl_to_and conseq)])*)
            
  
  (*keeps labels only if both sides have labels otherwise do a smart collection.*)
  (*this applies to term reasoning for example as it seems the termination annotations loose the labels...*)
    let imply_label_filter ante conseq = 
      let pr = !print_formula in
      Debug.no_2 "imply_label_filter" pr pr (pr_list (pr_pair pr pr)) imply_label_filter ante conseq
  
let assumption_filter_slicing (ante : CP.formula) (cons : CP.formula) : (CP.formula * CP.formula) =
  let overlap (nlv1, lv1) (nlv2, lv2) =
	if (nlv1 = [] && nlv2 = []) then (Gen.BList.list_equiv_eq CP.eq_spec_var lv1 lv2)
	else (Gen.BList.overlap_eq CP.eq_spec_var nlv1 nlv2) && (Gen.BList.list_equiv_eq CP.eq_spec_var lv1 lv2)
  in
  
  let rec group_conj l = match l with
    | [] -> (false,[]) 
    | ((f_nlv, f_lv), fs)::t ->  
      let b,l = group_conj t in
      let l1, l2 = List.partition (fun (cfv, _) -> overlap (f_nlv, f_lv) cfv) l in
      if l1==[] then (b,((f_nlv, f_lv), fs)::l) 
      else 
        let l_fv, nfs = List.split l1 in
		let l_nlv, l_lv = List.split l_fv in
        let nfs = CP.join_conjunctions (fs::nfs) in
        let n_nlv = CP.remove_dups_svl (List.concat (f_nlv::l_nlv)) in
		let n_lv = CP.remove_dups_svl (List.concat (f_lv::l_lv)) in
        (true,((n_nlv, n_lv), nfs)::l2)
  in
  
  let rec fix n_l = 
    let r1, r2 = group_conj n_l in
    if r1 then fix r2 else r2
  in    

  let split_sub_f f = 
    let conj_list = CP.split_conjunctions f in
    let n_l = List.map
	  (fun c -> (CP.fv_with_slicing_label c, c)) conj_list in
    snd (List.split (fix n_l))
  in

  let pick_rel_constraints cons ante =
	let fv = CP.fv cons in
	let rec exhaustive_collect_with_selection fv ante =
	  let (n_fv, n_ante1, r_ante) = List.fold_left (
		fun (afv, ac, rc) f ->
		  let f_ulv, f_lv = CP.fv_with_slicing_label f in
		  let cond_direct = Gen.BList.overlap_eq CP.eq_spec_var afv f_ulv in
		  let cond_link = (f_ulv = []) && (Gen.BList.subset_eq CP.eq_spec_var f_lv afv) in
		  if (cond_direct || cond_link) then
			(afv@(CP.fv f), ac@[f], rc)
		  else (afv, ac, rc@[f])
	  ) (fv, [], []) ante
	  in
	  if n_fv = fv then n_ante1
	  else
		let n_ante2 = exhaustive_collect_with_selection n_fv r_ante in
		n_ante1 @ n_ante2
	in
	exhaustive_collect_with_selection fv ante
  in

  let ante = CP.elim_exists(*_with_fresh_vars*) ante in

  let l_ante = split_sub_f ante in

  (*let _ = print_string ("imply_timeout: filter: l_ante:\n" ^
    (List.fold_left (fun acc f -> acc ^ "+++++++++\n" ^ (Cprinter.string_of_pure_formula f) ^ "\n") "" l_ante)) in*)

  (CP.join_conjunctions (pick_rel_constraints cons l_ante), cons)
	   
let assumption_filter (ante : CP.formula) (cons : CP.formula) : (CP.formula * CP.formula) =
  let conseq_vars = CP.fv cons in
  if (List.exists (fun v -> CP.name_of_spec_var v = waitlevel_name) conseq_vars) then
    (ante,cons)
  else
  CP.assumption_filter ante cons

let assumption_filter (ante : CP.formula) (cons : CP.formula) : (CP.formula * CP.formula) =
  let pr = Cprinter.string_of_pure_formula in
  Debug.no_2 "assumption_filter" pr pr (fun (l, _) -> pr l)
	assumption_filter ante cons

	  
(* rename and shorten variables for better caching of formulas *)
(* TODO WN: check if it avoids name clashes? *)
let norm_var_name (e: CP.formula) : CP.formula =
  let shorten_sv (CP.SpecVar (typ, name, prm)) vnames =
    let short_name =
      try
        Hashtbl.find vnames name
      with Not_found ->
        let fresh_name = "v" ^ (string_of_int (Hashtbl.length vnames)) in
        let _ = Hashtbl.add vnames name fresh_name in
        fresh_name
    in
    CP.SpecVar (typ, short_name, prm)
  in
  let f_bf vnames bf =
	let (pf,il) = bf in
	match pf with
    | CP.BVar (sv, l) -> Some ((CP.BVar (shorten_sv sv vnames, l)), il)
    | _ -> None
  in
  let f_e vnames e = match e with
    | CP.Var (sv, l) ->
        Some (CP.Var (shorten_sv sv vnames, l))
    | _ -> None
  in
  let rec simplify f0 vnames = match f0 with
    | CP.Forall (sv, f1, lbl, l) ->
        let nsv = shorten_sv sv vnames in
        let nf1 = simplify f1 vnames in
        CP.Forall (nsv, nf1, lbl, l)
    | CP.Exists (sv, f1, lbl, l) ->
        let nsv = shorten_sv sv vnames in
        let nf1 = simplify f1 vnames in
        CP.Exists (nsv, nf1, lbl, l)
    | CP.And (f1, f2, l) ->
        let nf1 = simplify f1 vnames in
        let nf2 = simplify f2 vnames in
        CP.And (nf1, nf2, l)
	| CP.AndList b -> CP.AndList (map_l_snd (fun c -> simplify c vnames) b)
    | CP.Or (f1, f2, lbl, l) ->
        let nf1 = simplify f1 vnames in
        let nf2 = simplify f2 vnames in
        CP.mkOr nf1 nf2 lbl l
    | CP.Not (f1, lbl, l) ->
        CP.Not (simplify f1 vnames, lbl, l)
    | CP.BForm (bf, lbl) ->
        CP.BForm (CP.map_b_formula_arg bf vnames (f_bf, f_e) (idf2, idf2), lbl)
  in
  simplify e (Hashtbl.create 100)

let norm_var_name (e: CP.formula) : CP.formula =
  let pr = Cprinter.string_of_pure_formula in
  Debug.no_1 "norm_var_name" pr pr norm_var_name e

(* Statistical function for formula size counting *)
let disj_cnt a c s =
  if (!Globals.enable_counters) then
	begin
	  let rec p_f_size f = match f with
		| CP.BForm _ -> 1
		| CP.AndList b -> List.fold_left (fun a (_,c)-> a+(p_f_size c)) 0 b
		| CP.And (f1,f2,_) | CP.Or (f1,f2,_,_) -> (p_f_size f1)+(p_f_size f2)
		| CP.Not (f,_,_) | CP.Forall (_,f,_,_ ) | CP.Exists (_,f,_,_) -> p_f_size f in

	  let rec or_f_size f = match f with
		| CP.BForm _ -> 1
		| CP.And (f1,f2,_) -> (or_f_size f1)*(or_f_size f2)
		| CP.AndList b -> List.fold_left (fun a (_,c)-> a*(p_f_size c)) 0 b
		| CP.Or (f1,f2,_,_) -> (or_f_size f1)+(or_f_size f2)
		| CP.Not (f,_,_) | CP.Forall (_,f,_,_ ) | CP.Exists (_,f,_,_) -> or_f_size f in
      let rec add_or_f_size f = match f with
		| CP.BForm _ -> 0
		| CP.AndList b -> List.fold_left (fun a (_,c)-> a+(p_f_size c)) 0 b
		| CP.And (f1,f2,_) -> (add_or_f_size f1)+(add_or_f_size f2)
		| CP.Or (f1,f2,_,_) -> 1+(add_or_f_size f1)+(add_or_f_size f2)
		| CP.Not (f,_,_) | CP.Forall (_,f,_,_ ) | CP.Exists (_,f,_,_) -> add_or_f_size f in
      match c with
		| None -> 
          Gen.Profiling.inc_counter ("stat_count_"^s);
          Gen.Profiling.add_to_counter ("z_stat_disj_"^s) (1+(add_or_f_size a));
          Gen.Profiling.add_to_counter ("stat_disj_count_"^s) (or_f_size a);
          Gen.Profiling.add_to_counter ("stat_size_count_"^s) (p_f_size a)
		| Some c-> 
          Gen.Profiling.inc_counter ("stat_count_"^s);
          Gen.Profiling.add_to_counter ("z_stat_disj_"^s) (1+(add_or_f_size a)); 
          Gen.Profiling.add_to_counter ("stat_disj_count_"^s) ((or_f_size a)+(or_f_size c));
          Gen.Profiling.add_to_counter ("stat_size_count_"^s) ((p_f_size a)+(p_f_size c)) ;
    end
  else ()

let tp_is_sat_no_cache (f : CP.formula) (sat_no : string) =
  if not !tp_batch_mode then start_prover ();
  let f = if (!Globals.allow_locklevel) then
        (*should translate waitlevel before level*)
        let f = CP.translate_waitlevel_pure f in
        let f = CP.translate_level_pure f in
        let _ = Debug.devel_hprint (add_str "After translate_: " Cprinter.string_of_pure_formula) f no_pos in
        f
      else
        (* let f = CP.drop_svl_pure f [(CP.mkWaitlevelVar Unprimed);(CP.mkWaitlevelVar Primed)] in *)
        (* let f = CP.drop_locklevel_pure f in *)
        f
  in
  let vrs = Cpure.fv f in
  let imm_vrs = List.filter (fun x -> (CP.type_of_spec_var x) == AnnT) vrs in 
  let f = Cpure.add_ann_constraints imm_vrs f in
  let _ = disj_cnt f None "sat_no_cache" in
  let (pr_weak,pr_strong) = CP.drop_complex_ops in
  let (pr_weak_z3,pr_strong_z3) = CP.drop_complex_ops_z3 in
    (* Handle Infinity Constraints *)
  let f = if !Globals.allow_inf then Infinity.normalize_inf_formula_sat f else f in
  let wf = f in
  let omega_is_sat f = Omega.is_sat_ops pr_weak pr_strong f sat_no in
  let redlog_is_sat f = Redlog.is_sat_ops pr_weak pr_strong f sat_no in
  let mathematica_is_sat f = Mathematica.is_sat_ops pr_weak pr_strong f sat_no in
  let mona_is_sat f = Mona.is_sat_ops pr_weak pr_strong f sat_no in
  let coq_is_sat f = Coq.is_sat_ops pr_weak pr_strong f sat_no in
  let z3_is_sat f = Smtsolver.is_sat_ops pr_weak_z3 pr_strong_z3 f sat_no in

  (* let _ = Gen.Profiling.push_time "tp_is_sat" in *)
  let res = (
    match !pure_tp with
    | DP -> 
        let r = Dp.is_sat f sat_no in
        if test_db then (
          (* let r2 = Smtsolver.is_sat f sat_no in *)
          let r2 = z3_is_sat f in
          if r=r2 then r
          else failwith ("dp-omega mismatch on sat: "^(Cprinter.string_of_pure_formula f)^" d:"^(string_of_bool r)^" o:"^(string_of_bool r2)^"\n")
        )
        else r
    | OmegaCalc ->
        if (CP.is_float_formula wf) then (redlog_is_sat wf)
        else (omega_is_sat f);
    | CvcLite -> Cvclite.is_sat f sat_no
    | Cvc3 -> (
        match !provers_process with
          |Some proc -> Cvc3.is_sat_increm !provers_process f sat_no
          | _ -> Cvc3.is_sat f sat_no
      )
    | Z3 -> z3_is_sat f
    | Isabelle -> Isabelle.is_sat wf sat_no
    | Coq ->
        if (is_list_constraint wf) then (coq_is_sat wf)
        else (Smtsolver(*Omega*).is_sat f sat_no);
    | Mona | MonaH -> mona_is_sat wf
    | CO -> (
        let result1 = (Cvc3.is_sat_helper_separate_process wf sat_no) in
        match result1 with
        | Some f -> f
        | None -> omega_count := !omega_count + 1;
                  (omega_is_sat f)
      )
    | CM -> (
        if (is_bag_constraint wf) then (mona_is_sat wf)
        else
          let result1 = (Cvc3.is_sat_helper_separate_process wf sat_no) in
          match result1 with
            | Some f -> f
            | None -> omega_count := !omega_count + 1;
                      (omega_is_sat f)
      )
    | OM ->
        if (is_bag_constraint wf) then (mona_is_sat wf)
        else (omega_is_sat f)
    | AUTO ->
        if (is_bag_constraint wf) then (mona_is_sat wf)
        else if (is_list_constraint wf) then (coq_is_sat wf)
        else if (is_array_constraint f) then (z3_is_sat f)
        else (omega_is_sat f)
    | OZ ->
        if (is_array_constraint f) then (z3_is_sat f)
        else (omega_is_sat f)
    | OI ->
        if (is_bag_constraint wf) then (Isabelle.is_sat wf sat_no)
        else (omega_is_sat f)
    | SetMONA -> Setmona.is_sat wf
    | Redlog -> redlog_is_sat wf
    | Mathematica -> mathematica_is_sat wf
    | RM ->
        if (is_bag_constraint wf) && (CP.is_float_formula wf) then
            (* Mixed bag constraints and float constraints *)
            (*TO CHECK: soundness. issat(f) = issat(f1) & is(satf2)*)
          let f_no_float = CP.drop_float_formula wf in
          let f_no_bag = CP.drop_bag_formula wf in
          let _ = Debug.devel_zprint (lazy ("SAT #" ^ sat_no ^ " : mixed float + bag constraints ===> partitioning: \n ### " ^ (!print_pure wf) ^ "\n INTO : " ^ (!print_pure f_no_float) ^ "\n AND : " ^ (!print_pure f_no_bag) )) no_pos
          in
          let b1 = mona_is_sat f_no_float in
          let b2 = redlog_is_sat f_no_bag in
            (* let _ = print_endline ("\n### b1 = " ^ (string_of_bool b1) ^ "\n ### b2 = "^ (string_of_bool b2)) in *)
          (b1 && b2)
        else
          if (is_bag_constraint wf) then
            mona_is_sat wf
          else
            redlog_is_sat wf
    | PARAHIP ->
          if (is_relation_constraint wf) && (is_bag_constraint wf) && (CP.is_float_formula wf) then
            (* Mixed bag constraints, relations and float constraints *)
            (*TO CHECK: soundness. issat(f) = issat(f1) & is(satf2)*)
            let f_no_float_rel = CP.drop_rel_formula (CP.drop_float_formula wf) in
            let f_no_bag_rel = CP.drop_rel_formula (CP.drop_bag_formula wf) in
            let f_no_float_bag = CP.drop_float_formula (CP.drop_bag_formula wf) in
            let _ = Debug.devel_zprint (lazy ("SAT #" ^ sat_no ^ " : mixed float + relation + bag constraints ===> partitioning: \n ### " ^ (!print_pure wf) ^ "\n INTO : " ^ (!print_pure f_no_float_rel) ^ "\n AND : " ^ (!print_pure f_no_bag_rel) ^ "\n AND : " ^ (!print_pure f_no_float_bag) )) no_pos
            in
            let b1 = mona_is_sat f_no_float_rel in
            let b2 = redlog_is_sat f_no_bag_rel in
            let b3 = z3_is_sat f_no_float_bag in
            (b1 && b2 &&b3)
          else
          (*UNSOUND - for experimental purpose only*)
          if (is_bag_constraint wf) && (CP.is_float_formula wf) then
            (* Mixed bag constraints and float constraints *)
            (*TO CHECK: soundness. issat(f) = issat(f1) & is(satf2)*)
            let f_no_float = CP.drop_float_formula wf in
            let f_no_bag = CP.drop_bag_formula wf in
            let _ = Debug.devel_zprint (lazy ("SAT #" ^ sat_no ^ " : mixed float + bag constraints ===> partitioning: \n ### " ^ (!print_pure wf) ^ "\n INTO : " ^ (!print_pure f_no_float) ^ "\n AND : " ^ (!print_pure f_no_bag) )) no_pos
            in
            let b1 = mona_is_sat f_no_float in
            let b2 = redlog_is_sat f_no_bag in
            (b1 && b2)
          else
          if (is_relation_constraint wf) then
            let f = CP.drop_bag_formula (CP.drop_float_formula wf) in
            z3_is_sat f
          else
          if (is_bag_constraint wf ) then
            let f = CP.drop_rel_formula (CP.drop_float_formula wf) in
            mona_is_sat f
          else
            let f = CP.drop_rel_formula (CP.drop_bag_formula wf) in
            redlog_is_sat f
    | ZM ->
        if (is_bag_constraint wf) then mona_is_sat wf
        else z3_is_sat wf
    | SPASS -> Spass.is_sat f sat_no
    | MINISAT -> Minisat.is_sat f sat_no
    | LOG -> find_bool_proof_res sat_no
  ) in 
  if not !tp_batch_mode then stop_prover ();
  res

let tp_is_sat_no_cache (f : CP.formula) (sat_no : string) = 
  Gen.Profiling.do_1 "tp_is_sat_no_cache" (tp_is_sat_no_cache f) sat_no
	
let tp_is_sat_no_cache (f : CP.formula) (sat_no : string) = 
	Debug.no_2 "tp_is_sat_no_cache" 
	Cprinter.string_of_pure_formula (fun s -> s) string_of_bool
	tp_is_sat_no_cache f sat_no
  
let tp_is_sat_perm f sat_no = 
  if !perm=Dperm then match CP.has_tscons f with
	| No_cons -> tp_is_sat_no_cache f sat_no
	| No_split	-> true
	| Can_split ->
		let tp_wrap f = if CP.isConstTrue f then true else tp_is_sat_no_cache f sat_no in
		let tp_wrap f = Debug.no_1 "tp_is_sat_perm_wrap" Cprinter.string_of_pure_formula (fun c-> "") tp_wrap f in
		let ss_wrap (e,f) = if f=[] then true else Share_prover_w.sleek_sat_wrapper (e,f) in
		List.exists (fun f-> tp_wrap (CP.tpd_drop_perm f) && ss_wrap ([],CP.tpd_drop_nperm f)) (snd (CP.dnf_to_list f)) 
  else tp_is_sat_no_cache f sat_no
 
let tp_is_sat_perm f sat_no =  Debug.no_1_loop "tp_is_sat_perm" Cprinter.string_of_pure_formula string_of_bool (fun _ -> tp_is_sat_perm f sat_no) f

let cache_status = ref false 
let cache_sat_count = ref 0 
let cache_sat_miss = ref 0 
let cache_imply_count = ref 0 
let cache_imply_miss = ref 0 

let last_prover () =
  if !cache_status then "CACHED"
  else  Others.last_tp_used # string_of

let sat_cache is_sat (f:CP.formula) : bool  = 
  let _ = Gen.Profiling.push_time_always "cache overhead" in
  let sf = norm_var_name f in
  let fstring = Cprinter.string_of_pure_formula sf in
  let _ = cache_sat_count := !cache_sat_count+1 in
  let _ = cache_status := true in
  let _ = Gen.Profiling.pop_time_always "cache overhead" in
  let res =
    try
      Hashtbl.find !sat_cache fstring
    with Not_found ->
        let r = is_sat f in
        let _ = Gen.Profiling.push_time_always "cache overhead" in
        let _ = cache_status := false in
        let _ = cache_sat_miss := !cache_sat_miss+1 in
        let _ = Hashtbl.add !sat_cache fstring r in
        let _ = Gen.Profiling.pop_time_always "cache overhead" in
        r
  in res

let sat_cache is_sat (f:CP.formula) : bool = 
  let pr = Cprinter.string_of_pure_formula in
  let pr2 b = ("found?:"^(string_of_bool !cache_status)
    ^" ans:"^(string_of_bool b)) in
  Debug.no_1 "sat_cache" pr pr2 (sat_cache is_sat) f

let tp_is_sat (f:CP.formula) (old_sat_no :string) = 
  (* TODO WN : can below remove duplicate constraints? *)
  (* let f = CP.elim_idents f in *)
  (* this reduces x>=x to true; x>x to false *)
  proof_no := !proof_no+1 ;
  let sat_no = (string_of_int !proof_no) in
  Debug.devel_zprint (lazy ("SAT #" ^ sat_no)) no_pos;
  Debug.devel_zprint (lazy (!print_pure f)) no_pos;
  (* let tstart = Gen.Profiling.get_time () in		 *)
  let fn_sat f = (tp_is_sat_perm f) sat_no in
  let cmd = PT_SAT f in
  let _ = Log.last_proof_command # set cmd in
  let res = 
    (if !Globals.no_cache_formula then
      Timelog.logtime_wrapper "SAT-nocache" fn_sat f
    else
      (Timelog.logtime_wrapper "SAT" sat_cache fn_sat) f)
  in
  (* let tstop = Gen.Profiling.get_time () in *)
  let _= add_proof_log !cache_status old_sat_no sat_no (string_of_prover !pure_tp) cmd (Timelog.logtime # get_last_time) (PR_BOOL res) in 
  res

let tp_is_sat f sat_no =
  Debug.no_1 "tp_is_sat" Cprinter.string_of_pure_formula string_of_bool 
      (fun f -> tp_is_sat f sat_no) f
    
(* let tp_is_sat (f: CP.formula) (sat_no: string) do_cache = *)
(*   let pr = Cprinter.string_of_pure_formula in *)
(*   Debug.no_1 "tp_is_sat" pr string_of_bool (fun _ -> tp_is_sat f sat_no do_cache) f *)

(* let simplify_omega (f:CP.formula): CP.formula =  *)
(*   if is_bag_constraint f then f *)
(*   else Omega.simplify f    *)
            
(* let simplify_omega f = *)
(*   Debug.no_1 "simplify_omega" *)
(* 	Cprinter.string_of_pure_formula *)
(* 	Cprinter.string_of_pure_formula *)
(* 	simplify_omega f *)

let simplify (f : CP.formula) : CP.formula =
  proof_no := !proof_no + 1;
  let simpl_no = (string_of_int !proof_no) in
  if !Globals.no_simpl then f else
    if !perm=Dperm && CP.has_tscons f<>CP.No_cons then f 
    else 
      let cmd = PT_SIMPLIFY f in
      let _ = Log.last_proof_command # set cmd in
      let omega_simplify f = Omega.simplify f in
      (* this simplifcation will first remove complex formula as boolean
         vars but later restore them *)
      if !external_prover then 
        match Netprover.call_prover (Simplify f) with
          | Some res -> res
          | None -> f
      else 
        begin
          let tstart = Gen.Profiling.get_time () in
          try
            if not !tp_batch_mode then start_prover ();
              Gen.Profiling.push_time "simplify";
              let fn f = 
                match !pure_tp with
                  | DP -> Dp.simplify f
                  | Isabelle -> Isabelle.simplify f
                  | Coq -> 
                        if (is_list_constraint f) then
                          (Coq.simplify f)
                        else ((*Omega*)Smtsolver.simplify f)
                  | Mona | MonaH ->
                        if (is_bag_constraint f) then
                          (Mona.simplify f)
                        else
                          (* exist x, f0 ->  eexist x, x>0 /\ f0*)
                          let f1 = CP.add_gte0_for_mona f in
                          let f=(omega_simplify f1) in
                          CP.arith_simplify 12 f
                  | OM ->
                        if (is_bag_constraint f) then (Mona.simplify f)
                        else
                          let f=(omega_simplify f) in
                          CP.arith_simplify 12 f
                  | OI ->
                        if (is_bag_constraint f) then (Isabelle.simplify f)
                        else (omega_simplify f)
                  | SetMONA -> Mona.simplify f
                  | CM ->
                        if is_bag_constraint f then Mona.simplify f
                        else omega_simplify f
                  | Z3 -> Smtsolver.simplify f
                  | Redlog -> Redlog.simplify f
                  | RM ->
                        if is_bag_constraint f then Mona.simplify f
                        else Redlog.simplify f
                  | PARAHIP ->
                        if is_bag_constraint f then
                          Mona.simplify f
                        else
                          Redlog.simplify f
                  | ZM -> 
                        if is_bag_constraint f then Mona.simplify f
                        else Smtsolver.simplify f
                  | AUTO ->
                        if (is_bag_constraint f) then (Mona.simplify f)
                        else if (is_list_constraint f) then (Coq.simplify f)
                        else if (is_array_constraint f) then (Smtsolver.simplify f)
                        else (omega_simplify f)
                  | OZ ->
                        if (is_array_constraint f) then (Smtsolver.simplify f)
                        else (omega_simplify f)
                  | SPASS -> Spass.simplify f
                  | LOG -> find_formula_proof_res simpl_no
                  | _ -> omega_simplify f 
              in
              let r = Timelog.logtime_wrapper "simplify" fn f in
              Gen.Profiling.pop_time "simplify";
              let tstop = Gen.Profiling.get_time () in
              if not !tp_batch_mode then stop_prover ();
              (*let _ = print_string ("\nsimplify: f after"^(Cprinter.string_of_pure_formula r)) in*)
              (* To recreate <IL> relation after simplifying *)
              let res = ( 
                  (* if !Globals.do_slicing then *)
                  if not !Globals.dis_slc_ann then
                    let rel_vars_lst =
                      let bfl = CP.break_formula f in
                      (* let bfl_no_il = List.filter (fun (_,il) -> match il with *)
                      (* | None -> true | _ -> false) bfl in                      *)
                      (List.map (fun (svl,lkl,_) -> (svl,lkl)) (CP.group_related_vars bfl))
                    in CP.set_il_formula_with_dept_list r rel_vars_lst
                  else r
              ) in   
              (* TODO : add logtime for simplify *)
              (* Why start/stop prver when interactive? *)
              let _= add_proof_log !cache_status simpl_no simpl_no (string_of_prover !pure_tp) cmd (Timelog.logtime # get_last_time) (PR_FORMULA res) in
              res
          with | _ -> 
              let _= add_proof_log !cache_status simpl_no simpl_no (string_of_prover !pure_tp) cmd 
                (0.0) (PR_exception) in
              f
        end
(*for AndList it simplifies one batch at a time*)
let simplify (f:CP.formula):CP.formula =
  let rec helper f = match f with 
   | Or(f1,f2,lbl,pos) -> mkOr (helper f1) (helper f2) lbl pos
   | AndList b -> mkAndList (map_l_snd simplify b)
   | _ -> simplify f in
  helper f

let simplify (f:CP.formula):CP.formula =
  let pr = !CP.print_formula in
  Debug.no_1 "TP.simplify" pr pr simplify f
	  
let rec simplify_raw (f: CP.formula) = 
  let is_bag_cnt = is_bag_constraint f in
  if is_bag_cnt then
    let _,new_f = trans_dnf f in
    let disjs = list_of_disjs new_f in
    let disjs = List.map (fun disj -> 
        let rels = CP.get_RelForm disj in
        let disj = CP.drop_rel_formula disj in
        let (bag_cnts, others) = List.partition is_bag_constraint (list_of_conjs disj) in
        let others = simplify_raw (conj_of_list others no_pos) in
        conj_of_list ([others]@bag_cnts@rels) no_pos
      ) disjs in
    List.fold_left (fun p1 p2 -> mkOr p1 p2 None no_pos) (mkFalse no_pos) disjs
  else
    let rels = CP.get_RelForm f in
    let ids = List.concat (List.map get_rel_id_list rels) in
    let f_memo, subs, bvars = CP.memoise_rel_formula ids f in
    let res_memo = simplify f_memo in
    CP.restore_memo_formula subs bvars res_memo

let simplify_raw_w_rel (f: CP.formula) = 
  let is_bag_cnt = is_bag_constraint f in
  if is_bag_cnt then
    let _,new_f = trans_dnf f in
    let disjs = list_of_disjs new_f in
    let disjs = List.map (fun disj -> 
        let (bag_cnts, others) = List.partition is_bag_constraint (list_of_conjs disj) in
        let others = simplify (conj_of_list others no_pos) in
        conj_of_list (others::bag_cnts) no_pos
      ) disjs in
    List.fold_left (fun p1 p2 -> mkOr p1 p2 None no_pos) (mkFalse no_pos) disjs
  else simplify f
	
let simplify_raw f =
	let pr = !CP.print_formula in
	Debug.no_1 "simplify_raw" pr pr simplify_raw f

let simplify_exists_raw exist_vars (f: CP.formula) = 
  let is_bag_cnt = is_bag_constraint f in
  if is_bag_cnt then
    let _,new_f = trans_dnf f in
    let disjs = list_of_disjs new_f in
    let disjs = List.map (fun disj -> 
        let (bag_cnts, others) = List.partition is_bag_constraint (list_of_conjs disj) in
        let others = simplify (CP.mkExists exist_vars (conj_of_list others no_pos) None no_pos) in
        let bag_cnts = List.filter (fun b -> CP.intersect (CP.fv b) exist_vars = []) bag_cnts in
        conj_of_list (others::bag_cnts) no_pos
      ) disjs in
    List.fold_left (fun p1 p2 -> mkOr p1 p2 None no_pos) (mkFalse no_pos) disjs
  else
    simplify (CP.mkExists exist_vars f None no_pos)

(* always simplify directly with the help of prover *)
let simplify_always (f:CP.formula): CP.formula = 
  let _ = Gen.Profiling.inc_counter ("stat_count_simpl") in
  simplify f 

let simplify (f:CP.formula): CP.formula = 
  CP.elim_exists_with_simpl simplify f 

(* let simplify (f:CP.formula): CP.formula =  *)
(*   let pr = Cprinter.string_of_pure_formula in *)
(*   Debug.no_1 "TP.simplify" pr pr simplify f *)

let simplify (f : CP.formula) : CP.formula =
  let pf = Cprinter.string_of_pure_formula in
  Debug.no_1 "simplify_2" pf pf simplify f

let simplify_a (s:int) (f:CP.formula): CP.formula = 
  let pf = Cprinter.string_of_pure_formula in
  Debug.no_1_num s ("TP.simplify_a") pf pf simplify f

let hull (f : CP.formula) : CP.formula =
  let _ = if no_andl f then () else report_warning no_pos "trying to do hull over labels!" in
  if not !tp_batch_mode then start_prover ();
  let res = match !pure_tp with
    | DP -> Dp.hull  f
    | Isabelle -> Isabelle.hull f
    | Coq -> (* Coq.hull f *)
        if (is_list_constraint f) then (Coq.hull f)
        else ((*Omega*)Smtsolver.hull f)
    | Mona   -> Mona.hull f  
    | MonaH
    | OM ->
        if (is_bag_constraint f) then (Mona.hull f)
        else (Omega.hull f)
    | OI ->
        if (is_bag_constraint f) then (Isabelle.hull f)
        else (Omega.hull f)
    | SetMONA -> Mona.hull f
    | CM ->
        if is_bag_constraint f then Mona.hull f
        else Omega.hull f
    | Z3 -> Smtsolver.hull f
    | Redlog -> Redlog.hull f
    | Mathematica -> Mathematica.hull f
    | RM ->
        if is_bag_constraint f then Mona.hull f
        else Redlog.hull f
    | ZM ->
        if is_bag_constraint f then Mona.hull f
        else Smtsolver.hull f
    | _ -> (Omega.hull f) in
  if not !tp_batch_mode then stop_prover ();
  res

let hull (f : CP.formula) : CP.formula =
  let pr = Cprinter.string_of_pure_formula in
  Debug.no_1 "hull" pr pr hull f

let tp_pairwisecheck (f : CP.formula) : CP.formula =
  if not !tp_batch_mode then start_prover ();
  let res = match !pure_tp with
    | DP -> Dp.pairwisecheck f
    | Isabelle -> Isabelle.pairwisecheck f
    | Coq -> 
        if (is_list_constraint f) then (Coq.pairwisecheck f)
        else (Smtsolver.pairwisecheck f)
    | Mona 
    | OM ->
        if (is_bag_constraint f) then (Mona.pairwisecheck f)
        else (Omega.pairwisecheck f)
    | OI ->
        if (is_bag_constraint f) then (Isabelle.pairwisecheck f)
        else (Omega.pairwisecheck f)
    | SetMONA -> Mona.pairwisecheck f
    | CM ->
        if is_bag_constraint f then Mona.pairwisecheck f
        else Omega.pairwisecheck f
    | Z3 -> Smtsolver.pairwisecheck f
    | Redlog -> Redlog.pairwisecheck f
    | Mathematica -> Mathematica.pairwisecheck f
    | RM ->
        if is_bag_constraint f then Mona.pairwisecheck f
        else Redlog.pairwisecheck f
    | ZM ->
        if is_bag_constraint f then Mona.pairwisecheck f
        else Smtsolver.pairwisecheck f
    | _ -> (Omega.pairwisecheck f) in
  if not !tp_batch_mode then stop_prover ();
  res
  
let rec pairwisecheck_x (f : CP.formula) : CP.formula = 
  if no_andl f then  tp_pairwisecheck f 
  else 
	  let rec helper f =  match f with 
	  | Or (p1, p2, lbl , pos) -> Or (pairwisecheck_x p1, pairwisecheck_x p2, lbl, pos)
	  | AndList l -> AndList (map_l_snd tp_pairwisecheck l)
	  | _ ->  tp_pairwisecheck f in
	  helper f
	  
  
let pairwisecheck (f : CP.formula) : CP.formula = 
  let pr = Cprinter.string_of_pure_formula in
  Debug.no_1 "pairwisecheck" pr pr pairwisecheck_x f
  


let pairwisecheck_raw (f : CP.formula) : CP.formula =
  let rels = CP.get_RelForm f in
  let ids = List.concat (List.map get_rel_id_list rels) in
  let f_memo, subs, bvars = CP.memoise_rel_formula ids f in
  let res_memo = pairwisecheck f_memo in
  CP.restore_memo_formula subs bvars res_memo

let pairwisecheck_raw (f : CP.formula) : CP.formula =
  let pr = Cprinter.string_of_pure_formula in
  Debug.no_1 "pairwisecheck_raw" pr pr pairwisecheck_raw f


let simplify_with_pairwise (f : CP.formula) : CP.formula =
  let pf = Cprinter.string_of_pure_formula in
  let f1 = simplify f in
  let f2 = pairwisecheck f1 in
  Debug.ninfo_hprint (add_str "simplifyX(input)" pf) f no_pos;
  Debug.ninfo_hprint (add_str "simplifyX(output)" pf) f1 no_pos;
  Debug.ninfo_hprint (add_str "simplifyX(pairwise)" pf) f2 no_pos;
  f2

let simplify_with_pairwise (s:int) (f:CP.formula): CP.formula = 
  let pf = Cprinter.string_of_pure_formula in
  Debug.no_1_num s ("TP.simplify_with_pairwise") pf pf simplify_with_pairwise f


let should_output () = !print_proof && not !suppress_imply_out

let suppress_imply_output () = suppress_imply_out := true

let unsuppress_imply_output () = suppress_imply_out := false

let suppress_imply_output_stack = ref ([] : bool list)

let push_suppress_imply_output_state () = 
	suppress_imply_output_stack := !suppress_imply_out :: !suppress_imply_output_stack

let restore_suppress_imply_output_state () = match !suppress_imply_output_stack with
	| [] -> suppress_imply_output ()
	| h :: t -> begin
					suppress_imply_out := h;
					suppress_imply_output_stack := t;
				end

let tp_imply_no_cache ante conseq imp_no timeout process =
  let ante,conseq = if (!Globals.allow_locklevel) then
        (*should translate waitlevel before level*)
        let ante = CP.translate_waitlevel_pure ante in
        let ante = CP.translate_level_pure ante in
        let conseq = CP.translate_waitlevel_pure conseq in
        let conseq = CP.translate_level_pure conseq in
        let _ = Debug.devel_hprint (add_str "After translate_: ante = " Cprinter.string_of_pure_formula) ante no_pos in
        let _ = Debug.devel_hprint (add_str "After translate_: conseq = " Cprinter.string_of_pure_formula) conseq no_pos in
        (ante,conseq)
      else 
        (* let ante = CP.drop_svl_pure ante [(CP.mkWaitlevelVar Unprimed);(CP.mkWaitlevelVar Primed)] in *)
        (* let ante = CP.drop_locklevel_pure ante in *)
        (* let conseq = CP.drop_svl_pure conseq [(CP.mkWaitlevelVar Unprimed);(CP.mkWaitlevelVar Primed)] in *)
        (* let conseq = CP.drop_locklevel_pure conseq in *)
        (ante,conseq)
  in
  let vrs = Cpure.fv ante in
  let vrs = (Cpure.fv conseq)@vrs in
  let imm_vrs = List.filter (fun x -> (CP.type_of_spec_var x) == AnnT) vrs in 
  let imm_vrs = CP.remove_dups_svl imm_vrs in
  (* add invariant constraint @M<:v<:@A for each annotation var *)
  let ante = CP.add_ann_constraints imm_vrs ante in
  (* Handle Infinity Constraints *)
  let ante,conseq  = if !Globals.allow_inf then Infinity.normalize_inf_formula_imply ante conseq 
  else ante,conseq in
  if should_output () then (
    reset_generated_prover_input ();
    reset_prover_original_output ();
  );
  let (pr_weak,pr_strong) = CP.drop_complex_ops in
  let (pr_weak_z3,pr_strong_z3) = CP.drop_complex_ops_z3 in
  let ante_w = ante in
  let conseq_s = conseq in
  let omega_imply a c = Omega.imply_ops pr_weak pr_strong a c imp_no timeout in
  let redlog_imply a c = Redlog.imply_ops pr_weak pr_strong a c imp_no (* timeout *) in
  let mathematica_imply a c = Mathematica.imply_ops pr_weak pr_strong a c imp_no (* timeout *) in
  let mona_imply a c = Mona.imply_ops pr_weak pr_strong a c imp_no in
  let coq_imply a c = Coq.imply_ops pr_weak pr_strong a c in
  let z3_imply a c = Smtsolver.imply_ops pr_weak_z3 pr_strong_z3 a c timeout in
  if not !tp_batch_mode then start_prover ();
  let r = (
    match !pure_tp with
    | DP ->
        let r = Dp.imply ante_w conseq_s (imp_no^"XX") timeout in
        if test_db then
          let r2 = z3_imply (* Smtsolver.imply *) ante conseq (*(imp_no^"XX")*) (* timeout *) in
          if r=r2 then r
          else 
            failwith ("dp-omega imply mismatch on: "^(Cprinter.string_of_pure_formula ante)^"|-"^(Cprinter.string_of_pure_formula conseq)^
                      " d:"^(string_of_bool r)^" o:"^(string_of_bool r2)^"\n")
        else r
    | OmegaCalc ->
        if (CP.is_float_formula ante) || (CP.is_float_formula conseq) then
          redlog_imply ante_w conseq_s
        else (omega_imply ante conseq)
    | CvcLite -> Cvclite.imply ante_w conseq_s
    | Cvc3 -> (
        match process with
          | Some (Some proc, _) -> Cvc3.imply_increm process ante conseq imp_no
          | _ -> Cvc3.imply_increm (Some (!provers_process,true)) ante conseq imp_no
      )
    | Z3 -> z3_imply ante conseq
    | Isabelle -> Isabelle.imply ante_w conseq_s imp_no
    | Coq ->
        if (is_list_constraint ante) || (is_list_constraint conseq) then
         ( coq_imply ante_w conseq_s)
        else ( z3_imply ante conseq)
    | AUTO ->
        if (is_bag_constraint ante) || (is_bag_constraint conseq) then
          (mona_imply ante_w conseq_s)
        else if (is_list_constraint ante) || (is_list_constraint conseq) then
          (coq_imply ante_w conseq_s)
        else if (is_array_constraint ante) || (is_array_constraint conseq) then
          ( z3_imply ante conseq)
        else
          (omega_imply ante conseq);
    | OZ ->
        if (is_array_constraint ante) || (is_array_constraint conseq) then
          ((* called_prover :="smtsolver "; *) z3_imply ante conseq)
        else
          ((* called_prover :="omega "; *) omega_imply ante conseq)
    | Mona | MonaH -> mona_imply ante_w conseq_s 
    | CO -> (
        let result1 = Cvc3.imply_helper_separate_process ante conseq imp_no in
        match result1 with
        | Some f -> f
        | None -> (* CVC Lite is not sure is this case, try Omega *)
            omega_count := !omega_count + 1;
            omega_imply ante conseq 
      )
    | CM -> (
        if (is_bag_constraint ante) || (is_bag_constraint conseq) then
          mona_imply ante_w conseq_s
        else
          let result1 = Cvc3.imply_helper_separate_process ante conseq imp_no in
          match result1 with
            | Some f -> f
            | None -> (* CVC Lite is not sure is this case, try Omega *)
                  omega_count := !omega_count + 1;
                  omega_imply ante conseq
        )
    | OM ->
        if (is_bag_constraint ante) || (is_bag_constraint conseq) then
          ((* called_prover :="mona " ; *) mona_imply ante_w conseq_s)
        else ((* called_prover :="omega " ; *) omega_imply ante conseq)
    | OI ->
        if (is_bag_constraint ante) || (is_bag_constraint conseq) then
          (Isabelle.imply ante_w conseq_s imp_no)
        else (omega_imply ante conseq)
    | SetMONA -> Setmona.imply ante_w conseq_s 
    | Redlog -> redlog_imply ante_w conseq_s  
    | Mathematica -> mathematica_imply ante_w conseq_s  
    | RM ->
          (*use UNSOUND approximation
          a & b -> c&d ~~~ (a->c) & (b->d)*)
          (*TO CHECK*)
          if (is_bag_constraint ante) && (is_float_formula ante) then
            let ante_no_float = CP.drop_float_formula ante in
            let ante_no_bag = CP.drop_bag_formula ante in
            let conseq_no_float = CP.drop_float_formula conseq in
            let conseq_no_bag = CP.drop_bag_formula conseq in
            let b_no_float = mona_imply ante_no_float conseq_no_float in
            let b_no_bag = mona_imply ante_no_bag conseq_no_bag in
            (b_no_float && b_no_bag)
          else
          if (is_bag_constraint ante) || (is_bag_constraint conseq) then
            mona_imply ante_w conseq_s
          else
            redlog_imply ante_w conseq_s
    | PARAHIP ->
          (*use UNSOUND approximation
          a & b -> c&d ~~~ (a->c) & (b->d)*)
          (*TO CHECK*)
        let is_rel_ante = is_relation_constraint ante in
        let is_rel_conseq = is_relation_constraint conseq in
        let is_bag_ante = is_bag_constraint ante in
        let is_bag_conseq = is_bag_constraint conseq in
        let is_float_ante = is_float_formula ante in
        let is_float_conseq = is_float_formula conseq in
        if (is_rel_ante || is_rel_conseq) && (is_bag_ante || is_bag_conseq) && (is_float_ante || is_float_conseq) then
          let ante_no_float_rel = CP.drop_rel_formula (CP.drop_float_formula ante) in
          let ante_no_bag_rel = CP.drop_rel_formula (CP.drop_bag_formula ante) in
          let ante_no_bag_float = CP.drop_float_formula (CP.drop_bag_formula ante) in
          let conseq_no_float_rel = CP.drop_rel_formula (CP.drop_float_formula conseq) in
          let conseq_no_bag_rel = CP.drop_rel_formula (CP.drop_bag_formula conseq) in
          let conseq_no_bag_float = CP.drop_float_formula (CP.drop_bag_formula conseq) in
          let b_no_float_rel = mona_imply ante_no_float_rel conseq_no_float_rel in
          let b_no_bag_rel = redlog_imply ante_no_bag_rel conseq_no_bag_rel in
          let b_no_bag_float = z3_imply ante_no_bag_float conseq_no_bag_float in
          (b_no_float_rel && b_no_bag_rel & b_no_bag_float)
        else
          if (is_bag_ante || is_bag_conseq) && (is_float_ante || is_float_conseq) then
            let ante_no_float = CP.drop_float_formula ante in
            let ante_no_bag = CP.drop_bag_formula ante in
            let conseq_no_float = CP.drop_float_formula conseq in
            let conseq_no_bag = CP.drop_bag_formula conseq in
            (* let _ = print_endline (" ### ante_no_float = " ^ (Cprinter.string_of_pure_formula ante_no_float)) in *)
            (* let _ = print_endline (" ### conseq_no_float = " ^ (Cprinter.string_of_pure_formula conseq_no_float)) in *)
            (* let _ = print_endline (" ### ante_no_bag = " ^ (Cprinter.string_of_pure_formula ante_no_bag)) in *)
            (* let _ = print_endline (" ### conseq_no_bag = " ^ (Cprinter.string_of_pure_formula conseq_no_bag)) in *)
            let b_no_float = mona_imply ante_no_float conseq_no_float in
            let b_no_bag = redlog_imply ante_no_bag conseq_no_bag in
            (b_no_float && b_no_bag)
          else
            if (is_rel_ante) || (is_rel_conseq) then
              let ante = CP.drop_bag_formula (CP.drop_float_formula ante) in
              let conseq = CP.drop_bag_formula (CP.drop_float_formula conseq) in
              z3_imply ante conseq
            else
              if (is_bag_ante) || (is_bag_conseq) then
                mona_imply ante_w conseq_s
              else redlog_imply ante_w conseq_s
    | ZM -> 
        if (is_bag_constraint ante) || (is_bag_constraint conseq) then
          ((* called_prover := "mona "; *) mona_imply ante_w conseq_s)
        else z3_imply ante conseq
    | SPASS -> Spass.imply ante conseq timeout
    | MINISAT -> Minisat.imply ante conseq timeout
    | LOG -> find_bool_proof_res imp_no 
  ) in
  if not !tp_batch_mode then stop_prover ();
  (* let tstop = Gen.Profiling.get_time () in *)
  Gen.Profiling.push_time "tp_is_sat"; 
  if should_output () then (
    Prooftracer.push_pure_imply ante conseq r;
    Prooftracer.push_pop_prover_input (get_generated_prover_input ()) (string_of_prover !pure_tp);
    Prooftracer.push_pop_prover_output (get_prover_original_output ()) (string_of_prover !pure_tp);
    Prooftracer.add_pure_imply ante conseq r (string_of_prover !pure_tp) (get_generated_prover_input ()) (get_prover_original_output ());
    Prooftracer.pop_div ();
  );
  let _ = Gen.Profiling.pop_time "tp_is_sat" in 
  r

let tp_imply_no_cache ante conseq imp_no timeout process =
	(*wrapper for capturing equalities due to transitive equality with null*)
	let enull = CP.Var (CP.SpecVar(Void,"NULLV",Unprimed),no_pos) in
	let f_e _ (e,r) = match e with 
		| CP.Eq(CP.Null _,CP.Var v,p2) -> Some ( (CP.Eq(enull, CP.Var v,p2),r), true)
		| CP.Eq(CP.Var v,CP.Null _,p2) -> Some ( (CP.Eq(CP.Var v, enull,p2),r), true)
		| _ -> None in
	let transformer_fct = (fun _ _ -> None),f_e,(fun _ _ -> None) in
	let tr_arg = (fun _ _->()),(fun _ _->()),(fun _ _->()) in
	let ante,did = trans_formula ante ()  transformer_fct tr_arg (fun x -> List.exists (fun x->x) x) in
	let ante = if did then  And(ante, (CP.mkNull (CP.SpecVar(Void,"NULLV",Unprimed)) no_pos) ,no_pos) 
			   else ante in
	tp_imply_no_cache ante conseq imp_no timeout process

  
  
let tp_imply_no_cache ante conseq imp_no timeout process =
  let pr = Cprinter.string_of_pure_formula in
  Debug.no_4_loop "tp_imply_no_cache" pr pr (fun s -> s) string_of_prover string_of_bool
  (fun _ _ _ _ -> tp_imply_no_cache ante conseq imp_no timeout process) ante conseq imp_no !pure_tp

let tp_imply_perm ante conseq imp_no timeout process = 
 if !perm=Dperm then
	let conseq = Perm.drop_tauto conseq in
	let r_cons = CP.has_tscons conseq in 
	let l_cons = CP.has_tscons ante in
	if r_cons = No_cons then
	  if l_cons = No_cons then  tp_imply_no_cache ante conseq imp_no timeout process
	  else tp_imply_no_cache (tpd_drop_all_perm ante) conseq imp_no timeout process
	  else match join_res l_cons r_cons with
		| No_cons -> tp_imply_no_cache ante conseq imp_no timeout process
		| No_split -> false
		| Can_split -> 
			let ante_lex, antes= CP.dnf_to_list ante in
			let conseq_lex, conseqs= CP.dnf_to_list conseq in
			let antes = List.map (fun a-> CP.tpd_drop_perm a, (ante_lex,CP.tpd_drop_nperm a)) antes in
			let conseqs = List.map (fun c-> CP.mkExists conseq_lex (CP.tpd_drop_perm c) None no_pos, (conseq_lex,CP.tpd_drop_nperm c)) conseqs in
			let tp_wrap fa fc = if CP.isConstTrue fc then true else tp_imply_no_cache fa fc imp_no timeout process in
			let tp_wrap fa fc = Debug.no_2_loop "tp_wrap"  Cprinter.string_of_pure_formula  Cprinter.string_of_pure_formula string_of_bool tp_wrap fa fc in
			let ss_wrap (ea,fa) (ec,fc) = if fc=[] then true else Share_prover_w.sleek_imply_wrapper (ea,fa) (ec,fc) in
			List.for_all( fun (npa,pa) -> List.exists (fun (npc,pc) -> tp_wrap npa npc && ss_wrap pa pc ) conseqs) antes
  else tp_imply_no_cache ante conseq imp_no timeout process
	
let tp_imply_perm ante conseq imp_no timeout process =  
	let pr =  Cprinter.string_of_pure_formula in
	Debug.no_2_loop "tp_imply_perm" pr pr string_of_bool (fun _ _ -> tp_imply_perm ante conseq imp_no timeout process ) ante conseq
  
let imply_cache fn_imply ante conseq : bool  = 
  let _ = Gen.Profiling.push_time_always "cache overhead" in
  let f = CP.mkOr conseq (CP.mkNot ante None no_pos) None no_pos in
  let sf = norm_var_name f in
  let fstring = Cprinter.string_of_pure_formula sf in
  let _ = cache_imply_count := !cache_imply_count+1 in
  let _ = cache_status := true in
  let _ = Gen.Profiling.pop_time_always "cache overhead" in
  let res =
    try
      Hashtbl.find !imply_cache fstring
    with Not_found ->
        let r = fn_imply ante conseq in
        let _ = Gen.Profiling.push_time "cache overhead" in
        let _ = cache_status := false in
        let _ = cache_imply_miss := !cache_imply_miss+1 in
        let _ = Hashtbl.add !imply_cache fstring r in
        let _ = Gen.Profiling.pop_time "cache overhead" in
        r
  in res

let imply_cache fn_imply ante conseq : bool  = 
  let pr = Cprinter.string_of_pure_formula in
  let pr2 b = ("found?:"^(string_of_bool !cache_status)
    ^" ans:"^(string_of_bool b)) in
  Debug.no_2 "imply_cache" pr pr pr2 (imply_cache fn_imply) ante conseq

let tp_imply ante conseq imp_no timeout process =
  (* TODO WN : can below remove duplicate constraints? *)
  (* let ante = CP.elim_idents ante in *)
  (* let conseq = CP.elim_idents conseq in *)
  let fn_imply a c = tp_imply_perm a c imp_no timeout process in
  if !Globals.no_cache_formula then
    fn_imply ante conseq
  else
    imply_cache fn_imply ante conseq
    (* (\*let _ = Gen.Profiling.push_time "cache overhead" in*\) *)
    (* let f = CP.mkOr conseq (CP.mkNot ante None no_pos) None no_pos in *)
    (* let sf = norm_var_name f in *)
    (* let fstring = Cprinter.string_of_pure_formula sf in *)
    (* (\*let _ = Gen.Profiling.pop_time "cache overhead" in*\) *)
    (* let res =  *)
    (*   try *)
    (*     Hashtbl.find !imply_cache fstring *)
    (*   with Not_found -> *)
    (*     let r = tp_imply_perm ante conseq imp_no timeout process in *)
    (*     (\*let _ = Gen.Profiling.push_time "cache overhead" in*\) *)
    (*     let _ = Hashtbl.add !imply_cache fstring r in *)
    (*     (\*let _ = Gen.Profiling.pop_time "cache overhead" in*\) *)
    (*     r *)
    (* in res *)

let tp_imply ante conseq old_imp_no timeout process =	
  proof_no := !proof_no + 1 ;
  let imp_no = (string_of_int !proof_no) in
  Debug.devel_zprint (lazy ("IMP #" ^ imp_no)) no_pos;  
  Debug.devel_zprint (lazy ("imply_timeout: ante: " ^ (!print_pure ante))) no_pos;
  Debug.devel_zprint (lazy ("imply_timeout: conseq: " ^ (!print_pure conseq))) no_pos;
  let cmd = PT_IMPLY(ante,conseq) in
  let _ = Log.last_proof_command # set cmd in
  let fn () = tp_imply ante conseq imp_no timeout process in
  let final_res = Timelog.logtime_wrapper "imply" fn () in
  let _= add_proof_log !cache_status old_imp_no imp_no (string_of_prover !pure_tp) cmd (Timelog.logtime # get_last_time) (PR_BOOL (match final_res with | r -> r)) in
  final_res
;;

let tp_imply ante conseq imp_no timeout process =	
  let pr1 = Cprinter.string_of_pure_formula in
  let prout x = (last_prover())^": "^(string_of_bool x) in
  Debug.ho_2 "tp_imply" 
      (add_str "ante" pr1) 
      (add_str "conseq" pr1) 
      (add_str "solver" prout) (fun _ _ -> tp_imply ante conseq imp_no timeout process) ante conseq


(* renames all quantified variables *)
let rec requant = function
  | CP.And (f, g, l) -> CP.And (requant f, requant g, l)
  | CP.AndList b -> CP.AndList (map_l_snd requant b)
  | CP.Or (f, g, lbl, l) -> CP.Or (requant f, requant g, lbl, l)
  | CP.Not (f, lbl, l) -> CP.Not (requant f, lbl, l)
  | CP.Forall (v, f, lbl, l) ->
      let nv = CP.fresh_spec_var v in
      CP.Forall (nv, (CP.subst [v, nv] (requant f)), lbl, l)
  | CP.Exists (v, f, lbl, l) ->
      let nv = CP.fresh_spec_var v in
      CP.Exists (nv, (CP.subst [v, nv] (requant f)), lbl, l)
  | x -> x
;;

let rewrite_in_list list formula =
  match formula with
  | CP.BForm ((CP.Eq (CP.Var (v1, _), CP.Var(v2, _), _), _), _) ->
      List.map (fun x -> if x <> formula then CP.subst [v1, v2] x else x) list
  | CP.BForm ((CP.Eq (CP.Var (v1, _), (CP.IConst(i, _) as term), _), _), _) ->
      List.map (fun x -> if x <> formula then CP.subst_term [v1, term] x else x) list
  | x -> list
;;

(*do not rewrite bag_vars*)
let rec rewrite_in_and_tree bag_vars rid formula rform =
  let rec helper rid formula rform =
  match formula with
  | CP.And (x, y, l) ->
      let (x, fx) = helper rid x rform in
      let (y, fy) = helper rid y rform in
      (CP.And (x, y, l), (fun e -> fx (fy e)))
  | CP.AndList b -> 
		let r1,r2 = List.fold_left (fun (a, f) (l,c)-> 
		let r1,r2 = helper rid c rform in
		(l,r1)::a, (fun e -> r2 (f e))) ([],(fun c-> c)) b in
		(AndList r1, r2)
  | x ->
      let subst_fun =
        match rform with
        | CP.BForm ((CP.Eq (CP.Var (v1, _), CP.Var(v2, _), _), _), _) ->
            if (List.mem v1 bag_vars || (List.mem v2 bag_vars)) then  fun x -> x else
              CP.subst [v1, v2]
        | CP.BForm ((CP.Eq (CP.Var (v1, _), (CP.IConst(i, _) as term), _), _), _) ->
            if (List.mem v1 bag_vars) then  fun x -> x else
            CP.subst_term [v1, term]
        | CP.BForm ((CP.Eq ((CP.IConst(i, _) as term), CP.Var (v1, _), _), _), _) ->
            if (List.mem v1 bag_vars) then  fun x -> x else
            CP.subst_term [v1, term]
        | _ -> fun x -> x
      in
      if ((not rid) && x = rform) then (x, subst_fun) else (subst_fun x, subst_fun)
  in helper rid formula rform
;;

let is_irrelevant = function
  | CP.BForm ((CP.Eq (CP.Var (v1, _), CP.Var(v2, _), _), _), _) -> v1 = v2
  | CP.BForm ((CP.Eq (CP.IConst(i1, _), CP.IConst(i2, _), _), _), _) -> i1 = i2
  | _ -> false
;;

let rec get_rid_of_eq = function
  | CP.And (x, y, l) -> 
      if is_irrelevant x then (get_rid_of_eq y) else
      if is_irrelevant y then (get_rid_of_eq x) else
      CP.And (get_rid_of_eq x, get_rid_of_eq y, l)
  | CP.AndList b -> AndList (map_l_snd get_rid_of_eq b)
  | z -> z
;;

let rec fold_with_subst fold_fun current = function
  | [] -> current
  | h :: t ->
      let current, subst_fun = fold_fun current h in
      fold_with_subst fold_fun current (List.map subst_fun t)
;;

(* TODO goes in just once *)
(*do not simpl bag_vars*)
let rec simpl_in_quant formula negated rid =
  let bag_vars = CP.bag_vars_formula formula in
  let related_vars = List.map (fun v -> CP.find_closure_pure_formula v formula) bag_vars in
  let bag_vars = List.concat related_vars in
  let bag_vars = CP.remove_dups_svl bag_vars in
  let bag_vars = bag_vars@[(CP.mkWaitlevelVar Unprimed);(CP.mkWaitlevelVar Primed)] in
  (* let _ = print_endline (" ### bag_vars = " ^ (Cprinter.string_of_spec_var_list bag_vars)) in *)
  let rec helper formula negated rid = 
  match negated with
  | true ->
      begin match formula with
      | CP.Not (f, lbl, l) -> CP.Not (helper f false rid, lbl, l)
      | CP.Forall (v, f, lbl, l) -> CP.Forall (v, helper f true rid, lbl, l)
      | CP.Exists (v, f, lbl, l) -> CP.Exists (v, helper f true rid, lbl, l)
      | CP.Or (f, g, lbl, l) -> CP.mkOr (helper f false false) (helper g false false) lbl l
      | CP.And (_, _, _) ->
          let subfs = split_conjunctions formula in
          let nformula = fold_with_subst (rewrite_in_and_tree bag_vars rid) formula subfs in
          let nformula = get_rid_of_eq nformula in
          nformula
	  | CP.AndList b -> AndList (map_l_snd (fun c-> helper c negated rid) b)
      | x -> x
      end
  | false ->
      begin match formula with
      | CP.Not (f, lbl, l) -> CP.Not (helper f true true, lbl, l)
      | CP.Forall (v, f, lbl, l) -> CP.Forall (v, helper f false rid, lbl, l)
      | CP.Exists (v, f, lbl, l) -> CP.Exists (v, helper f false rid, lbl, l)
      | CP.And (f, g, l) -> CP.And (helper f true false, helper g true false, l)
	  | CP.AndList b -> AndList (map_l_snd (fun c-> helper c negated rid) b)
      | x -> x
      end
  in helper formula negated rid
;;

(* Why not used ?*)
let simpl_pair rid (ante, conseq) =
  (* let conseq_vars = CP.fv conseq in *)
  (* if (List.exists (fun v -> CP.name_of_spec_var v = waitlevel_name) conseq_vars) then *)
  (*   (ante,conseq) *)
  (* else *)
  let bag_vars = CP.bag_vars_formula ante in
  let bag_vars = bag_vars@[(CP.mkWaitlevelVar Unprimed);(CP.mkWaitlevelVar Primed)] in
  let related_vars = List.map (fun v -> CP.find_closure_pure_formula v ante) bag_vars in
  let l1 = List.concat related_vars in
  let vars = CP.fv ante in
  let lock_vars = List.filter (fun v -> CP.type_of_spec_var v = lock_typ) vars in
  (*l1 is bag vars in both ante and conseq*)
  (*lock_vars are simplify*)
  let l1 = CP.remove_dups_svl (l1 @ (CP.bag_vars_formula conseq) @lock_vars) in
  (* let _ = print_endline (" ### l1 = " ^ (Cprinter.string_of_spec_var_list l1)) in *)
  let antes = split_conjunctions ante in
  let fold_fun l_f_vars (ante, conseq)  = function
    | CP.BForm ((CP.Eq (CP.Var (v1, _), CP.Var(v2, _), _), _), _) ->
		if (List.mem v1 l1 || (List.mem v2 l1)) then ((ante, conseq), fun x -> x) else
        ((CP.subst [v1, v2] ante, CP.subst [v1, v2] conseq), (CP.subst [v1, v2]))
    | CP.BForm ((CP.Eq (CP.Var (v1, _), (CP.IConst(i, _) as term), _), _), _)
    | CP.BForm ((CP.Eq ((CP.IConst(i, _) as term), CP.Var (v1, _), _), _), _) ->
		if (List.mem v1 l1) then ((ante, conseq), fun x -> x)
		 else ((CP.subst_term [v1, term] ante, CP.subst_term [v1, term] conseq), (CP.subst_term [v1, term]))
    | _ -> ((ante, conseq), fun x -> x)
  in
  let (ante1, conseq) = fold_with_subst (fold_fun l1) (ante, conseq) antes in
  let ante1 = get_rid_of_eq ante1 in
  (* let _ = print_endline ("ante1 = " ^ (Cprinter.string_of_pure_formula ante1)) in *)
  let ante2 = simpl_in_quant ante1 true rid in
  (* let _ = print_endline ("ante2 = " ^ (Cprinter.string_of_pure_formula ante2)) in *)
  let ante3 = simpl_in_quant ante2 true rid in
  (ante3, conseq)

let simpl_pair rid (ante, conseq) = (ante, conseq)

(* let simpl_pair rid (ante, conseq) = *)
(*   let pr_o = pr_pair Cprinter.string_of_pure_formula Cprinter.string_of_pure_formula in *)
(*   Debug.no_2 "simpl_pair" *)
(*       Cprinter.string_of_pure_formula Cprinter.string_of_pure_formula pr_o *)
(*       (fun _ _ -> simpl_pair rid (ante, conseq)) ante conseq *)

let simpl_pair rid (ante, conseq) =
	Gen.Profiling.do_1 "simpl_pair" (simpl_pair rid) (ante, conseq)
;;

let is_sat (f : CP.formula) (old_sat_no : string): bool =
  let f = elim_exists f in
  if (CP.isConstTrue f) then true 
  else if (CP.isConstFalse f) then false
  else
    let (f, _) = simpl_pair true (f, CP.mkFalse no_pos) in
    (* let f = CP.drop_rel_formula f in *)
    let res= sat_label_filter (fun c-> tp_is_sat c old_sat_no) f in
    res
;;

let is_sat (f : CP.formula) (sat_no : string): bool =
  Debug.no_1 "[tp]is_sat"  Cprinter.string_of_pure_formula string_of_bool (fun _ -> is_sat f sat_no) f

  
let imply_timeout_helper ante conseq process ante_inner conseq_inner imp_no timeout =  
	  let acpairs = imply_label_filter ante conseq in
	  let pairs = List.map (fun (ante,conseq) -> 
              let _ = Debug.devel_hprint (add_str "ante 1: " Cprinter.string_of_pure_formula) ante no_pos in
              (* RHS split already done outside *)
	      (* let cons = split_conjunctions conseq in *)
	      let cons = [conseq] in
	      List.map (fun cons-> 
                  let (ante,cons) = simpl_pair false (requant ante, requant cons) in
                  let _ = Debug.devel_hprint (add_str "ante 3: " Cprinter.string_of_pure_formula) ante no_pos in
		  let ante = CP.remove_dup_constraints ante in
                  let _ = Debug.devel_hprint (add_str "ante 4: " Cprinter.string_of_pure_formula) ante no_pos in
		  match process with
		    | Some (Some proc, true) -> (ante, cons) (* don't filter when in incremental mode - need to send full ante to prover *)
		    | _ -> assumption_filter ante cons  ) cons) acpairs in
	  let pairs = List.concat pairs in
	  let pairs_length = List.length pairs in
          let _ = (ante_inner := List.map fst pairs) in
          let _ = (conseq_inner := List.map snd pairs) in
	  let imp_sub_no = ref 0 in
          (* let _ = (let _ = print_string("\n!!!!!!! bef\n") in flush stdout ;) in *)
	  let fold_fun (res1,res2,res3) (ante, conseq) =
	    (incr imp_sub_no;
	    if res1 then 
	      let imp_no = 
		if pairs_length > 1 then ( (* let _ = print_string("\n!!!!!!! \n") in flush stdout ; *) (imp_no ^ "." ^ string_of_int (!imp_sub_no)))
		else imp_no in
              (*DROP VarPerm formula before checking*)
              let conseq = CP.drop_varperm_formula conseq in
              let ante = CP.drop_varperm_formula ante in
	      let res1 =
		if (not (CP.is_formula_arith ante))&& (CP.is_formula_arith conseq) then
		  let res1 = tp_imply(*_debug*) (CP.drop_bag_formula ante) conseq imp_no timeout process in
		  if res1 then res1
		  else tp_imply(*_debug*) ante conseq imp_no timeout process
		else 
                  tp_imply(*_debug*) ante conseq imp_no timeout process 
              in
              let _ = Debug.devel_hprint (add_str "res: " string_of_bool) res1 no_pos in
	      let l1 = CP.get_pure_label ante in
              let l2 = CP.get_pure_label conseq in
	      if res1 then (res1,(l1,l2)::res2,None)
	      else (res1,res2,l2)
	    else 
              (res1,res2,res3) )
	  in
	  List.fold_left fold_fun (true,[],None) pairs;;
  
   
let imply_timeout (ante0 : CP.formula) (conseq0 : CP.formula) (old_imp_no : string) timeout process
      : bool*(formula_label option * formula_label option )list * (formula_label option) = (*result+successfull matches+ possible fail*)
  (* proof_no := !proof_no + 1 ; *)
  (* let imp_no = (string_of_int !proof_no) in *)
  (* let count_inner = ref 0 in *)
  let imp_no = old_imp_no in
  let ante_inner = ref [] in
  let conseq_inner = ref [] in
  (* let tstart = Gen.Profiling.get_time () in		 *)
  (* Debug.devel_zprint (lazy ("IMP #" ^ imp_no)) no_pos;   *)
  (* Debug.devel_zprint (lazy ("imply_timeout: ante: " ^ (!print_pure ante0))) no_pos; *)
  (* Debug.devel_zprint (lazy ("imply_timeout: conseq: " ^ (!print_pure conseq0))) no_pos; *)
  (* let cmd = PT_IMPLY(ante0,conseq0) in *)
  (* let _ = Log.last_proof_command # set cmd in *)
  let fn () =
    if !external_prover then 
      match Netprover.call_prover (Imply (ante0,conseq0)) with
          Some res -> (res,[],None)       
        | None -> (false,[],None)
    else begin
      let ante0,conseq0 = if (!Globals.allow_locklevel) then
        (*should translate waitlevel before level*)
        let ante0 = CP.translate_waitlevel_pure ante0 in
        let ante0 = CP.translate_level_pure ante0 in
        let conseq0 = CP.translate_waitlevel_pure conseq0 in
        let conseq0 = CP.translate_level_pure conseq0 in
        let _ = Debug.devel_hprint (add_str "After translate_: ante0 = " Cprinter.string_of_pure_formula) ante0 no_pos in
        let _ = Debug.devel_hprint (add_str "After translate_: conseq0 = " Cprinter.string_of_pure_formula) conseq0 no_pos in
        (ante0,conseq0)
      else 
        (* let ante0 = CP.drop_svl_pure ante0 [(CP.mkWaitlevelVar Unprimed);(CP.mkWaitlevelVar Primed)] in *)
        (* let ante0 = CP.drop_locklevel_pure ante0 in *)
        (* let conseq0 = CP.drop_svl_pure conseq0 [(CP.mkWaitlevelVar Unprimed);(CP.mkWaitlevelVar Primed)] in *)
        (* let conseq0 = CP.drop_locklevel_pure conseq0 in *)
        (ante0,conseq0)
      in

      let conseq = if CP.should_simplify conseq0 then simplify_a 12 conseq0 else conseq0 in
      (*let _ = print_string ("imply_timeout: new_conseq: " ^ (Cprinter.string_of_pure_formula conseq) ^ "\n") in*)
      if CP.isConstTrue conseq then (true, [],None)
      else
        let ante = if CP.should_simplify ante0 then simplify_a 13 ante0 else ante0 in
	if (* CP.isConstFalse ante0 || *) CP.isConstFalse ante then (true,[],None)
	else
	  let ante = elim_exists ante in
	  let conseq = elim_exists conseq in
	  (*let _ = print_string ("imply_timeout: new_conseq: " ^ (Cprinter.string_of_pure_formula conseq) ^ "\n") in*)
	  (*if no_andl conseq || *)
	  if (CP.rhs_needs_or_split conseq)&& not (no_andl ante) then
		let conseq_disj = CP.split_disjunctions conseq in
		List.fold_left (fun (r1,r2,r3) d -> 
		   if not r1 then imply_timeout_helper ante d process ante_inner conseq_inner imp_no timeout
		   else (r1,r2,r3) ) (false,[],None) conseq_disj 
	  else imply_timeout_helper ante conseq process ante_inner conseq_inner imp_no timeout
    end;
  in 
  let final_res = (* Timelog.logtime_wrapper "imply" *) fn () in
  (* let tstop = Gen.Profiling.get_time () in *)
  (* let _ = print_string ("length of pairs: "^(string_of_int (List.length !ante_inner))) in *)
  (* let ante0 = CP.join_conjunctions !ante_inner in *)
  (* let conseq0 = CP.join_conjunctions !conseq_inner in *)
  (* let _= add_proof_log !cache_status old_imp_no imp_no (string_of_prover !pure_tp) cmd (\* (PT_IMPLY (ante0, conseq0)) *\) (Timelog.logtime # get_last_time) (PR_BOOL (match final_res with | r,_,_ -> r)) in *)
  final_res
;;

let imply_timeout (ante0 : CP.formula) (conseq0 : CP.formula) (imp_no : string) timeout process
	  : bool*(formula_label option * formula_label option )list * (formula_label option) (*result+successfull matches+ possible fail*)
  = let pf = Cprinter.string_of_pure_formula in
  (*let _ = print_string "dubios!!\n" in*)
  Debug.no_2 "imply_timeout 2" pf pf (fun (b,_,_) -> string_of_bool b)
      (fun a c -> imply_timeout a c imp_no timeout process) ante0 conseq0


(* let imply_timeout_slicing (ante0 : CP.formula) (conseq0 : CP.formula) (imp_no : string) timeout process *)
(* 	: bool*(formula_label option * formula_label option )list * (formula_label option) = (\*result+successfull matches+ possible fail*\) *)
(*   (\* let _ = print_string ("\nTpdispatcher.ml: imply_timeout begining") in *\) *)
(*   proof_no := !proof_no + 1 ;  *)
(*   let imp_no = (string_of_int !proof_no) in *)
(*   (\* let _ = print_string ("\nTPdispatcher.ml: imply_timeout:" ^ imp_no) in *\) *)
(*   Debug.devel_zprint (lazy ("IMP #" ^ imp_no)) no_pos;   *)
(*   Debug.devel_zprint (lazy ("ante: " ^ (!print_pure ante0))) no_pos; *)
(*   Debug.devel_zprint (lazy ("conseq: " ^ (!print_pure conseq0))) no_pos; *)
(*   if !external_prover then  *)
(*     match Netprover.call_prover (Imply (ante0,conseq0)) with *)
(*       | Some res -> (res,[],None)        *)
(* 	  | None -> (false,[],None) *)
(*   else begin  *)
(* 	(\*let _ = print_string ("Imply: => " ^(Cprinter.string_of_pure_formula ante0)^"\n==> "^(Cprinter.string_of_pure_formula conseq0)^"\n") in*\) *)
(* 	let conseq = if CP.should_simplify conseq0 then simplify_a 12 conseq0 else conseq0 in (\* conseq is Exists formula *\) *)
(* 	(\*let _ = print_string ("imply_timeout: new_conseq: " ^ (Cprinter.string_of_pure_formula conseq) ^ "\n") in*\) *)
(* 	if CP.isConstTrue conseq then (true, [], None) *)
(* 	else *)
(* 	  let ante = if CP.should_simplify ante0 then simplify_a 13 ante0 else ante0 in *)
(* 	  (\*let _ = print_string ("imply_timeout: new_ante: " ^ (Cprinter.string_of_pure_formula ante) ^ "\n") in*\) *)
(* 	  if CP.isConstFalse ante then (true, [], None) *)
(* 	  else *)
(*         (\* let _ = print_string ("\nTpdispatcher.ml: imply_timeout bef elim exist ante") in *\) *)
(* 		let ante = elim_exists ante in *)
(*         (\* let _ = print_string ("\nTpdispatcher.ml: imply_timeout after elim exist ante") in *\) *)
(* 		let conseq = elim_exists conseq in *)
        (* let conseq0 = CP.drop_svl_pure conseq0 [(CP.mkWaitlevelVar Unprimed);(CP.mkWaitlevelVar Primed)] in *)
        (* let conseq0 = CP.drop_locklevel_pure conseq0 in *)
  (*       (ante0,conseq0) *)
  (* in *)



(* 		(\*let _ = print_string ("imply_timeout: new_conseq: " ^ (Cprinter.string_of_pure_formula conseq) ^ "\n") in*\) *)

(*         (\* A1 -> B => A1 /\ A2 => B *\) *)
(* 		(\* A1 is (filter A1 /\ A2)  *\) *)
(* 		let imply_conj_lhs ante conseq = *)
(* 		  let conseq = if CP.should_simplify conseq then simplify_a 14 conseq else conseq in *)
(* 		  if CP.isConstTrue conseq then (true, [], None) *)
(* 		  else *)
(* 			let ante = if CP.should_simplify ante then simplify_a 15 ante else ante in *)
(* 			if CP.isConstFalse ante then (true, [], None) *)
(* 			else *)
(* 			  let (ante, cons) = simpl_pair false (requant ante, requant conseq) in  *)
(* 			  let ante = CP.remove_dup_constraints ante in *)
(* 			  let (ante, cons) = match process with *)
(* 				| Some (Some proc, true) -> (ante, cons) (\* don't filter when in incremental mode - need to send full ante to prover *\) *)
(* 				| _ -> assumption_filter ante cons in *)
(* 			  let cons = CP.drop_varperm_formula cons in *)
(*               let ante = CP.drop_varperm_formula ante in *)
(* 			  let res = *)
(* 				if (not (CP.is_formula_arith ante)) && (CP.is_formula_arith cons) then *)
(* 				  let res = tp_imply (CP.drop_bag_formula ante) cons imp_no timeout process in *)
(* 				  if res then res *)
(* 				  else tp_imply ante cons imp_no timeout process *)
(* 				else tp_imply ante cons imp_no timeout process *)
(* 			  in *)
(*  			  let l1 = CP.get_pure_label ante in *)
(*               let l2 = CP.get_pure_label cons in *)
(* 			  if res then (res, [(l1,l2)], None) *)
(* 			  else (res, [], l2) *)
(* 		in *)

(* 		let imply_conj_lhs ante conseq = *)
(* 		  let pr = Cprinter.string_of_pure_formula in *)
(* 		  Debug.no_2 "imply_timeout: imply_conj_lhs" pr pr *)
(* 			(fun (r, _, _) -> string_of_bool r) imply_conj_lhs ante conseq *)
(* 		in *)
				
(* 		(\* A \/ B -> C <=> (A -> C) /\ (B -> C) *\) *)
(* 		let imply_disj_lhs ante conseq = *)
(* 		  let ante = CP.elim_exists_with_simpl simplify ante in *)
(* 		  let _,l_ante = CP.dnf_to_list ante in *)
(* 		  let pairs = List.map (fun ante -> (ante, conseq)) l_ante in *)
(* 		  let fold_fun (res1, res2, res3) (ante, cons) = *)
(* 			if res1 then *)
(* 			  let (r1, r2, r3) = imply_conj_lhs ante cons in *)
(* 			  if r1 then (r1, r2@res2, None) *)
(* 			  else (r1, res2, r3) *)
(* 			else (res1, res2, res3) *)
(* 		  in *)
(* 		  List.fold_left fold_fun (true, [], None) pairs *)
(* 		in *)

(* 	    (\* A -> B /\ C <=> (A -> B) /\ (A -> C) *\) *)
(* 		let imply_conj_rhs ante conseq =  *)
(* 		  let split_conseq = split_conjunctions conseq in *)
(* 		  let pairs = List.map (fun cons -> (ante, cons)) split_conseq in *)
(* 		  let fold_fun (res1, res2, res3) (ante, cons) = *)
(* 			if res1 then *)
(* 			  let (r1, r2, r3) = imply_disj_lhs ante cons in *)
(* 			  if r1 then (r1, r2@res2, None) *)
(* 			  else (r1, res2, r3) *)
(* 			else (res1, res2, res3) *)
(* 		  in *)
(* 		  List.fold_left fold_fun (true, [], None) pairs *)
(* 		in *)

(* 		(\* A -> B \/ C <=> (A -> B) \/ (A -> C) *\) *)
(* 		let imply_disj_rhs ante conseq = *)
(* 		  let cons = CP.elim_exists_with_simpl simplify conseq in *)
(* 		  let _,l_cons = CP.dnf_to_list cons in (\* Transform conseq into DNF *\) *)
(* 		  let pairs = List.map (fun cons -> (ante, cons)) l_cons in *)
(* 		  let fold_fun (res1, res2, res3) (ante, cons) = *)
(* 			if not res1 then *)
(* 			  let (r1, r2, r3) = imply_conj_rhs ante cons in *)
(* 			  (r1, r2@res2, r3) (\* Should store r3 as a list of failure reason *\) *)
(* 			else (res1, res2, res3) *)
(* 		  in *)
(* 		  List.fold_left fold_fun (false, [], None) pairs *)
(* 		in *)
(* 		imply_disj_rhs ante conseq *)
(*   end; *)
(* ;; *)

let imply_timeout (ante0 : CP.formula) (conseq0 : CP.formula) (imp_no : string) timeout do_cache process
	  : bool*(formula_label option * formula_label option )list * (formula_label option) =
  (* if !do_slicing && !multi_provers then                      *)
	(* imply_timeout_slicing ante0 conseq0 imp_no timeout process *)
  (* else                                                       *)
	(* imply_timeout ante0 conseq0 imp_no timeout process         *)
	imply_timeout ante0 conseq0 imp_no timeout process


let imply_timeout (ante0 : CP.formula) (conseq0 : CP.formula) (imp_no : string) timeout do_cache process
	  : bool*(formula_label option * formula_label option )list * (formula_label option) (*result+successfull matches+ possible fail*)
  = let pf = Cprinter.string_of_pure_formula in
  let prf = add_str "timeout" string_of_float in
  Debug.no_4 "imply_timeout 3" pf pf prf pr_id (fun (b,_,_) -> string_of_bool b)
      (fun a c _ _ -> imply_timeout a c imp_no timeout do_cache process) ante0 conseq0 timeout (next_proof_no ())

let imply_timeout ante0 conseq0 imp_no timeout do_cache process =
  let s = "imply" in
  let _ = Gen.Profiling.push_time s in
  let (res1,res2,res3) = imply_timeout ante0 conseq0 imp_no timeout do_cache process in
  let _ = Gen.Profiling.pop_time s in
  if res1  then Gen.Profiling.inc_counter "true_imply_count" else Gen.Profiling.inc_counter "false_imply_count" ; 
  (res1,res2,res3)
	
let imply_timeout a c i t dc process =
  disj_cnt a (Some c) "imply";
  Gen.Profiling.do_5 "TP.imply_timeout" imply_timeout a c i t dc process
	
let memo_imply_timeout ante0 conseq0 imp_no timeout = 
  (* let _ = print_string ("\nTPdispatcher.ml: memo_imply_timeout") in *)
  let _ = Gen.Profiling.push_time "memo_imply" in
  let r = List.fold_left (fun (r1,r2,r3) c->
    if not r1 then (r1,r2,r3)
    else 
      let l = List.filter (fun d -> (List.length (Gen.BList.intersect_eq CP.eq_spec_var c.memo_group_fv d.memo_group_fv))>0) ante0 in
      let ant = MCP.fold_mem_lst_m (CP.mkTrue no_pos) true (*!no_LHS_prop_drop*) true l in
      let con = MCP.fold_mem_lst_m (CP.mkTrue no_pos) !no_RHS_prop_drop false [c] in
      let r1',r2',r3' = imply_timeout ant con imp_no timeout false None in 
      (r1',r2@r2',r3')) (true, [], None) conseq0 in
  let _ = Gen.Profiling.pop_time "memo_imply" in
  r

let memo_imply_timeout ante0 conseq0 imp_no timeout =
  Debug.no_2 "memo_imply_timeout"
	(Cprinter.string_of_memoised_list)
	(Cprinter.string_of_memoised_list)
	(fun (r,_,_) -> string_of_bool r)
	(fun a c -> memo_imply_timeout a c imp_no timeout) ante0 conseq0
	
let mix_imply_timeout ante0 conseq0 imp_no timeout = 
  match ante0,conseq0 with
  | MCP.MemoF a, MCP.MemoF c -> memo_imply_timeout a c imp_no timeout
    | MCP.OnePF a, MCP.OnePF c -> imply_timeout a c imp_no timeout false None
  | _ -> report_error no_pos ("mix_imply_timeout: mismatched mix formulas ")

let rec imply_one i ante0 conseq0 imp_no do_cache process =
Debug.no_2_num i "imply_one" (Cprinter.string_of_pure_formula) (Cprinter.string_of_pure_formula) 
      (fun (r, _, _) -> string_of_bool r)
      (fun ante0 conseq0 -> imply_x ante0 conseq0 imp_no do_cache process) ante0 conseq0

and imply_x ante0 conseq0 imp_no do_cache process = imply_timeout ante0 conseq0 imp_no !imply_timeout_limit do_cache process ;;

let simpl_imply_raw_x ante conseq = 
	let (r,_,_)= imply_one 0 ante conseq "0" false None in
	r

let simpl_imply_raw ante conseq = 
Debug.no_2 "simpl_imply_raw" (Cprinter.string_of_pure_formula)(Cprinter.string_of_pure_formula) string_of_bool
	simpl_imply_raw_x ante conseq
	
let memo_imply ante0 conseq0 imp_no = memo_imply_timeout ante0 conseq0 imp_no !imply_timeout_limit ;;

let mix_imply ante0 conseq0 imp_no = mix_imply_timeout ante0 conseq0 imp_no !imply_timeout_limit ;;

(* CP.formula -> string -> 'a -> bool *)
let is_sat f sat_no do_cache =
  if !external_prover then 
      match Netprover.call_prover (Sat f) with
      Some res -> res       
      | None -> false
  else  begin   
    disj_cnt f None "sat";
    Gen.Profiling.do_1 "is_sat" (is_sat f) sat_no
  end
;;

let is_sat i f sat_no do_cache = 
  Debug.no_1_num i "is_sat" Cprinter.string_of_pure_formula string_of_bool (fun _ -> is_sat f sat_no do_cache) f


let sat_no = ref 1 ;;

let incr_sat_no () =  sat_no := !sat_no +1  ;;

let is_sat_sub_no_c (f : CP.formula) sat_subno do_cache : bool = 
  let sat = is_sat 1 f ((string_of_int !sat_no) ^ "." ^ (string_of_int !sat_subno)) do_cache in
  sat_subno := !sat_subno+1;
  sat
;;

let is_sat_sub_no_c i (f : CP.formula) sat_subno do_cache : bool =
  Debug.no_1_num i "is_sat_sub_no_c" Cprinter.string_of_pure_formula string_of_bool (fun f -> is_sat_sub_no_c f sat_subno do_cache) f
;;

let is_sat_sub_no_with_slicing_orig (f:CP.formula) sat_subno : bool =  
  let rec group_conj l = match l with
    | [] -> (false,[]) 
    | (fvs, fs)::t ->  
      let b,l = group_conj t in
      let l1,l2 = List.partition (fun (c,_)-> not((Gen.BList.intersect_eq CP.eq_spec_var fvs c)==[])) l in
      if l1==[] then (b,(fvs,fs)::l) 
      else 
        let vars,nfs = List.split l1 in 
        let nfs = CP.join_conjunctions (fs::nfs) in
        let nvs = CP.remove_dups_svl (List.concat (fvs::vars)) in
        (true,(nvs,nfs)::l2) in
      
  let rec fix n_l = 
    let r1,r2 = group_conj n_l in
    if r1 then fix r2 else r2 in    
  let split_sub_f f = 
    let conj_list = CP.split_conjunctions f in
    let n_l = List.map (fun c-> (CP.fv c , c)) conj_list in
    snd (List.split (fix n_l)) in
  let  n_f_l = split_sub_f f in
  List.fold_left (fun a f -> if not a then a else is_sat_sub_no_c 1 f sat_subno false) true n_f_l 

let is_sat_sub_no_slicing (f:CP.formula) sat_subno : bool =
  let overlap (nlv1, lv1) (nlv2, lv2) =
	if (nlv1 = [] && nlv2 = []) then (Gen.BList.list_equiv_eq CP.eq_spec_var lv1 lv2)
	else (Gen.BList.overlap_eq CP.eq_spec_var nlv1 nlv2)
  in
  
  let rec group_conj l = match l with
    | [] -> (false,[]) 
    | ((f_nlv, f_lv), fs)::t ->  
      let b,l = group_conj t in
      let l1, l2 = List.partition (fun (cfv, _) -> overlap (f_nlv, f_lv) cfv) l in
      if l1==[] then (b,((f_nlv, f_lv), fs)::l) 
      else 
        let l_fv, nfs = List.split l1 in
		let l_nlv, l_lv = List.split l_fv in
        let nfs = CP.join_conjunctions (fs::nfs) in
        let n_nlv = CP.remove_dups_svl (List.concat (f_nlv::l_nlv)) in
		let n_lv = CP.remove_dups_svl (List.concat (f_lv::l_lv)) in
        (true,((n_nlv, n_lv), nfs)::l2)
  in
  
  let rec fix n_l = 
    let r1, r2 = group_conj n_l in
    if r1 then fix r2 else r2
  in    

  let split_sub_f f = 
    let conj_list = CP.split_conjunctions f in
    let n_l = List.map
	  (fun c -> (CP.fv_with_slicing_label c, c)) conj_list in
    snd (List.split (fix n_l))
  in

  let n_f = (*CP.elim_exists_with_fresh_vars*) CP.elim_exists_with_simpl simplify f in
  let dnf_f = snd (CP.dnf_to_list n_f) in
  
  let is_related f1 f2 =
	let (nlv1, lv1) = CP.fv_with_slicing_label f1 in
	let fv = CP.fv f2 in
	if (nlv1 == []) then Gen.BList.overlap_eq CP.eq_spec_var fv lv1
	else Gen.BList.overlap_eq CP.eq_spec_var fv nlv1
  in 

  let pick_rel_constraints f f_l = List.find_all (fun fs -> fs != f && is_related fs f) f_l in 

  (* SAT(A /\ B) = SAT(A) /\ SAT(B) if fv(A) and fv(B) are disjointed (auto-slicing) *)
  let check_sat f =
	let n_f_l = split_sub_f f in
	List.fold_left (fun a f ->
	  if not a then a
	  else is_sat_sub_no_c 2 (CP.join_conjunctions (f::(pick_rel_constraints f n_f_l))) sat_subno false) true n_f_l
  in

  (* SAT(A \/ B) = SAT(A) \/ SAT(B) *)
  
  List.fold_left (fun a f -> if a then a else check_sat f) false dnf_f
	
let is_sat_sub_no_slicing (f:CP.formula) sat_subno : bool =
  Debug.no_1 "is_sat_sub_no_with_slicing"
	Cprinter.string_of_pure_formula
	string_of_bool
	(fun f -> is_sat_sub_no_slicing f sat_subno) f

let is_sat_sub_no (f : CP.formula) sat_subno : bool =
  if !is_sat_slicing then is_sat_sub_no_slicing f sat_subno
  (* else if !do_slicing && !multi_provers then is_sat_sub_no_slicing f sat_subno *)
  else is_sat_sub_no_c 3 f sat_subno false

let is_sat_sub_no i (f : CP.formula) sat_subno : bool =  
  Debug.no_2_num i "is_sat_sub_no " (Cprinter.string_of_pure_formula) (fun x-> string_of_int !x)
    (string_of_bool ) is_sat_sub_no f sat_subno;;

let is_sat_memo_sub_no_orig (f : memo_pure) sat_subno with_dupl with_inv : bool =
  if !f_2_slice || !dis_slicing then
		let f_lst = MCP.fold_mem_lst_to_lst f with_dupl with_inv true in
		(is_sat_sub_no 1 (CP.join_conjunctions f_lst) sat_subno)
  else if (MCP.isConstMFalse (MemoF f)) then false
  else
		(* let f = if !do_slicing                            *)
		(* 	(* Slicing: Only check changed slice *)          *)
		(* 	then List.filter (fun c -> c.memo_group_unsat) f *)
		(* 	else f in                                        *)
		let f_lst = MCP.fold_mem_lst_to_lst f with_dupl with_inv true in
		not (List.exists (fun f -> not (is_sat_sub_no 2 f sat_subno)) f_lst)

let is_sat_memo_sub_no_orig (f : memo_pure) sat_subno with_dupl with_inv : bool =
  Debug.no_1 "is_sat_memo_sub_no_orig"
  Cprinter.string_of_memo_pure_formula
	string_of_bool
  (fun _ -> is_sat_memo_sub_no_orig f sat_subno with_dupl with_inv) f

let is_sat_memo_sub_no_slicing (f : memo_pure) sat_subno with_dupl with_inv : bool =
  if (not (is_sat_memo_sub_no_orig f sat_subno with_dupl with_inv)) then (* One slice is UNSAT *) false
  else (* Improve completeness of SAT checking *)
	  let f_l = MCP.fold_mem_lst_to_lst_gen_for_sat_slicing f with_dupl with_inv true true in
	  not (List.exists (fun f -> not (is_sat_sub_no 3 f sat_subno)) f_l)
    
let is_sat_memo_sub_no_slicing (f : memo_pure) sat_subno with_dupl with_inv : bool =
  Debug.no_1 "is_sat_memo_sub_no_slicing"
  Cprinter.string_of_memo_pure_formula
	string_of_bool
  (fun _ -> is_sat_memo_sub_no_slicing f sat_subno with_dupl with_inv) f
	  
let rec is_sat_memo_sub_no_ineq_slicing (mem : memo_pure) sat_subno with_dupl with_inv : bool =
  Debug.no_1 "is_sat_memo_sub_no_ineq_slicing"
	Cprinter.string_of_memo_pure_formula
	string_of_bool
	(fun mem -> is_sat_memo_sub_no_ineq_slicing_x2 mem sat_subno with_dupl with_inv) mem

and is_sat_memo_sub_no_ineq_slicing_x1 (mem : memo_pure) sat_subno with_dupl with_inv : bool =
  let is_sat_one_slice mg =
  	if (MCP.is_ineq_linking_memo_group mg)
  	then (* mg is a linking inequality *)
  	  true
  	else
  	  let aset = mg.memo_group_aset in
  	  let apart = EMapSV.partition aset in
  	  (* let r = List.fold_left (fun acc p -> if acc then acc else MCP.exists_contradiction_eq mem p) false apart in *)
      let r = List.exists (fun p -> MCP.exists_contradiction_eq mem p) apart in
  	  if r then false (* found an equality contradiction *)
  	  else
        let related_ineq = List.find_all (fun img ->
          (MCP.is_ineq_linking_memo_group img) && 
          (Gen.BList.subset_eq eq_spec_var img.memo_group_fv mg.memo_group_fv)) mem in
  		let f = join_conjunctions (MCP.fold_mem_lst_to_lst (mg::related_ineq) with_dupl with_inv true) in
  		is_sat_sub_no 4 f sat_subno
  in
  (* List.fold_left (fun acc mg -> if not acc then acc else is_sat_one_slice mg) true mem *)
  not (List.exists (fun mg -> not (is_sat_one_slice mg)) mem)
  
and is_sat_memo_sub_no_ineq_slicing_x2 (mem : memo_pure) sat_subno with_dupl with_inv : bool =
  let is_sat_one_slice mg =
    if (MCP.is_ineq_linking_memo_group mg)
    then (* mg is a linking inequality *)
      true
    else
      let related_ineq = List.find_all (fun img ->
        (MCP.is_ineq_linking_memo_group img) && 
        (Gen.BList.subset_eq eq_spec_var img.memo_group_fv mg.memo_group_fv)) mem in
      let f = join_conjunctions (MCP.fold_mem_lst_to_lst (mg::related_ineq) with_dupl with_inv true) in
      is_sat_sub_no 5 f sat_subno
  in
  (* List.fold_left (fun acc mg -> if not acc then acc else is_sat_one_slice mg) true mem *)
  not (List.exists (fun mg -> not (is_sat_one_slice mg)) mem)

(* and is_sat_memo_sub_no_ineq_slicing_x2 (mem : memo_pure) sat_subno with_dupl with_inv : bool =                                            *)
(*   (* Aggressive search on inequalities *)                                                                                                 *)
(*   let is_sat_one_slice mg (kb : (bool option * memoised_group) list) =                                                                    *)
(* 	if (MCP.is_ineq_linking_memo_group mg)                                                                                                  *)
(* 	then (* mg is a linking inequality *)                                                                                                   *)
(* 	  (* For each fv v of a linking ineq, find all other slices that relates to v *)                                                        *)

(* 	  let _ = print_string ("\nis_sat_memo_sub_no_ineq_slicing_x2: ineq: " ^ (Cprinter.string_of_spec_var_list mg.memo_group_fv) ^ "\n") in *)

(* 	  (* Find slices which contain both free vars of ineq and                                                                               *)
(* 		 try to discover contradictory cycle in those slices first *)                                                                         *)
(* 	  let (d_kb, s_kb) = List.partition (fun (_, s) ->                                                                                      *)
(* 		(s != mg) && (Gen.BList.subset_eq eq_spec_var mg.memo_group_fv s.memo_group_fv)) kb in                                                *)

(* 	  let res = List.fold_left (fun a_r (_, s) ->                                                                                           *)
(* 		if not a_r then a_r                                                                                                                   *)
(* 		else                                                                                                                                  *)
(* 		  let aset = s.memo_group_aset in                                                                                                     *)
(* 		  let apart = EMapSV.partition aset in                                                                                                *)
(* 		  (* r = true -> a contradictory cycle is found *)                                                                                    *)
(* 		  let r = List.fold_left (fun acc p -> if acc then acc else MCP.exists_contradiction_eq mem p) false apart in                         *)
(* 		  not r                                                                                                                               *)
(* 	  ) true d_kb in                                                                                                                        *)

(* 	  if not res then (res, kb)                                                                                                             *)
(* 	  else                                                                                                                                  *)
		
(* 		let (related_slices, unrelated_slices) = List.fold_left (fun (a_rs, a_urs) v ->                                                       *)
(* 		  let (v_rs, v_urs) = List.partition (fun (_, s) -> (* No overlapping slices btw variables *)                                         *)
(* 			(s != mg) &&                                                                                                                        *)
(* 			  (List.mem v s.memo_group_fv) &&                                                                                                   *)
(* 			  not (MCP.is_ineq_linking_memo_group s)                                                                                            *)
(* 		  ) a_urs in (v_rs::a_rs, v_urs)                                                                                                      *)
(* 		) ([], s_kb) mg.memo_group_fv in                                                                                                      *)

(* 		let _ = print_string ("\nis_sat_memo_sub_no_ineq_slicing_x2: related_slices: " ^                                                      *)
(* 								 (pr_list (fun l_x -> pr_list (fun (_, x) -> Cprinter.string_of_memoised_group x) l_x) related_slices)) in                *)
		
(* 	    (* Filter slices without relationship, for example, keep x<=z and z<=y for x!=y *)                                                  *)
(* 		let rec filter_slices (l_l_slices : (bool * (bool option * memoised_group)) list list) = (* (is_marked, (is_sat, slice)) *)           *)
(* 		(* Only work if the initial size of ll_slices is 2 *)                                                                                 *)
(* 		(* Return a pair of used and unused slices *)                                                                                         *)
(* 		  match l_l_slices with                                                                                                               *)
(* 			| [] -> ([], [])                                                                                                                    *)
(* 			| l_x::l_l_rest ->                                                                                                                  *)
(* 			  let (l_used_x, l_unused_x, marked_l_l_rest) =                                                                                     *)
(* 				List.fold_left (fun (a_l_x, a_l_ux, a_l_l_rest) (x_is_marked, (x_is_sat, x)) -> (* (_, x) is (x_is_sat, x) *)                     *)
(* 				  if x_is_marked then ((x_is_sat, x)::a_l_x, a_l_ux, a_l_l_rest) (* x shared variables with some previous lists of slices *)      *)
(* 				  else                                                                                                                            *)
(* 				    (* Mark all slice which overlaps with x *)                                                                                    *)
(* 					let n_l_l_rest = List.map (fun l_y ->                                                                                           *)
(* 					  List.fold_left (fun acc (y_is_marked, (y_is_sat, y)) ->                                                                       *)
(* 						if y_is_marked then (y_is_marked, (y_is_sat, y))::acc                                                                         *)
(* 						else (Gen.BList.overlap_eq eq_spec_var x.memo_group_fv y.memo_group_fv, (y_is_sat, y))::acc                                   *)
(* 					  ) [] l_y) a_l_l_rest in                                                                                                       *)
(* 					let n_l_x, n_l_ux =                                                                                                             *)
(* 					  if (List.exists (fun l_y ->                                                                                                   *)
(* 						List.exists (fun (_, (_, y)) ->                                                                                               *)
(* 						  Gen.BList.overlap_eq eq_spec_var x.memo_group_fv y.memo_group_fv) l_y)                                                      *)
(* 							a_l_l_rest) then                                                                                                            *)
(* 						((x_is_sat, x)::a_l_x, a_l_ux)                                                                                                *)
(* 					  else                                                                                                                          *)
(* 						(a_l_x, (x_is_sat, x)::a_l_ux)                                                                                                *)
(* 					in (n_l_x, n_l_ux, n_l_l_rest)                                                                                                  *)
(* 				) ([], [], l_l_rest) l_x                                                                                                          *)
(* 			  in                                                                                                                                *)
(* 			  let r_l_x, r_l_ux = filter_slices marked_l_l_rest in                                                                              *)
(* 			  (l_used_x::r_l_x, l_unused_x::r_l_ux)                                                                                             *)
(* 		in                                                                                                                                    *)
(* 		let (used_slices, unused_slices) = filter_slices (List.map (fun l_x -> List.map (fun x -> (false, x)) l_x) related_slices) in         *)
(* 		let ineq_related_slices = (List.concat used_slices) @ d_kb in                                                                         *)
(* 		let ineq_unrelated_slices = (List.concat unused_slices) @ unrelated_slices in                                                         *)

(* 	    (* Check SAT for each slice in ineq_related_slices before merging them to ineq *)                                                   *)
		
(* 		let (res, n_ineq_related_slices, l_formulas) = List.fold_left (fun (a_r, a_irs, a_l_f) (is_sat, x) ->                                 *)
(* 		  if not a_r then (a_r, a_irs, a_l_f) (* head of a_irs will be the UNSAT slice *)                                                     *)
(* 		  else                                                                                                                                *)
(* 			let f = MCP.fold_slice_gen x with_dupl with_inv true true in                                                                        *)
(* 			match is_sat with                                                                                                                   *)
(* 			  | None ->                                                                                                                         *)
(* 				let r = is_sat_sub_no f sat_subno in                                                                                              *)
(* 				(r, (Some r, x)::a_irs, f::a_l_f)                                                                                                 *)
(* 			  | Some r -> (r, (Some r, x)::a_irs, f::a_l_f)                                                                                     *)
(* 		) (true, [], []) ineq_related_slices in                                                                                               *)
(* 		if not res then (res, n_ineq_related_slices @ ineq_unrelated_slices)                                                                  *)
(* 		else                                                                                                                                  *)
(* 		  let f = join_conjunctions ((MCP.fold_slice_gen mg with_dupl with_inv true true)::l_formulas) in                                     *)
(* 		  let res = is_sat_sub_no f sat_subno in                                                                                              *)
(* 		  (res, n_ineq_related_slices @ ineq_unrelated_slices)                                                                                *)
(* 	else                                                                                                                                    *)
(* 	  let rec update_kb mg kb =                                                                                                             *)
(* 		match kb with                                                                                                                         *)
(* 		  | [] -> (true, [])                                                                                                                  *)
(* 		  | (is_sat, x)::rest ->                                                                                                              *)
(* 			if mg = x then                                                                                                                      *)
(* 			  match is_sat with                                                                                                                 *)
(* 				| None ->                                                                                                                         *)
(* 				  let f = MCP.fold_slice_gen mg with_dupl with_inv true true in                                                                   *)
(* 				  let r = is_sat_sub_no f sat_subno in (r, (Some r, x)::rest)                                                                     *)
(* 				| Some r -> (r, kb)                                                                                                               *)
(* 			else                                                                                                                                *)
(* 			  let (r, n_rest) = update_kb mg rest in                                                                                            *)
(* 			  (r, (is_sat, x)::n_rest)                                                                                                          *)
(* 	  in update_kb mg kb                                                                                                                    *)
(*   in                                                                                                                                      *)
(*   let kb = List.map (fun mg -> (None, mg)) mem in                                                                                         *)
(*   let (res, _) = List.fold_left (fun (a_r, a_kb) mg -> if not a_r then (a_r, a_kb) else is_sat_one_slice mg a_kb) (true, kb) mem in       *)
(*   res                                                                                                                                     *)

let is_sat_memo_sub_no (f : memo_pure) sat_subno with_dupl with_inv : bool =
  (* Modified version with UNSAT optimization *)
  (* if !do_slicing && !multi_provers then                       *)
  (*   is_sat_memo_sub_no_slicing f sat_subno with_dupl with_inv *)
  (* if !do_slicing && !opt_ineq then  *)
  if (not !dis_slc_ann) && !opt_ineq then
    is_sat_memo_sub_no_ineq_slicing f sat_subno with_dupl with_inv
    (* MCP.is_sat_memo_sub_no_ineq_slicing_complete f with_dupl with_inv (fun f -> is_sat_sub_no f sat_subno) *)
    (* MCP.is_sat_memo_sub_no_complete f with_dupl with_inv (fun f -> is_sat_sub_no f sat_subno) *)
  (* else if !do_slicing && !infer_lvar_slicing then *)
  else if (not !dis_slc_ann) && !infer_lvar_slicing then
    MCP.is_sat_memo_sub_no_complete f with_dupl with_inv (fun f -> is_sat_sub_no 5 f sat_subno)
  else is_sat_memo_sub_no_orig f sat_subno with_dupl with_inv

let is_sat_memo_sub_no (f : memo_pure) sat_subno with_dupl with_inv : bool =
  Debug.no_1 "is_sat_memo_sub_no" Cprinter.string_of_memo_pure_formula string_of_bool
	(fun f -> is_sat_memo_sub_no f sat_subno with_dupl with_inv) f	  

(* let is_sat_memo_sub_no_new (mem : memo_pure) sat_subno with_dupl with_inv : bool =                                          *)
(*   let memo_group_linking_vars_exps (mg : memoised_group) =                                                                  *)
(* 	let cons_lv = List.fold_left (fun acc mc -> acc @ (b_formula_linking_vars_exps mc.memo_formula)) [] mg.memo_group_cons in *)
(* 	let slice_lv = List.fold_left (fun acc f -> acc @ (formula_linking_vars_exps f)) [] mg.memo_group_slice in                *)
(* 	Gen.BList.remove_dups_eq eq_spec_var (cons_lv @ slice_lv)                                                                 *)
(*   in                                                                                                                        *)

(*   let fv_without_linking_vars_exps mg =                                                                                     *)
(* 	let fv_no_lv = Gen.BList.difference_eq eq_spec_var mg.memo_group_fv (memo_group_linking_vars_exps mg) in                  *)
(* 	(* If all fv are linking vars then mg should be a linking constraint *)                                                   *)
(* 	if (fv_no_lv = []) then mg.memo_group_fv else fv_no_lv                                                                    *)
(*   in                                                                                                                        *)

(*   let filter_fold_mg mg =                                                                                                   *)
(* 	let slice = mg.memo_group_slice in (* with_slice = true; with_disj = true *)                                              *)
(* 	let cons = List.filter (fun c -> match c.memo_status with                                                                 *)
(* 	  | Implied_R -> (*with_R*) with_dupl                                                                                     *)
(* 	  | Implied_N -> true                                                                                                     *)
(* 	  | Implied_P-> (*with_P*) with_inv) mg.memo_group_cons in                                                                *)
(* 	let cons  = List.map (fun c -> (BForm (c.memo_formula, None))) cons in                                                    *)
(* 	let asetf = List.map (fun (c1,c2) -> form_formula_eq_with_const c1 c2) (get_equiv_eq_with_const mg.memo_group_aset) in    *)
(* 	join_conjunctions (asetf @ slice @ cons)                                                                                  *)
(*   in                                                                                                                        *)
  
(*   let is_sat_slice_memo_pure (mp : memo_pure) : bool * (spec_var list * spec_var list * formula) list =                     *)
(* 	(* OUT: list of (list of fv, list of fv without linking vars, formula folded from SAT memo_groups) *)                     *)
(* 	let repart acc mg =                                                                                                       *)
(* 	  let (r, acc_fl) = acc in                                                                                                *)
(* 	  if not r then (r, [])                                                                                                   *)
(* 	  else                                                                                                                    *)
(* 		let f_mg = filter_fold_mg mg in                                                                                         *)
(* 		let r = is_sat_sub_no f_mg sat_subno in                                                                                 *)
(* 		if not r then (r, [])                                                                                                   *)
(* 		else                                                                                                                    *)
(* 		  let mg_fv_no_lv = fv_without_linking_vars_exps mg in                                                                  *)
(* 		  let (ol, nl) = List.partition (* overlap_list, non_overlap_list with mg *)                                            *)
(* 			(fun (_, vl, _) -> (Gen.BList.overlap_eq eq_spec_var vl mg_fv_no_lv)                                                  *)
(* 			) acc_fl                                                                                                              *)
(* 		  in                                                                                                                    *)
(* 		  let n_fvl = List.fold_left (fun a (fvl, _, _) -> a@fvl) mg.memo_group_fv ol in                                        *)
(* 		  let n_vl = List.fold_left (fun a (_, vl, _) -> a@vl) mg_fv_no_lv ol in                                                *)
(* 		  let n_fl = List.fold_left (fun a (_, _, fl) -> a@[fl]) [f_mg] ol in                                                   *)
(* 		  (r, (Gen.BList.remove_dups_eq eq_spec_var n_fvl,                                                                      *)
(* 			   Gen.BList.remove_dups_eq eq_spec_var n_vl,                                                                         *)
(* 			   join_conjunctions n_fl)::nl)                                                                                       *)
(* 	in List.fold_left repart (true, []) mp                                                                                    *)
(*   in                                                                                                                        *)

(*   let is_sat_slice_linking_vars_constraints (fl : (spec_var list * spec_var list * formula) list) : bool =                  *)
(* 	(* Separate the above list of formula list into two parts: *)                                                             *)
(* 	(* - Need to check SAT in combined form *)                                                                                *)
(* 	(* - Unneed to check SAT (constraints of linking vars) *)                                                                 *)
(* 	let rec repart (unchk_l, n_l, un_l) =                                                                                     *)
(* 	  (* If we know how to determine the constraints of linking vars,                                                         *)
(* 		 we do not need n_l *)                                                                                                  *)
(* 	  match unchk_l with                                                                                                      *)
(* 		| [] -> true                                                                                                            *)
(* 		| (fvl, vl, f)::unchk_rest ->                                                                                           *)
(* 		  let f_lv = Gen.BList.difference_eq eq_spec_var fvl vl in                                                              *)
(* 		  if (f_lv = []) then                                                                                                   *)
(* 			let r = is_sat_sub_no f sat_subno in (* Can reduce the # of SAT checking here *)                                      *)
(* 			if not r then r                                                                                                       *)
(* 			else repart (unchk_rest, (fvl, vl, f)::n_l, un_l)                                                                     *)
(* 		  else                                                                                                                  *)
(* 			let is_related vl1 vl2 = Gen.BList.overlap_eq eq_spec_var vl1 vl2 in                                                  *)

(* 			(* Search relevant constraints in list of unchecked constraints *)                                                    *)
(* 			(* Move merged constraints into list of unneeded to check SAT constraints *)                                          *)
(* 			let (merged_fl1, unmerged_fl1) = List.partition (fun (_, vl1, _) -> is_related vl1 f_lv) unchk_rest in                *)

(* 			(* Search relevant constraints in list of needed to check SAT constraints *)                                          *)
(* 			(* Move merged constraints into list of unneeded to check SAT constraints *)                                          *)
(* 			let (merged_fl2, unmerged_fl2) = List.partition (fun (_, vl2, _) -> is_related vl2 f_lv) n_l in                       *)

(* 			(* Search relevant constraints in list of unneeded to check SAT constraints *)                                        *)
(* 			let merged_fl3 = List.find_all (fun (_, vl3, _) -> is_related vl3 f_lv) un_l in                                       *)

(* 			let n_f = join_conjunctions                                                                                           *)
(* 			  (List.fold_left (fun acc (_, _, f) -> acc@[f])                                                                      *)
(* 				 [f] (merged_fl1 @ merged_fl2 @ merged_fl3)) in                                                                     *)

(* 			let r = is_sat_sub_no n_f sat_subno in                                                                                *)
(* 			if not r then r                                                                                                       *)
(* 			else                                                                                                                  *)
(* 			  let n_unchk_l = unmerged_fl1 in                                                                                     *)
(* 			  let n_n_l = (fvl, vl, n_f)::unmerged_fl2 in                                                                         *)
(* 			  let n_un_l = merged_fl1 @ merged_fl2 @ un_l in                                                                      *)
(* 			  repart (n_unchk_l, n_n_l, n_un_l)                                                                                   *)
(* 	in                                                                                                                        *)
(* 	repart (fl, [], [])                                                                                                       *)
(*   in                                                                                                                        *)

(*   let (r, fl) = is_sat_slice_memo_pure mem in                                                                               *)
(*   let res =                                                                                                                 *)
(* 	if not r then r                                                                                                           *)
(* 	else is_sat_slice_linking_vars_constraints fl                                                                             *)
(*   in                                                                                                                        *)
(*   res                                                                                                                       *)
  
let is_sat_mix_sub_no (f : MCP.mix_formula) sat_subno with_dupl with_inv : bool = match f with
  | MCP.MemoF f -> is_sat_memo_sub_no f sat_subno with_dupl with_inv
  | MCP.OnePF f -> (if !do_sat_slice then is_sat_sub_no_with_slicing_orig else is_sat_sub_no 61) f sat_subno

let is_sat_mix_sub_no (f : MCP.mix_formula) sat_subno with_dupl with_inv =
  Debug.no_1 "is_sat_mix_sub_no"
	Cprinter.string_of_mix_formula
	string_of_bool
	(fun f -> is_sat_mix_sub_no f sat_subno with_dupl with_inv) f

let is_sat_msg_no_no prof_lbl (f:CP.formula) do_cache :bool = 
  let sat_subno = ref 0 in
  let _ = Gen.Profiling.push_time prof_lbl in
  let sat = is_sat_sub_no_c 4 f sat_subno do_cache in
  let _ = Gen.Profiling.pop_time prof_lbl in
  sat
  
let imply_sub_no ante0 conseq0 imp_no do_cache =
  Debug.devel_zprint (lazy ("IMP #" ^ imp_no ^ "\n")) no_pos;
  (* imp_no := !imp_no+1;*)
  imply_one 2 ante0 conseq0 imp_no do_cache

let imply_sub_no ante0 conseq0 imp_no do_cache =
  let pr = !CP.print_formula in
  Debug.no_2 "imply_sub_no" pr pr (fun _ -> "")
  (fun _ _ -> imply_sub_no ante0 conseq0 imp_no do_cache) ante0 conseq0

let imply_msg_no_no ante0 conseq0 imp_no prof_lbl do_cache =
  let _ = Gen.Profiling.push_time prof_lbl in  
  let r = imply_sub_no ante0 conseq0 imp_no do_cache in
  let _ = Gen.Profiling.pop_time prof_lbl in
  r

(* is below called by pruning *)
let imply_msg_no_no ante0 conseq0 imp_no prof_lbl do_cache process =
Debug.no_2 "imply_msg_no_no " 
  Cprinter.string_of_pure_formula 
  Cprinter.string_of_pure_formula
 (fun (x,_,_)-> string_of_bool x) 
 (fun _ _ -> imply_msg_no_no ante0 conseq0 imp_no prof_lbl do_cache process) ante0 conseq0
  
let print_stats () =
  print_string ("\nTP statistics:\n");
  print_string ("omega_count = " ^ (string_of_int !omega_count) ^ "\n")

let prover_log = Buffer.create 5096

let get_prover_log () = Buffer.contents prover_log
let clear_prover_log () = Buffer.clear prover_log

let change_prover prover =
  clear_prover_log ();
  pure_tp := prover;
  start_prover ();;


let is_sat_raw (f: MCP.mix_formula) =
  is_sat_mix_sub_no f (ref 9) true true

let imply_raw ante conseq =
  let (res,_,_) = mix_imply (MCP.mix_of_pure ante) (MCP.mix_of_pure conseq) "999" in
  res

let imply_raw_mix ante conseq =
  let (res,_,_) = mix_imply ante conseq "99" in
  res

let check_diff xp0 xp1 =
  let (x,_,_) = mix_imply xp0 xp1 "check_diff" in x

let check_diff xp0 xp1 =
  let pr1 = Cprinter.string_of_mix_formula in
  Debug.no_2 "check_diff" pr1 pr1 string_of_bool check_diff xp0 xp1
