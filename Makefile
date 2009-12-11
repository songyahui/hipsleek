OCAMLC=ocamlc
OCAMLOPT=ocamlopt.opt
OCAMLDEP=ocamldep
OCAMLDOC=ocamldoc

DIRS=.
INCLUDES=-I ./xml -dtypes
#OCAMLFLAGS=-dtypes $(INCLUDES)    # add other options for ocamlc here
#OCAMLOPTFLAGS=-dtypes $(INCLUDES) # add other options for ocamlopt here
OCAMLFLAGS=$(INCLUDES) # add other options for ocamlc here
OCAMLOPTFLAGS=$(INCLUDES) -p # add other options for ocamlopt here
OCAMLYACC=ocamlyacc
OCAMLYACCFLAGS=-v
OCAMLLEX=ocamllex -q
BIN=../bin
DOC=../doc
DOC_SRC=*/*.ml */*.mli
DEP_DOT_FILE=$(DOC)/depend/dependencies.dot
DEP_PS_FILE=$(DOC)/depend/dependencies.ps
DEP_PDF_FILE=$(DOC)/depend/dependencies.pdf

all: hip hip.opt sleek sleek.opt prover prover.opt

sparser.cmo sparser.ml: sparser.mly
	$(OCAMLYACC) $(OCAMLYACCFLAGS) sparser.mly
	rm sparser.mli
	$(OCAMLC) $(OCAMLFLAGS) -c -g sparser.ml

slexer.cmo slexer.ml: slexer.mll sparser.ml
	$(OCAMLLEX) slexer.mll
	$(OCAMLC) $(OCAMLFLAGS) -c -g slexer.ml

iparser.cmo iparser.ml: iparser.mly
	$(OCAMLYACC) $(OCAMLYACCFLAGS) iparser.mly
	rm iparser.mli
	$(OCAMLC) $(OCAMLFLAGS) -c -g iparser.ml

ilexer.cmo ilexer.ml: ilexer.mll iparser.ml
	$(OCAMLLEX) ilexer.mll
	$(OCAMLC) $(OCAMLFLAGS) -c -g ilexer.ml

ocparser.cmo ocparser.ml: ocparser.mly
	$(OCAMLYACC) $(OCAMLYACCFLAGS) ocparser.mly
	rm ocparser.mli
	$(OCAMLC) $(OCAMLFLAGS) -c -g ocparser.ml

oclexer.cmo oclexer.ml: oclexer.mll ocparser.ml
	$(OCAMLLEX) oclexer.mll
	$(OCAMLC) $(OCAMLFLAGS) -c -g oclexer.ml

MAIN_FILES=globals.cmo error.cmo util.cmo debug.cmo \
	cpure.cmo ipure.cmo \
	iformula.cmo iast.cmo \
	iparser.cmo ilexer.cmo \
	iprinter.cmo \
	cformula.cmo cast.cmo cprinter.cmo \
	ocparser.cmo oclexer.cmo unix_add.cmo isabelle.cmo coq.cmo omega.cmo mona.cmo setmona.cmo \
    net.cmo \
	cvclite.cmo tpdispatcher.cmo \
	prooftracer.cmo context.cmo solver.cmo \
	drawing.cmo \
	env.cmo checks.cmo \
	inliner.cmo \
	typeinference.cmo \
	astsimp.cmo \
	java.cmo cjava.cmo predcomp.cmo rtc.cmo \
	typechecker.cmo \
	globalvars.cmo \
	main.cmo

SLEEK_FILES=globals.cmo error.cmo util.cmo debug.cmo \
	cpure.cmo ipure.cmo \
	iformula.cmo iast.cmo \
	cformula.cmo cast.cmo cprinter.cmo \
	sleekcommons.cmo \
	sparser.cmo slexer.cmo iparser.cmo ilexer.cmo \
	iprinter.cmo \
	ocparser.cmo oclexer.cmo unix_add.cmo isabelle.cmo coq.cmo omega.cmo mona.cmo setmona.cmo \
    net.cmo \
	cvclite.cmo tpdispatcher.cmo \
	prooftracer.cmo context.cmo solver.cmo \
	drawing.cmo \
	env.cmo checks.cmo \
	inliner.cmo \
	typeinference.cmo newxpure.cmo \
	astsimp.cmo \
	java.cmo cjava.cmo predcomp.cmo rtc.cmo \
	typechecker.cmo \
	xmlfront.cmo nativefront.cmo \
	sleekengine.cmo \
	sleek.cmo


MAIN_FILES_2=util.cmo debug.cmo globals.cmo \
	ipure.cmo iformula.cmo iast.cmo \
	iparser.cmo ilexer.cmo \
	iprinter.cmo


