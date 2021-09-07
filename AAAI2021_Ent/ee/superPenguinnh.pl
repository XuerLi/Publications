:- working_directory(_, '/Users/lixue/GoogleDrive/01PHD/01program/eclipse-workspace/ABC_Clean/src/').
:-[main].


axiom([-penguin(\x),+bird(\x)]).
axiom([-bird(\x),+fly(\x)]).
axiom([-superPenguin(\x),+penguin(\x)]).
%axiom([-superPenguin(\x),+fly(\x)]).
axiom([+superPenguin(opus)]).
axiom([+brokenWing(opus)]).
axiom([-brokenWing(\x),-bird(\x),+cannotFly(\x)]).
axiom([-fly(\x),-cannotFly(\x)]).

trueSet([fly(opus)]).
falseSet([]).
protect([]).
heuristics([]).
theoryFile:- !.
