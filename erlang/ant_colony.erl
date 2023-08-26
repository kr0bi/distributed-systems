-module(ant_colony).
-compile([export_all]).

-record(ant, {cost_current_path, pheromone_strength, returning_flag, best_tour_cost, path}).

%% Starts an iteration of the ACO algorithm
start_aco(Client) ->
    %% genero un numero di formiche pari a quante ne abbiamo decise di mettere
    Amount = 5,
    Ants = generate_ants(Amount, Client),       %% dentro il metodo verranno create le formiche e inviate ai vicini
    send_ants(Ants).
    
%% Returns the best neighbour for a given ant
%% prende il valore da dove parte in base all'ultimo nodo visitato
%% poi chiede al nodo aco dove deve inviare effettivamente
get_best_neighbour(Ant) ->
    done.

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


%% Send multiple ants
send_ants([]) ->
    ok;

send_ants([Ant|Others]) ->
    send_ant(Ant, get_best_neighbour(Ant)),
    send_ants(Others).

%% Send an ant to the ACO node
send_ant(Ant, Receiver) ->
    aco_node:send_ant(Ant, get_last_visited(Ant), Receiver).

%% Handles the receiving of ants
%% qua va aggiornato il best cost, etc
receive_ant() ->
    done.

%% Pops an ant from the queue
pop_ant_queue() ->
    done.

%% Pushes an ant on the ant queue
push_ant_queue() ->
    done.

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



