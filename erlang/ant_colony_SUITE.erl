-module(ant_colony_SUITE).
-include_lib("common_test/include/ct.hrl").
-record(node, {name}).
-record(edge, {from, to, weight, tau}).
-export([test_qa194/1, test_wi29/1, test_uy734/1, test_be52/1]).
-export([extract_graph_from_dataset/2, test_tsp_dataset/4, split_clients_per_node/2]).

%%%
%% Test cases 
%%%

% Test for the b52 dataset
% Contains 52 nodes, best cost is 575
test_be52(Config) ->
    {NodeList, EdgeList} = extract_graph_from_dataset(?config(data_dir, Config), "be52"),
    test_tsp_dataset(575, NodeList, EdgeList, 15).


% Test for the qa194 dataset
% Contains 194 nodes, best cost is 9352
test_qa194(Config) ->
    {NodeList, EdgeList} = extract_graph_from_dataset(?config(data_dir, Config), "qa194"),
    test_tsp_dataset(9352, NodeList, EdgeList, 30).

% Test for the uy29 dataset
% Contains 734 nodes, best cost is 79114
test_uy734(Config) ->
    {NodeList, EdgeList} = extract_graph_from_dataset(?config(data_dir, Config), "uy734"),
    test_tsp_dataset(79114, NodeList, EdgeList, 65).

% Test for the wi29 dataset
% Contains 29 nodes, best cost is 27603
test_wi29(Config) ->
    {NodeList, EdgeList} = extract_graph_from_dataset(?config(data_dir, Config), "wi29"),
    test_tsp_dataset(27603, NodeList, EdgeList, 7).

% Tests a TSP dataset
% needs the cost of the tsp solution, a list of nodes and one of edges and the amount of nodes per peer
test_tsp_dataset(BestCost, NodeList, EdgeList, ClientsPerPeer) ->
    ClientList = lists:map(fun (X) -> list_to_integer(X) end, NodeList),
    ClientsLists = split_clients_per_node(ClientsPerPeer, ClientList),
    PeerList = [HeadPeer | _ ] = generate_peers(length(ClientsLists)),
    start_colony_link(PeerList),
    io:format("ClientList: ~w~n", [ClientsLists]),
    add_nodes(PeerList, ClientsLists),
    EdgeRecordList = lists:map(fun ([From, To, Weight])-> 
                                        {Num, _} = string:to_float(Weight),
                                        #edge{from=#node{name=list_to_integer(From)}, to=#node{name=list_to_integer(To)}, weight=Num} end, EdgeList),
    ping_all_nodes(PeerList),
    io:format("Edges: ~w ~n", [EdgeRecordList]),
    add_egdes_to_peers(HeadPeer, EdgeRecordList),
    start_aco(HeadPeer, 3),
    loop_until_good_approx(BestCost, HeadPeer, 10*60, time()).


%%%
%% I/O Utilities
%%%

% Extracts graph data from the given dataset
% needs a directory and a filename prefix
extract_graph_from_dataset(Dir, FileName) ->
    NodeFileName = lists:append(FileName, "_node_data.txt"),
    EdgeFileName = lists:append(FileName, "_edge_data.txt"),
    {ok, NodesBin} = file:read_file(filename:join([Dir, NodeFileName])),
    {ok, EdgesBin} = file:read_file(filename:join([Dir, EdgeFileName])),
    NodeList = string:tokens(binary_to_list(NodesBin), "\n"),
    EdgeList = string:tokens(binary_to_list(EdgesBin), "\n"),
    NewEdgeList = lists:map(fun(X) -> string:tokens(X, " ") end, EdgeList),
    {NodeList, NewEdgeList}.

%%%
%% Peer Utilities
%%%

% Splits a list of clients into lists with at most Amount nodes
split_clients_per_node(Amount, []) ->
    [];
split_clients_per_node(Amount, List) ->
    case length(List) > Amount of
        true ->
            {Head, Tail} = lists:split(Amount, List),
            lists:append([Head], split_clients_per_node(Amount, Tail));
        false ->
            case length(List) == 1 of
                true ->
                    [List];
                false ->
                    List
            end
    end.

% Generates a list of peers
% returns a list of tuples Peer, Node
generate_peers(0) ->
    [];
generate_peers(Amount) ->
    Name = ?CT_PEER_NAME(),
    {ok, Peer, Node} = ?CT_PEER(#{name => Name, connection => standard_io}),
    peer:call(Peer, net_kernel, start, [undefined, #{name_domain => shortnames}]),
    lists:append([{Peer, Node}], generate_peers(Amount - 1 )).

% Pings every node in a list to establish a connection
ping_nodes(Peer, []) ->
    ok;
ping_nodes(Peer = {Pid, _}, [{_, Node} | Nodes]) ->
    peer:call(Pid, net_adm, ping , [Node]),
    ping_nodes(Peer, Nodes).
    
ping_all_nodes([]) ->
    ok;
ping_all_nodes([Node | Nodes]) ->
    ping_nodes(Node, Nodes).

% Stars an aco_node link on every peer
start_colony_link([]) ->
    ok;
start_colony_link([{Peer, _} | Peers]) ->
    peer:call(Peer, aco_node, start_link, []),
    start_colony_link(Peers).

%% Start the ACO algorithm
start_aco({Peer, _}, Amount) ->
    peer:call(Peer, aco_node, start_aco, [Amount]).

%%%
%% Graph utilities
%%%

% Adds a list of nodes to a peer's aco_node process
add_nodes_to_peer(_, []) ->
    ok;
%add_nodes_to_peer(Peer, Node) ->
%    peer:call(Peer, aco_node, add_local_node, [#node{name=Node}]);
add_nodes_to_peer(Peer, [Node | Nodes]) ->
    peer:call(Peer, aco_node, add_local_node, [#node{name=Node}]),
    add_nodes_to_peer(Peer, Nodes).

% Adds a list of nodes to a list of peers
add_nodes(_, []) ->
    ok;
add_nodes([], _) ->
    ok;
add_nodes([{Peer, _} | Peers], [Nodes | NodesLists]) ->
    add_nodes_to_peer(Peer, Nodes),
    add_nodes(Peers, NodesLists).

% Adds a list of edges to the graph
add_egdes_to_peers({Peer, _}, EdgeList) ->
    peer:call(Peer, aco_node, add_local_edges, [EdgeList]).

%%%
%% General utilities
%%%

%% Runs a loop until a good approximation of the TSP solution has been found
% Needs the cost to compare against, a peer, a timeout and at which time the loop started
loop_until_good_approx(Cost, Node = {Peer, _}, Timeout, StartTime) ->
    {_, PeerCost} = peer:call(Peer, aco_node, what_s_the_best_path,[]),
    TimeElapsed = calendar:time_to_seconds(time()) - calendar:time_to_seconds(StartTime),
    case is_cost_acceptable(PeerCost, Cost) of
        true ->
            io:format("Acceptable cost found after ~w seconds: ~w ~n", [TimeElapsed, PeerCost]),
            ok;
        false ->
            case (Timeout - TimeElapsed) > 0 of
                true ->
                    loop_until_good_approx(Cost, Node, Timeout, StartTime);
                false ->
                    io:format("Best cost found was: ~w ~n", [PeerCost]),
                    {failed, loop_timeout}
            end
    end.

% Returns whether the peer cost is within acceptable parameters
is_cost_acceptable(PeerCost, Cost) ->
    %io:format("Peer Cost: ~w ~n Cost : ~w ~n", [PeerCost, Cost]),
    (((PeerCost - Cost)/Cost) * 100) < 15.


