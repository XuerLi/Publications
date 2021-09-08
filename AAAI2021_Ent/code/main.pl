/*
Date: 07 Jan 2019
Macintosh HD⁩/⁨Users⁩/lixue⁩/GoogleDrive⁩/01PHD⁩/01program⁩/eclipse-workspace⁩/ABC_Clean⁩/src⁩
*/

:- use_module(library(lists)).
:-[preprocess, concepChange, equalities, repairPlanGen, repairApply, entrenchment].
    % clear all assertions. So main has to be compiling before the input theory file.
:-    maplist(retractall, [trueSet(_), falseSet(_), heuristics(_), protect(_), spec(_)]).

/********************************************************************************************************************** Global Variable and their values.
debugMode:    0 -- no write_term information.
            1 -- write_term informaiton.
spec(pft(:        the true set of the preferred structure in the internal format.
spec(pff:        the false set of the preferrd structure in the internal format.
costLimit:    the maximum length of the repair plans.
Signature:  [predicateInfoList, ConstantLists], where
            predicateInfoList = [(predsymbol, Arity Info, Arguments Domain), ...]
            Arity Info:  [(arity1, source1), (arity2, source2)], e.g., mum, [(3, theory), (2, prefStruc)].
            Arguments Domain: [[c11,c12..], [c21, c22,..]...], where [c11,c12..] is a list of constants occur as the first argument of that predicate in all theorems of P.
proofStatus:  0 -- default value.
            1 -- will get an axiom for resolving the goal, but there is no more axiom in the input theory.
            2 -- a positive literal is derived.
**********************************************************************************************************************/

:-dynamic pause/0.
:-spy(pause).
pause().

abc:-
    % Initialisation
    supplyInput,
    % Initialision: the theory, the preferred structure, the signature, the protected items and Equality Class and Inequality Set.
    initTheory(Theory),    % clear previous data and initialise new ones.
    precheckPS,
    theoryFileName(TheoryFile),
    % setup log
    (exists_directory('log') -> true; make_directory('log')),
    
    fileName('record', TheoryFile, Fname),
    open(Fname, write, StreamRec),
    
    fileName('repNum', TheoryFile, Fname2),
    open(Fname2, write, StreamRepNum),
    assert(spec(repNum(StreamRepNum))),
    
    (exists_file('repTimeHeu.txt')->
     open('repTimeHeu.txt', append, StreamRepTimeH);
    \+exists_file('repTimeHeu.txt')->
    open('repTimeHeu.txt', write, StreamRepTimeH)),
    assert(spec(repTimeH(StreamRepTimeH))),

    (exists_file('repTimenNoH.txt')->
     open('repTimenNoH.txt', append, StreamRepTimeNH);
    \+exists_file('repTimenNoH.txt')->
    open('repTimenNoH.txt', write, StreamRepTimeNH)),
    assert(spec(repTimeNH(StreamRepTimeNH))),
        
    % record is written only when the debugMode is 1.
    maplist(assert, [spec(debugMode(1)), spec(logStream(StreamRec))]),
    
    %(OverloadedPred \= [] -> concepChange(OverloadedPred,  AllSents, RepSents, CCRepairs, Signature, RSignature);        %Detect if there is conceptual changes: a predicate has multiple arities.
    %RepSents = AllSents, CCRepairs = []),
    
    %statistics(walltime, [_ | [ExecutionTime1]]),
    statistics(walltime, [S,_]),%statistics(walltime, Result) sets Result as a list, with the head being the total time since the Prolog instance was started, and the tail being a single-element list representing the time since the last
    
    % writeLog([nl,write_term('--------------executation time 1---'), nl,write_term('time takes'),nl, write_term(ExecutionTime1),nl]),
    % repair process
    detRep(Theory, AllRepStates),
    writeLog([nl,write_term('--------------AllRepStates: '),write_termAll(AllRepStates),nl, finishLog]),

    % Sort and remove duplicate repairs.
    %quicksort(AllRepTheos, RepairsSorted),
    %eliminateDuplicates(RepairsSorted, SetOfRepairs),
    % output
    
    statistics(walltime, [E,_]),
    ExecutionTime is E-S,
    print('11111111111111111111111'),nl,
    writeLog([nl,write_term('--------------executation time 2---'),
                nl,write_term('time takes'),nl, write_term(ExecutionTime),nl]),
    %ExecutionTime is ExecutionTime1 + ExecutionTime2,
    output(AllRepStates, ExecutionTime),
    close(StreamRec),
    close(StreamRepNum),
    close(StreamRepTimeNH),
    close(StreamRepTimeH),
    nl,write_term('-------------- Finish. --------------'),nl.