PROVE_FILES=globals.cmo error.cmo util.cmo debug.cmo \
	cpure.cmo ipure.cmo \
	iformula.cmo iast.cmo \
	iparser.cmo ilexer.cmo \
	iprinter.cmo \
	cformula.cmo cast.cmo cprinter.cmo \
	ocparser.cmo oclexer.cmo unix_add.cmo isabelle.cmo coq.cmo omega.cmo mona.cmo setmona.cmo \
    net.cmo \
	cvclite.cmo tpdispatcher.cmo \
	prooftracer.cmo context.cmo solver.cmo \
	drawing.cmo \
	env.cmo checks.cmo \
	inliner.cmo \
	typeinference.cmo \
	astsimp.cmo \
	java.cmo cjava.cmo predcomp.cmo rtc.cmo \
	typechecker.cmo \
	prove.cmo

hip1: $(MAIN_FILES_2)
	$(OCAMLC) -g -o $@ $(OCAMLFLAGS) unix.cma str.cma graph.cma $(MAIN_FILES_2)

hipc:
	make clean; make hip

hip: $(MAIN_FILES)
	$(OCAMLC) -g -o $@ $(OCAMLFLAGS) unix.cma str.cma graph.cma $(MAIN_FILES)

hip.opt: $(MAIN_FILES:*.cmo=*.cmx)
	make -f Makefile.opt hip.opt

prover: $(PROVE_FILES)
	$(OCAMLC) -g -o $@ $(OCAMLFLAGS) unix.cma str.cma graph.cma $(PROVE_FILES)

prover.opt: $(PROVE_FILES:*.cmo=*.cmx)
	make -f Makefile.opt prover.opt

sleekc:
	make clean; make sleek 

xml/xml-light.cma:
	make -C xml

xml/xml-light.cmxa:
	make -C xml xml-light.cmxa

sleek: $(SLEEK_FILES) xml/xml-light.cma
	$(OCAMLC) -g -o $@ $(OCAMLFLAGS) unix.cma str.cma graph.cma xml-light.cma $(SLEEK_FILES)

sleek.opt: $(SLEEK_FILES) xml/xml-light.cmxa
	make -f Makefile.opt sleek.opt

CRISTINA_FILES=util.cmo debug.cmo globals.cmo error.cmo \
	cpure.cmo cformula.cmo cast.cmo

cristina: $(CRISTINA_FILES)

TEST_OO_FILES=util.cmo debug.cmo globals.cmo error.cmo \
	cpure.cmo ipure.cmo \
	iformula.cmo iast.cmo \
	checks.cmo \
	iparser.cmo ilexer.cmo \
	iprinter.cmo \
	cformula.cmo cast.cmo cprinter.cmo \
	ocparser.cmo oclexer.cmo unix_add.cmo isabelle.cmo coq.cmo omega.cmo mona.cmo\
	cvclite.cmo tpdispatcher.cmo \
	context.cmo \
	solver.cmo \
	env.cmo astsimp.cmo \
	test-oo.cmo \
#	typechecker.cmo \
#	main.cmo

oo: $(TEST_OO_FILES)
	$(OCAMLC) -g -o $@ $(OCAMLFLAGS) unix.cma str.cma graph.cma $(TEST_OO_FILES)


JAVA_FILES=util.cmo debug.cmo globals.cmo error.cmo \
	cpure.cmo ipure.cmo \
	iformula.cmo iast.cmo iprinter.cmo \
	iparser.cmo ilexer.cmo \
	java.cmo

j: $(JAVA_FILES)
	$(OCAMLC) -g -o $@ $(OCAMLFLAGS) unix.cma str.cma graph.cma $(JAVA_FILES)

# ------------------------------------------------------------
# Common rules
# ------------------------------------------------------------
.SUFFIXES: .ml .mli .cmo .cmi .cmx .mly .mll

.ml.annot:
	$(OCAMLC) $(OCAMLFLAGS) -c -g $<

.ml.cmo:
	$(OCAMLC) $(OCAMLFLAGS) -c -g $<

.mli.cmi:
	$(OCAMLC) $(OCAMLFLAGS) -c -g $<

.ml.cmx:
	$(OCAMLOPT) $(OCAMLOPTFLAGS) -c $<

# Clean up
clean: 
	rm -f slexer.ml ilexer.ml iparser.ml oclexer.ml ocparser.ml *.cmo *.cmi *.cmx *.o *.mli *.output *.annot ss.exe hip.exe hip hip.opt ss ss.opt sleek.opt sleek sleek.exe prover prover.opt *~ oo oo.exe

# Dependencies
beforedepend: iparser.ml ocparser.ml

depend: beforedepend
	(for d in $(DIRS); \
	do $(OCAMLDEP) $(INCLUDES) $$d/*.mli $$d/*.ml; \
	done) > .depend

-include .depend
# DO NOT DELETE
