(* scanx.ml - template for scanner *)

let f ch = Std.fprintf ch "\
(* This file is generated by ocfgc from %s. *)
(* %sscan.ml - scanner (characters to input tokens) *)

{
(* input token / terminal *)
type t =
  (* builtin tokens *)
%a  | Eof

  (* user-defined tokens *)
%a

let trim (m:int) (n:int) (b:Lexing.lexbuf) : string = 
  Strx.trim m n (Lexing.lexeme b)
}

let white = \"\\009\" | \"\\011\" | \"\\012\" | \"\\032\"
let crlf = \"\\013\" | \"\\010\" | \"\\013\\010\"
let digit = ['0'-'9']
let letter = ['A'-'Z' 'a'-'z' '_' '$']
let alpha = letter | digit
let ident = letter alpha*

(*---- Integral numbers (int). *)

let oct_digit = ['0'-'7']
let oct = '0' oct_digit+
let dec1 = '0'
let dec2 = ['1'-'9'] digit*
let hex_digit = ['0'-'9' 'a'-'f' 'A'-'F']
let hex = '0' ['x' 'X'] hex_digit+
let int = oct | dec1 | dec2 | hex

(*---- Floating-point numbers (float). *)

let float_exp = ['e' 'E'] ['+' '-']? digit+
let float1 = digit+ '.' digit* float_exp? 
let float2 = '.' digit+ float_exp? 
let float3 = digit+ float_exp 
let float4 = digit+ float_exp?
let float = float1 | float2 | float3


rule token = parse
| crlf { Util.line lexbuf; token lexbuf }
| white+ { token lexbuf }
%a\
%s
(* (* Pattern bindings unsupported in F# *)
| (int as x) ['l' 'L'] { Int64 (Int64.of_string x) }
| (float as x) ['f' 'F']? { Float (float_of_string x) }
| (float as x) ['d' 'D']? { Double (float_of_string x) }
| (float4 as x) ['f' 'F'] { Float (float_of_string x) }
| (float4 as x) ['d' 'D'] { Double (float_of_string x) }
| ident as x { Ident x } *)
| int ['l' 'L'] { Int64 (Int64.of_string (trim 0 1 lexbuf)) }
| float ['f' 'F']? { Float (float_of_string (trim 0 1 lexbuf)) }
| float ['d' 'D']? { Double (float_of_string (trim 0 1 lexbuf)) }
| float4 ['f' 'F'] { Float (float_of_string (trim 0 1 lexbuf)) }
| float4 ['d' 'D'] { Double (float_of_string (trim 0 1 lexbuf)) }
| ident { Ident (trim 0 0 lexbuf) }
| \"//\" { comment lexbuf; token lexbuf }
| \"/*\" { comment2 (Util.info lexbuf) lexbuf; token lexbuf }
| '\\'' { char (Util.info lexbuf) (Buffer.create 8) lexbuf }
| '\"' { str (Util.info lexbuf) (Buffer.create 8) lexbuf }
| _ { Std.printf \"%%s: Scan error: unknown token %%s\\n\" 
  (Util.info lexbuf) (trim 0 0 lexbuf); exit 1 }
| eof { Eof }

and comment = parse
| crlf { Util.line lexbuf }
| _ { comment lexbuf }
| eof { }

and comment2 z = parse
| crlf { Util.line lexbuf; comment2 z lexbuf }
| \"*/\" { }
| _ { comment2 z lexbuf }
| eof { print_endline (z ^ \": End-of-file while scanning for comment\");
  exit 1 }

and char z b = parse
| '\\'' { Char (Buffer.contents b) }
| '\\\\' { escape b lexbuf; char z b lexbuf }
| _ { Buffer.add_string b (trim 0 0 lexbuf); char z b lexbuf }
| eof { print_endline (z ^ \": End-of-file while scanning for character\");
  exit 1 }

and str z b = parse
| '\"' { String (Buffer.contents b) }
| '\\\\' { escape b lexbuf; str z b lexbuf }
| _ { Buffer.add_string b (trim 0 0 lexbuf); str z b lexbuf }
| eof { print_endline (z ^ \": End-of-file while scanning for string\");
  exit 1 }

and escape b = parse
| 'b' { Buffer.add_char b '\\b' }
| 'n' { Buffer.add_char b '\\n' }
| 'r' { Buffer.add_char b '\\r' }
| 't' { Buffer.add_char b '\\t' }
| 'u' hex_digit+ { Buffer.add_char b 'u'; Buffer.add_string b (trim 1 0 lexbuf) }
| '\"' { Buffer.add_char b '\\\"' }
| '\\\'' { Buffer.add_char b '\\\'' }
| '\\\\' { Buffer.add_char b '\\\\' }
| int { Buffer.add_char b '\\\\'; Buffer.add_string b (trim 0 0 lexbuf) }
| _ { Std.printf \"%%s: Scan error: unknown escape character %%s\\n\" 
  (Util.info lexbuf) (trim 0 0 lexbuf); exit 1 }
| eof { print_endline \": End-of-file while scanning for escape character\";
  exit 1 }
"