/**********************************************************************************************************************
    detRep(Theory, RepTheories):
            detect faults of the objective theory based on preferred structure and UNAE and repair it.
    Input:  Theory: the object theory.
    Output: AllRepSolutions is a list of [(Repairs, TheoryRepaired),....],
            where Repairs is the list of repairs applied to Theory resulting TheoryRepaired.
************************************************************************************************************************/
detRep(Theory, AllRepSolutions):-
    findall(TheoryRep,
            (% calculate equivalence classes, and then detect and repair the unae faults.
            unaeMain(Theory,  OptimalUnae),
            member((TheoryState, InsufIncomp), OptimalUnae),
            
            InsufIncomp = (_,INSUFF,ICOM),
            length(INSUFF,InsuffNum),
            length(ICOM,IncompNum),
            assert(spec(faultsNum(InsuffNum, IncompNum))),
            
             (InsufIncomp = (_,[],[])->
                     TheoryRep = ([fault-free, 0, TheoryState]);    % if the theory is fault free.
             % Otherwise, repair all the faults and terminate with a fault-free theory or failure due to out of the costlimit.
              InsufIncomp \= (_,[],[])->
                      repInsInc(TheoryState, 0, InsufIncomp, TheoryRep))),
            AllRepTheos1), 
    % Only select the minimal repairs w.r.t. the number of repair plans.
    findall((Len, Rep), 
                (member(Rep, AllRepTheos1),
                 Rep = [_,_ ,[[RepPlans,_]|_]],
                 length(RepPlans, Len)),
            AllRepTheos2),
    sort(AllRepTheos2, [(MiniCost, _)|_]),
    setof(RepState, member((MiniCost, RepState), AllRepTheos2), AllRepSolutions).

/**********************************************************************************************************************
    detInsInc(TheoryState, FaultState)
            detect sufficiencies and faults of insufficiencies, incompatibilities of the objective theory based on preferred structure.
    Input:  TheoryState = [[Repairs, BanRs], EC, EProof, TheoryIn, TrueSetE, TrueSetE], where:
            Theory is the current theory.
            Repairs is the repairs that have been applied to get the current theory.
            BanRs is the repairs that have been banned to apply, e.g., the ones failed in applying or violates some constrains.
            TrueSetE/FalseE: the true/false set of the preferred structure where all constants have been replaced by their representatives.
    Output: FaultState = (Suffs, InSuffs, InComps), where
                        Suffs: the provable goals from pf(T).
                        InSuffs: the unprovable goals from pf(T).
                        InComps: the provable goals from pf(F).
************************************************************************************************************************/
detInsInc(TheoryState, FaultState):- 
    TheoryState = [_, EC, _, Theory, TrueSetE, FalseSetE],
    writeLog([nl, write_term('---------Start detInsInc, Input theory is:------'), nl,
    nl,write_term(Theory),nl,write_termAll(Theory),nl,finishLog]),
    % Find all proofs or failed proofs of each preferred proposition.
    findall( [Suff, InSuff],
            ( % Each preferred sentence is negated, and then added into Theory.
              member([+[Pre| Args]], TrueSetE),
              % skip equalities/inequalities which have been tackled.
              notin(Pre, [\=, =]),
              Goal = [-[Pre| Args]],

              % Get all proofs and failed proofs of the goal.
              findall( [Proof, Evidence],
                     ( slRL(Goal, Theory, EC, Proof, Evidence, [])),
                     Proofs1),    
              % Proofs1= [[P1, []],[P2, []],[[],E1]...]; Proofs2 = [[P1,P2,[]],[[],[],E]]
              transposeF(Proofs1, [Proofs, Evis]),
              % only collect none empty proofs/evidences
              (Proofs = []-> Suff = [], InSuff =(Goal, Evis);
               Proofs = [_|_]->Suff =(Goal, Proofs), InSuff=[])),
           AllP),
     % Split into a list of sufficiencies (Suffs), and a list of insufficiencies (InSuffs).
     transposeF(AllP, [Suffs, InSuffs]),

     writeLog([nl, write_term('---------SufGoals is------'), nl,write_term(Suffs),
     nl, write_term('---------InsufGoals is------'), nl,write_term(InSuffs), finishLog]),

    % detect the incompatibilities represented as a list of (Goal, Proofs), where -Goal is from F(PS).
      findall((Goal, UnwProofs),
           (member([+[Pre| Args]], FalseSetE),
            % skip equalities/inequalities which have been tackled.
            notin(Pre, [\=, =]),
            Goal = [-[Pre| Args]],
            % Get all proofs of the goal.
            findall(UnwProof,
                    (slRL(Goal, Theory, EC, UnwProof, [], []), UnwProof \= []),  
                    UnwProofs),
            UnwProofs \= []), % Detected incompatibility based on refutation.
           InComps),             % Find all incompatibilities.

    writeLog([nl, write_term('---------InComps are------'),nl, write_termAll(InComps), finishLog]),
    % detect the inconsistencies due to the violation of constrains
    findall((Constrain, UnwProofs),
              (member(Constrain, Theory),        % get a constrain axiom from the theory.
               notin(+_, Constrain),
               % Get all proofs of the goal.
               findall(UnwProof,
                       (slRL(Constrain, Theory, EC, UnwProof, [], []), UnwProof \= []),
                       UnwProofs),
            UnwProofs \= []), 
          Violations),
      writeLog([nl, write_term('---------Violations are------'),nl, write_termAll(Violations), finishLog]),
    append(InComps, Violations, Unwanted),
    FaultState = (Suffs, InSuffs, Unwanted).
