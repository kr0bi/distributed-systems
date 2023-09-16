-module(flooding).
-behaviour(gen_server).
-include_lib("xmerl/include/xmerl.hrl").


%% API
-export([start/0, stop/1, start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3, write_graph_to_file/0]).
-record(state, {nodes, edges}).
-record(node, {name}).
-record(edge, {from, to, weight, tau}).
-export([get_nodes_from_path/1, write_path_to_file/1]).


start() ->
   gen_server:start({global, ?MODULE}, ?MODULE, [], []).

start_link() ->
    {ok, Pid} = gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

stop(Name) ->
    gen_server:call(Name, stop).

init(_Args) ->
    {ok,IOF}=file:open('path.xml',[write]),
    io:format(IOF, "~s~n", ["<?xml version=\"1.0\"?><pathdata></pathdata>"]),
    %io:format("Path Init XML: ~s~n", ["<?xml version=\"1.0\"?><pathdata></pathdata>"]),
    file:close(IOF),
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
    GraphXML = lists:flatten(xmerl:export_simple([{clients, lists:append(Nodes, Edges)}], xmerl_xml)),
    {ok,IOF}=file:open('graph.xml',[write]),
    io:format(IOF, "~s~n", [GraphXML]),
    file:close(IOF).

write_path_to_file({Path, Cost}) ->
    case is_float(Cost) of 
        true -> CostXML = [{cost, [float_to_list(Cost)]}]; %% get path and cost as xmerl-ready lists
        false -> CostXML = [{cost, [integer_to_list(Cost)]}]
    end,
    PathXML = get_nodes_from_path(Path),

    {RootEl,_}=xmerl_scan:file('path.xml'), %% xml generation
    #xmlElement{content=Content} = RootEl,
    NewContent = Content ++ lists:flatten([{path, lists:append(PathXML, CostXML)}]),
    NewRootEl = RootEl#xmlElement{content=NewContent}, 
    Export = xmerl:export_simple([NewRootEl],xmerl_xml),

    {ok,IOF} = file:open('path.xml',[write]), %% write to file
    io:format(IOF,"~s~n",[lists:flatten(Export)]).

%% Floods path and its relative cost to neighbour nodes
send_path_data(PathMsg) ->
    gen_server:abcast(flooding, nodes(), PathMsg).

%% Receives graph data from the aco_nodes in the systems
get_graph_data() ->
    {NodeReplies, _} = gen_server:multi_call(aco_node, my_nodes),
    Nodes = get_nodes_from_replies(NodeReplies),
    {EdgeReplies, _} = gen_server:multi_call(aco_node, my_edges),
    Edges = get_edges_from_replies(EdgeReplies),
    {Nodes, Edges}.

get_nodes_from_path([])->
    [];
get_nodes_from_path([#node{name = ClientId} | Nodes]) ->
    List = get_nodes_from_path(Nodes),
    lists:append([{client, [integer_to_list(ClientId)]}], List).


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
    case is_float(Cost) of 
        true -> CostXML = float_to_list(Cost); %% get path and cost as xmerl-ready lists
        false -> CostXML = integer_to_list(Cost)
    end,
    lists:append([{route, [{from, [integer_to_list(From)]}, {to, [integer_to_list(To)]}, {weight, [CostXML]}]}], get_edges_from_replies(Replies));
get_edges_from_replies([{_, Replies} | Tail]) ->
    lists:append(get_edges_from_replies(Replies), get_edges_from_replies(Tail)).



