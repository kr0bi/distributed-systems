-module(aco_node).

-behaviour(gen_server).

-include("aco_node_constants.hrl").

%% - algoritmo ACO 
%%     generare le formiche / fatto
%%     mandare le formiche
%%     ricevere le formiche
%%     una volta ricevuta seguire l'automa
%%     elaborazione delle ant


-compile(export_all).

% -export([
%         start/0,
%         start_aco/1,
%         start_link/0,
%         add_local_node/1,
%         add_local_edges/1,
%         %  add_local_edges/1,
%         %  start_exchanging_nodes/0,
%         fetch_node/1,
%         % add_resources/2,
%         % add_resource/3,
%         which_nodes_do_i_have/0,
%         which_nodes_i_know/0,
%         which_edges_do_i_have/0,
%         what_s_the_best_path/0,
%         % filter_nodes/2,
%         % p/2
%         where_is_client/2
%         ]).

-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(SERVER, ?MODULE).

-record(state, {local_nodes,          %% lista nodi che sono locali e che conosco
                local_edges,          %% lista edge che sono locali e che conosco
                best_path,            %% best path trovato dalla formica
                best_cost,            %% best cost trovato dalla formica
                found_nodes,          %% lista di nodi che so dove sono  
                parent,               %% parent del nodo 
                current_ticket}).     %% ticket: valore intero che rappresenta le chiamate soddisfatte finora

-record(node, {name}).
-record(edge, {from, 
               to,
               weight,
               tau}).

-record(ant,    {cost_current_path, 
                pheromone_strength, 
                returning_flag, 
                best_tour_cost, 
                path}).


%% API

start_link() ->
    gen_server:start_link({local, aco_node}, ?MODULE, [], []).