/**********************************************************************************************************************
    repInsInc(TheoryState, Layer, FaultState, TheoryRep):
            return a repaired theory w.r.t. one fault among the FaultStates by applying an Parento optimal repair.
    Input:  TheoryState = [[Repairs, BanRs], EC, EProof, TheoryRep, TrueSetNew, FalseSetNew],
                            for more information, please see unaeMain.
            FaultState = (Suffs, InSuffs, InComps), for more information, please see detInsInc.
            Layer: the layer of repInsInc.
    Output: TheoryRep=[faulty/fault-free, Repairs, TheoryOut]
            Repairs: the repairs which have been applied to achieving a fault-free theory.
            TheoryOut: the fault-free theory which is formalised by applying Repairs to the input theory.
************************************************************************************************************************/
% If there is no faults in the theory, terminate with the fault-free theory.
repInsInc(TheoryState, Layer, (_, [], []), [fault-free, (Layer/N),  TheoryState]):-
    writeLog([nl,write_term('******** A solution is reached. *******'),nl]), !,
    TheoryState = [[RepPlans,_]|_],
    length(RepPlans, Len),
    spec(repNum(StreamRepNum)),
    write(StreamRepNum, Len),
    write(StreamRepNum, ', '), write(StreamRepNum, TheoryState),nl(StreamRepNum),nl(StreamRepNum),
    spec(roundNum(N)).%TheoryState = [[Repairs,_], _, _, TheoryRep, _, _], !.

% If the cost limit is reached, terminate with failure.
repInsInc(TheoryState, Layer, (_, Insuf, Incomp), [fault, (Layer/N), TheoryState]):-
    TheoryState = [[Repairs,_], _, _, _, _, _],
    costRepairs(Repairs, Cost),
    spec(costLimit(CostLimit)),
    spec(roundLimit(RoundLimit)),
    spec(roundNum(N)),
    retractall(spec(roundNum(_))),
    NewN is N+1,
    assert(spec(roundNum(NewN))),
    (Cost >= CostLimit; RoundLimit \= 0, N >= RoundLimit), !,
    write_term('******** Cost Limit is reached. *******'),nl,
    writeLog([nl, write_term('******** Cost Limit is reached. *******'),nl,
        write_term('Cost is: '), write_term(Cost), write_term('; Round: '), write_term(N),
        write_term('---------The current faulty TheoryState is------'), nl,write_termAll(TheoryState),
    nl, write_term('---------The remaining inffuficiencies are------'), nl,write_termAll(Insuf),
    nl, write_term('---------The remaining incompatibilities are------'), nl,write_termAll(Incomp), finishLog]).


