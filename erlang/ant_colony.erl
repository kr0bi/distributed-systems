-module(ant_colony).

-compile(export_all).

-include("aco_node_constants.hrl").

% -export([get_best_neighbour/4,
%         elaborate_ant/3,
%         pheromone_evaporation/3,
%         is_tour_complete/1,
%         remove_last_visited_node/1,
%         get_pheromone_strength/1,
%         is_returned/1,
%         deposit_pheromones/1,
%         reset_ant/2,
%         generate_ants/2,
%          set_ant_flag/2]).
 
-record(node, {name}).                %% nome in stringa del nodo
-record(edge, {from,                  %% nodo
               to,                    %% nodo
               weight,                %% valore numerico >= 0
               tau}).                 %% feromoni depositati nell'arco all'inizio, valore numerico >= 0     

-record(ant,    {cost_current_path,   %% valore numerico >=0
                pheromone_strength,   %% feromoni depositati dalla formica al ritorno da un path, valore numerico >=0
                returning_flag,       %% walking o returning
                best_tour_cost,       %% valore numerico >=0
                path,                 %% pila contenente: lista di nodi 
                complete_path}).      %% lista di nodi

%% Returns the best neighbour for a given ant
%% prende il valore da dove parte in base all'ultimo nodo visitato
%% poi chiede al nodo aco dove deve inviare effettivamente