add_local_node(Node=#node{}, Ticket) ->
    gen_server:call(aco_node, {add_local_node_ticket, {Node, node(), Ticket}}).

add_local_node(Node=#node{}) -> 
    gen_server:call(aco_node, {add_local_node, {Node, node()}}).

%% aggiungere un arco dal nodo utente
%% aggiunge l'arco a tutti e solamente chi ha almeno uno dei due nodi dell'arco se lo aggiunge localmente

add_local_edges(Edges) ->
    gen_server:multi_call([node()|nodes()], aco_node, {add_local_edges, Edges}, 10*1000).

% add_local_edges(Edge=#edge{from=From, to=To, weight=Weight}) ->
%     gen_server:cast(aco_node, {add_local_edge, {Edge=#edge{from=From, to=To, weight=Weight}}}).

% add_local_resource_edge(Edge=#edge{}) ->
%     gen_server:cast(aco_node, {add_local_edge, {Edge}}).


start() ->
    gen_server:call(aco_node, start).

% start_exchanging_nodes() ->
%     gen_server:cast(aco_node, start_exchanging_nodes).

fetch_node(Node=#node{}) ->
    gen_server:call(aco_node, {fetch_resources, Node}).

which_nodes_do_i_have() ->
    gen_server:call(aco_node, my_nodes).

which_edges_do_i_have() ->
    gen_server:call(aco_node, my_edges).

which_nodes_i_know() ->
    gen_server:call(aco_node, my_found_nodes).

what_s_the_best_path() ->
    gen_server:call(aco_node, path).

start_aco(Amount) ->
    gen_server:call(aco_node, start),
    gen_server:abcast([node()|nodes()], aco_node, {start_aco, Amount}).

remove_node(Node) ->
    gen_server:multi_call(aco_node, {remove_node_ticket, Node, 0}).

%% Callbacks

init([]) ->
    {ok, #state{local_nodes = dict:new(),       
                local_edges = sets:new(),
                found_nodes = dict:new(),
                best_path = [],
                best_cost = ?WORST_COST,
                current_ticket = 0}}.

handle_call(start, _From, State) ->
    LocalNodes = State#state.local_nodes,
    {Replies, _} = gen_server:multi_call(nodes(), aco_node, {start, LocalNodes, node()}, 10*1000),
    NewFoundNodesFromReplies = add_resources(convert_replies_to_lists(Replies), State#state.found_nodes),
    {reply, success, State#state{parent = node(), found_nodes=NewFoundNodesFromReplies}};


handle_call({start, RemoteNodes, From}, _From, State) ->
    % io:format("handle_call_start~n"),
    Parent = State#state.parent,
    MyGraphNodes = State#state.local_nodes,
    OldFound = State#state.found_nodes,
    OldPlusMyNodes = add_resources(dict:to_list(MyGraphNodes), OldFound),
    % io:format("Where:~s~n", [From]),
    case Parent of
        undefined ->
            % io:format("Parent = Undefined~n"),
            NewFound = add_resources(dict:to_list(RemoteNodes), OldFound),
            NewFoundPlusMyNodes = add_resources(dict:to_list(MyGraphNodes), NewFound),
            NewParent = From,
            AllNodesExceptParent = remove_parent(nodes(), NewParent),
            % io:format("Before if~n"),
            if length(AllNodesExceptParent) > 0 ->
                % io:format("Inside if~n"),
                gen_server:abcast(AllNodesExceptParent, aco_node, {start, MyGraphNodes, node()}),
                {reply, NewFoundPlusMyNodes, State#state{found_nodes=NewFoundPlusMyNodes, parent=NewParent}};
            true ->
                % io:format("Else:~n"),
                {reply, NewFoundPlusMyNodes, State#state{found_nodes=NewFoundPlusMyNodes, parent=NewParent}}
            end;
        _ ->
            % io:format("Parent WAS defined~n"),
            {reply, OldPlusMyNodes, State#state{}}
    end;

handle_call({add_local_node_ticket, {Node=#node{}, From, Ticket}}, _From, State) ->
    case State#state.current_ticket == Ticket of 
        true -> 
            LocalNodes = State#state.local_nodes,
            NewLocalNodes = add_resource(Node, From, LocalNodes),
            {reply, {success, Ticket}, State#state{local_nodes = NewLocalNodes}};
        false -> 
            case State#state.current_ticket < Ticket of
                true ->
                    gen_server:cast(aco_node, {add_local_node_ticket, {Node, From, Ticket, _From}}),
                    {noreply, State#state{}};
                false ->
                    {reply, {failure, Ticket}, State#state{}}
            end
    end;


handle_call({add_local_node, {Node=#node{}, From}}, _From, State) ->
    LocalNodes = State#state.local_nodes,
    NewLocalNodes = add_resource(Node, From, LocalNodes),
    {reply, ok, State#state{local_nodes = NewLocalNodes}};


handle_call({remove_node_ticket, Node=#node{}, Ticket}, _From, State) ->
    case Ticket == State#state.current_ticket of
        true -> 
            LocalNode = State#state.local_nodes,
            RemoteNodes = State#state.found_nodes,
            NewLocalNodes = dict:erase(Node, LocalNode),
            NewFoundNodes = dict:erase(Node, RemoteNodes),
            LocalEdges = State#state.local_edges,
            NewLocalEdges = sets:from_list(remove_edges(Node, sets:to_list(LocalEdges))),
            {reply, {success, Ticket}, State#state{local_nodes = NewLocalNodes, local_edges = NewLocalEdges, found_nodes=NewFoundNodes, best_cost=?WORST_COST, best_path=[]}};
        false ->
            case Ticket > State#state.current_ticket of
                true ->
                    gen_server:cast(aco_node, {remove_node_ticket, Node, Ticket, _From}),
                    {noreply, State#state{}};
                false ->
                    {reply, {failure, Ticket}, State#state{}}
            end
    end;

handle_call({update_edges, Edges, Ticket}, _From, State) ->
    case Ticket == State#state.current_ticket of
        true ->
            LocalEdges = State#state.local_edges,
            NewLocalEdges = sets:from_list(update_edges(sets:to_list(Edges), sets:to_list(LocalEdges))),
            {reply, {success, Ticket}, State#state{local_edges = NewLocalEdges, current_ticket = Ticket + 1, best_cost=?WORST_COST, best_path=[]}};
        false ->
            case Ticket > State#state.current_ticket of 
                true ->
                    gen_server:cast(aco_node, {update_edges, {Edges, Ticket, _From}}),
                    {noreply, State#state{}};
                false ->
                    {reply, {failure, Ticket}, State#state{}}
                end
        end;

handle_call({add_local_edges_ticket, {Edges, Ticket}}, _From, State) ->
    case State#state.current_ticket == Ticket of 
        true -> 
            My_Nodes = State#state.local_nodes,
            My_Edges = State#state.local_edges,
            New_Edges = add_edges(find_new_edges(My_Nodes, Edges, []), My_Edges),
            {reply, {success, Ticket}, State#state{local_edges=New_Edges, current_ticket=Ticket + 1}};
        false ->
            case State#state.current_ticket < Ticket of
                true -> 
                    gen_server:cast(aco_node, {add_local_edges_ticket, {Edges, Ticket, _From}}),
                    {noreply, State#state{}};
                false ->
                    {reply, {failure, Ticket}, State#state{}}
            end
    end;
    
handle_call({add_local_edges, Edges}, _From, State) ->
    My_Nodes = State#state.local_nodes,
    My_Edges = State#state.local_edges,
    New_Edges = add_edges(find_new_edges(My_Nodes, Edges, []), My_Edges),
    {reply, ok, State#state{local_edges=New_Edges}};

handle_call({fetch_resources, Node=#node{}}, _From, State) ->
    {reply, dict:find(Node, State#state.found_nodes), State};

handle_call(my_nodes, _From, State) ->
    {reply, dict:to_list(State#state.local_nodes), State};

handle_call(my_edges, _From, State) ->
    {reply, sets:to_list(State#state.local_edges), State};

handle_call(my_found_nodes, _From, State) ->
    {reply, dict:to_list(State#state.found_nodes), State};

handle_call(path, _From, State) ->
    {reply, {State#state.best_path, State#state.best_cost}, State};

handle_call(ticket_counter, _From, State) ->
    {reply, {ticket_counter, State#state.current_ticket}, State};

handle_call({update_ticket, Ticket}, _From, State) ->
    case Ticket == State#state.current_ticket of
        true ->
            {reply, {success, Ticket}, State#state{current_ticket=Ticket + 1}};
        false ->
            case Ticket > State#state.current_ticket of 
                true ->
                    gen_server:cast(aco_node, {update_ticket, {Ticket, _From}}),
                    {noreply, State#state{}};
                false ->
                    {reply, {failure, Ticket}, State#state{}}
                end
        end.

handle_cast({update_ticket, Ticket, _From}, State) ->
    case State#state.current_ticket == Ticket of 
        true -> 
            gen_server:reply(_From, {success, Ticket}),
            {noreply, State#state{current_ticket=Ticket + 1}};
        false -> 
            case State#state.current_ticket < Ticket of
                true ->
                    gen_server:cast(aco_node, {update_ticket, {Ticket, _From}}),
                    {noreply, State#state{}};
                false ->
                    gen_server:reply(_From, {failure, Ticket}),
                    {noreply, State#state{}}
            end
    end;

handle_cast({add_local_node_ticket, {Node=#node{}, From, Ticket, _From}}, State) ->
    case State#state.current_ticket == Ticket of 
        true -> 
            gen_server:call(aco_node, {add_local_node, {Node, node()}}),
            gen_server:reply(_From, {success, Ticket}),
            {noreply, State};
        false -> 
            case State#state.current_ticket < Ticket of
                true ->
                    gen_server:cast(aco_node, {add_local_node_ticket, {Node, From, Ticket, _From}}),
                    {noreply, State#state{}};
                false ->
                    gen_server:reply(_From, {failure, Ticket}),
                    {noreply, State#state{}}
            end
    end;

handle_cast({add_local_edges_ticket, {Edges, Ticket, _From}}, State) ->
    case State#state.current_ticket == Ticket of 
        true -> 
            My_Nodes = State#state.local_nodes,
            My_Edges = State#state.local_edges,
            New_Edges = add_edges(find_new_edges(My_Nodes, Edges, []), My_Edges),
            gen_server:reply(_From, {success, Ticket}),
            {noreply, State#state{local_edges=New_Edges, current_ticket=Ticket + 1}};
        false -> 
            case State#state.current_ticket < Ticket of
                true ->
                    gen_server:cast(aco_node, {add_local_edges_ticket, {Edges, Ticket, _From}}),
                    {noreply, State#state{}};
                false ->
                    gen_server:reply(_From, {failure, Ticket}),
                    {noreply, State#state{}}
            end
    end;

handle_cast({remove_node_ticket, Node=#node{}, Ticket, _From}, State) ->
    case Ticket == State#state.current_ticket of
        true -> 
            LocalNode = State#state.local_nodes,
            RemoteNodes = State#state.found_nodes,
            NewLocalNodes = dict:erase(Node, LocalNode),
            NewFoundNodes = dict:erase(Node, RemoteNodes),
            LocalEdges = State#state.local_edges,
            NewLocalEdges = sets:from_list(remove_edges(Node, sets:to_list(LocalEdges))),
            gen_server:reply(_From, {success, Ticket}),
            {noreply, State#state{local_nodes = NewLocalNodes, local_edges = NewLocalEdges, found_nodes=NewFoundNodes, best_cost=?WORST_COST, best_path=[]}};
        false ->
            case Ticket > State#state.current_ticket of
                true ->
                    gen_server:cast(aco_node, {remove_node_ticket, Node, Ticket, _From}),
                    {noreply, State#state{}};
                false ->                                        
                    gen_server:reply(_From, {failure, Ticket}),
                    {reply, State#state{}}
            end
    end;

handle_cast({update_edges, Edges, Ticket, _From}, State) ->
    case Ticket == State#state.current_ticket of
        true ->
            LocalEdges = State#state.local_edges,
            NewLocalEdges = sets:from_list(update_edges(sets:to_list(Edges), sets:to_list(LocalEdges))),
            gen_server:reply(_From, {success, Ticket}),
            {noreply, State#state{local_edges = NewLocalEdges, current_ticket = Ticket + 1, best_cost=?WORST_COST, best_path=[]}};
        false ->
            case Ticket > State#state.current_ticket of 
                true ->
                    gen_server:cast(aco_node, {update_edges, {Edges, Ticket, _From}}),
                    {noreply, State#state{}};
                false ->
                    gen_server:reply(_From, {failure, Ticket}),
                    {reply, {failure, Ticket}, State#state{}}
                end
        end;


handle_cast({start, RemoteNodes, From}, State) ->
    % io:format("handle_call_start~n"),
    Parent = State#state.parent,
    MyGraphNodes = State#state.local_nodes,
    OldFound = State#state.found_nodes,
    OldPlusMyNodes = add_resources(dict:to_list(MyGraphNodes), OldFound),
    % io:format("Where:~s~n", [From]),
    case Parent of
        undefined ->
            % io:format("Parent = Undefined~n"),
            NewFound = add_resources(dict:to_list(RemoteNodes), OldFound),
            NewParent = From,
            AllNodesExceptParent = remove_parent(nodes(), NewParent),
            % io:format("Before if~n"),
            if length(AllNodesExceptParent) > 0 ->
                % io:format("Inside if~n"),
                gen_server:abcast(AllNodesExceptParent, aco_node, {start, MyGraphNodes, node()}),
                {noreply, State#state{found_nodes=NewFound, parent=NewParent}};
            true ->
                % io:format("Else:~n"),
                {noreply, State#state{found_nodes=NewFound, parent=NewParent}}
            end;
        _ ->
            % io:format("Parent WAS defined~n"),
            FromOtherNode = add_resources(dict:to_list(RemoteNodes), OldPlusMyNodes),
            {noreply, State#state{found_nodes=FromOtherNode}}
    end;

handle_cast({start_aco, Amount}, State) ->
    Local_Nodes = State#state.local_nodes,
    lists:foreach(
        fun({Node=#node{}, AcoNodeFrom}) ->
            Ants = ant_colony:generate_ants(Amount, Node),
            Edges = find_new_edges(dict:store(Node, AcoNodeFrom, dict:new()), sets:to_list(State#state.local_edges), []),        %% voglio solo gli edges che sono interessati al node
            OtherNodes = filter_nodes(dict:to_list(State#state.found_nodes), Edges),
            lists:foreach(
                fun(Ant) ->
                    {Edge, Best_Neighbour} = ant_colony:get_best_neighbour(Node, Edges, ?ALPHA, ?BETA),
                    AcoNode = where_is_client(Best_Neighbour, dict:from_list(OtherNodes)),
                    gen_server:cast({aco_node, AcoNode}, {receive_ant, Ant, Node, Best_Neighbour, Edge})
                end,
                Ants)
            end,
            dict:to_list(Local_Nodes)),
    {noreply, State};

handle_cast({new_ant, From}, State) ->
    NewAnt = #ant{cost_current_path=0, 
                pheromone_strength=0, 
                returning_flag=walking, 
                best_tour_cost=?WORST_COST,
                path=[From]},
    Edges = find_new_edges(dict:store(From, node(), dict:new()), 
                           sets:to_list(State#state.local_edges), []),        %% voglio solo gli edges che sono interessati al node
    OtherNodes = filter_nodes(dict:to_list(State#state.found_nodes), Edges),
    {Edge, Best_Neighbour} = ant_colony:get_best_neighbour(From, Edges, ?ALPHA, ?BETA),
    AcoNode = where_is_client(Best_Neighbour, dict:from_list(OtherNodes)),
    gen_server:cast({aco_node, AcoNode}, {receive_ant, NewAnt, From, Best_Neighbour, Edge}),
    {noreply, State};

handle_cast({receive_ant, Ant=#ant{}, _From, To=#node{}, ByEdge=#edge{}}, State) ->
    Ant_elaborated = ant_colony:elaborate_ant(Ant, To, ByEdge),       
    OtherNodes = State#state.found_nodes,                                  %% aggiorno da dove proviene la ant
    case Ant#ant.returning_flag of
        returning -> case ant_colony:is_returned(Ant_elaborated) of                     %% la formica ha completato il suo ciclo due volte e il suo path e' vuoto
                        true -> 
                            NewAnt = ant_colony:reset_ant(Ant_elaborated, To),          %% passare l'ant elaborated potrebbe servire per aggiornare il best cost conosciuto
                            Edges = usable_edges(ant_colony:get_last_visited(NewAnt),
                                                 [],
                                                sets:to_list(State#state.local_edges)),
                            {Edge, Best_Neighbour} = ant_colony:get_best_neighbour(To, Edges, ?ALPHA, ?BETA),
                            AcoNode = where_is_client(Best_Neighbour, OtherNodes),                                 
                            NewEdge = ant_colony:pheromone_evaporation(Edge, ?TAU_ZERO, ?XI),        
                            gen_server:cast({aco_node, AcoNode}, {receive_ant, NewAnt, To, Best_Neighbour, NewEdge}),           
                            UpdatedEdges = sets:add_element(NewEdge, 
                                                            sets:del_element(Edge, State#state.local_edges)),               
                            {noreply, State#state{local_edges = UpdatedEdges}};                                                                
                        false -> 
                            Best_Neighbour = ant_colony:get_last_visited(Ant_elaborated),
                            {Response, Edge} = find_return_edge(To, Best_Neighbour, sets:to_list(State#state.local_edges)),
                            case Response of 
                                ok ->
                                    NewEdge = ant_colony:pheromone_evaporation(Edge, ant_colony:get_pheromone_strength(Ant_elaborated), ?RHO),
                                    UpdatedEdges = sets:add_element(NewEdge, 
                                                                        sets:del_element(Edge, State#state.local_edges)),
                                    NewEdge2 = ant_colony:pheromone_evaporation(NewEdge, ?TAU_ZERO, ?XI),               
                                    UpdatedEdges2 = sets:add_element(NewEdge2, 
                                                                    sets:del_element(NewEdge, UpdatedEdges)),   
                                    gen_server:cast({aco_node, where_is_client(Best_Neighbour, OtherNodes)}, 
                                                        {receive_ant, Ant_elaborated, To, Best_Neighbour, NewEdge2}),

                                    C = State#state.best_cost,
                                    case Ant_elaborated#ant.best_tour_cost < C of
                                        true -> {noreply, State#state{best_cost = Ant_elaborated#ant.best_tour_cost, 
                                                                    local_edges = UpdatedEdges2}};
                                        false ->  {noreply, State#state{local_edges = UpdatedEdges2}}
                                    end;
                                error ->
                                    {NewNode, AcoNode} = random_pick_from_other_nodes(dict:to_list(OtherNodes)),     %% nodo client 
                                    gen_server:cast({aco_node, AcoNode}, 
                                        {new_ant, NewNode}),
                                    {noreply, State#state{}}
                                end             
                    end;
        walking -> 
            case ant_colony:is_tour_complete(Ant_elaborated) of                                     %% la formica ha completato il suo ciclo una sola volta e il suo path contiene come primo e ultimo elemento uguali
                        true ->                             
                            UpdatedAnt = ant_colony:set_ant_flag(Ant_elaborated, returning),
                            A = ant_colony:deposit_pheromones(                                       %% quando deposita i feromoni, aggiorna i suoi costi la formica
                                        ant_colony:remove_last_visited_node(UpdatedAnt)),            %% sto finendo i nomi delle ant, aggiorno anche la forza dei feromoni
                            Best_Neighbour = ant_colony:get_last_visited(A),
                            {Response, Edge} = find_return_edge(To, Best_Neighbour, sets:to_list(State#state.local_edges)),
                            case Response of 
                                ok ->
                                    NewEdge = ant_colony:pheromone_evaporation(Edge, ant_colony:get_pheromone_strength(A), ?RHO),
                                    UpdatedEdges = sets:add_element(NewEdge, 
                                                                        sets:del_element(Edge, State#state.local_edges)),               %% calcolo l'evaporazione dell'edge e rimuovo il vecchio edge
                                    % io:format("Visitato tutte le citta', sto tornando, cost: ~w~n", [A#ant.cost_current_path]),
                                    % io:format("Visitato tutte le citta', sto tornando, cost: ~w~n", [A#ant.cost_current_path]),
                                    gen_server:cast({aco_node, where_is_client(Best_Neighbour, OtherNodes)}, 
                                                        {receive_ant, A, To, Best_Neighbour, NewEdge}),
                                    
                                    C = State#state.best_cost,
                                    case A#ant.best_tour_cost < C of
                                        true -> 
                                            gen_server:abcast(nodes(), flooding, {path, {A#ant.path, A#ant.best_tour_cost}}),
                                            {noreply, State#state{best_path= A#ant.path, 
                                            best_cost = A#ant.best_tour_cost, local_edges = UpdatedEdges}};
                                        false ->  {noreply, State#state{local_edges = UpdatedEdges}}
                                    end;
                                error ->
                                    {NewNode, AcoNode} = random_pick_from_other_nodes(dict:to_list(OtherNodes)),     %% nodo client 
                                    gen_server:cast({aco_node, AcoNode}, 
                                        {new_ant, NewNode}),
                                    {noreply, State#state{}}
                                end;             
                        false -> 
                            UpdatedAnt = Ant_elaborated,                                        %% aggiorno da dove proviene la ant
                            L = lists:delete(To, UpdatedAnt#ant.path),
                            Edges = usable_edges(ant_colony:get_last_visited(UpdatedAnt),
                                                 L,
                                                sets:to_list(State#state.local_edges)),                                                                 %% calcolo gli edges possibili dove si puo' spostare la formica senza tornare in un nodo gia' visitato
                            if length(Edges) > 0 ->
                                {Edge, Best_Neighbour} = ant_colony:get_best_neighbour(To, Edges, ?ALPHA, ?BETA),   %% nuovo neighbour + edge usato
                                AcoNode = where_is_client(Best_Neighbour, OtherNodes),                                          %% computo dove si trova il cliente nei nodi aco
                                gen_server:cast({aco_node, AcoNode}, {receive_ant, UpdatedAnt, To, Best_Neighbour, Edge}),           %% invio la formica
                                NewEdge = ant_colony:pheromone_evaporation(Edge, ?TAU_ZERO, ?XI),
                                UpdatedEdges = sets:add_element(NewEdge, 
                                                                sets:del_element(Edge, State#state.local_edges)),               %% calcolo l'evaporazione dell'edge e rimuovo il vecchio edge
                                {noreply, State#state{local_edges = UpdatedEdges}};                                              %% aggiorno l'edge                             
                            true -> 
                                Best_Neighbour = ant_colony:get_anthill(UpdatedAnt),
                                {Response, Edge} = find_return_edge(To, Best_Neighbour, sets:to_list(State#state.local_edges)),
                                case Response of 
                                    ok -> 
                                        NewEdge = ant_colony:pheromone_evaporation(Edge, ?TAU_ZERO, ?XI),
                                        UpdatedEdges = sets:add_element(NewEdge, 
                                                                        sets:del_element(Edge, State#state.local_edges)),               %% calcolo l'evaporazione dell'edge e rimuovo il vecchio edge
                                        gen_server:cast({aco_node, where_is_client(Best_Neighbour, OtherNodes)}, 
                                                        {receive_ant, UpdatedAnt, To, Best_Neighbour, NewEdge}),
                                        {noreply, State#state{local_edges = UpdatedEdges}};                                     %% aggiorno l'edge  
                                    error ->
                                        {NewNode, AcoNode} = random_pick_from_other_nodes(dict:to_list(OtherNodes)),     %% nodo client 
                                        gen_server:cast({aco_node, AcoNode}, 
                                            {new_ant, NewNode}),
                                        {noreply, State#state{}}
                                end
                            end
                    end
    end.


handle_info(ok = _Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%% Utilities

%% aggiunge una entry ad un dictionary, che sia un nodo o un edge e' indifferente
add_resources([{Resource, From}|T], Dict) ->
    add_resources(T, add_resource(Resource, From, Dict));
add_resources([], Dict) ->
    Dict.

add_resource(Resource, From, Dict) ->
    dict:store(Resource, From, Dict).

add_edges([E|T], Set) ->
    add_edges(T, add_edge(E, Set));
add_edges([], Set) -> Set.

add_edge(#edge{from=From, to=To, weight=Weight}, Set) ->
    NewE = #edge{from=From, to=To, weight=Weight, tau=?TAU_ZERO},
    sets:add_element(NewE, Set).

remove_parent(List, Parent) ->
    lists:delete(Parent, List).

convert_replies_to_lists([{_, ReplyMsg}|T]) ->
    case ReplyMsg of
        ok -> convert_replies_to_lists(T);
        _ -> convert_replies_to_lists(T) ++ dict:to_list(ReplyMsg)
    end;
convert_replies_to_lists([]) -> [].

find_new_edges(My_Nodes, [E=#edge{from=From, to=To}|T], Acc) ->
    case dict:find(From, My_Nodes) of 
        {ok, _} -> 
            find_new_edges(My_Nodes, T, Acc ++ [E]);
        _ ->
            case dict:find(To, My_Nodes) of
                {ok, _} ->
                    find_new_edges(My_Nodes, T, Acc ++ [E]);
                _ ->
                    find_new_edges(My_Nodes, T, Acc)
            end
        end;

find_new_edges(_, [] , Acc) -> Acc.

where_is_client(Client, AcoNodes) ->
    case dict:find(Client, AcoNodes) of
        {ok, Where} ->
            Where;
        _ ->
            io:format("Client: ~w~n AcoNodes: ~w~n", [Client, AcoNodes]),
            throw("error: client cannot be found in this aco node")
        end.

filter_nodes(Nodes=[{#node{},_From} | _], Edges) ->
    lists:filter(
        fun(Node) ->
            p(Node, Edges)
            end
        ,Nodes).

p({Node=#node{}, _From}, [#edge{from=From, to=To} | Edges]) -> 
    if (Node == From) or (Node == To) ->
        true;
    true ->
        p({Node, _From}, Edges)
    end;

p(_, []) -> false.

find_return_edge(From, To, [Edge=#edge{}|T]) ->
    case ((From == Edge#edge.from) and (To == Edge#edge.to)) or
         ((From == Edge#edge.to) and (To == Edge#edge.from)) of
        true -> {ok, Edge};
        _ -> find_return_edge(From, To, T)
    end;

%% genero una formica e la mando 
find_return_edge(_, _, []) ->
    {error, #edge{}}.


exclude_edges_from_nodes([], EdgeList) ->
  EdgeList;
                 
exclude_edges_from_nodes([Node | Nodes], EdgeList) ->
  NewEdgeList = exclude_edges_from_node(Node, EdgeList),
  exclude_edges_from_nodes(Nodes, NewEdgeList).
  
  
exclude_edges_from_node(_, []) ->
  [];  
exclude_edges_from_node(Node, [Edge = #edge{from=From, to=To} | Edges]) ->
  case ((Node == From) or (Node == To)) of 
    true ->
      exclude_edges_from_node(Node, Edges);
    false ->
      exclude_edges_from_node(Node, Edges) ++ [Edge]
  end.

usable_edges(CurrentNode, NodeList, EdgeList) ->
  NewEdgeList = lists:filter(
                    fun(#edge{from=From, to=To}) ->
                        ((From == CurrentNode) or (To == CurrentNode)) 
                        end
                , EdgeList),
  exclude_edges_from_nodes(NodeList, NewEdgeList).

remove_edges(Node, Edges) ->
    remove_edges(Node, Edges, []).

remove_edges(Node, [Edge|Edges], Acc) ->
    if (Edge#edge.from == Node) or (Edge#edge.to == Node) ->
        remove_edges(Node, Edges, Acc);
    true ->
        remove_edges(Node, Edges, Acc ++ [Edge])
    end;

remove_edges(_, [], Acc) -> Acc.

% per ogni arco da modificare, 
% - controllare dove sta in LocalEdges
% - andare a modificare il peso 
% - resettare il tau
% - iterare per tutti gli edges rimasti
update_edges([Edge|Edges], LocalEdges) ->
    L = lists:sort(LocalEdges),
    update_edges(Edges, update_edge(Edge, L, L));

update_edges([], LocalEdges) -> LocalEdges.

update_edge(Edge=#edge{from=F, to=T, weight=W}, [CE|NE], L) ->
    if (F == CE#edge.from) and (T == CE#edge.to) ->
        lists:delete(CE, L) ++ [#edge{from=F, to=T, weight=W, tau=?TAU_ZERO}];
    true ->
        update_edge(Edge, NE, L)
    end.

random_pick_from_other_nodes(Nodes) ->  %% lista di nodi
    _ = crypto:rand_seed(),
    Length = length(Nodes),
    R = rand:uniform(Length),
    lists:nth(R, Nodes).