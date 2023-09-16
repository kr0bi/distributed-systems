-module(graph).
-export([add_node/4, remove_node/3, update_edges_cost/2]).

%% Adds a node to the graph
%% Needs node id (Id1) and its relative edges and costs
add_node(Id1, Edges = [{{Id1, Id2}, Cost}], NodeList, EdgeList) ->
    NewNodes = sets:add_element(Id1, NodeList),
    NewEdges = sets:union(Edges, EdgeList),
    {NewNodes, NewEdges}.
    

%% Removes a node from the graph
remove_node(Id, NodeList, EdgeList) ->
    NewNodes = sets:del_element(Id, NodeList),
    NewEdges = sets:filter((fun (X = {{Id1, Id2}, Cost}) -> 
                                ((Id1 /= Id) and (Id2 /= Id))
                            end), 
                            EdgeList),
    {NewNodes, NewEdges}.
%% Updates the costs of a set of edges
update_edges_cost(Edges = [{{Id1, Id2}, Cost}], NodeList) ->
    Filter = sets:filter((fun (X = {{Id_1, Id_2}, Cost1}) -> 
                                not (((Id1 == Id_1) and (Id2 == Id_2)) or ((Id2 == Id_1) and (Id1 == Id_2)))
                          end),
                         NodeList),
    NewEdges = sets:union(Edges, Filter),
    NewEdges.

%% Initializes a partial graph
%% Needs a list of nodes and a list of edges
init_graph([Node], [{Edge, Cost}]) ->
    done.