get_best_neighbour(Node, All_Edges = [Edge=#edge{}|Edges], Alpha, Beta) ->
    Denominatore = calculate_denominatore(All_Edges, Alpha, Beta),          %% calcola il denominatore della formula 3.1
    Pij_all = calculate_probability(Edges, Alpha, Beta, Denominatore, [], Edge),        %% calcola il resto4
    _ = crypto:rand_seed(),
    R = rand:uniform(),
    NewE = pij_final(Pij_all, R),         %% quello per sparare un numero a caso da 0 a 1 in float e il numero dove rientra nel vettore della probabilita' viene scelto
    {NewE, find_neighbour(Node, NewE)}.

%% calcola il denominatore della formula per calcolare la probabilità di prendere un certo arco ij
calculate_denominatore(Edges, Alpha, Beta) ->
    lists:foldl(fun(X=#edge{}, Sum) -> (math:pow(X#edge.tau, Alpha) * math:pow(1/X#edge.weight, Beta)) + Sum end, 0.000, Edges).
%% calcola la probabilità del numeratore della formula
calculate_probability([Next_Edge | Edges], Alpha, Beta, Denominatore, AccProbability, Current_Edge=#edge{}) ->
    Tau = math:pow(Current_Edge#edge.tau, Alpha),
    Eta = math:pow(1.00/Current_Edge#edge.weight, Beta),
    Result = (Tau * Eta)/Denominatore,
    calculate_probability(Edges, Alpha, Beta, Denominatore, AccProbability ++ [{Result, Current_Edge}], Next_Edge);

calculate_probability([] , Alpha, Beta, Denominatore, AccProbability, Last_Edge) -> 
    Tau = math:pow(Last_Edge#edge.tau, Alpha),
    Eta = math:pow(1.00/Last_Edge#edge.weight, Beta),
    Result = (Tau * Eta)/Denominatore,
    AccProbability ++ [{Result, Last_Edge}].

%% seleziona l'arco in base alla probabilità
%% R: valore randomico
pij_final([{Pij, E=#edge{}} | T], R) ->
    if R =< Pij ->
        E;
    true ->
        pij_final(T, R-Pij)
    end.

%% individua se il nodo era from o to
find_neighbour(Node=#node{}, #edge{from=From, to=To}) ->
    if From == Node ->
        To;
    true ->
        From
    end.

%% Returns the anthill (generating node) for a given ant
get_anthill(Ant=#ant{}) ->
    lists:nth(1, Ant#ant.path).

%% Generates a number of ants
generate_ants(Amount, Client) ->
    loop_gen_ants(Amount, Client, []).

loop_gen_ants(0, _, Acc) -> Acc;
loop_gen_ants(Amount, Client, Acc) ->
    loop_gen_ants(Amount - 1, Client, 
        Acc ++ [#ant{cost_current_path=0, 
                    pheromone_strength=0, 
                    returning_flag=walking,
                    best_tour_cost=?WORST_COST, 
                    path=[Client],
                    complete_path=[Client]}]).

%% Returns the pheromone strength of a given ant
get_pheromone_strength(Ant = #ant{}) ->
    Ant#ant.pheromone_strength.

%% Sets the a given ant's flag
set_ant_flag(#ant{cost_current_path = CC, 
                        pheromone_strength = PS,
                        best_tour_cost = BTC,
                        path = P, complete_path=CP}, Flag) ->
    #ant{cost_current_path = CC, 
        pheromone_strength = PS, 
        returning_flag = Flag, 
        best_tour_cost = BTC, 
        path = P,
        complete_path=CP}.


%% Re-initializes a given ant
%% una ant viene rinizializzata solamente quando completa 2 volte il giro
%% l'unico elemento che deve essere in path e' il nodo del grafo di origine
reset_ant(Ant, From) when length(Ant#ant.path) == 0 ->
    #ant{cost_current_path = 0, 
        pheromone_strength = 0, 
        returning_flag = walking, 
        best_tour_cost = ?WORST_COST, 
        path = [From],
        complete_path= [From]};

reset_ant(_, _) -> throw("The length of the Ant's path isn't 1.").

%% calcola il valore della forza del feromone
%% inoltre aggiorna il best_tout_cost 
deposit_pheromones(Ant=#ant{}) ->
    Cost_Current_Path = Ant#ant.cost_current_path,
    if Ant#ant.best_tour_cost > Cost_Current_Path ->
        #ant{cost_current_path = Cost_Current_Path, 
            pheromone_strength = 1/Cost_Current_Path, 
            returning_flag = Ant#ant.returning_flag, 
            best_tour_cost = Cost_Current_Path, 
            path = Ant#ant.path,
            complete_path = Ant#ant.complete_path};
    true ->
        #ant{cost_current_path = Cost_Current_Path, 
            pheromone_strength = 1/Cost_Current_Path, 
            returning_flag = Ant#ant.returning_flag, 
            best_tour_cost = Ant#ant.best_tour_cost, 
            path = Ant#ant.path,
            complete_path = Ant#ant.complete_path}
    end.

%% Updates and elaborates a given ant
%% walking -> aggiorna i valori del path
%% returning -> rimuove l'ultimo nodo visitato nella pila
elaborate_ant(Ant=#ant{}, To=#node{}, ByEdge=#edge{}) ->
    case Ant#ant.returning_flag of 
        walking ->
            #ant{cost_current_path = Ant#ant.cost_current_path + ByEdge#edge.weight,
                pheromone_strength = Ant#ant.pheromone_strength,
                returning_flag = Ant#ant.returning_flag,
                best_tour_cost = Ant#ant.best_tour_cost,
                path = Ant#ant.path ++ [To],
                complete_path = Ant#ant.path ++ [To]};
        returning ->
            A = remove_last_visited_node(Ant),
            #ant{cost_current_path = Ant#ant.cost_current_path,
                    pheromone_strength = Ant#ant.pheromone_strength,
                    returning_flag = Ant#ant.returning_flag,
                    best_tour_cost = Ant#ant.best_tour_cost,
                    path = A#ant.path,
                    complete_path = Ant#ant.complete_path}
    end.

%% Handles pheromone evaporation on the set of edges
%% Torna l'edge aggiornato con i nuovi valori dei feromoni
pheromone_evaporation(Edge=#edge{from=From, to=To, weight=Weight}, Tau_Zero, Rho) ->
    New_tau = (1 - Rho ) * Edge#edge.tau + (Rho * Tau_Zero),
    #edge{from=From,
        to=To,
        weight=Weight,
        tau=New_tau}.

%% Returns the last visited node for a given ant
get_last_visited(Ant=#ant{}) ->
    lists:last(Ant#ant.path).

%% verifica che una ant sia walking e che il primo e ultimo nodo del path siano identici
is_tour_complete(Ant=#ant{}) ->
    LastVisited = get_last_visited(Ant),
    FirstVisited = get_anthill(Ant),
    if (Ant#ant.returning_flag == walking) and (LastVisited == FirstVisited) ->
        true;
    true ->
        false
    end.

%% rimuove l'ultimo nodo visitato
remove_last_visited_node(Ant=#ant{}) ->
    PathWithoutLastNode = lists:droplast(Ant#ant.path),
    #ant{cost_current_path = Ant#ant.cost_current_path,
                pheromone_strength = Ant#ant.pheromone_strength,
                returning_flag = Ant#ant.returning_flag,
                best_tour_cost = Ant#ant.best_tour_cost,
                path = PathWithoutLastNode,
                complete_path = Ant#ant.complete_path}.

%% verifica che un ant sia returning e che la sua pila del path sia vuota
%% questo implica che l'ant è ritornata due volte al suo punto di partenza
is_returned(Ant=#ant{}) ->
    if (length(Ant#ant.path) == 0) and (Ant#ant.returning_flag == returning) ->
        true;
    true ->
        false
    end.