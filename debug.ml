open Globals

let debug_on = ref false
let devel_debug_on = ref false
let devel_debug_print_orig_conseq = ref false
let trace_on = ref true

let log_devel_debug = ref false
let debug_log = Buffer.create 5096

let clear_debug_log () = Buffer.clear debug_log
let get_debug_log () = Buffer.contents debug_log

(* debugging facility for user *)

(* used to enable the printing of the original consequent while devel debugging. By default, orig_conseq is disabled*)
let enable_dd_and_orig_conseq_printing () =
 devel_debug_on := true;
 devel_debug_print_orig_conseq :=  true

let string_of_pos (pos:loc) =
  pos.start_pos.Lexing.pos_fname ^ ":" ^ (string_of_int pos.start_pos.Lexing.pos_lnum) ^ ": "^(string_of_int (pos.start_pos.Lexing.pos_cnum-pos.start_pos.Lexing.pos_bol))^": "

let print s = if !debug_on then (print_string ("\n\n!!!" ^ s); flush stdout) else ()

let pprint msg (pos:loc) = 
  let tmp = pos.start_pos.Lexing.pos_fname ^ ":" ^ (string_of_int pos.start_pos.Lexing.pos_lnum) ^ ": "^ (string_of_int (pos.start_pos.Lexing.pos_cnum-pos.start_pos.Lexing.pos_bol))^ ": " ^ msg in
	print tmp

(* system development debugging *)
let ho_print flag (pr:'a->string) (m:'a) : unit = 
  let d = Gen.StackTrace.is_same_dd_get () in
  if flag (* !devel_debug_on *)  || not(d==None) then 
    let s = (pr m) in
    let msg = match d with 
      | None -> ("\n!!!" ^ s)
      | Some cid -> ("\n@"^(string_of_int cid)^"!"^ s) 
    in
    if !log_devel_debug then 
      Buffer.add_string debug_log msg
    else
      (print_string msg; flush stdout)
  else ()

(* system development debugging *)
let devel_print s = 
  ho_print !devel_debug_on (fun x -> x) s 
(* let d = Gen.StackTrace.is_same_dd_get () in *)
(*   if !devel_debug_on  || not(d==None) then  *)
(*     let msg = match d with  *)
(*       | None -> ("\n!!!" ^ s) *)
(*       | Some cid -> ("\n@"^(string_of_int cid)^"!"^ s)  *)
(*     in *)
(*     if !log_devel_debug then  *)
(*       Buffer.add_string debug_log msg *)
(*     else *)
(*       (print_string msg; flush stdout) *)
(*   else () *)

