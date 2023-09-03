-module(aco_node).

-behaviour(gen_server).

%% things to implement
%% - aggiungere gli edge locali         
%% - far partire la sincronizzazione con i propri nodi e chiedere chi ha cosa, l'effetto deve essere
%%   che se sono il nodo A, prima della chiamata non so che nodo ha cosa, dopo lo so
%%   bisogna che ci sia una tabella nodo | nodo_aco


%% - algoritmo ACO 
%%     generare le formiche 
%%     mandare le formiche
%%     ricevere le formiche
%%     una volta ricevuta seguire l'automa
%%     elaborazione delle ant



-export([
        start/0,
        start_link/0,
        add_local_node/1,
        %  add_local_edges/1,
        %  start_exchanging_nodes/0,
        fetch_node/1,
        % add_resources/2,
        % add_resource/3,
        which_nodes_do_i_have/0,
        which_nodes_i_know/0
        ]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {local_nodes,          %% lista nodi che sono locali e che conosco
                local_edges,          %% lista edge che sono locali e che conosco
                found_nodes,          %% lista di nodi che so dove sono  
                parent}).             %% parent del nodo

-record(node, {name}).
-record(edge, {from, 
               to,
               weight}).

%% API

start_link() ->
    gen_server:start_link({local, aco_node}, ?MODULE, [], []).

