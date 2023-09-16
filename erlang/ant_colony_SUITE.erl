-module(ant_colony_SUITE).
-include_lib("common_test/include/ct.hrl").
-record(node, {name}).
-record(edge, {from, to, weight, tau}).
-export([test_qa194/1, test_wi29/1, test_uy734/1, test_be52/1, test_removal/1, test_update/1, test_addition/1, test_addition_removal/1]).
-export([test_qa194_ticket/1, test_wi29_ticket/1, test_uy734_ticket/1, test_be52_ticket/1, test_aco_removal_wi29/1, test_peer_addition_wi29/1]).
-export([add_peer_loop/8]).
-export([all/0, groups/0]).
-define(ACCEPT_PARAM, 5).

%%%
%% Test cases 
%%%

all() -> [{group, dataset_ticket}, {group, add_rem}].
groups() -> [{dataset_ticket, [sequence, {repeat, 20}], [test_be52_ticket, test_wi29_ticket]},
             {add_rem, [sequence, {repeat, 500}], [test_addition_removal]}].

% Test for the b52 dataset
% Contains 52 nodes, best cost is 7542
test_be52(Config) ->
    {NodeList, EdgeList} = extract_graph_from_dataset(?config(data_dir, Config), "be52"),
    test_tsp_dataset(7542, NodeList, EdgeList, 15, 10*60).

%test_be52_ticket(Config) ->
%    {NodeList, EdgeList} = extract_graph_from_dataset(?config(data_dir, Config), "be52"),
%    test_tsp_dataset(7542, NodeList, EdgeList, 15, 1*60, true).


% Test for the qa194 dataset
% Contains 194 nodes, best cost is 9352
test_qa194(Config) ->
    {NodeList, EdgeList} = extract_graph_from_dataset(?config(data_dir, Config), "qa194"),
    test_tsp_dataset(9352, NodeList, EdgeList, 2, 20*60).

%test_qa194_ticket(Config) ->
%    {NodeList, EdgeList} = extract_graph_from_dataset(?config(data_dir, Config), "qa194"),
%    test_tsp_dataset(9352, NodeList, EdgeList, 30, 20*60, true).

% Test for the uy29 dataset
% Contains 734 nodes, best cost is 79114
test_uy734(Config) ->
    {NodeList, EdgeList} = extract_graph_from_dataset(?config(data_dir, Config), "uy734"),
    test_tsp_dataset(79114, NodeList, EdgeList, 65, 30*60).

%test_uy734_ticket(Config) ->
%    {NodeList, EdgeList} = extract_graph_from_dataset(?config(data_dir, Config), "uy734"),
%    test_tsp_dataset(79114, NodeList, EdgeList, 65, 30*60, true).

% Test for the wi29 dataset
% Contains 29 nodes, best cost is 27603
test_wi29(Config) ->
    {NodeList, EdgeList} = extract_graph_from_dataset(?config(data_dir, Config), "wi29"),
    test_tsp_dataset(27603, NodeList, EdgeList, 7, 60).

%test_wi29_ticket(Config) ->
%    {NodeList, EdgeList} = extract_graph_from_dataset(?config(data_dir, Config), "wi29"),
%    test_tsp_dataset(27603, NodeList, EdgeList, 7, 40, true).