let prior_msg pos =
  let tmp = pos.start_pos.Lexing.pos_fname ^ ":" ^ (string_of_int pos.start_pos.Lexing.pos_lnum) ^ ": " ^ (string_of_int (pos.start_pos.Lexing.pos_cnum-pos.start_pos.Lexing.pos_bol)) ^ ": " in
  let tmp = if is_no_pos !entail_pos then tmp 
  else (tmp^"[entail:"^(string_of_int !entail_pos.start_pos.Lexing.pos_lnum)^"]"^"[post:"^(string_of_int (post_pos#get).start_pos.Lexing.pos_lnum)^"]") 
  in tmp

let devel_pprint (msg:string) (pos:loc) =
  let flag = !devel_debug_on in
  ho_print flag (fun m -> (prior_msg pos)^m) msg

let devel_hprint (pr:'a->string) (m:'a) (pos:loc) = 
  let flag = !devel_debug_on in
  ho_print flag (fun x -> (prior_msg pos)^(pr x)) m

let devel_zprint msg (pos:loc) =
  let flag = !devel_debug_on in
  ho_print flag (fun m -> (prior_msg pos)^(Lazy.force m)) msg

let dinfo_zprint m p = devel_zprint m p
let dinfo_hprint pr m p  = devel_hprint pr m p
let dinfo_pprint m p = devel_pprint m p

let binfo_pprint (msg:string) (pos:loc) =
  let s = if !devel_debug_on then (prior_msg pos) else " " in
  let flag = !trace_on or !devel_debug_on in
  ho_print flag (fun m -> s^m) msg


let binfo_hprint (pr:'a->string) (m:'a) (pos:loc) = 
  let s = if !devel_debug_on then (prior_msg pos) else " " in
  let flag = !trace_on or !devel_debug_on in
  ho_print flag (fun x -> s^(pr x)) m

let binfo_zprint msg (pos:loc) =
  let s = if !devel_debug_on then (prior_msg pos) else " " in
  let flag = !trace_on or !devel_debug_on in
  ho_print flag (fun m -> s^(Lazy.force m)) msg


let binfo_start (msg:string) =
        binfo_pprint "**********************************" no_pos;
        binfo_pprint ("**** "^msg^" ****") no_pos;
        binfo_pprint "**********************************" no_pos

let binfo_end (msg:string) =
        binfo_pprint "**********************************" no_pos;
        binfo_pprint ("**** end of "^msg^" ****") no_pos;
        binfo_pprint "**********************************" no_pos

let dinfo_start (msg:string) =
        dinfo_pprint "**********************************" no_pos;
        dinfo_pprint ("**** "^msg^" detected ****") no_pos;
        dinfo_pprint "**********************************" no_pos

let dinfo_end (msg:string) =
        dinfo_pprint "**********************************" no_pos;
        dinfo_pprint ("**** end of "^msg^" ****") no_pos;
        dinfo_pprint "**********************************" no_pos

let ninfo_zprint m p = ()
let ninfo_hprint pr m p  = ()
let ninfo_pprint m p = ()

(*
  -- -v:10-50 (for details + all tracing + omega)
  -- -v:1-9 (for details only)
  -- -v:50.. (for tracing only)
  -- -v:-1 (minimal tracing)
  -- -v:-2..(exact tracing)
*)

let add_str s f xs = s^":"^(f xs)

let gen_vv_flags d =
  let m = !Globals.verbose_num in
  let (flag,str) =
    if d<0 then (m==d,"EXACT:")
    else if m>50 then (d>=m,"DEBUG:")
    else if m<10 then (m>=d,"")
    else if d>=50 then (true,"DEBUG_"^(string_of_int d)^":")
    else (m>=d,"") in
  (flag,str)


let verbose_hprint (d:int) (p:'a -> string) (arg:'a)  =
  let (flag,str)=gen_vv_flags d in
  ho_print flag (add_str str p) arg

(* let verbose_pprint (d:int) (msg:string)  = *)
(*   verbose_hprint d (fun m -> m) msg *)

(* let verbose_pprint (d:int) (msg)  = *)
(*   verbose_hprint d (fun m -> m) msg *)

let vv_pprint d msg = verbose_hprint d (fun m -> m) msg

let vv_hprint d f arg = verbose_hprint d f arg

let vv_zprint d lmsg = 
  verbose_hprint d (fun x -> Lazy.force x) lmsg

let vv_plist d ls = 
  let (flag,str) = gen_vv_flags d in
  let rec helper ls =
    match ls with
      | [] -> ()
      | ((m,y)::xs) ->
            begin
            (ho_print flag (fun msg -> str^m^":"^msg) y)
                ; helper xs
            end
  in helper ls

let vv_hdebug f arg = vv_hprint 200 f arg 

(* less tracing *)
let vv_pdebug msg = vv_hdebug (fun m -> m) msg

let vv_debug msg = vv_pdebug msg

(* detailed tracing *)
let vv_trace msg = vv_hprint 100 (fun m -> m) msg

let vv_zdebug msg = vv_hdebug (fun x -> Lazy.force x) msg

let vv_result (s:string) (d:int) ls =
  vv_pprint d (">>>>>>>>>"^s^">>>>>>>>>");
  vv_plist d ls;
  vv_pprint d (">>>>>>>>>"^s^">>>>>>>>>")

let trace_pprint (msg:string) (pos:loc) : unit = 
	ho_print false (fun a -> " "^a) msg

let trace_hprint (pr:'a->string) (m:'a) (pos:loc) = 
	ho_print false (fun x -> " "^(pr x)) m

let trace_zprint m (pos:loc) = 
	ho_print false (fun x -> Lazy.force x) m

let tinfo_zprint m p = trace_zprint m p
let tinfo_hprint pr m p  = trace_hprint pr m p
let tinfo_pprint m p = trace_pprint m p

let info_pprint (msg:string) (pos:loc) : unit = 
	ho_print true (fun a -> " "^a) msg

let info_hprint (pr:'a->string) (m:'a) (pos:loc) = 
	ho_print true (fun x -> " "^(pr x)) m

let info_zprint m (pos:loc) = 
	ho_print true (fun x -> Lazy.force x) m

(* let devel_zprint msg (pos:loc) = *)
(* 	lazy_print (prior_msg pos) msg *)

(* let trace_zprint msg (pos:loc) =  *)
(* 	lazy_print (fun () -> " ") msg *)


let print_info prefix str (pos:loc) = 
  let tmp = "\n" ^ prefix ^ ":" ^ pos.start_pos.Lexing.pos_fname ^ ":" ^ (string_of_int pos.start_pos.Lexing.pos_lnum) ^": " ^ (string_of_int (pos.start_pos.Lexing.pos_cnum-pos.start_pos.Lexing.pos_bol)) ^": " ^ str ^ "\n" in
	print_string tmp; flush stdout


open Gen.StackTrace
 
  (* let ho_2_opt_aux (loop_d:bool) (test:'z -> bool) (s:string) (pr1:'a->string) (pr2:'b->string) (pr_o:'z->string)  (f:'a -> 'b -> 'z)  *)
  (*       (e1:'a) (e2:'b) : 'z = *)
  (*   let s,h = push s in *)
  (*   (if loop_d then print_string (h^" inp :"^(pr1 e1)^"\n")); *)
  (*   let r = try *)
  (*     pop_ho (f e1) e2  *)
  (*   with ex ->  *)
  (*       let _ = print_string (h^"\n") in *)
  (*       let _ = print_string (s^" inp1 :"^(pr1 e1)^"\n") in *)
  (*       let _ = print_string (s^" inp2 :"^(pr2 e2)^"\n") in *)
  (*       let _ = print_string (s^" Exception"^(Printexc.to_string ex)^"Occurred!\n") in *)
  (*       raise ex in *)
  (*   if not(test r) then r else *)
  (*     let _ = print_string (h^"\n") in *)
  (*     let _ = print_string (s^" inp1 :"^(pr1 e1)^"\n") in *)
  (*     let _ = print_string (s^" inp2 :"^(pr2 e2)^"\n") in *)
  (*     let _ = print_string (s^" out :"^(pr_o r)^"\n") in *)
  (*     r *)

let ho_aux df lz (loop_d:bool) (test:'z -> bool) (g:('a->'z) option) (s:string) (args:string list) (pr_o:'z->string) (f:'a->'z) (e:'a) :'z =
  let pr_args xs =
    let rec helper (i:int) args = match args with
      | [] -> ()
      | a::args -> (print_string (s^" inp"^(string_of_int i)^" :"^a^"\n");(helper (i+1) args)) in
    helper 1 xs in
  let pr_lazy_res xs =
    let rec helper xs = match xs with
      | [] -> ()
      | (i,a)::xs -> let a1=Lazy.force a in
        if (a1=(List.nth args (i-1))) then helper xs
        else (print_string (s^" res"^(string_of_int i)^" :"^(a1)^"\n");(helper xs)) in
    helper xs in
  let (test,pr_o) = match g with
    | None -> (test,pr_o)
    | Some g -> 
          let res = ref (None:(string option)) in
          let new_test z =
            (try
              let r = g e in
              let rs = pr_o r in              
              if String.compare (pr_o z) rs==0 then false
              else (res := Some rs; true)
            with ex ->  
                (res := Some (" OLD COPY : EXIT Exception"^(Printexc.to_string ex)^"!\n");
                true)) in
          let new_pr_o x = (match !res with
            | None -> pr_o x
            | Some s -> ("DIFFERENT RESULT from PREVIOUS METHOD"^
                  ("\n PREV :"^s)^
                  ("\n NOW :"^(pr_o x)))) in
          (new_test, new_pr_o) in
  let s,h = push_call_gen s df in
  (if loop_d then print_string ("\n"^h^" ENTRY :"^(String.concat "  " args)^"\n"));
  flush stdout;
  let r = (try
    pop_aft_apply_with_exc f e
  with ex -> 
      (let _ = print_string ("\n"^h^"\n") in
      (* if not df then *) 
        (pr_args args; pr_lazy_res lz);
      let _ = print_string (s^" EXIT Exception"^(Printexc.to_string ex)^"Occurred!\n") in
      flush stdout;
      raise ex)) in
  (if not(test r) then r else
    let _ = print_string ("\n"^h^"\n") in
    (* if not df then *)
      (pr_args args; pr_lazy_res lz);
    let _ = print_string (s^" EXIT out :"^(pr_o r)^"\n") in
    flush stdout;
    r)

let choose bs xs = 
  let rec hp bs xs = match bs,xs with
    |[], _ -> []
    | _, [] -> []
    | b::bs, (i,s)::xs -> if b then (i,s)::(hp bs xs) else (hp bs xs) in
  hp bs xs

let ho_aux_no (f:'a -> 'z) (last:'a) : 'z =
  push_no_call ();
  pop_aft_apply_with_exc_no f last


let ho_1_opt_aux df (flags:bool list) (loop_d:bool) (test:'z -> bool) g (s:string) (pr1:'a->string) (pr_o:'z->string)  (f:'a -> 'z) (e1:'a) : 'z =
  let a1 = pr1 e1 in
  let lz = choose flags [(1,lazy (pr1 e1))] in
  let f  = f in
  ho_aux df lz loop_d test g s [a1] pr_o  f  e1


let ho_2_opt_aux df (flags:bool list) (loop_d:bool) (test:'z -> bool) g (s:string) (pr1:'a->string) (pr2:'b->string) (pr_o:'z->string)  (f:'a -> 'b -> 'z) 
      (e1:'a) (e2:'b) : 'z =
  let a1 = pr1 e1 in
  let a2 = pr2 e2 in
  let lz = choose flags [(1,lazy (pr1 e1)); (2,lazy (pr2 e2))] in
  let f  = f e1 in
  let g  = match g with None -> None | Some g -> Some (g e1) in
  ho_aux df lz loop_d test g s [a1;a2] pr_o f e2

let ho_3_opt_aux df  (flags:bool list) (loop_d:bool) (test:'z -> bool) g (s:string) (pr1:'a->string) (pr2:'b->string) (pr3:'c->string) (pr_o:'z->string)  (f:'a -> 'b -> 'c -> 'z) (e1:'a) (e2:'b) (e3:'c) : 'z =
  let a1 = pr1 e1 in
  let a2 = pr2 e2 in
  let a3 = pr3 e3 in
  let lz = choose flags [(1,lazy (pr1 e1)); (2,lazy (pr2 e2)); (3,lazy (pr3 e3))] in
  let f  = f e1 e2 in
  let g  = match g with None -> None | Some g -> Some (g e1 e2) in
  ho_aux df lz loop_d test g s [a1;a2;a3] pr_o f e3


let ho_4_opt_aux df (flags:bool list) (loop_d:bool) (test:'z->bool) g (s:string) (pr1:'a->string) (pr2:'b->string) (pr3:'c->string) (pr4:'d->string) (pr_o:'z->string) 
      (f:'a -> 'b -> 'c -> 'd-> 'z) (e1:'a) (e2:'b) (e3:'c) (e4:'d): 'z =
  let a1 = pr1 e1 in
  let a2 = pr2 e2 in
  let a3 = pr3 e3 in
  let a4 = pr4 e4 in
  let lz = choose flags [(1,lazy (pr1 e1)); (2,lazy (pr2 e2)); (3,lazy (pr3 e3)); (4,lazy (pr4 e4))] in
  let f  = f e1 e2 e3 in
  let g  = match g with None -> None | Some g -> Some (g e1 e2 e3) in
  ho_aux df lz loop_d test g s [a1;a2;a3;a4] pr_o f e4


let ho_5_opt_aux df (flags:bool list) (loop_d:bool) (test:'z -> bool)  g (s:string) (pr1:'a->string) (pr2:'b->string) (pr3:'c->string) (pr4:'d->string)
      (pr5:'e->string) (pr_o:'z->string) 
      (f:'a -> 'b -> 'c -> 'd -> 'e -> 'z) (e1:'a) (e2:'b) (e3:'c) (e4:'d) (e5:'e) : 'z =
  let a1 = pr1 e1 in
  let a2 = pr2 e2 in
  let a3 = pr3 e3 in
  let a4 = pr4 e4 in
  let a5 = pr5 e5 in
  let lz = choose flags [(1,lazy (pr1 e1)); (2,lazy (pr2 e2)); (3,lazy (pr3 e3)); (4,lazy (pr4 e4)); (5,lazy (pr5 e5))] in
  let f  = f e1 e2 e3 e4 in
  let g  = match g with None -> None | Some g -> Some (g e1 e2 e3 e4) in
  ho_aux df lz loop_d test g s [a1;a2;a3;a4;a5] pr_o f e5


let ho_6_opt_aux df (flags:bool list) (loop_d:bool) (test:'z->bool) g (s:string) (pr1:'a->string) (pr2:'b->string) (pr3:'c->string) (pr4:'d->string)
      (pr5:'e->string) (pr6:'f->string) (pr_o:'z->string) 
      (f:'a -> 'b -> 'c -> 'd -> 'e -> 'f -> 'z) (e1:'a) (e2:'b) (e3:'c) (e4:'d) (e5:'e) (e6:'f): 'z =
  let a1 = pr1 e1 in
  let a2 = pr2 e2 in
  let a3 = pr3 e3 in
  let a4 = pr4 e4 in
  let a5 = pr5 e5 in
  let a6 = pr6 e6 in
  let lz = choose flags [(1,lazy (pr1 e1)); (2,lazy (pr2 e2)); (3,lazy (pr3 e3)); (4,lazy (pr4 e4)); (5,lazy (pr5 e5)); (6,lazy (pr6 e6))] in
  let f  = f e1 e2 e3 e4 e5 in
  let g  = match g with None -> None | Some g -> Some (g e1 e2 e3 e4 e5) in
  ho_aux df lz loop_d test g s [a1;a2;a3;a4;a5;a6] pr_o f e6

let ho_7_opt_aux df (flags:bool list) (loop_d:bool) (test:'z->bool) g (s:string) (pr1:'a->string) (pr2:'b->string) (pr3:'c->string) (pr4:'d->string)
      (pr5:'e->string) (pr6:'f->string) (pr7:'h->string) (pr_o:'z->string) 
      (f:'a -> 'b -> 'c -> 'd -> 'e -> 'f -> 'h-> 'z) (e1:'a) (e2:'b) (e3:'c) (e4:'d) (e5:'e) (e6:'f) (e7:'h): 'z =
  let a1 = pr1 e1 in
  let a2 = pr2 e2 in
  let a3 = pr3 e3 in
  let a4 = pr4 e4 in
  let a5 = pr5 e5 in
  let a6 = pr6 e6 in
  let a7 = pr7 e7 in
  let lz = choose flags [(1,lazy (pr1 e1)); (2,lazy (pr2 e2)); (3,lazy (pr3 e3)); (4,lazy (pr4 e4)); (5,lazy (pr5 e5)); (6,lazy (pr6 e6)); (7,lazy (pr7 e7))] in
  let f  = f e1 e2 e3 e4 e5 e6 in
  let g  = match g with None -> None | Some g -> Some (g e1 e2 e3 e4 e5 e6) in
  ho_aux df lz loop_d test g s [a1;a2;a3;a4;a5;a6;a7] pr_o f e7

(* better re-organization *)
let ho_1_preopt f b_loop = ho_1_opt_aux false [] b_loop f None
let to_1_preopt f b_loop = ho_1_opt_aux true [] b_loop f None
let ho_1_pre b_loop = ho_1_preopt (fun _ -> true) b_loop
let to_1_pre b_loop = to_1_preopt (fun _ -> true) b_loop
let ho_1 s = ho_1_pre false s
let to_1 s = to_1_pre false s
let ho_1_opt f = ho_1_preopt f false
let ho_1_loop s = ho_1_pre true s 

let ho_1 s = ho_1_opt_aux false [] false (fun _ -> true) None s
let ho_2 s = ho_2_opt_aux false [] false (fun _ -> true) None s
let ho_3 s = ho_3_opt_aux false [] false (fun _ -> true) None s
let ho_4 s = ho_4_opt_aux false [] false (fun _ -> true) None s
let ho_5 s = ho_5_opt_aux false [] false (fun _ -> true) None s
let ho_6 s = ho_6_opt_aux false [] false (fun _ -> true) None s
let ho_7 s = ho_7_opt_aux false [] false (fun _ -> true) None s

type debug_option =
  | DO_None
  | DO_Trace
  | DO_Loop
  | DO_Normal

let debug_map = Hashtbl.create 50

let read_from_debug_file chn : string list =
  let line = ref [] in
  let quitloop = ref false in
  (try
    while true do
      let xs = (input_line chn) in
      let n = String.length xs in
      (* let s = String.sub xs 0 1 in *)
      if n > 0 && xs.[0]!='#' (* String.compare s "#" !=0 *) then begin
        line := xs::!line;
      end;
    done;
  with _ -> ());
  !line

let read_from_debug_file chn : string list =
 ho_1 "read_from_debug_file" (fun _ -> "?") (pr_list (fun x -> x))read_from_debug_file chn

let read_main () =
  let xs = read_from_debug_file (debug_file ()) in
  (* let _ = print_endline ((pr_list (fun x -> x)) xs) in *)
  List.iter (fun x ->
      try
        let l = String.index x ',' in
        let m = String.sub x 0 l in
        let split = String.sub x (l+1) ((String.length x) -l -1) in
        let _ = print_endline (m) in
        let _ = print_endline (split) in
        let kind = if String.compare split "Trace" == 0 then DO_Trace else
          if String.compare split "Loop" == 0 then DO_Loop else
            DO_Normal
        in
        Hashtbl.add debug_map m kind
      with _ ->
      Hashtbl.add debug_map x DO_Normal
  ) xs

let in_debug x =
  try
    Hashtbl.find debug_map x
  with _ -> DO_None


let to_1 s = ho_1_opt_aux true [] false (fun _ -> true) None s
let to_2 s = ho_2_opt_aux true [] false (fun _ -> true) None s
let to_3 s = ho_3_opt_aux true [] false (fun _ -> true) None s
let to_4 s = ho_4_opt_aux true [] false (fun _ -> true) None s
let to_5 s = ho_5_opt_aux true [] false (fun _ -> true) None s
let to_6 s = ho_6_opt_aux true [] false (fun _ -> true) None s
let to_7 s = ho_7_opt_aux true [] false (fun _ -> true) None s

let ho_1_loop s = ho_1_opt_aux false [] true (fun _ -> true) None s
let ho_2_loop s = ho_2_opt_aux false [] true (fun _ -> true) None s
let ho_3_loop s = ho_3_opt_aux false [] true (fun _ -> true) None s
let ho_4_loop s = ho_4_opt_aux false [] true (fun _ -> true) None s
let ho_5_loop s = ho_5_opt_aux false [] true (fun _ -> true) None s
let ho_6_loop s = ho_6_opt_aux false [] true (fun _ -> true) None s
let ho_7_loop s = ho_7_opt_aux false [] true (fun _ -> true) None s

(* let splitter s f_norm f_trace f_loop f_none = *)
(*   (\* if !read_debug_flag then *\) *)
(*   if String.compare !z_debug_file "" != 0 then *)
(*     match (in_debug s) with *)
(*       | DO_Normal -> f_norm *)
(*       | DO_Trace -> f_trace  *)
(*       | DO_Loop -> f_loop  *)
(*       | DO_None -> f_none *)
(*   else f_none *)

let splitter s f_none f_gen f_norm f_trace f_loop =
  (* if !read_debug_flag then *)
  if !z_debug_flag then
    (* String.compare !z_debug_file "" != 0 then *)
    match (in_debug s) with
      | DO_Normal -> f_gen f_norm
      | DO_Trace -> f_gen f_trace 
      | DO_Loop -> f_gen f_loop 
      | DO_None -> f_none
  else f_none

let no_1 s p1 p0 f =
  let code_gen fn = fn s p1 p0 f in
  let code_none = ho_aux_no f in
  splitter s code_none code_gen ho_1 to_1 ho_1_loop

let no_2 s p1 p2 p0 f e1 =
  let code_gen fn = fn s p1 p2 p0 f e1 in
  let code_none = ho_aux_no (f e1) in
  splitter s code_none code_gen ho_2 to_2 ho_2_loop

let no_3 s p1 p2 p3 p0 f e1 e2 =
  let code_gen fn = fn s p1 p2 p3 p0 f e1 e2 in
  let code_none = ho_aux_no (f e1 e2) in
  splitter s code_none code_gen ho_3 to_3 ho_3_loop

let no_4 s p1 p2 p3 p4 p0 f e1 e2 e3 =
  let code_gen fn = fn s p1 p2 p3 p4 p0 f e1 e2 e3 in
  let code_none = ho_aux_no (f e1 e2 e3) in
  splitter s code_none code_gen ho_4 to_4 ho_4_loop

let no_5 s p1 p2 p3 p4 p5 p0 f e1 e2 e3 e4 =
  let code_gen fn = fn s p1 p2 p3 p4 p5 p0 f e1 e2 e3 e4 in
  let code_none = ho_aux_no (f e1 e2 e3 e4) in
  splitter s code_none code_gen ho_5 to_5 ho_5_loop

let no_6 s p1 p2 p3 p4 p5 p6 p0 f e1 e2 e3 e4 e5 =
  let code_gen fn = fn s p1 p2 p3 p4 p5 p6 p0 f e1 e2 e3 e4 e5 in
  let code_none = ho_aux_no (f e1 e2 e3 e4 e5) in
  splitter s code_none code_gen ho_6 to_6 ho_6_loop

let no_7 s p1 p2 p3 p4 p5 p6 p7 p0 f e1 e2 e3 e4 e5 e6 =
  let code_gen fn = fn s p1 p2 p3 p4 p5 p6 p7 p0 f e1 e2 e3 e4 e5 e6 in
  let code_none = ho_aux_no (f e1 e2 e3 e4 e5 e6) in
  splitter s code_none code_gen ho_7 to_7 ho_7_loop


let ho_1_opt f = ho_1_opt_aux false [] false f None
let ho_2_opt f = ho_2_opt_aux false [] false f None
let ho_3_opt f = ho_3_opt_aux false [] false f None
let ho_4_opt f = ho_4_opt_aux false [] false f None
let ho_5_opt f = ho_5_opt_aux false [] false f None
let ho_6_opt f = ho_6_opt_aux false [] false f None

let to_1_opt f = ho_1_opt_aux true [] false f None
let to_2_opt f = ho_2_opt_aux true [] false f None
let to_3_opt f = ho_3_opt_aux true [] false f None
let to_4_opt f = ho_4_opt_aux true [] false f None
let to_5_opt f = ho_5_opt_aux true [] false f None
let to_6_opt f = ho_6_opt_aux true [] false f None
let to_7_opt f = ho_7_opt_aux true [] false f None

let no_1_opt _ _ _ _ f 
      = ho_aux_no f
let no_2_opt _ _ _ _ _ f e1 
      = ho_aux_no (f e1)
let no_3_opt _ _ _ _ _ _ f e1 e2 
      = ho_aux_no (f e1 e2)
let no_4_opt _ _ _ _ _ _ _ f e1 e2 e3 
      = ho_aux_no (f e1 e2 e3)
let no_5_opt _ _ _ _ _ _ _ _ f e1 e2 e3 e4 
      = ho_aux_no (f e1 e2 e3 e4)
let no_6_opt _ _ _ _ _ _ _ _ _ f e1 e2 e3 e4 e5 
      = ho_aux_no (f e1 e2 e3 e4 e5)

let add_num f i s = let str=(s^"#"^(string_of_int i)) in f str

let ho_1_num i =  add_num ho_1 i
let ho_2_num i =  add_num ho_2 i
let ho_3_num i =  add_num ho_3 i
let ho_4_num i =  add_num ho_4 i
let ho_5_num i =  add_num ho_5 i
let ho_6_num i =  add_num ho_6 i

let to_1_num i =  add_num to_1 i
let to_2_num i =  add_num to_2 i
let to_3_num i =  add_num to_3 i
let to_4_num i =  add_num to_4 i
let to_5_num i =  add_num to_5 i
let to_6_num i =  add_num to_6 i

let ho_1_loop_num i =  add_num ho_1_loop i
let ho_2_loop_num i =  add_num ho_2_loop i
let ho_3_loop_num i =  add_num ho_3_loop i
let ho_4_loop_num i =  add_num ho_4_loop i
let ho_5_loop_num i =  add_num ho_5_loop i
let ho_6_loop_num i =  add_num ho_6_loop i

let to_1_loop s = ho_1_opt_aux true [] true (fun _ -> true) None s
let to_2_loop s = ho_2_opt_aux true [] true (fun _ -> true) None s
let to_3_loop s = ho_3_opt_aux true [] true (fun _ -> true) None s
let to_4_loop s = ho_4_opt_aux true [] true (fun _ -> true) None s
let to_5_loop s = ho_5_opt_aux true [] true (fun _ -> true) None s
let to_6_loop s = ho_6_opt_aux true [] true (fun _ -> true) None s

let to_1_loop_num i =  add_num to_1_loop i
let to_2_loop_num i =  add_num to_2_loop i
let to_3_loop_num i =  add_num to_3_loop i
let to_4_loop_num i =  add_num to_4_loop i
let to_5_loop_num i =  add_num to_5_loop i
let to_6_loop_num i =  add_num to_6_loop i

(* let no_1_num (i:int) s _ _ f *)
(*       = ho_aux_no f *)
(* let no_2_num (i:int) s _ _ _ f e1 *)
(*       = ho_aux_no (f e1) *)
(* let no_3_num (i:int) s _ _ _ _ f e1 e2 *)
(*       = ho_aux_no (f e1 e2) *)
(* let no_4_num (i:int) s _ _ _ _ _ f e1 e2 e3 *)
(*       = ho_aux_no (f e1 e2 e3) *)
(* let no_5_num (i:int) s _ _ _ _ _ _ f e1 e2 e3 e4 *)
(*       = ho_aux_no (f e1 e2 e3 e4) *)
(* let no_6_num (i:int) s _ _ _ _ _ _ _ f e1 e2 e3 e4 e5 *)
(*       = ho_aux_no (f e1 e2 e3 e4 e5) *)

let no_1_num (i:int) s p1 p0 f =
  let code_gen fn = fn i s p1 p0 f in
  let code_none = ho_aux_no f in
  splitter s code_none code_gen ho_1_num to_1_num ho_1_loop_num

let no_2_num (i:int) s p1 p2 p0 f e1 =
  let code_gen fn = fn i s p1 p2 p0 f e1 in
  let code_none = ho_aux_no (f e1) in
  splitter s code_none code_gen ho_2_num to_2_num ho_2_loop_num

let no_3_num (i:int) s p1 p2 p3 p0 f e1 e2 =
  let code_gen fn = fn i s p1 p2 p3 p0 f e1 e2 in
  let code_none = ho_aux_no (f e1 e2) in
  splitter s code_none code_gen ho_3_num to_3_num ho_3_loop_num

let no_4_num (i:int) s p1 p2 p3 p4 p0 f e1 e2 e3 =
  let code_gen fn = fn i s p1 p2 p3 p4 p0 f e1 e2 e3 in
  let code_none = ho_aux_no (f e1 e2 e3) in
  splitter s code_none code_gen ho_4_num to_4_num ho_4_loop_num

let no_5_num (i:int) s p1 p2 p3 p4 p5 p0 f e1 e2 e3 e4 =
  let code_gen fn = fn i s p1 p2 p3 p4 p5 p0 f e1 e2 e3 e4 in
  let code_none = ho_aux_no (f e1 e2 e3 e4) in
  splitter s code_none code_gen ho_5_num to_5_num ho_5_loop_num

let no_6_num (i:int) s p1 p2 p3 p4 p5 p6 p0 f e1 e2 e3 e4 e5 =
  let code_gen fn = fn i s p1 p2 p3 p4 p5 p6 p0 f e1 e2 e3 e4 e5 in
  let code_none = ho_aux_no (f e1 e2 e3 e4 e5) in
  splitter s code_none code_gen ho_6_num to_6_num ho_6_loop_num


let ho_1_cmp g = ho_1_opt_aux false [] false (fun _ -> true) (Some g) 
let ho_2_cmp g = ho_2_opt_aux false [] false (fun _ -> true) (Some g) 
let ho_3_cmp g = ho_3_opt_aux false [] false (fun _ -> true) (Some g) 
let ho_4_cmp g = ho_4_opt_aux false [] false (fun _ -> true) (Some g) 
let ho_5_cmp g = ho_5_opt_aux false [] false (fun _ -> true) (Some g) 
let ho_6_cmp g = ho_6_opt_aux false [] false (fun _ -> true) (Some g) 

let no_1_cmp _ _ _ _ f 
      = ho_aux_no f
let no_2_cmp _ _ _ _ _ f e1 
      = ho_aux_no (f e1)
let no_3_cmp _ _ _ _ _ _ f e1 e2 
      = ho_aux_no (f e1 e2)
let no_4_cmp _ _ _ _ _ _ _ f e1 e2 e3 
      = ho_aux_no (f e1 e2 e3)
let no_5_cmp _ _ _ _ _ _ _ _ f e1 e2 e3 e4 
      = ho_aux_no (f e1 e2 e3 e4)
let no_6_cmp _ _ _ _ _ _ _ _ _ f e1 e2 e3 e4 e5 
      = ho_aux_no (f e1 e2 e3 e4 e5)

let ho_eff_1 s l = ho_1_opt_aux false l false (fun _ -> true) None s
let ho_eff_2 s l = ho_2_opt_aux false l false (fun _ -> true) None s
let ho_eff_3 s l = ho_3_opt_aux false l false (fun _ -> true) None s
let ho_eff_4 s l = ho_4_opt_aux false l false (fun _ -> true) None s
let ho_eff_5 s l = ho_5_opt_aux false l false (fun _ -> true) None s
let ho_eff_6 s l = ho_6_opt_aux false l false (fun _ -> true) None s

let to_eff_1 s l = ho_1_opt_aux true l false (fun _ -> true) None s
let to_eff_2 s l = ho_2_opt_aux true l false (fun _ -> true) None s
let to_eff_3 s l = ho_3_opt_aux true l false (fun _ -> true) None s
let to_eff_4 s l = ho_4_opt_aux true l false (fun _ -> true) None s
let to_eff_5 s l = ho_5_opt_aux true l false (fun _ -> true) None s
let to_eff_6 s l = ho_6_opt_aux true l false (fun _ -> true) None s

let no_eff_1 _ _ _ _ f 
      = ho_aux_no f
let no_eff_2 _ _ _ _ _ f e1 
      = ho_aux_no (f e1)
let no_eff_3 _ _ _ _ _ _ f e1 e2 
      = ho_aux_no (f e1 e2)
let no_eff_4 _ _ _ _ _ _ _ f e1 e2 e3 
      = ho_aux_no (f e1 e2 e3)
let no_eff_5 _ _ _ _ _ _ _ _ f e1 e2 e3 e4 
      = ho_aux_no (f e1 e2 e3 e4)
let no_eff_6 _ _ _ _ _ _ _ _ _ f e1 e2 e3 e4 e5 
      = ho_aux_no (f e1 e2 e3 e4 e5)

let ho_eff_1_num i =  add_num ho_eff_1 i
let ho_eff_2_num i =  add_num ho_eff_2 i
let ho_eff_3_num i =  add_num ho_eff_3 i
let ho_eff_4_num i =  add_num ho_eff_4 i
let ho_eff_5_num i =  add_num ho_eff_5 i
let ho_eff_6_num i =  add_num ho_eff_6 i

let to_eff_1_num i =  add_num to_eff_1 i
let to_eff_2_num i =  add_num to_eff_2 i
let to_eff_3_num i =  add_num to_eff_3 i
let to_eff_4_num i =  add_num to_eff_4 i
let to_eff_5_num i =  add_num to_eff_5 i
let to_eff_6_num i =  add_num to_eff_6 i

let no_eff_1_num _ _ _ _ _ f 
      =  ho_aux_no (f)
let no_eff_2_num _ _ _ _ _ _ f e1 
      =  ho_aux_no (f e1)
let no_eff_3_num _ _ _ _ _ _ _ f e1 e2 
      =  ho_aux_no (f e1 e2)
let no_eff_4_num _ _ _ _ _ _ _ _ f e1 e2 e3 
      =  ho_aux_no (f e1 e2 e3)
let no_eff_5_num _ _ _ _ _ _ _ _ _ f e1 e2 e3 e4 
      =  ho_aux_no (f e1 e2 e3 e4)
let no_eff_6_num _ _ _ _ _ _ _ _ _ _ f e1 e2 e3 e4 e5 
      =  ho_aux_no (f e1 e2 e3 e4 e5)



let no_1_loop _ _ _ f 
      = ho_aux_no f
let no_2_loop _ _ _ _ f e1 
      = ho_aux_no (f e1)
let no_3_loop _ _ _ _ _ f e1 e2
      = ho_aux_no (f e1 e2)
let no_4_loop _ _ _ _ _ _ f e1 e2 e3
      = ho_aux_no (f e1 e2 e3)
let no_5_loop _ _ _ _ _ _ _ f e1 e2 e3 e4
      = ho_aux_no (f e1 e2 e3 e4)
let no_6_loop _ _ _ _ _ _ _ _ f e1 e2 e3 e4 e5
      = ho_aux_no (f e1 e2 e3 e4 e5)


let no_1_loop_num _ _ _ _ f 
      = ho_aux_no f
let no_2_loop_num _ _ _ _ _ f e1 
      = ho_aux_no (f e1)
let no_3_loop_num _ _ _ _ _ _ f e1 e2
      = ho_aux_no (f e1 e2)
let no_4_loop_num _ _ _ _ _ _ _ f e1 e2 e3
      = ho_aux_no (f e1 e2 e3)
let no_5_loop_num _ _ _ _ _ _ _ _ f e1 e2 e3 e4
      = ho_aux_no (f e1 e2 e3 e4)
let no_6_loop_num _ _ _ _ _ _ _ _ _ f e1 e2 e3 e4 e5
      = ho_aux_no (f e1 e2 e3 e4 e5)

  (* let no_eff_1_opt  _ _ _ _ _ f = f *)
  (* let no_eff_2_opt  _ _ _ _ _ _ f = f *)
  (* let no_eff_3_opt  _ _ _ _ _ _ _ f = f *)
  (* let no_eff_4_opt  _ _ _ _ _ _ _ _ f = f *)
  (* let no_eff_5_opt  _ _ _ _ _ _ _ _ _ f = f *)
  (* let no_eff_6_opt  _ _ _ _ _ _ _ _ _ _ f = f *)