add_local_node(Node=#node{}) -> 
    gen_server:cast(aco_node, {add_local_node, {Node, node()}}).
% %% From è node()
% add_local_resource(Node=#node{}, From) ->
%     gen_server:cast(aco_node, {add_local_node, {Node, From}}).

% add_local_edges(Edge=#edge{from=From, to=To, weight=Weight}) ->
%     gen_server:cast(aco_node, {add_local_edge, {Edge=#edge{from=From, to=To, weight=Weight}}}).

% add_local_resource_edge(Edge=#edge{}) ->
%     gen_server:cast(aco_node, {add_local_edge, {Edge}}).


start() ->
    gen_server:cast(aco_node, start).

% start_exchanging_nodes() ->
%     gen_server:cast(aco_node, start_exchanging_nodes).

fetch_node(Node=#node{}) ->
    gen_server:call(aco_node, {fetch_resources, Node}).

which_nodes_do_i_have() ->
    gen_server:call(aco_node, my_nodes).

which_nodes_i_know() ->
    gen_server:call(aco_node, my_found_nodes).

% % tabella 
% who_has_nodes() ->
%     gen_server:cast(aco_node, trade_resources).

%% Callbacks

init([]) ->
    {ok, #state{local_nodes = dict:new(),       
                local_edges = dict:new(),
                found_nodes = dict:new()}}.

handle_call({start, RemoteNodes, From}, _From, State) ->
    io:format("handle_call_start~n"),
    Parent = State#state.parent,
    MyGraphNodes = State#state.local_nodes,
    OldFound = State#state.found_nodes,
    OldPlusMyNodes = add_resources(dict:to_list(MyGraphNodes), OldFound),
    io:format("Where:~s~n", [From]),
    case Parent of
        undefined ->
            io:format("Parent = Undefined~n"),
            NewFound = add_resources(dict:to_list(RemoteNodes), OldFound),
            NewFoundPlusMyNodes = add_resources(dict:to_list(MyGraphNodes), NewFound),
            NewParent = From,
            AllNodesExceptParent = remove_parent(nodes(), NewParent),
            io:format("Before if~n"),
            if length(AllNodesExceptParent) > 0 ->
                io:format("Inside if~n"),
                gen_server:abcast(AllNodesExceptParent, aco_node, {start, MyGraphNodes, node()}),
                {reply, NewFoundPlusMyNodes, State#state{found_nodes=NewFoundPlusMyNodes, parent=NewParent}};
            true ->
                io:format("Else:~n"),
                {reply, NewFoundPlusMyNodes, State#state{found_nodes=NewFoundPlusMyNodes, parent=NewParent}}
            end;
        _ ->
            io:format("Parent WAS defined~n"),
            {reply, OldPlusMyNodes, State#state{}}
    end;

    % MyGraphNodes = State#state.local_nodes,
    % OldFound = State#state.found_nodes,
    % NewFound = add_resources(dict:to_list(MyGraphNodes), OldFound),
    % {reply, ok, State#state{parent=From, found_nodes=NewFound}};

handle_call({fetch_resources, Node=#node{}}, _From, State) ->
    {reply, dict:find(Node, State#state.found_nodes), State};

handle_call(my_nodes, _From, State) ->
    {reply, dict:to_list(State#state.local_nodes), State};

handle_call(my_found_nodes, _From, State) ->
    {reply, dict:to_list(State#state.found_nodes), State}.

handle_cast({start, RemoteNodes, From}, State) ->
    io:format("handle_call_start~n"),
    Parent = State#state.parent,
    MyGraphNodes = State#state.local_nodes,
    OldFound = State#state.found_nodes,
    OldPlusMyNodes = add_resources(dict:to_list(MyGraphNodes), OldFound),
    io:format("Where:~s~n", [From]),
    case Parent of
        undefined ->
            io:format("Parent = Undefined~n"),
            NewFound = add_resources(dict:to_list(RemoteNodes), OldFound),
            NewParent = From,
            AllNodesExceptParent = remove_parent(nodes(), NewParent),
            io:format("Before if~n"),
            if length(AllNodesExceptParent) > 0 ->
                io:format("Inside if~n"),
                gen_server:abcast(AllNodesExceptParent, aco_node, {start, MyGraphNodes, node()}),
                {noreply, State#state{found_nodes=NewFound, parent=NewParent}};
            true ->
                io:format("Else:~n"),
                {noreply, State#state{found_nodes=NewFound, parent=NewParent}}
            end;
        _ ->
            io:format("Parent WAS defined~n"),
            FromOtherNode = add_resources(dict:to_list(RemoteNodes), OldPlusMyNodes),
            {noreply, State#state{found_nodes=FromOtherNode}}
    end;

handle_cast(start, State) ->
    LocalNodes = State#state.local_nodes,
    {Replies, _} = gen_server:multi_call(nodes(), aco_node, {start, LocalNodes, node()}, 10*1000),
    NewFoundNodesFromReplies = add_resources(convert_replies_to_lists(Replies), State#state.found_nodes),
    {noreply, State#state{parent = node(), found_nodes=NewFoundNodesFromReplies}};

handle_cast({add_local_node, {Node=#node{}, From}}, State) ->
    LocalNodes = State#state.local_nodes,
    NewLocalNodes = add_resource(Node, From, LocalNodes),
    {noreply, State#state{local_nodes = NewLocalNodes}}.

% handle_cast({add_local_edge, {Edge=#edge{from=From, to=To, weight=Weight}}}, State) ->
%     LocalEdges = State#state.local_edges,
%     NewLocalEdges = add_resource_edge(Edge=#edge{from=From, to=To, weight=Weight}, LocalEdges),
%     {noreply, State#state{local_edges = NewLocalEdges}};

% handle_cast(start_exchanging_nodes, State) ->
%     MyGraphNodes = State#state.local_nodes,
%     AllNodes = [node() | nodes()],
%     lists:foreach(
%         fun(Node) ->
%             gen_server:cast({aco_node, Node},
%                             {start_exchanging_nodes, {node(), MyGraphNodes}})
%         end,
%         AllNodes),
%     {noreply, State};

% handle_cast({start_exchanging_nodes, {ReplyTo, OtherGraphNodes}}, 
%             State = #state{local_nodes = Locals, 
%                            found_nodes = OldFound}) ->
%     NewFound = add_resources(dict:to_list(OtherGraphNodes), OldFound),
%     case ReplyTo of
%         noreply -> ok;
%         _ -> gen_server:cast({aco_node, ReplyTo}, 
%                              {start_exchanging_nodes, {noreply, Locals}})
%         end,
%     {noreply, State#state{found_nodes = NewFound}}.

handle_info(ok = _Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%% Utilities

% add_resources_edge([Edge=#edge{} | T], Dict) ->
%     add_resource_edge(T, add_resource_edge(Edge, Dict)).

% add_resource_edge(Edge=#edge{from=From, to=To, weight=Weight}, Dict) ->
%     case dict:find(Edge, Dict) of
%         {ok, List} ->  
%             NewList = [From | lists:delete({From, To, Weight}, List)],
%             dict:store(Edge, NewList, Dict);
%         error ->
%             dict:store(Edge, [{From, To, Weight}, Dict])
%         end.

add_resources([{Node, Identifier}|T], Dict) ->
    add_resources(T, add_resource(Node, Identifier, Dict));
add_resources([], Dict) ->
    Dict.

add_resource(Node=#node{}, From, Dict) ->
    case dict:find(Node, Dict) of
        _ ->
            dict:store(Node, From, Dict)
    end.

remove_parent(List, Parent) ->
    lists:delete(Parent, List).


convert_replies_to_lists([{_, ReplyMsg}|T]) ->
    case ReplyMsg of
        ok -> convert_replies_to_lists(T);
        _ -> convert_replies_to_lists(T) ++ dict:to_list(ReplyMsg)
    end;
convert_replies_to_lists([]) -> [].

% resources_for_types(Types, ResourceTuples) ->
%     Fun =
%         fun(Type, Acc) ->
%             case dict:find(Type, ResourceTuples) of
%                 {ok, List} ->
%                     [{Type, Resource} || Resource <- List] ++ Acc;
%                 error ->
%                     Acc
%             end
%         end,
%     lists:foldl(Fun, [], Types).
