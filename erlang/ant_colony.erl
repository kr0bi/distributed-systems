-module(ant_colony).

-compile(export_all).

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
 
-record(node, {name}).
-record(edge, {from, 
               to,
               weight,
               tau}).

-record(ant, {cost_current_path, 
            pheromone_strength, 
            returning_flag, 
            best_tour_cost, 
            path}).                     %% lista: Start -> Next -> Next -> ... -> Final

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

calculate_denominatore(Edges, Alpha, Beta) ->
    lists:foldl(fun(X=#edge{}, Sum) -> (math:pow(X#edge.tau, Alpha) * math:pow(1/X#edge.weight, Beta)) + Sum end, 0.000, Edges).

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

pij_final([{Pij, E=#edge{}} | T], R) ->
    if R =< Pij ->
        E;
    true ->
        pij_final(T, R-Pij)
    end.

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
                    best_tour_cost=10000, 
                    path=[Client]}]).



%% Returns the pheromone strength of a given ant
get_pheromone_strength(Ant = #ant{}) ->
    Ant#ant.pheromone_strength.

%% Sets the a given ant's flag
set_ant_flag(#ant{cost_current_path = CC, 
                        pheromone_strength = PS,
                        best_tour_cost = BTC,
                        path = P}, Flag) ->
    #ant{cost_current_path = CC, 
        pheromone_strength = PS, 
        returning_flag = Flag, 
        best_tour_cost = BTC, 
        path = P}.

%% Returns the flag for a given ant
% get_ant_flag(Ant = #ant{}) ->
%     Ant#ant.returning_flag.

% %% Updates node's best known cost 
% update_best_cost(Ant = #ant{}, Best_cost) ->
%     #ant{cost_current_path = Ant#ant.cost_current_path, 
%         pheromone_strength = Ant#ant.pheromone_strength, 
%         returning_flag = Ant#ant.returning_flag, 
%         best_tour_cost = Best_cost, 
%         path = Ant#ant.best_tour_cost}.

% %% Returns best known cost for a given ant
% get_ant_best_cost(Ant) ->
%     Ant#ant.best_tour_cost.

%% Re-initializes a given ant
%% una ant viene rinizializzata solamente quando completa 2 volte il giro
%% l'unico elemento che deve essere in path e' il nodo del grafo di origine
reset_ant(Ant, From) when length(Ant#ant.path) == 0 ->
    #ant{cost_current_path = 0, 
        pheromone_strength = 0, 
        returning_flag = walking, 
        best_tour_cost = 10000, 
        path = [From]};

reset_ant(_, _) -> throw("The length of the Ant's path isn't 1.").

%% Deposits pheromones on the edges visited by the ant
%% chiede al nodo ACO di calcolargli il tau corrispondente all'edge
%% così i coefficienti li deve tenere solamente il nodo ACO
%% gli passa solamente la forza del 
deposit_pheromones(Ant=#ant{}) ->
    Cost_Current_Path = Ant#ant.cost_current_path,
    if Ant#ant.best_tour_cost > Cost_Current_Path ->
        #ant{cost_current_path = Cost_Current_Path, 
            pheromone_strength = 1/Cost_Current_Path, 
            returning_flag = Ant#ant.returning_flag, 
            best_tour_cost = Cost_Current_Path, 
            path = Ant#ant.path};
    true ->
        #ant{cost_current_path = Cost_Current_Path, 
            pheromone_strength = 1/Cost_Current_Path, 
            returning_flag = Ant#ant.returning_flag, 
            best_tour_cost = Ant#ant.best_tour_cost, 
            path = Ant#ant.path}
    end.


% -record(ant, {cost_current_path, 
%             pheromone_strength, 
%             returning_flag, 
%             best_tour_cost, 
%             path}).    

%% Updates and elaborates a given ant (magari spiegare meglio)
elaborate_ant(Ant=#ant{}, To=#node{}, ByEdge=#edge{}) ->
    case Ant#ant.returning_flag of 
        walking ->
            #ant{cost_current_path = Ant#ant.cost_current_path + ByEdge#edge.weight,
                pheromone_strength = Ant#ant.pheromone_strength,
                returning_flag = Ant#ant.returning_flag,
                best_tour_cost = Ant#ant.best_tour_cost,
                path = Ant#ant.path ++ [To]};
        returning ->
            A = remove_last_visited_node(Ant),
            #ant{cost_current_path = Ant#ant.cost_current_path,
                    pheromone_strength = Ant#ant.pheromone_strength,
                    returning_flag = Ant#ant.returning_flag,
                    best_tour_cost = Ant#ant.best_tour_cost,
                    path = A#ant.path}
    end.


    

%% Handles pheromone evaporation on the set of edges
%% Deve tornarmi l'edge aggiornato
pheromone_evaporation(Edge=#edge{from=From, to=To, weight=Weight}, Tau_Zero, Rho) ->
    New_tau = (1 - Rho ) * Edge#edge.tau + (Rho * Tau_Zero),
    #edge{from=From,
        to=To,
        weight=Weight,
        tau=New_tau}.

% %% Updates a given ant's path with a new node
% update_ant_path(Ant, Node, Cost) ->
%     done.

%% Returns the last visited node for a given ant
get_last_visited(Ant=#ant{}) ->
    lists:last(Ant#ant.path).


is_tour_complete(Ant=#ant{}) ->
    LastVisited = get_last_visited(Ant),
    FirstVisited = get_anthill(Ant),
    if (Ant#ant.returning_flag == walking) and (LastVisited == FirstVisited) ->
        true;
    true ->
        false
    end.

remove_last_visited_node(Ant=#ant{}) ->
    PathWithoutLastNode = lists:droplast(Ant#ant.path),
    #ant{cost_current_path = Ant#ant.cost_current_path,
                pheromone_strength = Ant#ant.pheromone_strength,
                returning_flag = Ant#ant.returning_flag,
                best_tour_cost = Ant#ant.best_tour_cost,
                path = PathWithoutLastNode}.


is_returned(Ant=#ant{}) ->
    if (length(Ant#ant.path) == 0) and (Ant#ant.returning_flag == returning) ->
        true;
    true ->
        false
    end.