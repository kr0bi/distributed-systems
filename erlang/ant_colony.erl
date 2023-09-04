-module(ant_colony).

-export([get_best_neighbour/4]).

-record(state, {server,
                name=""}).   
-record(node, {name}).
-record(edge, {from, 
               to,
               weight,
               tau}).

-record(ant, {cost_current_path, pheromone_strength, returning_flag, best_tour_cost, path}).

%% Returns the best neighbour for a given ant
%% prende il valore da dove parte in base all'ultimo nodo visitato
%% poi chiede al nodo aco dove deve inviare effettivamente

get_best_neighbour(Node, [Edge=#edge{}|Edges], Alpha, Beta) ->
    Denominatore = calculate_denominatore(Edges, Alpha, Beta),          %% calcola il denominatore della formula 3.1
    Pij_all = calculate_probability(Edges, Alpha, Beta, Denominatore, [], Edge=#edge{}),        %% calcola il resto4
    _ = rand:seed(exs928ss),
    R = rand:uniform(),
    E = pij_final(Pij_all, R),         %% quello per sparare un numero a caso da 0 a 1 in float e il numero dove rientra nel vettore della probabilita' viene scelto
    find_neighbour(Node, E).

calculate_denominatore(Edges, Alpha, Beta) ->
    lists:foldl(fun(X=#edge{}, Sum) -> (math:pow(X#edge.tau, Alpha) * math:pow(1/X#edge.weight, Beta)) + Sum end, 0, Edges).

calculate_probability([Next_Edge | Edges], Alpha, Beta, Denominatore, AccProbability, Current_Edge=#edge{}) ->
    Tau = math:pow(Current_Edge#edge.tau, Alpha),
    Eta = math:pow(1/Current_Edge#edge.weight, Beta),
    Result = (Tau * Eta)/Denominatore,
    calculate_probability(Edges, Alpha, Beta, Denominatore, AccProbability ++ [{Result, Current_Edge}], Next_Edge);

calculate_probability([] , Alpha, Beta, Denominatore, AccProbability, Last_Edge) -> 
    Tau = math:pow(Last_Edge#edge.tau, Alpha),
    Eta = math:pow(1/Last_Edge#edge.weight, Beta),
    Result = (Tau * Eta)/Denominatore,
    AccProbability ++ [{Result, Last_Edge}].

pij_final([{Pij, E=#edge{}} | T], R) ->
    if R =< Pij ->
        E;
    true ->
        pij_final(T, R-Pij)
    end.

find_neighbour(Node=#node{}, E=#edge{from=From, to=To}) ->
    if From == Node ->
        From;
    true ->
        To
    end.

%% Returns the anthill (generating node) for a given ant
get_anthill(Ant) ->
    done.

%% Generates a number of ants
generate_ants(Amount, Client) ->
    loop_gen_ants(Amount, 0, Client).

loop_gen_ants(0, _, _) ->
    throw("Can't generate a zero amount of ants!");

loop_gen_ants(Amount, 0, Client) ->
    [#ant{cost_current_path=0, 
        pheromone_strength=0, 
        returning_flag=false, 
        best_tour_cost=0, 
        path=Client}] ++ loop_gen_ants(Amount, 1, Client);

loop_gen_ants(Amount, Idx, Client) when Idx == Amount - 1->
    [#ant{cost_current_path=0, 
        pheromone_strength=0, 
        returning_flag=false, 
        best_tour_cost=0, 
        path=Client}];

loop_gen_ants(Amount, Idx, _) when Idx == Amount -> [].


%% Returns the pheromone strength of a given ant
get_pheromone_strength(Ant = #ant{}) ->
    Ant#ant.pheromone_strength.

%% Sets the a given ant's flag
set_ant_flag(Ant = #ant{}, Flag) ->
    #ant{cost_current_path = Ant#ant.cost_current_path, 
        pheromone_strength = Ant#ant.pheromone_strength, 
        returning_flag = Flag, 
        best_tour_cost = Ant#ant.best_tour_cost, 
        path = Ant#ant.best_tour_cost}.

%% Returns the flag for a given ant
get_ant_flag(Ant = #ant{}) ->
    Ant#ant.returning_flag.

%% Updates node's best known cost 
update_best_cost(Ant = #ant{}, Best_cost) ->
    #ant{cost_current_path = Ant#ant.cost_current_path, 
        pheromone_strength = Ant#ant.pheromone_strength, 
        returning_flag = Ant#ant.returning_flag, 
        best_tour_cost = Best_cost, 
        path = Ant#ant.best_tour_cost}.

%% Returns best known cost for a given ant
get_ant_best_cost(Ant) ->
    Ant#ant.best_tour_cost.

%% Re-initializes a given ant
%% una ant viene rinizializzata solamente quando completa 2 volte il giro
%% l'unico elemento che deve essere in path e' il nodo del grafo di origine
reset_ant(Ant) when length(Ant#ant.path) == 1 ->
    #ant{cost_current_path = 0, 
        pheromone_strength = 0, 
        returning_flag = false, 
        best_tour_cost = 0, 
        path = Ant#ant.path};

reset_ant(_) -> throw("The length of the Ant's path isn't 1.").

%% Deposits pheromones on the edges visited by the ant
%% chiede al nodo ACO di calcolargli il tau corrispondente all'edge
%% così i coefficienti li deve tenere solamente il nodo ACO
%% gli passa solamente la forza del 
deposit_pheromones(Ant=#ant{path=[Last|[Second_Last|_]]}) ->
    Edge = {Last, Second_Last},
    aco_node:calculate_pheromones(Edge, Ant#ant.pheromone_strength).

%% Updates and elaborates a given ant (magari spiegare meglio)
elaborate_ant(Ant) ->
    done.

%% Handles pheromone evaporation on the set of edges
pheromone_evaporation() ->
    done.

%% Updates a given ant's path with a new node
update_ant_path(Ant, Node, Cost) ->
    done.

%% Returns the last visited node for a given ant
get_last_visited(Ant) ->
    done.