% repair theory
repInsInc(TheoryStateIn, Layer, FaultStateIn, TheoryRep):-
    spec(roundNum(R)),
    writeLog([nl, write_term('--------- Start repInsInc round: '), write_term(R),nl, finishLog]),
    FaultStateIn = (SuffsIn, InsuffsIn, IncompsPair),
    TheoryStateIn = [_,_, _, TheoryIn, _, _],
    
    % Collect all unwanted proofs and ignore their goals 
    findall(UnwantProof, 
            (member((_, UnwantedProofs), IncompsPair), member(UnwantProof, UnwantedProofs)),
            IncompsIn),
    
    entrechmentA(TheoryIn, FaultStateIn, [], AxiomsEE, (0,0), (E1SumOrig, E2SumOrig)),
    % member(Insuff, InsuffsIn),
    % repairPlan(Insuff, TheoryStateIn, SuffsIn, RepPlan1),
    appEach(InsuffsIn, [repairPlan, TheoryStateIn, SuffsIn], RepPlans1),
    appEach(IncompsIn, [repairPlan, TheoryStateIn, SuffsIn], RepPlans2),
    append(RepPlans1, RepPlans2, RepPlans),
    % RepPlans = [RepPlan1|RepPlans2],
    length(RepPlans, RepPlansLen),
    writeLog([nl, write_term(RepPlansLen),write_term(' fault\'s new repair plans found: '), write_term(RepPlans), nl,nl,nl,write_term(TheoryIn),nl, finishLog]),

    repCombine(RepPlans, TheoryIn, RepSolutions),
    
    appEach(RepSolutions, [appRepair, TheoryStateIn], RepStatesTem),
    %print('000000'),print(RepStatesTem),nl,nl,print('RepStatesTem'),nl,nl,        
    sort(RepStatesTem, RepStatesAll),
    length(RepStatesAll, LengthO),
    writeLog([nl, write_term('-- There are '), write_term(LengthO),
                  write_term(' repaired states: '),nl,write_termAll(RepStatesAll), nl, finishLog]),
    
    % get the maximum commutative set of repairs.
    mergeRs(RepStatesAll, RepStatesFine), 
    writeLog([nl, write_term('-- RepStatesFine '), write_term(RepStatesFine),nl, finishLog]),
    %print('111111 RepStatesFine'),print(RepStatesFine),nl,nl,  

    length(TheoryIn, OriTheoryLen),
    % calculate entrenchment scores.          
    findall((NumR1, NumAxioms, (E1SumDiff, E2SumDiff), RepTheoryState, FaultStateNew),
                    (member(RepTheoryState, RepStatesFine),
                      detInsInc(RepTheoryState, FaultStateNew),
                      RepTheoryState = [[Rs1, _],_, _, TheoryRep, _, _],
                      length(Rs1, NumR1),
                      length(TheoryRep, TheoryRepLen),
                      (TheoryRepLen =< OriTheoryLen ->
                       subtract(TheoryIn, TheoryRep, AxiomsRep), % get the list axioms that are changed/deleted.
                       findall([E1, E2], (member(X, AxiomsRep), member([(E1, E2), X],AxiomsEE)), EList),
                       transposeF(EList, [E1List, E2List]),
                       sum_list(E1List, E1SumDiff),
                       sum_list(E2List, E2SumDiff);
                       TheoryRepLen > OriTheoryLen,
                       entrechmentA(TheoryRep, FaultStateNew, [], _, (0,0), (E1SumRep, E2SumRep)),
                       E1SumDiff is E1SumOrig - E1SumRep, 
                       E2SumDiff is E2SumOrig - E2SumRep),
                      length(TheoryRep, NumAxioms)),
             AllRepStates),
    length(AllRepStates, Length),
    writeLog([nl, write_term('-- All faulty states: '), write_term(Length),nl,
                write_termAll(AllRepStates), finishLog]),
   
    % pruning the repairs which do not delete the least entrenched axioms/preconditions, or add the most entrenched ones. 
    eePrune(AllRepStates, Optimals),
    length(Optimals, LO),
    writeLog([    nl, write_term('--The number of Optimals: '), write_term(LO), nl, write_termAll(Optimals), finishLog]),
    % get one optimal repaired theory along with its remaining faults and applied repairs Rep.
    member((TheoryStateOp, FaultStateOp), Optimals),
    NewLayer is Layer+1,
    repInsInc(TheoryStateOp, NewLayer, FaultStateOp, TheoryRep).

/**********************************************************************************************************************
    eePrune(StatesFaultsAll, OptStates):
            return a repaired theory w.r.t. one fault among the FaultStates by applying an Parento optimal repair.
    Input:  StatesFaultsAll is a list: [(FNum1, FNum2, TheoryState, FaultState),...]
    Output: OptStates is also a list of (TheoryState, FaultState) by pruning the sub-optimals.
            For more information about TheoryState/FaultState, please see detInsInc.
************************************************************************************************************************/
eePrune([], []).
% if the sub-optimal pruning is not applied, return the input.
eePrune(StatesFaultsAll, TheoryStateOut):-
    spec(heuris(H)),
    member(noEE, H), 
    findall((TheoryState, FaultState),
             member((_, _, _, TheoryState, FaultState), StatesFaultsAll),
            TheoryStateOut).

