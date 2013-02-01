(* jjar.ml - java jar (zip of class files) *)
(* written by Matthew Gruskin <mgruskin@seas.upenn.edu> *)

open Std
module T = Jtyped
module H = Hashx
module Z = Unzip
module R = Regex
module L = Listx


(*** Design choices: avoid loading up all classes, fields, or
methods. Use lazy parsing of bytecode files. *)

(* jar filename for the standard runtime classes: 
   rt.jar (linux) or classes (mac osx) *)

(*Bachle: changed here to link to jvm/jdk*)
(*let jdk = Util.dirname (Util.dirname (Util.locate "java"))*)
let jdk = "/usr/lib/jvm/java-1.6.0-openjdk"
let linux_jar = jdk ^ "/jre/lib/rt.jar"
let osx_jar = jdk ^ "/Classes/classes.jar"

let jar_filename = 
  if Sys.file_exists linux_jar then linux_jar
  else if Sys.file_exists osx_jar then osx_jar
  else error "error: cannot find rt.jar or classes.jar"

(* we make rt.jar global so we only have to load it once *)
let jar = Z.load jar_filename

(* file_string simulates file reads from a string *)
type file_string = string * int ref

let fs_skip_bytes ((_,i):file_string) (count:int) : unit =
  i := !i + count
    
let fs_read_short ((s,i):file_string) : int =
  let high = int_of_char s.[!i] in
  let low = int_of_char s.[!i+1] in
  i := !i + 2;
  (high * 256) + low
      
let fs_read_byte ((s,i):file_string) : int =
  let b = int_of_char s.[!i] in
  i := !i + 1;
  b

let fs_read_int ((s,i):file_string) : int =
  let b1 = int_of_char s.[!i] in
  let b2 = int_of_char s.[!i+1] in
  let b3 = int_of_char s.[!i+2] in
  let b4 = int_of_char s.[!i+3] in
  i := !i + 4;
  (b1 * 256 * 256 * 256) + (b2 * 256 * 256) + (b3 * 256) + b4

let fs_seek ((_,i):file_string) (n:int) : unit =
  i := n

let fs_get_pos ((_,i):file_string) : int =
  !i

(* new constant pool implementation *)
type cpool = int array

let get_cpindex_utf8 (file:file_string) (cpindex:cpool) (cpentry:int) : string =
  let curpos = fs_get_pos file in
  fs_seek file cpindex.(cpentry);
  let b = fs_read_byte file in
  match b with
    1 ->
      let length = fs_read_short file in
      let (s0,i) = file in
      let s = String.sub s0 !i length in
      i := !i + length;
      fs_seek file curpos;
      s
  | _ ->
      fs_seek file curpos;
      "constant pool error: not a utf8"

let get_cpindex_class_utf8 (file:file_string) (cpindex:cpool) (cpentry:int) : string =
  let curpos = fs_get_pos file in
  fs_seek file cpindex.(cpentry);
  let b = fs_read_byte file in
  match b with
    7 ->
      let entry_index = fs_read_short file in
      fs_seek file curpos;
      get_cpindex_utf8 file cpindex entry_index
  | _ ->
      fs_seek file curpos;
      "constant pool error: not a class"

let index_constant_pool (file:file_string) : cpool =
  let cp_len = fs_read_short file in
  let cpindex = Array.make cp_len 0 in
  let rec index_cp_entry (remain:int) : (int array) =
    match remain with 1 -> cpindex | _ ->
      cpindex.(cp_len-remain+1) <- (fs_get_pos file);
      let b = fs_read_byte file in
      match b with
	7 | 8 ->
          fs_skip_bytes file 2;
          index_cp_entry (remain-1)
      | 9 | 10 | 11 | 12 | 3 | 4 ->
          fs_skip_bytes file 4;
          index_cp_entry (remain-1)
      | 5 | 6 ->
          fs_skip_bytes file 8;
          index_cp_entry (remain-2)
      | 1 ->
          let len = fs_read_short file in
          fs_skip_bytes file len;
          index_cp_entry (remain-1)
      | t ->
          print_string "Unknown constant pool type ";
          print_int t;
          print_endline ".";
          index_cp_entry (remain-1)
  in
  index_cp_entry cp_len


