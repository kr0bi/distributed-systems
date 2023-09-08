-module(flooding).
-behaviour(gen_server).

%% API
-export([start/0, stop/1, start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3, write_graph_to_file/0]).
-record(state, {nodes, edges}).
-record(node, {name}).
-record(edge, {from, to, weight, tau}).


start() ->
   gen_server:start({global, ?MODULE}, ?MODULE, [], []).

start_link() ->
    {ok, Pid} = gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

stop(Name) ->
    gen_server:call(Name, stop).

init(_Args) ->
    {ok, #state{}}.

handle_call(stop, _From, State) ->
    {stop, normal, stopped, State};

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast({path, Path}, State) ->
    write_path_to_file(Path),
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% Writes a graph to file
write_graph_to_file() ->
    {Nodes, Edges} = get_graph_data(),
    io:format("Edges: ~w~n", [Edges]),
    io:format("Nodes: ~w~n", [Nodes]),
    NodeXML = lists:flatten(xmerl:export_simple([{clients, Nodes}], xmerl_xml)),
    EdgesXML = lists:flatten(xmerl:export_simple([{routes, Edges}], xmerl_xml)),
    {ok,IOF}=file:open('graph.xml',[write]),
    io:format(IOF, "~s~n", [NodeXML]),
    io:format(IOF, "~s~n", [EdgesXML]),
    file:close(IOF).

write_path_to_file(Path) ->
    PathXML = lists:flatten(xmerl:export_simple(Path)),
    io:format("~s~n", [PathXML]).

%% Floods path and its relative cost to neighbour nodes
send_path_data(PathMsg) ->
    gen_server:abcast(flooding, nodes(), PathMsg).

get_graph_data() ->
    {NodeReplies, _} = gen_server:multi_call(aco_node, my_nodes),
    %io:format("~s~n", [Replies]),
    Nodes = get_nodes_from_replies(NodeReplies),
    %io:format("~s~n", Nodes),
    {EdgeReplies, _} = gen_server:multi_call(aco_node, my_edges),
    Edges = get_edges_from_replies(EdgeReplies),
    {Nodes, Edges}.

get_nodes_from_replies([]) ->
    [];
get_nodes_from_replies([{#node{name = ClientId}, _Node} | Replies]) ->
    %io:format("Appending ~s~n", [ClientId]),
    List = get_nodes_from_replies(Replies),
    %io:format("Appending ~s~n", [List]),
    lists:append([{client, [integer_to_list(ClientId)]}], List);
get_nodes_from_replies([{_, Replies} | Tail]) ->
    lists:append(get_nodes_from_replies(Replies), get_nodes_from_replies(Tail)).

get_edges_from_replies([]) ->
    [];
get_edges_from_replies([#edge{from = #node{name = To}, to = #node{name = From}, weight = Cost, tau = _} | Replies]) ->
    lists:append([{route, [{from, [integer_to_list(From)]}, {to, [integer_to_list(To)]}, {weight, [integer_to_list(Cost)]}]}], get_edges_from_replies(Replies));
get_edges_from_replies([{_, Replies} | Tail]) ->
    lists:append(get_edges_from_replies(Replies), get_edges_from_replies(Tail)).



