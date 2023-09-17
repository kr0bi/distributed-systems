-module(aco_node).

-behaviour(gen_server).

-include("aco_node_constants.hrl").

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
                init_status,          %% initialization status
                init_counter,         %% initialization message counter
                current_ticket,       %% ticket: valore intero che rappresenta le chiamate soddisfatte finora
                ant_flag_counter}).   %% counter: int, partendo da 0        

-record(node, {name}).                %% nome in stringa del nodo
-record(edge, {from,                  %% nodo
               to,                    %% nodo
               weight,                %% valore numerico >= 0
               tau}).                 %% feromoni depositati nell'arco all'inizio, valore numerico >= 0     

-record(ant,    {cost_current_path,   %% valore numerico >=0
                pheromone_strength,   %% feromoni depositati dalla formica al ritorno da un path, valore numerico >=0
                returning_flag,       %% walking o returning
                best_tour_cost,       %% valore numerico >=0
                path,                 %% coda contenente: lista di nodi 
                complete_path}).      %% lista di nodi


%% API
%% start_link: avvia il gen_server 
start_link() ->
    gen_server:start_link({local, aco_node}, ?MODULE, [], []).

%% add_local_node: aggiunge un nodo in locale ad un certo nodo aco
add_local_node(Node=#node{}) -> 
    gen_server:call(aco_node, {add_local_node, {Node, node()}}).

%% add_local_edges: aggiunge una lista di archi a tutti i nodi aco
%% vengono aggiunti solamente gli archi che hanno almeno un nodo nella lista dei nodi locali
add_local_edges(Edges) ->
    gen_server:multi_call([node()|nodes()], aco_node, {add_local_edges, Edges}, 10*1000).

%% add_edges: aggiunge gli archi locali ad un certo nodo aco
add_edges(Edges) -> 
    gen_server:call(aco_node, {add_local_edges, Edges}, 10*1000).

%% which_nodes_do_i_have: restituisce la lista dei nodi locali
which_nodes_do_i_have() ->
    gen_server:call(aco_node, my_nodes).

%% which_edges_do_i_have: restituisce la lista degli archi locali
which_edges_do_i_have() ->
    gen_server:call(aco_node, my_edges).

%% which_nodes_i_know: restituisce la lista dei nodi conosciuti, consiste sia nei nodi locali che quelli remoti
which_nodes_i_know() ->
    gen_server:call(aco_node, my_found_nodes).

%% what_s_the_best_path: restituisce la lista dei nodi per il cammino minimo, 
%% conosciuta da questo nodo aco, quando una formica passa su esso
what_s_the_best_path() ->
    gen_server:call(aco_node, path, 25*1000).

%% start_aco: avvia l'algoritmo di inizializzazione e l'aco
start_aco(Amount) ->
    gen_server:call(aco_node, start),
    gen_server:abcast([node()|nodes()], aco_node, {start_aco, Amount}).

%% methods: debugging purposes
start() ->
    gen_server:call(aco_node, start).

%% rimuove un nodo remoto su tutti i nodi aco
remove_node(Node) ->
    gen_server:multi_call(aco_node, {remove_node_ticket, Node, 0}).

%% aggiorna gli archi su tutti i nodi aco
update_edges(Edges) ->
    gen_server:multi_call(aco_node, {update_edges, Edges, 0}).

%% nodo e lista di edges
%% aggiunge un nodo cliente e i suoi archi ad un sistema che ha gia' avviato l'aco
add_running_node(Node, Edges) ->
    gen_server:call(aco_node, {add_running_node, Node, Edges, 0}).

%% aggiunge un nodo aco con i suoi nodi clienti e archi GIA' aggiunti al sistema
%% quando il sistema è gia in esecuzione
running_init(Amount) ->
    gen_server:call(aco_node, {running_init}, 30*1000),
    gen_server:cast(aco_node, {start_aco, Amount}).

%% Callbacks

init([]) ->
    {ok, #state{local_nodes = dict:new(),       
                local_edges = sets:new(),
                found_nodes = dict:new(),
                best_path = [],
                best_cost = ?WORST_COST,
                current_ticket = 0,
                ant_flag_counter = 0,
                init_status = init,
                init_counter = 0}}.


%%% ----------------------------------
%%%     INIZIO DELLE HANDLE CALL
%%% ----------------------------------

