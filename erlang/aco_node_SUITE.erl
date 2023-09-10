-module(aco_node_SUITE).
-include_lib("common_test/include/ct.hrl").
-export([all/0, groups/0, init_per_group/2, end_per_group/2, init_per_testcase/2]).
-export([test1/1]).
-export([init_add_nodes/2, write_to_file/0]).
-record(node, {name}).
-record(edge, {from, 
               to,
               weight,
               tau}).

groups() -> [{session,
              [sequence],
              [{group, aco_nodes}]},
             {aco_nodes,
              [parallel],
              [test1]}].

all() -> [{group, session}].

init_per_suite(Config) ->
    aco_node:start_link(),
    case net_adm:ping('graphdil@DESKTOP-QC52HG2.localdomain') of 
        pong ->
            io:format("Successfully pinged graphdil ~n"),
            ok;
        pang ->
            {failed, noping}
    end.

init_per_group(aco_nodes, _Config) ->
    aco_node:start_link(),
    case net_adm:ping('graphdil@DESKTOP-QC52HG2.localdomain') of 
        pong ->
            io:format("Successfully pinged graphdil ~n"),
            ok;
        pang ->
            {failed, noping}
    end;
init_per_group(_, _Config) ->
    ok.

init_add_nodes(Peer, [Node | []]) ->
    peer:call(Peer, aco_node, add_local_node, [#node{name=Node}]);
init_add_nodes(Peer, [Node | Nodes]) ->
    peer:call(Peer, aco_node, add_local_node, [#node{name=Node}]),
    init_add_nodes(Peer, Nodes).

end_per_group(aco_nodes, _Config) ->
    ok;
end_per_group(_, _Config) ->
    ok.

init_per_testcase(_, Config) ->
    Config.

end_per_testcase(_, _Config) ->
    ok.

test1(_Config) ->
    {ok, Dil1, Node1} = ?CT_PEER(#{connection => standard_io}),
    {ok, Dil2, Node2} = ?CT_PEER(#{connection => standard_io}),
    {ok, Dil3, Node3} = ?CT_PEER(#{connection => standard_io}),
    {ok, Dil4, _} = ?CT_PEER(#{connection => standard_io}),

    peer:call(Dil4, net_adm, ping, [Node1]),
    peer:call(Dil4, net_adm, ping, [Node2]),
    peer:call(Dil4, net_adm, ping, [Node3]),

    io:format("Dil init nodes: ~w~n", [peer:call(Dil4, erlang, nodes, [])]),

    aco_test(Dil1, [1,2,3], [{1,2,3}, {1,4,5}, {1,8,4}]),
    aco_test(Dil2, [4,5,6], [{4,5,3}, {1,4,5}, {5,8,4}]),
    aco_test(Dil3, [7,8], [{7,8,3}, {1,8,5}, {5,8,4}]),
    peer:call(Dil4, aco_node_SUITE, write_to_file, []).



aco_test(Peer, NodeList, EdgeList) ->
    peer:call(Peer, aco_node, start_link, []),
    init_add_nodes(Peer, NodeList),
    Edges = test_get_edges(EdgeList),
    {Replies, _} = peer:call(Peer, aco_node,add_local_edges, [Edges]),
    peer:call(Peer, aco_node, which_edges_do_i_have, []),
    Reply_Nodes = peer:call(Peer, aco_node, which_nodes_do_i_have, []),
    print_Replies(Replies),
    Nn = lists:sort(get_nodes(Reply_Nodes)),
    case lists:sort(NodeList) == Nn of
        false -> io:format("NodeList: ~w~n", [NodeList]),
                io:format("NodeReplies: ~w~n", [Nn]),
                {failed, nomatch};
        true -> ok
    end.

get_nodes([]) ->
    [];
get_nodes([{#node{name = ClientId}, _Node} | Replies]) ->
    List = get_nodes(Replies),
    lists:append([ClientId], List).

print_Replies([]) ->
    done;
print_Replies([Reply | Replies]) ->
    io:format("~w~n", [Reply]),
    print_Replies(Replies).

test_get_edges([]) ->
    [];
test_get_edges([{From, To, Cost} | Edges]) ->
    lists:append([#edge{from=From, to=To, weight=Cost, tau=undefined}], test_get_edges(Edges)).

write_to_file() ->
    timer:sleep(50),
    case nodes() == [] of
        true ->
            {failed, nonodes};
        false ->
            case write_graph_to_file() of
                ok ->
                    ok;
                {failed, noreplies} ->
                    {failed, noreplies};
                _ ->
                    {failed, unexpected}
            end
    end.
    
    
    

write_graph_to_file() ->
    Result = {Nodes, Edges} = get_graph_data(),
    case Result of
        {failed, _} ->
            {failed, noreplies};
        {Nodes, Edges} ->
            io:format("Edges: ~w~n", [Edges]),
            io:format("Nodes: ~w~n", [Nodes]),
            GraphXML = lists:flatten(xmerl:export_simple([{clients, lists:append(Nodes, Edges)}], xmerl_xml)),
            {ok,IOF}=file:open('graph.xml',[write]),
            io:format(IOF, "~s~n", [GraphXML]),
            file:close(IOF),
            ok
    end.

%% Receives graph data from the aco_nodes in the systems
get_graph_data() ->
    case nodes() of 
        [] ->
            {failed, nonodes};
        _ ->
                {NodeReplies, _} = gen_server:multi_call(aco_node, my_nodes),
                io:format("NodeReplies: ~w~n", [NodeReplies]),
                case NodeReplies of 
                    [] ->
                        {failed, nonodereplies};
                    _ ->
                        Nodes = get_nodes_from_replies(NodeReplies),
                        case Nodes of
                            [] ->
                                {failed, noreplies};
                            [_ | _] ->
                                {EdgeReplies, _} = gen_server:multi_call(aco_node, my_edges),
                                Edges = get_edges_from_replies(EdgeReplies),
                                {Nodes, Edges}
                        end
                end
        end.
            
       

%% Returns the list of nodes from the list of replies
get_nodes_from_replies([]) ->
    [];
get_nodes_from_replies([{#node{name = ClientId}, _Node} | Replies]) ->
    List = get_nodes_from_replies(Replies),
    lists:append([{client, [integer_to_list(ClientId)]}], List);
get_nodes_from_replies([{_, Replies} | Tail]) ->
    lists:append(get_nodes_from_replies(Replies), get_nodes_from_replies(Tail)).

%% Returns the list of edges from the list of replies
get_edges_from_replies([]) ->
    [];
get_edges_from_replies([#edge{from = #node{name = To}, to = #node{name = From}, weight = Cost, tau = _} | Replies]) ->
    lists:append([{route, [{from, [integer_to_list(From)]}, {to, [integer_to_list(To)]}, {weight, [integer_to_list(Cost)]}]}], get_edges_from_replies(Replies));
get_edges_from_replies([{_, Replies} | Tail]) ->
    lists:append(get_edges_from_replies(Replies), get_edges_from_replies(Tail)).
