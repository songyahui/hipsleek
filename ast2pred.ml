#include "xdebug.cppo"
open VarGen


(*
this module tranform an iast to pred
*)

open Globals
open Gen.Basic
open Wrapper
open Others
open Exc.GTable
open Printf
open Gen.Basic
open Gen.BList
open Mcpure_D
open Mcpure
open Label_only
open Typeinfer

module E = Env
module Err = Error
module I = Iast
module IF = Iformula
module IP = Ipure
module LO = Label_only.LOne
open IastUtil

let err_var = "#e"
let res_var = "#r"

type assert_err=
  | Safe
  | Unsafe
  | Unk
  | NotApp

let string_of_assert_err res= match res with
    | Safe -> "safe"
    | Unsafe -> "unsafe"
    | Unk -> "unknown"
    | NotApp -> "not applicable"

let exam_ass_error_proc iprog proc=
  match proc.I.proc_body with
    | Some e -> I.exists_assert_error iprog e
    | None -> false

let exam_ass_error_scc iprog scc=
  (*func call error*)
  List.exists (exam_ass_error_proc iprog) scc

(*
  x=y ==> x=y

  if (a) then C_1 else C_2
  a /\ rec(C_1) \/ -a /\ rec(C_2)

*)
let exe_gen_view iprog proc_args pos e0=
  (**)
  let rec recf e counter= match e with
    | I.Assign e_ass -> true
    | I.Binary e_bin -> true
    | I.Cond e_cond -> true
    | I.CallRecv _ -> true
    | I.CallNRecv _ -> true
    | I.Empty _ -> true
    | I.FloatLit _ -> true
    | I.IntLit _ -> true
    | I.Null _ -> true
    | I.Return _ -> true
    | I.Seq _ -> true
    | I.Unary _ -> true
    | I.Var _ -> true
    | I.VarDecl _ -> true
    | I.While _ -> true
    | _ -> true
  in
  IP.mkTrue pos


let gen_view_from_proc iprog iproc=
  (*
    - pred name
    - parameter list = method.para + option res + #e
    - parse body
  *)
  let pred_name = iproc.I.proc_name ^ "_v" in
  let r_args = match iproc.I.proc_return with
    | Void -> []
    | _ -> let r_arg =  res_var in
      [r_arg]
  in
  let e_arg = err_var in
  let proc_args = (List.map (fun para -> para.I.param_name) iproc.I.proc_args) in
  let pred_args = proc_args @ r_args @ [e_arg] in
  let f_body = match iproc.I.proc_body with
    | Some body -> exe_gen_view iprog proc_args iproc.I.proc_loc body
    | None -> IP.mkTrue iproc.I.proc_loc
  in
  true

let gen_view_from_prog iprog iproc=
  false

(* O: safe, 1: unsafe, 2: unknown, 3: not applicaple (all method donot have assert error) *)
let verify_as_sat iprog=
  (* sort method call*)
  let niprog,scc_procs = Iast.Ast_sort.sort_call_graph iprog in
  (* look up assert error location *)
  if List.for_all (exam_ass_error_scc niprog) scc_procs then
    (* transform *)
    (* check sat *)
    NotApp
  else
    NotApp
