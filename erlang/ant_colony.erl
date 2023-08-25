-module(ant_colony).

%% Starts an iteration of the ACO algorithm
start_aco() ->
    done.

%% Returns the best neighbour for a given ant
get_best_neighbour(Ant) ->
    done.

%% Returns the anthill (generating node) for a given ant
get_anthill(Ant) ->
    done.

%% Generates a number of ants
generate_ants(Amount) ->
    done.

%% Send an ant
send_ant(Ant, Receiver) ->
    done.

%% Handles the receiving of ants
receive_ant() ->
    done.

%% Pops an ant from the queue
pop_ant_queue() ->
    done.

%% Pushes an ant on the ant queue
push_ant_queue() ->
    done.

%% Returns the pheromone strength of a given ant
get_pheromone_strength(Ant) ->
    done.

%% Sets the a given ant's flag
set_ant_flag(Ant) ->
    done.

%% Returns the flag for a given ant
get_ant_flag(Ant) ->
    done.

%% Updates node's best known cost 
update_best_cost(Ant) ->
    done.

%% Returns best known cost for a given ant
get_ant_best_cost(Ant) ->
    done.

%% Re-initializes a given ant
reset_ant(Ant) ->
    done.

%% Deposits pheromones on the edges visited by the ant
deposit_pheromones(Ant) ->
    done.

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