test_removal(_Config) ->
    NodeList = [1, 2, 3, 4],
    EdgeList = [{1, 2, 1}, {1, 3, 26}, {1, 4, 9}, {2, 3, 11}, {2, 4, 9}, {3, 4, 15}],
    NewEdgeList = lists:map(fun ({From, To, Weight}) -> #edge{from=#node{name=From}, to=#node{name=To}, weight=Weight} end, EdgeList),
    ClientsLists = split_clients_per_node(1, NodeList),
    PeerList = [HeadPeer | _ ] = generate_peers(length(ClientsLists)),
    start_colony_link(PeerList),
    ping_all_nodes(PeerList),
    start_ticket_servers(PeerList),
    {Pid, _} = HeadPeer,
    peer:call(Pid, user_node, start_link, []),
    peer:call(Pid, flooding, start_link, []),
    peer:call(Pid, user_node, start_election, []),
    add_nodes(PeerList, ClientsLists, true),
    add_edges_to_peers(HeadPeer, NewEdgeList, true),
    start_aco(HeadPeer, 3),
    peer:call(Pid, flooding, write_graph_to_file, []),
    removal_loop(HeadPeer, 20, 10, time(), 4).

test_aco_removal_wi29(Config) ->
    {NodeList, EdgeList} = extract_graph_from_dataset(?config(data_dir, Config), "wi29"),
    NewNodeList = lists:map(fun (X) -> list_to_integer(X) end, NodeList),
    EdgeRecordList = lists:map(fun ([From, To, Weight])-> 
                                        {Num, _} = string:to_float(Weight),
                                        #edge{from=#node{name=list_to_integer(From)}, to=#node{name=list_to_integer(To)}, weight=Num} end, EdgeList),
    ClientsLists = split_clients_per_node(1, NewNodeList),
    PeerList = [HeadPeer | OtherPeers ] = generate_peers(length(ClientsLists)),
    start_colony_link(PeerList),
    ping_all_nodes(PeerList),
    start_ticket_servers(PeerList),
    {Pid, _} = HeadPeer,
    peer:call(Pid, user_node, start_link, []), % start user_node for api calls 
    peer:call(Pid, flooding, start_link, []), % start flooding process for writing xml files
    peer:call(Pid, user_node, start_election, []), % start ticket master election
    add_nodes(PeerList, ClientsLists, true),
    add_edges_to_peers(HeadPeer, EdgeRecordList, true),
    start_aco(HeadPeer, 3),
    RandomPeer = lists:nth(rand:uniform(length(OtherPeers)), OtherPeers),
    stop_peer_loop(HeadPeer, 80, 30, time(), RandomPeer, true).

test_peer_addition_wi29(Config) ->
    {NodeList, EdgeList} = extract_graph_from_dataset(?config(data_dir, Config), "wi29"),
    NewNodeList = lists:map(fun (X) -> list_to_integer(X) end, NodeList),
    NewEdgeList = lists:map(fun([X, Y, Z]) -> [list_to_integer(X), list_to_integer(Y), get_weight(Z)] end, EdgeList),
    ClientsLists = split_clients_per_node(4, NewNodeList),
    PeerList = [HeadPeer | _ ] = generate_peers(length(ClientsLists)),
    start_colony_link(PeerList),
    ping_all_nodes(PeerList),
    start_ticket_servers(PeerList),
    {Pid, _} = HeadPeer,
    peer:call(Pid, user_node, start_link, []), % start user_node for api calls 
    peer:call(Pid, flooding, start_link, []), % start flooding process for writing xml files
    peer:call(Pid, user_node, start_election, []), % start ticket master election
    Identities = generate_peer_id(PeerList, 0),
    add_nodes_to_office(Pid, Identities, ClientsLists),
    add_edges(Pid, NewEdgeList),
    start_aco(HeadPeer, 3),
    AddEdgeList = [[1, 30, 100], [2, 30, 100], [3, 30, 100], [4, 30, 100], [5, 30, 100],
            [6, 30, 100], [7, 30, 100], [8, 30, 100], [9, 30, 100], [10, 30, 100],
            [11, 30, 100], [12, 30, 100], [13, 30, 100], [14, 30, 100], [15, 30, 100],
            [16, 30, 100], [17, 30, 100], [18, 30, 100], [19, 30, 100], [20, 30, 100],
            [21, 30, 100], [22, 30, 100], [23, 30, 100], [24, 30, 100], [25, 30, 100],
            [26, 30, 100], [27, 30, 100], [28, 30, 100], [29, 30, 100], [30, 30, 100]],
    add_peer_loop(HeadPeer, 60, 20, time(), "Node 30", 30, AddEdgeList, true).



%% Tests the update of a number of edges while the algorithm is active
test_update(_Config) ->
    % Nodes and edges
    NodeList = [1, 2, 3, 4],
    EdgeList = [{1, 2, 1}, {1, 3, 26}, {1, 4, 9}, {2, 3, 11}, {2, 4, 9}, {3, 4, 15}],
    NewEdgeList = lists:map(fun ({From, To, Weight}) -> #edge{from=#node{name=From}, to=#node{name=To}, weight=Weight} end, EdgeList),
    % Splits the client nodes in various peers
    ClientsLists = split_clients_per_node(1, NodeList),
    % Generates peers
    PeerList = [HeadPeer | _ ] = generate_peers(length(ClientsLists)),
    start_colony_link(PeerList), % Start aco_node process on all peers
    ping_all_nodes(PeerList), % connects the peers between each other
    start_ticket_servers(PeerList), % starts the ticket process on all peers
    {Pid, _} = HeadPeer,
    peer:call(Pid, user_node, start_link, []), % start user_node for api calls 
    peer:call(Pid, flooding, start_link, []), % start flooding process for writing xml files
    peer:call(Pid, user_node, start_election, []), % start ticket master election
    add_nodes(PeerList, ClientsLists, true),
    add_edges_to_peers(HeadPeer, NewEdgeList, true),
    start_aco(HeadPeer, 3),
    update_edges_loop(HeadPeer, 20, 10, time(), [{{1,2},30}]).

%% Tests the addition of a new client node to the graph while the algorithm is active
test_addition(_Config) ->
    NodeList = [1, 2, 3, 4],
    EdgeList = [{1, 2, 30}, {1, 3, 26}, {1, 4, 9}, {2, 3, 11}, {2, 4, 9}, {3, 4, 15}],
    NewEdgeList = lists:map(fun ({From, To, Weight}) -> #edge{from=#node{name=From}, to=#node{name=To}, weight=Weight} end, EdgeList),
    ClientsLists = split_clients_per_node(1, NodeList),
    PeerList = [HeadPeer | _ ] = generate_peers(length(ClientsLists)),
    start_colony_link(PeerList),
    ping_all_nodes(PeerList),
    start_ticket_servers(PeerList),
    {Pid, _} = HeadPeer,
    peer:call(Pid, user_node, start_link, []),
    peer:call(Pid, flooding, start_link, []),
    peer:call(Pid, user_node, start_election, []),
    generate_peer_id(PeerList, 0),
    add_nodes(PeerList, ClientsLists, true),
    add_edges_to_peers(HeadPeer, NewEdgeList, true),
    start_aco(HeadPeer, 3),
    addition_loop(HeadPeer, 20, 10, time(), 5, "Node 1", [{{5, 1}, 17},
                                                        {{5, 2}, 33},
                                                        {{5, 3}, 7},
                                                        {{5, 4}, 29}], true).

%% Tests adding and then removing the same node from the graph while the algorithm is active

test_addition_removal(_Config) ->
    NodeList = [1, 2, 3, 4],
    EdgeList = [{1, 2, 30}, {1, 3, 26}, {1, 4, 9}, {2, 3, 11}, {2, 4, 9}, {3, 4, 15}],
    NewEdgeList = lists:map(fun ({From, To, Weight}) -> #edge{from=#node{name=From}, to=#node{name=To}, weight=Weight} end, EdgeList),
    ClientsLists = split_clients_per_node(1, NodeList),
    PeerList = [HeadPeer | _ ] = generate_peers(length(ClientsLists)),
    start_colony_link(PeerList),
    ping_all_nodes(PeerList),
    start_ticket_servers(PeerList),
    {Pid, _} = HeadPeer,
    peer:call(Pid, user_node, start_link, []),
    peer:call(Pid, flooding, start_link, []),
    peer:call(Pid, user_node, start_election, []),
    generate_peer_id(PeerList, 0),
    add_nodes(PeerList, ClientsLists, true),
    add_edges_to_peers(HeadPeer, NewEdgeList, true),
    start_aco(HeadPeer, 3),
    addition_loop(HeadPeer, 20, 10, time(), 5, "Node 1", [{{5, 1}, 17},
                                                        {{5, 2}, 33},
                                                        {{5, 3}, 7},
                                                    {{5, 4}, 29}], true),
    removal_loop(HeadPeer, 20, 10, time(), 5).                                                    
% Tests a TSP dataset
% needs the cost of the tsp solution, a list of nodes and one of edges and the amount of nodes per peer
%test_tsp_dataset(BestCost, NodeList, EdgeList, ClientsPerPeer, Timeout, Ticket) ->
%    ClientList = lists:map(fun (X) -> list_to_integer(X) end, NodeList),
%    ClientsLists = split_clients_per_node(ClientsPerPeer, ClientList),
%    PeerList = [HeadPeer | _ ] = generate_peers(length(ClientsLists)),
%    start_colony_link(PeerList),
%    ping_all_nodes(PeerList),
%    case Ticket of
%        true -> 
%            start_ticket_servers(PeerList),
%            {Pid, _} = HeadPeer,
%            peer:call(Pid, user_node, start_link, []),
%            peer:call(Pid, user_node, start_election, []),
%            peer:call(Pid, flooding, start_link, []);
%        false ->
%            ok
%    end,
%    add_nodes(PeerList, ClientsLists, Ticket),
%    EdgeRecordList = lists:map(fun ([From, To, Weight])-> 
%                                        {Num, _} = string:to_float(Weight),
%                                        #edge{from=#node{name=list_to_integer(From)}, to=#node{name=list_to_integer(To)}, weight=Num} end, EdgeList),
%    add_edges_to_peers(HeadPeer, EdgeRecordList, Ticket),
%    start_aco(HeadPeer, 3),
%    loop_until_good_approx(BestCost, HeadPeer, Timeout, time()).


test_tsp_dataset(BestCost, NodeList, EdgeList, ClientsPerPeer, Timeout) ->
    ClientList = lists:map(fun (X) -> list_to_integer(X) end, NodeList),
    NewEdgeList = lists:map(fun([X, Y, Z]) -> [list_to_integer(X), list_to_integer(Y), get_weight(Z)] end, EdgeList),
    ClientsLists = split_clients_per_node(ClientsPerPeer, ClientList),
    PeerList = [HeadPeer | _ ] = generate_peers(length(ClientsLists)),
    start_colony_link(PeerList),
    ping_all_nodes(PeerList),
    start_ticket_servers(PeerList),
    {Pid, _} = HeadPeer,
    peer:call(Pid, user_node, start_link, []),
    peer:call(Pid, user_node, start_election, []),
    peer:call(Pid, flooding, start_link, []),
    Identities = generate_peer_id(PeerList, 0),
    add_nodes_to_office(Pid, Identities, ClientsLists),
    add_edges(Pid, NewEdgeList),
    start_aco(HeadPeer, 3),
    loop_until_good_approx(BestCost, HeadPeer, Timeout, time()).


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

generate_peer_id([], _) ->
    [];
generate_peer_id([Peer = {Pid, Node} | PeerList], Count) ->
    List = generate_peer_id(PeerList, Count+1),
    OfficeID = "Node " ++ integer_to_list(Count), % Create office id
    peer:call(Pid, gen_server, multi_call, [user_node, {add_office, OfficeID, Node}]), %% add office to the list
    %io:format("Replies: ~w~n", [Replies]),
    lists:append([{OfficeID, Peer}], List).

% Splits a list of clients into lists with at most Amount nodes
split_clients_per_node(_, []) ->
    [];
split_clients_per_node(Amount, List) ->
    case length(List) > Amount of
        true ->
            {Head, Tail} = lists:split(Amount, List),
            lists:append([Head], split_clients_per_node(Amount, Tail));
        false ->
            [List]
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
ping_nodes(_, []) ->
    ok;
ping_nodes(Peer = {Pid, _}, [{_, Node} | Nodes]) ->
    peer:call(Pid, net_adm, ping , [Node]),
    ping_nodes(Peer, Nodes).

% Connects all nodes to each other
ping_all_nodes([]) ->
    ok;
ping_all_nodes([Node | Nodes]) ->
    ping_nodes(Node, Nodes),
    ping_all_nodes(Nodes).

% Starts an aco_node link on every peer
start_colony_link([]) ->
    ok;
start_colony_link([{Peer, _} | Peers]) ->
    peer:call(Peer, aco_node, start_link, []),
    start_colony_link(Peers).

% Starts ticket_server process on all peers in the list
start_ticket_servers([]) ->
    ok;
start_ticket_servers([{Peer, _} | Peers]) ->
    peer:call(Peer, ticket_system_server, start_link, []),
    start_ticket_servers(Peers).

%% Start the ACO algorithm
start_aco({Peer, _}, Amount) ->
    peer:call(Peer, aco_node, start_aco, [Amount]).

%%%
%% Graph utilities
%%%

% Adds a list of nodes to a peer's aco_node process
add_nodes_to_peer(_, [], _) ->
    ok;
add_nodes_to_peer({Peer, PeerNode}, [ Node | Nodes], Ticket) ->
    case Ticket of
        true ->
            {ok, _, TicketID} = peer:call(Peer, ticket_system, request_ticket, []),
            peer:call(Peer, gen_server, call, [aco_node, {add_local_node_ticket, {#node{name=Node}, PeerNode, TicketID}}]),
            peer:call(Peer, gen_server, multi_call, [aco_node, {update_ticket, TicketID}]);
        false ->
            peer:call(Peer, aco_node, add_local_node, [#node{name=Node}])
    end,
    add_nodes_to_peer({Peer, PeerNode} , Nodes, Ticket).

% Adds a list of nodes to a list of peers
add_nodes(_, [], _) ->
    ok;
add_nodes([], _, _) ->
    ok;
add_nodes([Peer | Peers], [Nodes | NodesLists], Ticket) ->
    add_nodes_to_peer(Peer, Nodes, Ticket),
    add_nodes(Peers, NodesLists, Ticket).

add_nodes_to_office(_, [], _) ->
    ok;
add_nodes_to_office(_, _, []) ->
    ok;
add_nodes_to_office(Peer, [{OfficeID, _} | PeerList], [Nodes | NodeList]) ->
    peer:call(Peer, user_api, init_add_clients, [[{Nodes, OfficeID}]]),
    add_nodes_to_office(Peer, PeerList, NodeList).

% Adds a list of edges to the graph
add_edges_to_peers({Peer, _}, EdgeList, Ticket) ->
    case Ticket of
        true ->
            {ok, _, TicketID} = peer:call(Peer, ticket_system, request_ticket, []),
            peer:call(Peer, gen_server, multi_call, [aco_node, {add_local_edges_ticket, {EdgeList, TicketID}}]);
        false ->
            peer:call(Peer, aco_node, add_local_edges, [EdgeList])
    end.

add_edges(Peer, EdgeList) ->
    NewList = lists:map(fun([X, Y, Z]) -> {X,Y,Z} end, EdgeList),
    peer:call(Peer, user_api, init_add_costs, [NewList]).

get_weight(X) ->
    {Test, _} = string:to_float(X),
    case Test of
        error -> {Test2, _} = string:to_integer(X),
                 case Test2 of
                     error -> error("the input should be a number~n");
                     _Else -> Test2
                 end;
        _Else -> Test
    end.

%%%
%% General utilities
%%%

%% Runs a loop until a good approximation of the TSP solution has been found
% Needs the cost to compare against, a peer, a timeout and at which time the loop started
loop_until_good_approx(Cost, Node = {Peer, _}, Timeout, StartTime) ->
    {Path, PeerCost} = peer:call(Peer, aco_node, what_s_the_best_path,[]),
    TimeElapsed = calendar:time_to_seconds(time()) - calendar:time_to_seconds(StartTime),
    case is_cost_acceptable(PeerCost, Cost) of
        true ->
            io:format("Acceptable cost ~w found after ~w seconds on path: ~w ~n", [PeerCost, TimeElapsed, Path]),
            ok;
        false ->
            case (Timeout - TimeElapsed) > 0 of
                true ->
                    loop_until_good_approx(Cost, Node, Timeout, StartTime);
                false ->
                    io:format("Best cost found was ~w on path: ~w ~n", [PeerCost, Path]),
                    {failed, loop_timeout}
            end
    end.

%% Loops for removing a node from the graph while the algorithm is running
% Node is the peer which makes the call
% Timeout is the time after which the loops stop
% RemoveTimer is the time after which the remove call is done
% Start time is the time when the loop first started
% CliendID is the ID of the clien node we want to remove

removal_loop(Node = {Peer, _}, Timeout, RemoveTimer, StartTime, ClientID) ->
    {Path, PeerCost} = peer:call(Peer, aco_node, what_s_the_best_path,[]),
    TimeElapsed = calendar:time_to_seconds(time()) - calendar:time_to_seconds(StartTime),
    case (RemoveTimer - TimeElapsed) < 0 of
        true ->
            peer:call(Peer, user_api, remove_client, [ClientID]);
        false ->
            ok
    end,
    case (Timeout - TimeElapsed) > 0 of
        true ->
            removal_loop(Node, Timeout, RemoveTimer, StartTime, ClientID);
        false ->
            peer:call(Peer, flooding, write_graph_to_file, []),
            io:format("Best cost found was ~w on path: ~w ~n", [PeerCost, Path]),
            ok
    end.

update_edges_loop(Node = {Peer, _}, Timeout, RemoveTimer, StartTime, Edges) ->
    {Path, PeerCost} = peer:call(Peer, aco_node, what_s_the_best_path,[]),
    TimeElapsed = calendar:time_to_seconds(time()) - calendar:time_to_seconds(StartTime),
    case (RemoveTimer - TimeElapsed) < 0 of
        true ->
            peer:call(Peer, user_api, update_costs, [Edges]);
        false ->
            ok
    end,
    case (Timeout - TimeElapsed) > 0 of
        true ->
            update_edges_loop(Node, Timeout, RemoveTimer, StartTime, Edges);
        false ->
            io:format("Best cost found was ~w on path: ~w ~n", [PeerCost, Path]),
            {Replies, _} = peer:call(Peer, gen_server, multi_call, [aco_node, my_edges]),
            io:format("All edges are: ~w ~n", [Replies]),
            ok
    end.

addition_loop(Node = {Peer, _}, Timeout, RemoveTimer, StartTime, NodeID, OfficeID, Edges, AddFlag) ->
    {Path, PeerCost} = peer:call(Peer, aco_node, what_s_the_best_path,[]),
    TimeElapsed = calendar:time_to_seconds(time()) - calendar:time_to_seconds(StartTime),
    case ((RemoveTimer - TimeElapsed) < 0) and AddFlag of
        true ->
            peer:call(Peer, user_api, add_client, [NodeID, OfficeID, Edges]),
            NewAddFlag = false;
        false ->
            NewAddFlag = AddFlag
    end,
    case (Timeout - TimeElapsed) > 0 of
        true ->
            addition_loop(Node, Timeout, RemoveTimer, StartTime, NodeID, OfficeID, Edges, NewAddFlag);
        false ->
            io:format("Best cost found was ~w on path: ~w ~n", [PeerCost, Path]),
            {Replies, _} = peer:call(Peer, gen_server, multi_call, [aco_node, my_edges]),
            io:format("All edges are: ~w ~n", [Replies]),
            ok
    end.

stop_peer_loop(Node = {Peer, _}, Timeout, StopTimer, StartTime, NodeToRemove = {RemovePid, _}, RemoveFlag) ->
    {Path, PeerCost} = peer:call(Peer, aco_node, what_s_the_best_path,[]),
    TimeElapsed = calendar:time_to_seconds(time()) - calendar:time_to_seconds(StartTime),
    case ((StopTimer - TimeElapsed) < 0) and RemoveFlag of
        true ->
            io:format("removing~n"),
            peer:stop(RemovePid),
            NewRemFlag = false;
        false ->
            NewRemFlag = RemoveFlag
    end,
    case (Timeout - TimeElapsed) > 0 of
        true ->
            stop_peer_loop(Node, Timeout, StopTimer, StartTime, NodeToRemove, NewRemFlag);
        false ->
            io:format("Ticket is ~w~n", [peer:call(Peer, ticket_system, request_ticket, [])]),
            io:format("Best cost found was ~w on path: ~w ~n", [PeerCost, Path]),
            {Replies, _} = peer:call(Peer, gen_server, multi_call, [aco_node, my_edges]),
            io:format("All edges are: ~w ~n", [Replies]),
            ok
    end.

add_peer_loop(Node = {Peer, _}, Timeout, AddTimer, StartTime, OfficeID, NodeToAdd, EdgeList, Flag) ->
    {Path, PeerCost} = peer:call(Peer, aco_node, what_s_the_best_path,[]),
    TimeElapsed = calendar:time_to_seconds(time()) - calendar:time_to_seconds(StartTime),
    case ((AddTimer - TimeElapsed) < 0) and Flag of
        true ->
            Name = ?CT_PEER_NAME(),
            {ok, Pid, NewNode} = ?CT_PEER(#{name => Name, connection => standard_io}), %% create peer
            peer:call(Pid, net_kernel, start, [undefined, #{name_domain => shortnames}]), %% make it distributed
            peer:call(Pid, ticket_system_server, start_link, []), %% start ticket process
            peer:call(Peer, net_adm, ping, [NewNode]), %% connect it to the other nodes
            peer:call(Pid, aco_node, start_link, []), %% start aco process
            peer:call(Pid, user_node, start_link, []), %% start user_node process
            peer:call(Pid, user_api, add_office, [OfficeID, NewNode]), %% add new office
            peer:call(Pid, gen_server, call, [ticket_system_server, connect]), %% connect to the ticket system
            peer:call(Pid, user_api, init_add_clients, [[{[NodeToAdd], OfficeID}]], 10000), %% add new client node
            add_edges(Pid, EdgeList), %% add new edges
            peer:call(Pid, aco_node, running_init, [3], 40*1000), %% connect aco process to the running algorithm
            NewFlag = false;
        false ->
            NewFlag = Flag
    end,
    case (Timeout - TimeElapsed) > 0 of
        true ->
            add_peer_loop(Node, Timeout, AddTimer, StartTime, OfficeID, NodeToAdd, EdgeList, NewFlag);
        false ->
            io:format("Ticket is ~w~n", [peer:call(Peer, ticket_system, request_ticket, [])]),
            io:format("Best cost found was ~w on path: ~w ~n", [PeerCost, Path]),
            {Replies, _} = peer:call(Peer, gen_server, multi_call, [aco_node, my_edges]),
            io:format("All edges are: ~w ~n", [Replies]),
            ok
    end.

% Returns whether the peer cost is within acceptable parameters
is_cost_acceptable(PeerCost, Cost) ->
    %io:format("Peer Cost: ~w ~n Cost : ~w ~n", [PeerCost, Cost]),
    (((PeerCost - Cost)/Cost) * 100) < ?ACCEPT_PARAM.


