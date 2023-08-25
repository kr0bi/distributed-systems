-module(graph).

%% Adds a node to the graph
%% Needs node id (Id1) and its relative edges and costs
add_node(Id1, [{{Id1, Id2}, Cost}]) ->
    done.

%% Removes a node from the graph
remove_node(Id) ->
    done.

%% Updates the costs of a set of edges
update_edges_cost([{{Id1, Id2}, Cost}]) ->
    done.

%% Initializes a partial graph
%% Needs a list of nodes and a list of edges
init_graph([Node], [{Edge, Cost}]) ->
    done.