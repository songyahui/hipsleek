/*
orders.pl: Orders propagation rules

%% DESCRIPTION

%% HOW TO USE
Events are pairs of role x label:
e.g.  event(A,1), event(B2,a)

Happens-before relations are pairs of (event x event):
e.g.  hb(event(A,1), event(B2,a))

Communicates-before relations are pairs of (event x event):
e.g.  cb(event(A,a), event(B2,a))
  

%% SAMPLE QUERIES
% ?- hb(event(X,1),event(Y,2)), hb(event(Y,2),event(Z,3)).
% hb(event(X, 1), event(Z, 3)),
% hb(event(Y, 2), event(Z, 3)),
% hb(event(X, 1), event(Y, 2)).

?- hb(event(X,1),event(Y,2)), hb(event(Y,2),event(Z,3)), hb(event(Z,3),event(T,a)).
hb(event(X, 1), event(T, a)),
hb(event(Y, 2), event(T, a)),
hb(event(X, 1), event(T, a)),
hb(event(Z, 3), event(T, a)),
hb(event(X, 1), event(Z, 3)),
hb(event(Y, 2), event(Z, 3)),
hb(event(X, 1), event(Y, 2)).

?- cb(event(X,2),event(Y,2)), hb(event(Y,2),event(Z,3)), hb(event(Z,3),event(T2,a)).
hb(event(X, 2), event(T2, a)),
hb(event(Y, 2), event(T2, a)),
hb(event(X, 2), event(T2, a)),
hb(event(Z, 3), event(T2, a)),
hb(event(X, 2), event(Z, 3)),
hb(event(Y, 2), event(Z, 3)),
cb(event(X, 2), event(Y, 2)).

?- cb(event(X,7),event(Y,2)), hb(event(Y,2),event(Z,3)), hb(event(Z,3),event(T2,a)).
  false

?- hb(event(X,1),event(Y,2)), hb(event(Y,4),event(Z,3)).

?- hb(event(X,1),event(Y,2)),hb(event(Y,2),event(Z,3)),guard(hb(event(X,1),event(Z,3))).
found.

*/

:- module(orders, [event/2,hb/2,cb/2,guard/1,pair/2,found/0]).
:- use_module(library(chr)).


%% Syntax for SWI / SICStus 4.x
:- chr_constraint event/2,hb/2,cb/2,guard/1,pair/2,found/0.

% hbhb   @ hb(event(A,L1),event(B,L2)), hb(event(B,L3),event(C,L4)) ==> L2=L3, hb(event(A,L1),event(C,L4)).
% cbhb   @ cb(event(A,L1),event(B,L2)), hb(event(B,L3),event(C,L4)) ==> L1=L2,L2=L3, hb(event(A,L1),event(C,L4)).

% and(X,Y) <=> X,Y.

check  @ guard(hb(event(A1,L1),event(B1,E1))), hb(event(A2,L2),event(B2,E2)) <=> A1=A2,B1=B2,L1=L2,E1=E2 |  found.
hbhb   @ hb(event(A,L1),event(B,L2)), hb(event(B,L2),event(C,L4)) ==> hb(event(A,L1),event(C,L4)).
cbhb   @ cb(event(A,L1),event(B,L1)), hb(event(B,L1),event(C,L4)) ==> hb(event(A,L1),event(C,L4)).
fhb    @ hb(event(A,L1),event(B,L2)), found <=> found.
fcb    @ cb(event(A,L1),event(B,L1)), found <=> found.