eePrune(StatesFaultsAll, OptStates):-
    %writeLog([nl, write_term('--------- Pruning the sub-optimals with Threshod: '), write_term(Theres), nl, finishLog]),
    findall((TheoryState1, FaultState1),
            % the smaller EE is, the better; the fewer Repair operations the better.
            (member((X, _, (EE1, EE2), TheoryState1, FaultState1), StatesFaultsAll),
             % Compare the same repair cost and with same theory length. For both axioms expansion or axioms deletion or rule modification, 
             % the repaired theories with biggest entrenchment scores are the best
             forall(member((X, _, (EE1T, EE2T), _, _), StatesFaultsAll),
                    (%writeLog([nl, write_term('Cost1 & Cost2 is ---------'),nl,write_term(Cost1), write_term(Cost2), finishLog]),
                      EE1T-X > EE1-X;
                      EE1T-X = EE1-X, EE2T >= EE2))),    % The repaired theory is not strictly dominated by any others.
            OptStates).


/**********************************************************************************************************************
    pareOpt(StatesFaultsAll, OptStates):
            return a repaired theory w.r.t. one fault among the FaultStates by applying an Parento optimal repair.
    Input:  StatesFaultsAll is a list: [(FNum1, FNum2, TheoryState, FaultState),...]
    Output: OptStates is also a list of (TheoryState, FaultState) by pruning the sub-optimals.
            For more information about TheoryState/FaultState, please see detInsInc.
************************************************************************************************************************/
pareOpt([], []).
% if the sub-optimal pruning is not applied, return the input.
pareOpt(StatesFaultsAll, TheoryStateOut):-
    spec(heuris(H)),
    member(noOpt, H), 
    findall([FNum, (TheoryState, FaultState)],
            (member((N1, N2, TheoryState, FaultState), StatesFaultsAll),
             FNum is N1 +N2),
            TheoryStateTem),
    sort(TheoryStateTem, TheoryStateTem2),
    transposeF(TheoryStateTem2, [_, TheoryStateOut]),!.

pareOpt(StatesFaultsAll, OptStates):-
    %writeLog([nl, write_term('--------- Pruning the sub-optimals with Threshod: '), write_term(Theres), nl, finishLog]),
    findall((TheoryState1, FaultState1),
            (member((NumF11, NumF12, TheoryState1, FaultState1), StatesFaultsAll),
             TheoryState1 = [[Rs1, _]|_],
             length(Rs1, NumR1),
             Cost1 is NumR1 + NumF11 + NumF12,
             forall((member((NumF21, NumF22, TheoryState2, _), StatesFaultsAll),
                      TheoryState2 = [[Rs2, _]|_],
                     length(Rs2, NumR2),
                     Cost2 is NumR2 + NumF21 + NumF22),
                    (%writeLog([nl, write_term('Cost1 & Cost2 is ---------'),nl,write_term(Cost1), write_term(Cost2), finishLog]),
                      Cost2 >= Cost1))),    % The repaired theory is not strictly dominated by any others.
            OptStates).


/**********************************************************************************************************************
    mergeRs(RepStates, RepStatesNew):- if the theory of two states are same, then merge these two states.
    Input:  RepStates is a list of theory state: [[Repairs, EC, EProof, TheoryNew, TrueSetE, FalseSetE],...]
    Output: RepStatesNew is also a list of [[Repairs, EC, EProof, TheoryNew, TrueSetE, FalseSetE]...]
************************************************************************************************************************/
mergeRs(RepStates, RepStatesNew):-
    mR(RepStates, [], RepStatesNew).

mR([], SIn, SOut):-
    findall(StateNew,
            (member([[Rs, BanRs], EC, EProof, TheoryIn, TrueSetE, FalseSetE],SIn),
             minimal(TheoryIn, EC, Rs, MiniT, RsOut), % only take the minimal set of the theory into account.
             StateNew = [[RsOut, BanRs], EC, EProof, MiniT, TrueSetE, FalseSetE]),
        SOut).

% The theory state is already in SIn.
mR([H|Rest], SIn, Sout):-
    H = [[Rs, _]|StateT],
    % the main body of the state occur in the later states, then it is a redundancy. maintain the one cost least w.r.t. the length of repairs.
    member([[Rs2,RsBan2]|StateT], SIn), !,
    length(Rs, L1),
    length(Rs2, L2),
    (L1< L2-> replace([[Rs2,RsBan2]|StateT], H, SIn, SNew),
        mR(Rest, SNew, Sout), !;
     L1 >= L2-> mR(Rest, SIn, Sout)).

% H is not in SIn yet
mR([H|Rest], SIn, Sout):-
    mR(Rest, [H| SIn], Sout).
    