(* convert 'java/lang/Object' type to a Jtyped.cname *)
let javatype_to_list (javatype:string) : T.cname =
    let conv s = (s) in 
    let s = List.map conv (R.split (R.regex "[/]") javatype) in
    let (p,_,i) = T.cname_of s in
    let l = List.rev (R.split (R.regex "[$]") i) in
    (p,List.tl l,List.hd l)

(* convert 'java.lang.Object' type to a Jtyped.name *)  
let javadots_to_list (javadots:string) : T.cname = 
    javatype_to_list (R.replace (R.regex "[.]") "/" javadots)

(* convert 'java/lang/Object' to 'java.lang.Object' *)
let javatype_to_javadots (javatype:string) : string =
    (R.replace (R.regex "[/]") "." javatype)

let list_to_javadots (c:T.cname) : string = T.cname_show c


(* method and field type descriptor parser *)

let rec parse_wildtype_descriptor (d:string) : T.wty list =    
    match (String.length d) with 0 -> [] | _ ->
    match d.[0] with
        '*' ->
            [T.WildCard] @ (parse_wildtype_descriptor (Strx.skip 1 d))
      | '+' ->
            (* see if it's another wildcard type *)
            begin
            let m = R.rmatch (R.regex "+\\([^;]*<.*>;\\)\\(.*\\)") d in
            match R.success m with
                true ->
                    let next_tys = (R.group m 2) in
                    let inside_ty = parse_type_descriptor (R.group m 1) in
                    [T.WildExtends(inside_ty)] @ (parse_wildtype_descriptor next_tys)
                | false ->
                    let m2 = R.rmatch (R.regex "+\\([^;]*;\\)\\(.*\\)") d in
                    let next_tys = (R.group m2 2) in
                    let inside_ty = parse_type_descriptor (R.group m2 1) in
                    [T.WildExtends(inside_ty)] @ (parse_wildtype_descriptor next_tys)
            end        
      | '-' ->
            (* see if it's another wildcard type *)
            begin
            let m = R.rmatch (R.regex "-\\([^;]*<.*>;\\)\\(.*\\)") d in
            match R.success m with
                true ->
                    let next_tys = (R.group m 2) in
                    let inside_ty = parse_type_descriptor (R.group m 1) in
                    [T.WildSuper(inside_ty)] @ (parse_wildtype_descriptor next_tys)
                | false ->
                    let m2 = R.rmatch (R.regex "-\\([^;]*;\\)\\(.*\\)") d in
                    let next_tys = (R.group m2 2) in
                    let inside_ty = parse_type_descriptor (R.group m2 1) in
                    [T.WildSuper(inside_ty)] @ (parse_wildtype_descriptor next_tys)
            end 
      | _ ->
            (* see if it's another wildcard type *)
            begin
            let m = R.rmatch (R.regex "\\([^;]*<.*>;\\)\\(.*\\)") d in
            match R.success m with
                true ->
                    let next_tys = (R.group m 2) in
                    let inside_ty = parse_type_descriptor (R.group m 1) in
                    [T.WildType(inside_ty)] @ (parse_wildtype_descriptor next_tys)
                | false ->
                    let m2 = R.rmatch (R.regex "\\([^;]*;\\)\\(.*\\)") d in
                    let next_tys = (R.group m2 2) in
                    let inside_ty = parse_type_descriptor (R.group m2 1) in
                    [T.WildType(inside_ty)] @ (parse_wildtype_descriptor next_tys)
            end

and parse_type_descriptor (d:string) : T.ty = 
    (* determine if it should be a ty or a wty *)
    let m = R.rmatch (R.regex "\\(L[^<]*\\)<\\(.*\\)>\\(.*\\)") d in
    match R.success m with
        true ->
            let inside_ty = (R.group m 1) ^ (R.group m 3) in
            T.Tinst(  
                    (parse_type_descriptor inside_ty),
                    (parse_wildtype_descriptor (R.group m 2))
                  )
        | false ->
            match d.[0] with
              | 'B' -> T.Tbyte
              | 'C' -> T.Tchar
              | 'D' -> T.Tdouble
              | 'F' -> T.Tfloat
              | 'I' -> T.Tint
              | 'J' -> T.Tlong
              | 'S' -> T.Tshort
              | 'Z' -> T.Tbool
              | 'V' -> T.Tvoid
              | 'L' ->
                    let m2 = R.rmatch (R.regex "L\\([^;]*\\);") d in
                    T.Tcname((javatype_to_list (R.group m2 1)))
              | '[' ->
                    let m2 = R.rmatch (R.regex "\\([[]+\\)\\(.*\\)") d in
                    T.Tarray( parse_type_descriptor(R.group m2 2), (String.length (R.group m2 1)))
              | 'T' ->
                    let m2 = R.rmatch (R.regex "T\\([^;]*\\);") d in
                    T.Tcname(T.cname_of [R.group m2 1])
              | _ -> 
                    print_string "Failed to identify descriptor: ";
                    print_endline d;
                    Std.assert_false ()

let rec get_next_param (p:T.ty) (d:string) : string =
    match p with
      T.Tcname _ ->
        let m = R.rmatch (R.regex "[^;]*;\\(.*\\)") d in
        assert (R.success m); R.group m 1
    | T.Tarray(inner_p,_) ->
        let m = R.rmatch (R.regex "[[]+\\(.*\\)") d in
        assert (R.success m); get_next_param inner_p (R.group m 1)
    | T.Tinst(_,_) ->
        let m = R.rmatch (R.regex "[^<]*<.*>;\\(.*\\)") d in
        assert (R.success m); R.group m 1
    | _ ->
        (Strx.skip 1 d)        

let rec parse_method_params (d:string) : T.ty list =
    match (String.length d) with 0 -> [] | _ ->
    let p = (parse_type_descriptor d) in
    [p] @ parse_method_params (get_next_param p d)

let rec parse_method_descriptor (d:string) : (T.ty list * T.ty) =
    (* check for type parameters *)
    let m = R.rmatch (R.regex "<[^(]*>\\(.*\\)") d in
    match R.success m with
      true ->
        (* ignore type parameters for now *)
        parse_method_descriptor (R.group m 1)
    | false ->
    let m2 = R.rmatch (R.regex "(\\(.*\\))\\(.*\\)") d in
    let ps = (R.group m2 1) in
    let ret = (R.group m2 2) in
    (parse_method_params ps, parse_type_descriptor ret)

(* get an fty given a signature or constant pool index *)
let lookup_fdescriptor (index:int) (signat:string) (file:file_string) (pool:cpool) : T.ty =
    match signat with
    "" ->
        let descriptor = (get_cpindex_utf8 file pool index) in
        parse_type_descriptor descriptor
    | _ ->
        parse_type_descriptor signat
        
let lookup_mdescriptor (index:int) (signat:string) (file:file_string) (pool:cpool) : (T.ty list * T.ty) =
    match signat with
    "" ->
        let descriptor = (get_cpindex_utf8 file pool index) in
        parse_method_descriptor descriptor
    | _ ->
        parse_method_descriptor signat

(* this is used when we don't care about any attributes *)
let rec skip_attributes (file:file_string) (count:int) : unit =
    match count with
    n when n > 0 ->
    fs_skip_bytes file 2;
    let attribute_length = (fs_read_int file) in
	    fs_skip_bytes file attribute_length;
  	  skip_attributes file (count-1)
    | _ -> ()

(* pulls out only the signature attribute, thats the only one we care about *)
let rec get_signat_attribute (file:file_string) (count:int) (pool:cpool) : string =
    match count with
    n when n > 0 ->
        let attribute_name_index = (fs_read_short file) in
        let attribute_length = (fs_read_int file) in
	let attribute_name = (get_cpindex_utf8 file pool attribute_name_index) in 
	begin
	match (attribute_name) with
	  "Signature" ->
	    let signat_index = (fs_read_short file) in
	    let signat = (get_cpindex_utf8 file pool signat_index) in
	    ignore(get_signat_attribute file (count-1) pool);
	    signat
	| _ ->
	    fs_skip_bytes file attribute_length;
	    get_signat_attribute file (count-1) pool
	end;
    | _ -> ""
    
exception Invalid_class_file
let read_header (file:file_string) : unit =
  (* check magic number *)
  match (fs_read_byte file, fs_read_byte file, fs_read_byte file, fs_read_byte file) with
    (ca,fe,ba,be) when (ca <> 202) || (fe <> 254) || (ba <> 186) || (be <> 190) ->
      raise Invalid_class_file
  | _ ->
    (* skip file version *)
    fs_skip_bytes file 4    

let find_class_in_jar (classname:T.cname) : file_string =
    let jarfn = (R.replace (R.regex "[.]") "/" (T.cname_show classname)) ^ ".class" in
    let e = Z.find jar jarfn in    
    let s = Z.read jar e in
    (s, ref 0)

let find_class_in_filesystem (c:T.cname) : file_string =
  let fn = (T.cname_show c) ^ ".class" in
  try
    let in_c = open_in_bin fn in
    let s = Compat.channel_to_string in_c in
    close_in in_c;
    (s, ref 0)
  with _ -> raise Not_found

let find_class (c:T.cname) : file_string = 
  try
    find_class_in_filesystem c
  with Not_found ->
    find_class_in_jar c

(*---- new interfaces *)

(* TODO: put all caches (hash tables) here *)
type t = int

(* Load a jar file. (TODO) and setup caches here *)
let load (x:string) : t = 0

(*--- cname_of: convert dot delimited names a.b.c.d.e to fully
qualified names with package and enclosing classes T.cname a.b.c$d.e.

From n1=[a;b;c] n2=[d;e] to ([a;b;c], [d]; e) 

Helper for 'cname_of': determining if the split of name n into n1
(pakcage) and n2 (enclosing classes and the class name) is a valid
filename entry in the jar.

*)
let rec cname_of2 (g:t) (n1:Jplain.name) (n2:Jplain.name): T.cname =
  try 
    let s = (String.concat "/" n1) ^ "/" ^ (String.concat "$" n2) in
    ignore (Z.find jar (s ^ ".class"));
    let (t,h) = L.tail_head n2 in       (* found it *)
    (n1, t, h)
  with Not_found -> 
    (match n1 with
    | [] -> raise Not_found
    | _ ->
      let (t,h) = L.tail_head n1 in
      cname_of2 g t (h :: n2))

let rec cname_of (g:t) (n:Jplain.name) : T.cname =
  assert (L.size n > 0); 
  let (t,h) = L.tail_head n in
  cname_of2 g t [h]


(* Alternative: during startup, load all filenames rewritten with '.' 
mapping the the real filename. Drawback: slow startup and most file
entries are not queried.

(* Load a jar file. (TODO) and setup caches here *)
let load (x:string) : t = 
  let h = H.create 30000 in             (* JDK 1.5 has 15186 classes *)
  let f e = 
    let x = Z.filename e in
    if Strx.is_suffix ".class" x then
    let s = Strx.subst x '$' '/' in  (* a/b/c$d$e.class -> a.b.c.d.e *)
    let c = javatype_to_list (Strx.cut_last 5 x) in
    H.add h s c in
  Util.timers_push (); L.iter f (Z.entries jar); 
printf_flush "%.01fs\n" (Util.timers_pop ());
h

(* From 'a/b/c/d' to ([a;b], [c]; d) *)
let cname_of (g:t) (n:Jplain.name) : T.cname = 
  H.get g (String.concat "/" n ^ ".class")
*)


(* All class names (including inner classes)
   of the package within the enclosing classes.*)

let cnames_filenames (jar:Z.zip) : string list =
  let get_fn (e:Z.entry) : string = Z.name e
  in List.map get_fn (Z.all jar)

let rec cnames_check_entries 
    (ipackage:T.package) 
    (ienclosing:T.id list) 
    (fs:string list)
    (ret:T.cname list)
    : T.cname list =
  match fs with [] -> ret | _ ->
  let f = (List.hd fs) in
  let whole_list = R.split (R.regex "[/]") f in
    match List.rev whole_list with
	classfn :: package when Listx.is_prefix ipackage (List.rev package) ->
          let package = List.rev package in
        
            begin
            let m = R.rmatch (R.regex "\\(.*\\).class") classfn in
            match R.success m with
		  true ->
		    let classid = R.group m 1 in
            
		    let inner_list = R.split (R.regex "[$]") classid in
            
		      begin
			match List.rev inner_list with
			    inner :: enclosing when Listx.is_prefix ienclosing (List.rev enclosing) ->
			      cnames_check_entries ipackage ienclosing (List.tl fs) ((package,List.rev enclosing,inner) :: ret)
			  | _ -> cnames_check_entries ipackage ienclosing (List.tl fs) ret
		      end
            
		| false -> cnames_check_entries ipackage ienclosing (List.tl fs) ret
            end       
        
      | _ -> cnames_check_entries ipackage ienclosing (List.tl fs) ret

let ht_cnames = (H.create 5)

(* return [] for default package [] *)
let cnames (g:t) (p:T.package) (cs:T.id list) : T.cname list =
  if p=[] then [] else
  (* printf "cnames looking for %s\n%!" (T.T.cname_show (p,cs,"")) *)
  match H.find ht_cnames (p,cs) with
      Some cname_list -> cname_list
    | None ->
	let cname_list = cnames_check_entries p cs (cnames_filenames jar) [] in
	  H.add ht_cnames (p,cs) cname_list;
	  cname_list

(* the constant pool caching is disabled for now, i need to figure out whether it saves a significant amount of time or not *)
(*
let pools = (H.create 5)
type hashpool = int * cpool

let cache_get_pool (file:file_string) (c:T.cname) : cpool =
  match H.find pools c with
    Some (l,pool) -> 
      begin
	match file with
	  (_,i) -> i := !i + l
      end;
      pool
  | None ->
      match file with (_,i) ->
      let i1 = !i in
      let pool = read_constant_pool file in
      match file with (_,i) ->
      let i2 = !i in
      let l = (i2 - i1) in
      H.add pools c (l,pool);
      pool
*)

let rec skip_cp_entry (file:file_string) (remain:int) : unit =
  match remain with 1 -> () | _ ->
  let b = fs_read_byte file in
    match b with
      7 | 8 ->
        fs_skip_bytes file 2;
        skip_cp_entry file (remain-1)
    | 9 | 10 | 11 | 12 | 3 | 4 ->
        fs_skip_bytes file 4;
        skip_cp_entry file (remain-1)
    | 5 | 6 ->
        fs_skip_bytes file 8;
        skip_cp_entry file (remain-2)
    | 1 ->
        let len = fs_read_short file in
          fs_skip_bytes file len;
        skip_cp_entry file (remain-1)
    | t ->
        print_string "Unknown constant pool type ";
        print_int t;
        print_endline ".";
        skip_cp_entry file (remain-1)

let skip_constant_pool (file:file_string) : unit =
  let cp_len = fs_read_short file in
    skip_cp_entry file cp_len

let lookup_cname (file:file_string) (index:int) (pool:int array) : T.cname =
  let txtname = get_cpindex_class_utf8 file pool index in
  T.cname_of (Strx.read '/' txtname)
    
let read_cname (file:file_string) (pool:int array) : T.cname = 
  let index = fs_read_short file in
    lookup_cname file index pool       

let rec read_ifaces (file:file_string) (pool:int array) (count:int) =
  match count with 0 -> [] | _ ->
  [read_cname file pool] @ read_ifaces file pool (count-1)

(* Interface classes of a class. *)
let rec ifaces (g:t) (c:T.cname) : T.cname list =
  (*
  print_string "Loading: ";
  print_endline (T.cname_show c);
  *)
  match c with (["java";"lang"],[],"Object") -> [] | _ ->
  try 
  let file = find_class c in
      read_header file;
      let pool = index_constant_pool file in
        (* skip access flags *)
        fs_skip_bytes file 2;
        (* skip this class *)
        fs_skip_bytes file 2;
        (* get super class - we need it to recursively load parent's interfaces *)
        let super_cname = read_cname file pool in
        (* interfaces count *)
        let iface_count = fs_read_short file in
          let ifaces_list = read_ifaces file pool iface_count in
            let ifaces_list =
            (* my interfaces *) ifaces_list @ 
            (* super-interfaces of my interfaces *) List.concat (List.map (ifaces g) ifaces_list) in
            
            (* sometimes interfaces will have superinterfaces that are implemented by superclasses *)
            (* so we need to remove duplicates *)
            let del_dupe ifaces_list iface =
              match List.mem iface ifaces_list with
                true -> ifaces_list
              | false -> ifaces_list @ [iface]
              in
            
            (* interfaces of my super class *)
            List.fold_left del_dupe ifaces_list (ifaces g super_cname)
  with Not_found -> []

let rec find_field (file:file_string) (remain:int) (x:T.id) (c:T.cname)
  (pool:cpool) : T.fty =
  match remain with 0 -> raise Not_found | _ ->
    let access_flags = (fs_read_short file) in
    let mods = if (access_flags land 0x0008) > 0 then [T.Static] else [] in
    let name_index = (fs_read_short file) in
    let descriptor_index = (fs_read_short file) in
    let attributes_count = (fs_read_short file) in
    let signat_attribute = (get_signat_attribute file attributes_count pool) in

    (* check name *)
    let field_name = (get_cpindex_utf8 file pool name_index) in
    match field_name with
      s when s=x ->  
        let fieldty = (lookup_fdescriptor descriptor_index signat_attribute file pool) in
        (mods,fieldty,c,x)
    | _ ->
        find_field file (remain-1) x c pool  

(* Field type of a field of a class, raise Not_found. *)
let rec field (g:t) (c:T.cname) (x:T.id) : T.fty =
  match c with (["java";"lang"],[],"Object") -> raise Not_found | _ ->
  let file = find_class c in
    read_header file;
      let pool = index_constant_pool file in
        (* skip access flags *)
        fs_skip_bytes file 2;
        (* skip this class *)
        fs_skip_bytes file 2;
        (* get super class *)
        let super_cname = read_cname file pool in
        (* skip interfaces *)
        let iface_count = fs_read_short file in
        fs_skip_bytes file (iface_count * 2);
        (* read field count *)
        let field_count = fs_read_short file in
        try find_field file field_count x c pool with
	  Not_found ->
	    let rename_class ((m,f,mc,x):T.fty) : T.fty =
	      (m,f,c,x) in
	    rename_class (field g super_cname x)
        
let rec skip_fields (file:file_string) (remain:int) : unit =
  match remain with 0 -> () | _ ->
  fs_skip_bytes file 6;
  let attrib_count = fs_read_short file in
  skip_attributes file attrib_count;
  skip_fields file (remain-1)

let rec find_methods (file:file_string) (remain:int) (x:T.id) (c:T.cname)
  (pool:cpool) : T.mty list =
  match remain with 0 -> [] | _ ->
    let access_flags = (fs_read_short file) in
    let mods = if (access_flags land 0x0008) > 0 then [T.Static] else [] in
    let (* abstract_flag *) _ = if (access_flags land 0x0400) > 0 then true else false in
    let name_index = (fs_read_short file) in
    let descriptor_index = (fs_read_short file) in
    let attributes_count = (fs_read_short file) in
    let signat_attribute = (get_signat_attribute file attributes_count pool) in

    (* check name *)
    let method_name = (get_cpindex_utf8 file pool name_index) in
    match method_name with
      s when s=x -> begin
        let methodkind =
          match method_name with
              "<init>" -> T.Ispecial
            | "<clinit>" -> T.Ispecial
            | _ ->
            
            (* if abstract_flag then Ivirtual else *)
            if (access_flags land 0x0008 > 0) then T.Istatic else
            T.Ivirtual in
            
        match (lookup_mdescriptor descriptor_index signat_attribute file pool) with
        (ps, ret) ->
          [(
            mods,
            methodkind,
            ret,
            c,
            method_name,
            ps
          )] @ find_methods file (remain-1) x c pool
    end  
    | _ ->
        find_methods file (remain-1) x c pool

(* Method types of a method of a class. *)
let rec methods (g:t) (c:T.cname) (x:T.id) : T.mty list =
  try 
  let file = find_class c in
    read_header file;
      let pool = index_constant_pool file in
        (* skip access flags *)
        fs_skip_bytes file 2;
        (* skip this class *)
        fs_skip_bytes file 2;
        (* get super class *)
        let super_cname = read_cname file pool in
        (* skip interfaces *)
        let iface_count = fs_read_short file in
        fs_skip_bytes file (iface_count * 2);
        (* skip fields *)
        let field_count = fs_read_short file in
        skip_fields file field_count;
        let method_count = fs_read_short file in
        let method_list = find_methods file method_count x c pool in
	let rename_class ((m,i,t,mc,id,tys):T.mty) : T.mty =
	  (m,i,t,c,id,tys) in
	let enclose_methods = 
    match c with
    | (_,[],_) -> []
    | (p,xs,x0) -> 
      let (t,h) = Listx.tail_head xs in 
      List.map rename_class (methods g (p,t,h) x) in
	let super_methods = List.map rename_class (methods g super_cname x) in
	let methods_for_iter (mc:T.cname) : T.mty list = methods g mc x in
	let iface_methods = List.map rename_class (List.concat (List.map methods_for_iter (ifaces g c))) in
  (* FIXME: what order? shadowing rules in JVM? *)
	method_list @ enclose_methods @ iface_methods @ super_methods 
  with Not_found -> []

(* Super class of a class. *)
let super (g:t) (c:T.cname) : T.cname =
  let file = find_class c in
    read_header file;
    let pool = index_constant_pool file in
      (* skip access flags *)
      fs_skip_bytes file 2;
      (* skip this class *)
      fs_skip_bytes file 2;
      (* get the super class *)
      let super_cname = read_cname file pool in
        super_cname                   

(* Modifiers of a class. *)
let mods (g:t) (c:T.cname) : T.modifiers = 
  let file = find_class c in
      read_header file;
      let _ = (skip_constant_pool file) in
        let access_flags = fs_read_short file in
          let mod_list = (ref [] : T.modifiers ref) in
          if (access_flags land 0x0001 > 0) then mod_list.contents <- !mod_list @ [T.Public];
          if (access_flags land 0x0010 > 0) then mod_list.contents <- !mod_list @ [T.Final];
          if (access_flags land 0x0400 > 0) then mod_list.contents <- !mod_list @ [T.Abstract];
          
          !mod_list

(* Kind of a class. *)
let kind (g:t) (c:T.cname) : T.ckind = 
  let file = find_class c in
    read_header file;
    let _ = (skip_constant_pool file) in
    let access_flags = fs_read_short file in
      
      if (access_flags land 0x0200 > 0)
      then T.Ciface
      else T.Cclass


(* testers *)

(*
let _ =
    List.iter print_endline (*ignore*) (List.map T.cname_show (cnames 0 ["java";"io";"ObjectInputStream"] []))
*)

(*
let _ =
  match (is_cname 0 ["java";"io";"BufferedaReader"]) with
    c when c = true -> print_endline "class exists"
  | _ -> print_endline "class does not exist"    
*)

(*
let _ =
  print_endline (T.cname_show (super 0 (["java";"lang"],[],"String")))
*)

(*
let _ =
    List.iter print_endline (List.map T.cname_show (ifaces 0 (["javax";"swing"],[],"JApplet")))
*)

(*
let _ =
    print_endline (modifiers_show (mods 0 (["javax";"swing"],[],"JApplet")))
*)

(*
let _ =
    print_endline (ckind_show (kind 0 (["javax";"swing"],[],"Scrollable")))
*)

(*
let _ =
    print_endline (fty_show (field 0 ([],["TestEnum"],"TestConstant") "ONE"))
*)

(*
let _ =
    List.iter print_endline (List.map mty_show (methods 0 (["java";"io"],["ObjectInputStream"],"GetField") "get"))
*)