%% avvio dello scambio di informazioni sui nodi locali di ogni nodo aco
handle_call(start, _From, State) ->
    LocalNodes = State#state.local_nodes,
    gen_server:abcast(nodes(), aco_node, {start, LocalNodes, node()}),
    {reply, success, State#state{parent = node()}};

%% aggiunta di un nodo locale e della sua provenienza ad un nodo aco tramite l'uso di ticket
%% From: nome del nodo aco
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

%% aggiunta di un nodo locale e della sua provenienza ad un nodo aco senza l'uso di ticket
%% From: nome del nodo aco
%% per uso di debugging o per aggiunte locali senza informare gli altri nodi
handle_call({add_local_node, {Node=#node{}, From}}, _From, State) ->
    LocalNodes = State#state.local_nodes,
    NewLocalNodes = add_resource(Node, From, LocalNodes),
    {reply, ok, State#state{local_nodes = NewLocalNodes}};

%% rimozione di un nodo cliente all'interno di un nodo aco con l'uso di ticket
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

%% aggiornamento degli archi presenti in un nodo aco tramite l'uso di ticket
%% vengono aggiornati solo gli archi che sono presenti in un certo nodo aco
%% modificandone il peso, non succede nulla se il peso è lo stesso
handle_call({update_edges, Edges, Ticket}, _From, State) ->
    case Ticket == State#state.current_ticket of
        true ->
            LocalEdges = State#state.local_edges,
            NewLocalEdges = sets:from_list(update_edges(Edges, sets:to_list(LocalEdges))),
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

%% aggiunta di una lista di archi locali tramite l'uso di ticket
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

%% aggiunta di una lista di archi locali senza l'uso di ticket
%% solo a scopi di debugging o per aggiunte senza informare altri nodi
%% da non utilizzare se il nodo è già connesso all'algoritmo aco in corso
handle_call({add_local_edges, Edges}, _From, State) ->
    My_Nodes = State#state.local_nodes,
    My_Edges = State#state.local_edges,
    New_Edges = add_edges(find_new_edges(My_Nodes, Edges, []), My_Edges),
    {reply, ok, State#state{local_edges=New_Edges}};

%% restituisce la lista di nodi locali
handle_call(my_nodes, _From, State) ->
    {reply, dict:to_list(State#state.local_nodes), State};

%% restituisce la lista di archi locali
handle_call(my_edges, _From, State) ->
    {reply, sets:to_list(State#state.local_edges), State};

%% restituisce la lista di nodi remoti e locali
handle_call(my_found_nodes, _From, State) ->
    {reply, dict:to_list(State#state.found_nodes), State};

%% restituisce la lista di nodi per il percorso minimo
handle_call(path, _From, State) ->
    {reply, {State#state.best_path, State#state.best_cost}, State};

%% restituisce il ticket corrente
handle_call(ticket_counter, _From, State) ->
    {reply, {ticket_counter, State#state.current_ticket}, State};

%% aggiunge un nodo cliente e la lista di archi associata ad un nodo aco tramite l'uso di ticket
handle_call({add_running_node, Node, Edges, Ticket}, _From, State) ->
    case Ticket == State#state.current_ticket of 
        true ->
            NewNodes = dict:store(Node, node(), State#state.local_nodes),
            NewEdges = add_edges(Edges, State#state.local_edges),
            NewOtherNodes = dict:store(Node, node(), State#state.found_nodes),
            gen_server:multi_call(nodes(), aco_node, {add_running_node_from, Node, node(), Edges, Ticket}, 10*1000),
            {reply, {success, Ticket}, State#state{local_nodes = NewNodes, local_edges = NewEdges, found_nodes = NewOtherNodes, best_cost=?WORST_COST, best_path=[]}};
        false ->
            case Ticket > State#state.current_ticket of
                true -> 
                    gen_server:cast(aco_node, {add_running_node, {Node, Edges, Ticket, _From}}),
                    {noreply, State};
                false ->
                    {reply, {failure, Ticket}, State}
            end
    end;

%% aggiunge un nodo cliente e la lista di archi associata ad un nodo aco tramite l'uso di ticket
%% viene usata solo tramite la call add_running_node filtrandone gli archi da aggiungere
handle_call({add_running_node_from, Node, From, Edges, Ticket}, _From, State) ->
    case Ticket == State#state.current_ticket of
        true ->
            NewOtherNodes = dict:store(Node, From, State#state.found_nodes),
            NewEdges = add_edges(filtered_edges(State#state.local_nodes, Edges, []), State#state.local_edges),
            {reply, {success, Ticket}, State#state{local_edges = NewEdges, found_nodes = NewOtherNodes, best_cost=?WORST_COST, best_path=[]}};
        false ->
            case Ticket > State#state.current_ticket of
                true ->
                    gen_server:cast(aco_node, {add_running_node_from, {Node, From, Edges, Ticket, _From}}),
                    {noreply, State};
                false ->
                    {reply, {failure, Ticket}, State}
            end
    end;

%% integra un nodo aco che contiene già dei nodi locali e archi locali aggiunti, SENZA avvisare altri nodi,
%% riceve dagli altri aco node la lista dei nodi locali presenti e successivamente
%% notificando gli altri nodi aco dei suoi nodi locali li aggiunge uno alla volta
handle_call({running_init}, _From, State) ->
    LocalNodes = State#state.local_nodes,
    LocalEdges = State#state.local_edges,
    {Replies, _} = gen_server:multi_call(nodes(), aco_node, my_nodes, 20*1000), %% Replies della forma {Nodo, Reply} -> Reply = {From, [nodes]}
    ListTuplesNode_Aco = convert_list_of_found_nodes_to_tuples_with_aco_nodes(Replies, []), 
    NewFoundNodesFromReplies = add_resources(dict:to_list(State#state.local_nodes), add_resources(ListTuplesNode_Aco, State#state.found_nodes)),
    %% ho aggiunto i nodi degli altri nei found
    add_running_nodes(dict:to_list(LocalNodes), sets:to_list(LocalEdges)),
    % {ok, _, Ticket} = ticket_system:request_ticket(),
    {reply, ok, State#state{local_nodes = LocalNodes, local_edges = LocalEdges, found_nodes=NewFoundNodesFromReplies,
                    best_cost = ?WORST_COST, best_path =[], init_status = done}};

%% aggiorna il ticket corrente
handle_call({update_ticket, Ticket}, _From, State) ->
    case Ticket == State#state.current_ticket of
        true ->
            {reply, {success, Ticket}, State#state{current_ticket=Ticket + 1}};
        false ->
            case Ticket > State#state.current_ticket of 
                true ->
                    gen_server:cast(aco_node, {update_ticket, Ticket, _From}),
                    {noreply, State#state{}};
                false ->
                    {reply, {failure, Ticket}, State#state{}}
                end
        end;

%% aggiorna di uno il valore del ticket 
handle_call({init_ticket, Ticket}, _From, State) ->
    {reply, ok, State#state{current_ticket=Ticket+1}}.

%%% ----------------------------------
%%%     INIZIO DELLE HANDLE CAST
%%% ----------------------------------

%% identico al call, solamente che viene usato quando il ticket non risulta up-to-date
handle_cast({update_ticket, Ticket, _From}, State) ->
    case State#state.current_ticket == Ticket of 
        true -> 
            gen_server:reply(_From, {success, Ticket}),
            {noreply, State#state{current_ticket=Ticket + 1}};
        false -> 
            case State#state.current_ticket < Ticket of
                true ->
                    gen_server:cast(aco_node, {update_ticket, Ticket, _From}),
                    {noreply, State#state{}};
                false ->
                    gen_server:reply(_From, {failure, Ticket}),
                    {noreply, State#state{}}
            end
    end;

%% identico al call, solamente che viene usato quando il ticket non risulta up-to-date
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

%% identico al call, solamente che viene usato quando il ticket non risulta up-to-date
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
%% identico al call, solamente che viene usato quando il ticket non risulta up-to-date
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
                    {noreply, State#state{}}
            end
    end;

%% identico al call, solamente che viene usato quando il ticket non risulta up-to-date
handle_cast({add_running_node_from, Node, From, Edges, Ticket, _From}, State) ->
    case Ticket == State#state.current_ticket of
        true ->
            NewOtherNodes = dict:store(Node, From, State#state.found_nodes),
            NewEdges = add_edges(filtered_edges(State#state.local_nodes, Edges, []), State#state.local_edges),
            gen_server:reply(_From, {success, Ticket}),
            {noreply, State#state{local_edges = NewEdges, found_nodes = NewOtherNodes, best_cost=?WORST_COST, best_path=[]}};
        false ->
            case Ticket > State#state.current_ticket of
                true ->
                    gen_server:cast(aco_node, {add_running_node_from, Node, From, Edges, Ticket, _From}),
                    {noreply, State};
                false ->
                    gen_server:reply(_From, {failure, Ticket}),
                    {noreply, State}
            end
    end;

%% identico al call, solamente che viene usato quando il ticket non risulta up-to-date
handle_cast({update_edges, Edges, Ticket, _From}, State) ->
    case Ticket == State#state.current_ticket of
        true ->
            LocalEdges = State#state.local_edges,
            NewLocalEdges = sets:from_list(update_edges(Edges, sets:to_list(LocalEdges))),
            gen_server:reply(_From, {success, Ticket}),
            {noreply, State#state{local_edges = NewLocalEdges, current_ticket = Ticket + 1, best_cost=?WORST_COST, best_path=[]}};
        false ->
            case Ticket > State#state.current_ticket of 
                true ->
                    gen_server:cast(aco_node, {update_edges, {Edges, Ticket, _From}}),
                    {noreply, State#state{}};
                false ->
                    gen_server:reply(_From, {failure, Ticket}),
                    {noreply, State#state{}}
                end
        end;

%% identico al call, solamente che viene usato quando il ticket non risulta up-to-date
handle_cast({add_running_node, Node, Edges, Ticket, _From}, State) ->
    case Ticket == State#state.current_ticket of
        true ->
            NewNodes = dict:store(Node, node(), State#state.local_nodes),
            NewEdges = add_edges(Edges, State#state.local_edges),
            NewOtherNodes = dict:store(Node, node(), State#state.found_nodes),
            gen_server:multi_call(nodes(), aco_node, {add_running_node_from, Node, node(), Edges, Ticket}, 10*1000),
            gen_server:reply(_From, {success, Ticket}),
            {noreply, State#state{local_nodes = NewNodes, local_edges = NewEdges, found_nodes = NewOtherNodes, best_cost=?WORST_COST, best_path=[]}};
        false -> 
            case Ticket > State#state.current_ticket of
                true ->
                    gen_server:cast(aco_node, {add_running_node, {Node, Edges, Ticket, _From}}),
                    {noreply, State};
                false ->
                    gen_server:reply(_From, {failure, Ticket}),
                    {noreply, State}
            end
        end;

%%% ----------------------------------------------------------------------
%%%     INIZIO DELL'ALGORITMO VERO E PROPRIO CON INIZIALIZZAZIONE
%%%     E ACO ALGORITHM
%%% ----------------------------------------------------------------------

%% avvio dello scambio dei nodi
%% RemoteNodes: dictionary di nodi remoti
%% From: nodo aco da aggiungere come parent
handle_cast({start, RemoteNodes, From}, State) ->
    InitCounter = State#state.init_counter + 1,
    case InitCounter == (length(nodes())) of
        true ->
            InitStatus = done;
        false ->
            InitStatus = State#state.init_status
    end,
    Parent = State#state.parent,
    MyGraphNodes = State#state.local_nodes,
    OldFound = State#state.found_nodes,
    OldPlusMyNodes = add_resources(dict:to_list(MyGraphNodes), OldFound),
    FromOtherNode = add_resources(dict:to_list(RemoteNodes), OldPlusMyNodes),
    case Parent of
        undefined ->
            NewParent = From,
            gen_server:abcast(nodes(), aco_node, {start, MyGraphNodes, node()}),
            {noreply, State#state{found_nodes=FromOtherNode, parent=NewParent, init_counter = InitCounter, init_status = InitStatus}};
        _ ->
            {noreply, State#state{found_nodes=FromOtherNode, init_counter = InitCounter, init_status = InitStatus}}
    end;

%% avvio dell'aco algorithm
%% Amount: numero di formiche da generare
%% l'algoritmo viene eseguito solo dopo l'inizializzazione tramite l'uso di init status
handle_cast({start_aco, Amount}, State) ->
    case State#state.init_status of
        done ->
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
                    dict:to_list(Local_Nodes));
        _ ->
            gen_server:cast(aco_node, {start_aco, Amount})
    end,
    
    {noreply, State};

%% generazione di una formica da un certo nodo client
%% From: nodo cliente
handle_cast({new_ant, From}, State) ->
    NewAnt = #ant{cost_current_path=0, 
                pheromone_strength=0, 
                returning_flag=walking, 
                best_tour_cost=?WORST_COST,
                path=[From],
                complete_path=[From]},
    Edges = find_new_edges(dict:store(From, node(), dict:new()), 
                           sets:to_list(State#state.local_edges), []),        %% voglio solo gli edges che sono interessati al node
    OtherNodes = filter_nodes(dict:to_list(State#state.found_nodes), Edges),
    {Edge, Best_Neighbour} = ant_colony:get_best_neighbour(From, Edges, ?ALPHA, ?BETA),
    AcoNode = where_is_client(Best_Neighbour, dict:from_list(OtherNodes)),
    gen_server:cast({aco_node, AcoNode}, {receive_ant, NewAnt, From, Best_Neighbour, Edge}),
    {noreply, State#state{best_cost=?WORST_COST, best_path=[]}};

%% controllo sul numero di formiche presenti nel sistema
%% la variabile di stato ant_flag_counter decide se non ci sono più formiche
%% nel caso in cui non ce ne siano vengono generate delle nuove formiche,
%% manca da parametrizzare quante formiche dovrebbero essere rigenerate, al momento 
%% vengono generate 3 formiche in caso di mancanza di formiche per nodo
handle_cast({check_for_ants}, State) ->
    Counter = State#state.ant_flag_counter - 1,
    case Counter > 0 of
        true -> 
            {noreply, State#state{ant_flag_counter = Counter}};
        false ->
            lists:foreach(
                fun({Node = #node{}, AcoNodeFrom}) ->
                    Ants = ant_colony:generate_ants(3, Node),

                    AcoNodesKnown = sets:to_list(sets:from_list(filter_other_nodes(dict:to_list(State#state.found_nodes)))),
                    AcoNodesConnected = lists:sort([node() | nodes()]),
                    case length(AcoNodesConnected) < length(AcoNodesKnown) of
                        true ->
                            OtherNodes = dict:from_list(remove_not_connected_s(AcoNodesConnected, dict:to_list(State#state.found_nodes))),
                            NewEdges = sets:from_list(remove_useless_edges(OtherNodes, sets:to_list(State#state.local_edges), [])),
                            Edges = find_new_edges(dict:store(Node, AcoNodeFrom, dict:new()), sets:to_list(NewEdges), []);
                        false ->
                            Edges = find_new_edges(dict:store(Node, AcoNodeFrom, dict:new()), sets:to_list(State#state.local_edges), []),
                            OtherNodes = dict:from_list(filter_nodes(dict:to_list(State#state.found_nodes), Edges))
                    end,
                    lists:foreach(
                        fun(Ant) ->
                            {Edge, Best_Neighbour} = ant_colony:get_best_neighbour(Node, Edges, ?ALPHA, ?BETA),
                            AcoNode = where_is_client(Best_Neighbour, OtherNodes),
                            gen_server:cast({aco_node, AcoNode}, {receive_ant, Ant, Node, Best_Neighbour, Edge})
                        end,
                        Ants)
                end,
                dict:to_list(State#state.local_nodes)),
            {noreply, State#state{best_cost=?WORST_COST, best_path=[], ant_flag_counter = 0}}
        end;


%%%     ---------------------------------------------
%%%     RICEZIONE DI UNA FORMICA, LOOP PRINCIPALE
%%%     ALGORITMO PRINCIPALE
%%%     ---------------------------------------------

%% metodo per la ricezione di una formica, è il cuore dell'algoritmo
%% Ant: formica ricevuta
%% _From: indica il nodo cliente di provenienza della formica
%% To: nodo in cui al momento si trova la formica
%% ByEdge: indica l'edge utilizzato per andare da {From, To}
handle_cast({receive_ant, Ant=#ant{}, _From, To=#node{}, ByEdge=#edge{}}, State) ->
    case State#state.init_status of
        done ->
            AcoNodesKnown = sets:to_list(sets:from_list(filter_other_nodes(dict:to_list(State#state.found_nodes)))),
            AcoNodesConnected = lists:sort([node() | nodes()]),
            case length(AcoNodesConnected) < length(AcoNodesKnown) of
            %% ritorna true solamente quando si perdono dei nodi aco connessi
                true ->    
                    OtherNodes = dict:from_list(remove_not_connected_s(AcoNodesConnected, dict:to_list(State#state.found_nodes))),
                    NewEdges = sets:from_list(remove_useless_edges(OtherNodes, sets:to_list(State#state.local_edges), [])),
                    {NewNode, AcoNode} = random_pick_from_other_nodes(dict:to_list(OtherNodes)),     %% nodo client 
                    gen_server:cast({aco_node, AcoNode}, {new_ant, NewNode}),
                    timer:apply_after(30*1000, gen_server, cast, [aco_node, {check_for_ants}]),
                    {noreply, State#state{found_nodes = OtherNodes, local_edges = NewEdges, best_cost=?WORST_COST, best_path=[], ant_flag_counter = State#state.ant_flag_counter + 1}};
            %% rileva false quando i nodi aco sono maggiori o uguali, se sono maggiori 
            %% ma non partecipano all'algoritmo ancora va tutto bene
                false ->
                    OtherNodes = State#state.found_nodes,
                    Ant_elaborated = ant_colony:elaborate_ant(Ant, To, ByEdge),                             %% aggiorno da dove proviene la ant   
                    case Ant#ant.returning_flag of

                        %% la formica sta ritornando all'anthill e rilasciando feromoni mentre passa
                        returning -> 
                            case ant_colony:is_returned(Ant_elaborated) of                     
                                %% la formica ha completato il suo ciclo due volte e il suo path e' vuoto
                                true -> 
                                    ClientNodes = filter_other_clients(dict:to_list(OtherNodes)),
                                    PathAnt = lists:sort(lists:delete(lists:last(Ant_elaborated#ant.complete_path), 
                                                                    Ant_elaborated#ant.complete_path)),
                                    case check_client_with_known_ones(ClientNodes, PathAnt) of 
                                        true ->
                                            NewAnt = ant_colony:reset_ant(Ant_elaborated, To),          %% passare l'ant elaborated potrebbe servire per aggiornare il best cost conosciuto
                                            Edges = usable_edges(ant_colony:get_last_visited(NewAnt),       %% assumiamo che esista almeno un edge ancora disponibile
                                                                [],
                                                                sets:to_list(State#state.local_edges)),
                                            {Edge, Best_Neighbour} = ant_colony:get_best_neighbour(To, Edges, ?ALPHA, ?BETA),
                                            AcoNode = where_is_client(Best_Neighbour, OtherNodes),                                 
                                            NewEdge = ant_colony:pheromone_evaporation(Edge, ?TAU_ZERO, ?XI),        
                                            gen_server:cast({aco_node, AcoNode}, {receive_ant, NewAnt, To, Best_Neighbour, NewEdge}),
                                            timer:apply_after(30*1000, gen_server, cast, [aco_node, {check_for_ants}]),
        
                                            UpdatedEdges = sets:add_element(NewEdge, 
                                                                            sets:del_element(Edge, State#state.local_edges)),               
                                            {noreply, State#state{local_edges = UpdatedEdges, ant_flag_counter = State#state.ant_flag_counter + 1}};     
                                        false ->
                                            {NewNode, AcoNode} = random_pick_from_other_nodes(dict:to_list(OtherNodes)),     %% nodo client 
                                            gen_server:cast({aco_node, AcoNode}, 
                                                {new_ant, NewNode}),
                                            timer:apply_after(30*1000, gen_server, cast, [aco_node, {check_for_ants}]),
                                            % io:format("returning completato + other nodes != path ant~n"),
                                            {noreply, State#state{best_cost=?WORST_COST, best_path=[], ant_flag_counter = State#state.ant_flag_counter + 1}}
                                    end;

                                %% la formica è returning ma sta ancora ritornando indietro, non si trova ancora all'anthill
                                false -> 
                                    ClientNodes = filter_other_clients(dict:to_list(OtherNodes)),
                                    PathAnt = lists:sort(lists:delete(lists:last(Ant_elaborated#ant.complete_path), 
                                                                    Ant_elaborated#ant.complete_path)),

                                    case check_client_with_known_ones(ClientNodes, PathAnt) of 
                                        true -> 
                                            %% check che non ci siano nuovi nodi che non aveva visitato che si sono aggiunti durante
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
                                                    timer:apply_after(30*1000, gen_server, cast, [aco_node, {check_for_ants}]),   
                                                    gen_server:cast({aco_node, where_is_client(Best_Neighbour, OtherNodes)}, 
                                                                        {receive_ant, Ant_elaborated, To, Best_Neighbour, NewEdge2}),

                                                    C = State#state.best_cost,
                                                    case Ant_elaborated#ant.best_tour_cost < C of
                                                        true -> {noreply, State#state{best_cost = Ant_elaborated#ant.best_tour_cost, 
                                                                                    local_edges = UpdatedEdges2, ant_flag_counter = State#state.ant_flag_counter + 1}};
                                                        false ->  {noreply, State#state{local_edges = UpdatedEdges2, ant_flag_counter = State#state.ant_flag_counter + 1}}
                                                    end;
                                                error ->
                                                    {NewNode, AcoNode} = random_pick_from_other_nodes(dict:to_list(OtherNodes)),     %% nodo client 
                                                    gen_server:cast({aco_node, AcoNode}, 
                                                        {new_ant, NewNode}),
                                                    timer:apply_after(30*1000, gen_server, cast, [aco_node, {check_for_ants}]),   
                                                    % io:format("returning in corso + can't find returning edge~n"),
                                                    {noreply, State#state{best_cost=?WORST_COST, best_path=[], ant_flag_counter = State#state.ant_flag_counter + 1}}
                                            end;
                                            
                                        false ->
                                            {NewNode, AcoNode} = random_pick_from_other_nodes(dict:to_list(OtherNodes)),     %% nodo client 
                                            gen_server:cast({aco_node, AcoNode}, 
                                                {new_ant, NewNode}),
                                            timer:apply_after(30*1000, gen_server, cast, [aco_node, {check_for_ants}]),
                                            % io:format("returning in corso + other nodes != path ant~n"),   
                                            {noreply, State#state{best_cost=?WORST_COST, best_path=[], ant_flag_counter = State#state.ant_flag_counter + 1}}
                                    end                                      
                            end;

                        %% la formica sta girando per il grafo 
                        %% non conosce ancora il best path generalmente
                        walking -> 

                            case ant_colony:is_tour_complete(Ant_elaborated) of  
                             %% la formica ha completato il suo ciclo una sola volta 
                             %% e il suo path contiene come primo e ultimo elemento uguali, che corrispondono all'anthill                                  
                                true ->                    

                                    ClientNodes = filter_other_clients(dict:to_list(OtherNodes)),
                                    PathAnt = lists:sort(lists:delete(lists:last(Ant_elaborated#ant.complete_path), 
                                                                    Ant_elaborated#ant.complete_path)),

                                    case check_client_with_known_ones(ClientNodes, PathAnt) of 
                                        true -> %% esecuzione normale
                                                    %% check che non siano stati aggiunti nodi quando termina il primo giro
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
                                                    
                                                    gen_server:cast({aco_node, where_is_client(Best_Neighbour, OtherNodes)}, 
                                                                        {receive_ant, A, To, Best_Neighbour, NewEdge}),
                                                    timer:apply_after(30*1000, gen_server, cast, [aco_node, {check_for_ants}]),

                                                    C = State#state.best_cost,
                                                    case A#ant.best_tour_cost < C of
                                                        true -> 
                                                            gen_server:abcast([node()|nodes()], flooding, {path, {A#ant.path, A#ant.best_tour_cost}}),
                                                            {noreply, State#state{best_path= A#ant.path, 
                                                            best_cost = A#ant.best_tour_cost, local_edges = UpdatedEdges,
                                                            ant_flag_counter = State#state.ant_flag_counter + 1}};
                                                        false ->  {noreply, State#state{local_edges = UpdatedEdges, ant_flag_counter = State#state.ant_flag_counter + 1}}
                                                    end;
                                                error ->                %% il penultimo nodo del path della formica e' sparito
                                                    {NewNode, AcoNode} = random_pick_from_other_nodes(dict:to_list(OtherNodes)),     %% nodo client 
                                                    gen_server:cast({aco_node, AcoNode}, 
                                                        {new_ant, NewNode}),
                                                    timer:apply_after(30*1000, gen_server, cast, [aco_node, {check_for_ants}]),
                                                    
                                                    {noreply, State#state{best_cost=?WORST_COST, best_path=[], ant_flag_counter = State#state.ant_flag_counter + 1}}
                                            end;

                                        false -> %% esecuzione in cui va resettata l'ant
                                            {NewNode, AcoNode} = random_pick_from_other_nodes(dict:to_list(OtherNodes)),     %% nodo client 
                                            gen_server:cast({aco_node, AcoNode}, 
                                                {new_ant, NewNode}),
                                            timer:apply_after(30*1000, gen_server, cast, [aco_node, {check_for_ants}]),
                                            
                                            {noreply, State#state{best_cost=?WORST_COST, best_path=[], ant_flag_counter = State#state.ant_flag_counter + 1}}
                                    end;

                                %% l'ant si ritrova in un punto a caso scelto del grafo, 
                                %% sta ancora trovando il percorso                
                                false -> 
                                    UpdatedAnt = Ant_elaborated,                                        %% aggiorno da dove proviene la ant
                                    L = lists:delete(To, UpdatedAnt#ant.path),
                                    Edges = usable_edges(ant_colony:get_last_visited(UpdatedAnt),
                                                        L,
                                                        sets:to_list(State#state.local_edges)),                             %% calcolo gli edges possibili dove si puo' spostare la formica senza tornare in un nodo gia' visitato
                                    %% nel caso in cui la formica non abbia più edge usabili, 
                                    %% significa che deve tornare al luogo di partenza
                                    if length(Edges) > 0 ->
                                        %% esecuzione normale di esplorazione
                                        {Edge, Best_Neighbour} = ant_colony:get_best_neighbour(To, Edges, ?ALPHA, ?BETA),   %% nuovo neighbour + edge usato
                                        AcoNode = where_is_client(Best_Neighbour, OtherNodes),                                          %% computo dove si trova il cliente nei nodi aco
                                        gen_server:cast({aco_node, AcoNode}, {receive_ant, UpdatedAnt, To, Best_Neighbour, Edge}),           %% invio la formica
                                        timer:apply_after(30*1000, gen_server, cast, [aco_node, {check_for_ants}]),
                                        NewEdge = ant_colony:pheromone_evaporation(Edge, ?TAU_ZERO, ?XI),
                                        UpdatedEdges = sets:add_element(NewEdge, 
                                                                        sets:del_element(Edge, State#state.local_edges)),               %% calcolo l'evaporazione dell'edge e rimuovo il vecchio edge
                                        {noreply, State#state{local_edges = UpdatedEdges, ant_flag_counter = State#state.ant_flag_counter + 1}};                                              %% aggiorno l'edge                             
                                    true -> 
                                        %% caso in cui deve ritornare all'anthill
                                        Best_Neighbour = ant_colony:get_anthill(UpdatedAnt),
                                        {Response, Edge} = find_return_edge(To, Best_Neighbour, sets:to_list(State#state.local_edges)),
                                        case Response of 
                                            ok -> 
                                                NewEdge = ant_colony:pheromone_evaporation(Edge, ?TAU_ZERO, ?XI),
                                                UpdatedEdges = sets:add_element(NewEdge, 
                                                                                sets:del_element(Edge, State#state.local_edges)),               %% calcolo l'evaporazione dell'edge e rimuovo il vecchio edge
                                                gen_server:cast({aco_node, where_is_client(Best_Neighbour, OtherNodes)}, 
                                                                {receive_ant, UpdatedAnt, To, Best_Neighbour, NewEdge}),
                                                timer:apply_after(30*1000, gen_server, cast, [aco_node, {check_for_ants}]),
                                                {noreply, State#state{local_edges = UpdatedEdges, ant_flag_counter = State#state.ant_flag_counter + 1}};                                     %% aggiorno l'edge  
                                            error ->
                                                {NewNode, AcoNode} = random_pick_from_other_nodes(dict:to_list(OtherNodes)),     %% nodo client 
                                                gen_server:cast({aco_node, AcoNode}, 
                                                    {new_ant, NewNode}),
                                                timer:apply_after(30*1000, gen_server, cast, [aco_node, {check_for_ants}]),

                                                {noreply, State#state{best_cost=?WORST_COST, best_path=[], ant_flag_counter = State#state.ant_flag_counter + 1}}
                                        end
                            end
                    end
                end
            end;
        %% caso in cui l'algoritmo non deve ancora partire, 
        %% perche' mancano dei nodi che non sono pronti
        _ ->
            gen_server:cast(aco_node, {receive_ant, Ant, _From, To, ByEdge}),
            {noreply, State}
    end.
    
handle_info(ok = _Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%%% -----------
%%% UTILITIES
%%% -----------

%% add_resources: aggiunge una lista di coppie di valori ad un dictionary
add_resources([{Resource, From}|T], Dict) ->
    add_resources(T, add_resource(Resource, From, Dict));
add_resources([], Dict) ->
    Dict.
%% aggiunge un solo valore ad un dictionary
%% Resource: nodo cliente
%% From: nodo aco
%% Dict: dictionary che contiene già i valori
add_resource(Resource, From, Dict) ->
    dict:store(Resource, From, Dict).

%% add_edges: aggiunge una lista di archi ad un set contenente gli archi
add_edges([E|T], Set) ->
    add_edges(T, add_edge(E, Set));
add_edges([], Set) -> Set.

%% aggiunge un singolo edge ad un set contenente degli archi
add_edge(#edge{from=From, to=To, weight=Weight}, Set) ->
    NewE = #edge{from=From, to=To, weight=Weight, tau=?TAU_ZERO},
    sets:add_element(NewE, Set).

%% rimuove da un elemento da una lista
%% List: lista che contiene dei valori
%% Parent: il valore da rimuovere
remove_parent(List, Parent) ->
    lists:delete(Parent, List).

%% converte i messaggi di reply ricevuti da altri aco node riguardanti 
%% ReplyMsg è un dictionary che contiene {NodoCliente, NodoAco}
%% li converte in una lista  
convert_replies_to_lists([{_, ReplyMsg}|T]) ->
    case ReplyMsg of
        ok -> convert_replies_to_lists(T);
        _ -> convert_replies_to_lists(T) ++ dict:to_list(ReplyMsg)
    end;
convert_replies_to_lists([]) -> [].

%% My_Nodes: dictionary dei nodi su cui effettuare la ricerca degli edge da aggiungere
%% Edges: una lista di archi da aggiungere
%% Acc: il risultato, cioe' la lista di archi da aggiungere
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

%% Client: nodo cliente da cercare in quale aco node appartiene
%% AcoNodes: dictionary contenente le coppie {NodoClient, NodoAco}
%% genera un eccezione se il client non è noto
where_is_client(Client, AcoNodes) ->
    case dict:find(Client, AcoNodes) of
        {ok, Where} ->
            Where;
        _ ->
            io:format("Client: ~w~n AcoNodes: ~w~n", [Client, AcoNodes]),
            io:format("Node: ~w~n", [node()]),
            throw("error: this aco node has no knowledge of where this client is")
        end.


%% Nodes: lista di coppie {NodoClient, NodoAco}
%% Edges: lista di archi
%%
%% restituisce solamente i nodi che sono presenti 
%% in almeno una delle due estremmità di un arco
filter_nodes(Nodes=[{#node{},_From} | _], Edges) ->
    lists:filter(
        fun(Node) ->
            p(Node, Edges)
            end
        ,Nodes).

%% predicato che controlla se il nodo è in una delle due estremità di una lista di archi
%% nel caso in cui non sia presente in nessuno restituisce false, altrimenti true
p({Node=#node{}, _From}, [#edge{from=From, to=To} | Edges]) -> 
    if (Node == From) or (Node == To) ->
        true;
    true ->
        p({Node, _From}, Edges)
    end;

p(_, []) -> false.

%% NodesDict: dictionary di nodi 
%% Edges: lista di archi 
%% Acc: risultato che contiene gli archi in cui almeno un nodo e' presente
%% e' la funzione opposta di filter_node
filtered_edges(_, [], Acc) -> Acc;
filtered_edges(NodesDict, [Edge|Edges], Acc) ->
    case dict:find(Edge#edge.from, NodesDict) of
        {ok, _} ->
            filtered_edges(NodesDict, Edges, Acc ++ [Edge]);
        _ ->
            case dict:find(Edge#edge.to, NodesDict) of
                {ok, _} ->
                    filtered_edges(NodesDict, Edges, Acc ++ [Edge]);
                _ ->
                    filtered_edges(NodesDict, Edges, Acc)
            end
    end.

%% NodesDict: dictionary dei nodi
%% Edges: lista di archi
%% Acc: resistuisce gli archi che rimangono quando vengono rimossi
%%      gli archi che non hanno nemmeno una delle due estremità nel dictionary dei nodi
remove_useless_edges(_, [], Acc) -> Acc;
remove_useless_edges(NodesDict, [Edge|Edges], Acc) ->
    case dict:find(Edge#edge.from, NodesDict) of
        {ok, _} ->
            case dict:find(Edge#edge.to, NodesDict) of
                {ok, _} -> 
                    remove_useless_edges(NodesDict, Edges, Acc ++ [Edge]);
                _ ->
                    remove_useless_edges(NodesDict, Edges, Acc)
            end;
        _ ->
            remove_useless_edges(NodesDict, Edges, Acc)
    end.

%% From: nodo cliente
%% To: nodo cliente
%% Edges: lista di archi
%% restituisce una coppia composta da {Response, Arco}
%% Controlla se esiste un arco che possa riportare alla coppia {From, To} o {To, From}
%% Response: può essere ok o error
%% Edge: può essere l'edge oppure ritornare un edge non inizializzato
find_return_edge(From, To, [Edge=#edge{}|T]) ->
    case ((From == Edge#edge.from) and (To == Edge#edge.to)) or
         ((From == Edge#edge.to) and (To == Edge#edge.from)) of
        true -> {ok, Edge};
        _ -> find_return_edge(From, To, T)
    end;
find_return_edge(_, _, []) ->
    {error, #edge{}}.

%% Nodes: lista di nodi cliente
%% EdgeList: lista di archi
%% Ritorna una lista di archi in cui non è presente nemmeno uno dei nodi in Nodes
%% L'utilizzo è di cercare gli edge possibili che può prendere una formica 
%%      senza ritornare all'interno di un nodo già visitato
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

%% Rimuove gli archi che contengono node
%% Node: nodo cliente
%% Edges: lista di archi
remove_edges(Node, Edges) ->
    remove_edges(Node, Edges, []).

remove_edges(Node, [Edge|Edges], Acc) ->
    if (Edge#edge.from == Node) or (Edge#edge.to == Node) ->
        remove_edges(Node, Edges, Acc);
    true ->
        remove_edges(Node, Edges, Acc ++ [Edge])
    end;

remove_edges(_, [], Acc) -> Acc.

%% Edges: lista di archi da caricare
%% LocalEdges: lista di archi vecchia da aggiornare
%% sostituisce gli archi con i nuovi pesi e resetta il valore dei feromoni presenti sull'arco
update_edges([], LocalEdges) -> LocalEdges;
update_edges([Edge|Edges], LocalEdges) ->
    L = lists:sort(LocalEdges),
    update_edges(Edges, update_edge(Edge, L, L)).

update_edge(_,[], L) -> L;
update_edge(Edge=#edge{from=F, to=T, weight=W}, [CE|NE], L) ->
    if ((F == CE#edge.from) and (T == CE#edge.to)) or
        ((F == CE#edge.to) and (T == CE#edge.from)) ->
        lists:delete(CE, L) ++ [#edge{from=F, to=T, weight=W, tau=?TAU_ZERO}];
    true ->
        update_edge(Edge, NE, L)
    end.

%% Nodes: lista di nodi
%% restituisce un nodo a caso
random_pick_from_other_nodes(Nodes) ->  %% lista di nodi
    _ = crypto:rand_seed(),
    Length = length(Nodes),
    R = rand:uniform(Length),
    lists:nth(R, Nodes).

%% OtherNodes: lista di tuple composte da {Client, AcoNode}
%% restituisce solamente i nodi Aco
filter_other_nodes(OtherNodes) ->
    AcoNodes = lists:map(fun({_, Aco}) -> Aco end, OtherNodes),
    lists:sort(AcoNodes).

%% OtherNodes: lista di tuple composte da {Client, AcoNode}
%% restituisce solamente i nodi Client
filter_other_clients(OtherNodes) ->
    ClientNodes = lists:map(fun({Client, _}) -> Client end, OtherNodes),
    lists:sort(ClientNodes).


%% itera due liste Nodes e Path e verifica in ordine che siano identiche
%% Nodes e Path devono essere due liste ordinate
check_client_with_known_ones([], []) -> true;
check_client_with_known_ones(_, []) -> false;
check_client_with_known_ones([], _) -> false;
%% due liste itero finche' non sono vuote entrambe
check_client_with_known_ones([N|Nodes], [P|Path]) ->
    if N == P ->
        check_client_with_known_ones(Nodes, Path);
    true ->
        false
    end.

%% replies of the form: {From, [#node{}, #node{}, ... ]}
%% returns [{#node{}, From}, {#node{}, From}, ...]
convert_list_of_found_nodes_to_tuples_with_aco_nodes([], Acc) -> Acc;
convert_list_of_found_nodes_to_tuples_with_aco_nodes([{_From, Nodes}|T], Acc) ->
    convert_list_of_found_nodes_to_tuples_with_aco_nodes(T, Acc ++ Nodes). %% [{node, from}]

%% nodes: lists, 
%% edges: lists
%% returns a side effect di aggiungere un nodo alla volta con gli edges agl altri aco nodes
add_running_nodes([], _) -> ok;
add_running_nodes([{Node=#node{}, _From}|Nodes], Edges) ->
    %% add_running_node_from, Node, From, Edges, Ticket
    {ok, _, Ticket} = ticket_system:request_ticket(),
    Edges_Filtrati = filtered_edges(dict:from_list([{Node, _From}]), Edges, []),
    gen_server:multi_call(nodes(), aco_node, {add_running_node_from, Node, node(), Edges_Filtrati, Ticket}, 20*1000),
    gen_server:multi_call([node()|nodes()], aco_node, {update_ticket, Ticket}, 20*1000),
    add_running_nodes(Nodes, Edges).

%% due liste
%% deve rimuovere da Known quelli che mancano in connected
%% [N1 | N] = ['A1@Computer', ...]
%% AcoNodesKnown [{#node{name = 1},'A1@Computer'}, {#node{name = 3},'A2@Computer'}, ... ]
remove_not_connected_s([], _A) -> [];
remove_not_connected_s([N1 | N], AcoNodesKnown) ->
    remove_not_connected(N1, AcoNodesKnown, []) ++ remove_not_connected_s(N, AcoNodesKnown).

remove_not_connected(_, [], Acc) -> Acc;
remove_not_connected(Aco1, [{N, Aco} | T], Acc) ->
    case Aco1 == Aco of
        true -> remove_not_connected(Aco1, T, Acc ++ [{N, Aco}]);
        false -> remove_not_connected(Aco1, T, Acc)
    end.
            
%% Possibile maniera di calcolare tau_zero in basi ai propri edge locali
compute_tau_zero(EdgeSet) ->
    CostList = lists:map(fun (#edge{weight = X}) -> X end, sets:to_list(EdgeSet)),
    TotalCost = lists:foldl(fun(X, Sum) -> X + Sum end, 0, CostList),
    TotalCost / length(CostList).