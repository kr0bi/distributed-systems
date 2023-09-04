-module(flooding).
-behaviour(gen_server).

%% API
-export([start/0, stop/1, start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-record(state, {nodes, edges}).
-record(node, {name}).
-record(edge, {from, to, cost}).


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
write_graph_to_file(Graph) ->
    {Nodes, Edges} = get_graph_data(),
    NodeXML = lists:flatten(xmerl:export_simple(Nodes, xmerl_xml)),
    EdgesXML = lists:flatten(xmerl:export_simple(Edges, xmerl_xml)),
    io:format("~s~n", [NodeXML]),
    io:format("~s~n", [EdgesXML]).

write_path_to_file(Path) ->
    PathXML = lists:flatten(xmerl:export_simple(Path)).

%% Floods path and its relative cost to neighbour nodes
send_path_data(PathMsg) ->
    gen_server:abcast(flooding, nodes(), PathMsg).

get_graph_data() ->
    {Replies, _} = gen_server:multi_call(aco_node, my_nodes),
    Nodes = get_nodes_from_replies(Replies),
    {Replies2, _} = gen_server:multi_call(aco_node, my_edges),
    Edges = get_edges_from_replies(Replies2),
    {Nodes, Edges}.

get_nodes_from_replies([]) ->
    [];
get_nodes_from_replies([{#node{name = ClientId} , _} | Replies]) ->
    lists:append([{node, ClientId}], get_nodes_from_replies(Replies)).

get_edges_from_replies([]) ->
    [];
get_edges_from_replies([{#edge{from = From, to = To, cost = Cost} , _} | Replies]) ->
    lists:append([{edge, [{from, From}, {to, To}, {weight, Cost}]}], get_edges_from_replies(Replies)).



