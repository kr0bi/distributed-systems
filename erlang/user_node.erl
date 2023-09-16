-module(user_node).
-behaviour(gen_server).

%% API
-export([start/0, stop/1, start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([start_election/0]).
-record(edge, {from, to, weight, tau}).
-record(node, {name}).
-record(state, {officelist}).

-define(ANT_COUNT, 3).

start() ->
   gen_server:start({local, ?MODULE}, ?MODULE, [], []).

stop(Name) ->
    gen_server:call(Name, stop).

start_link() ->
    gen_server:start_link({local, user_node}, ?MODULE, [], []).

init(_Args) ->
    {ok, #state{officelist=[]}}.

%% Handles call for stopping the user node
handle_call(stop, _From, State) ->
    {stop, normal, stopped, State};

handle_call({add_clients, [Client | OtherClients],  Office}, _From, State) ->
    {_, _, Ticket} = ticket_system:request_ticket(),
    OfficeNode = get_office_node(Office, State#state.officelist),
    case gen_server:call({aco_node, OfficeNode}, {add_local_node_ticket, {#node{name=Client}, OfficeNode, Ticket}}) of
        {success, Ticket} ->
            gen_server:multi_call(aco_node, {update_ticket, Ticket}),
            case add_clients_to_office(OtherClients, OfficeNode) of
                ok ->
                    {reply, {success, Ticket}, State};
                failure ->
                    {reply, {failure, Ticket}, State}
            end;
        _ ->
            {reply, {failure, Ticket}, State}
    end;

%% Handles call for adding clients
handle_call({add_client_running, Client,  Office, Costs}, _From, State) ->
    {_, _, Ticket} = ticket_system:request_ticket(),
    EdgeList = lists:map(fun({{Client1, Client2}, Cost}) -> #edge{from=#node{name=Client1}, to=#node{name=Client2}, weight=Cost} end, Costs),
    OfficeNode = get_office_node(Office, State#state.officelist),
    case gen_server:call({aco_node, OfficeNode}, {add_running_node, #node{name=Client}, EdgeList, Ticket}) of
        {success, Ticket} ->
            case gen_server:multi_call(aco_node, {update_ticket, Ticket}) of
                {success, Ticket} ->
                    {reply, {success, Ticket}, State};
                _ ->
                    {reply, {failure, Ticket}, State}
            end;   
        _ ->
            {reply, {failure, Ticket}, State}
    end;

%% Handles call for updating edge costs and/or adding new edges
handle_call({update_costs, Costs}, _From, State) ->
    {_, _, Ticket} = ticket_system:request_ticket(),
    io:format("Ticket requested is ~w~n", [Ticket]),
    EdgeList = lists:map(fun({Client1, Client2, Cost}) -> #edge{from=#node{name=Client1}, to=#node{name=Client2}, weight=Cost} end, Costs),
    io:format("EdgeList is ~w~n", [EdgeList]),
    case gen_server:multi_call(aco_node, {update_edges, EdgeList, Ticket}) of
        {[{_, {success, Ticket}} | _], _} ->
            {reply, {success, Ticket}, State};
        _ ->
            {reply, {failure, Ticket}, State}
    end;

handle_call({add_edges, Edges}, _From, State) ->
    {_, _, Ticket} = ticket_system:request_ticket(),
    io:format("Ticket requested is ~w~n", [Ticket]),
    EdgeList = lists:map(fun({Client1, Client2, Cost}) -> #edge{from=#node{name=Client1}, to=#node{name=Client2}, weight=Cost} end, Edges),
    io:format("EdgeList is ~w~n", [EdgeList]),
    case gen_server:multi_call(aco_node, {add_local_edges_ticket, {EdgeList, Ticket}}) of
        {[{_, {success, Ticket}} | _], _} ->
            {reply, {success, Ticket}, State};
        _ ->
            {reply, {failure, Ticket}, State}
    end;

%% Handles call for removing a client
handle_call({remove_client, Client}, _From, State) ->
    {_, _, Ticket} = ticket_system:request_ticket(),
    case gen_server:multi_call(aco_node, {remove_node_ticket, #node{name=Client}, Ticket}) of
        {[{_, {success, Ticket}} | _], _} ->
            case gen_server:multi_call(aco_node, {update_ticket, Ticket}) of
                {success, Ticket} ->
                    {reply, {success, Ticket}, State};
                _ ->
                    {reply, {failure, Ticket}, State}
            end;   
        _ ->
            {reply, {failure, Ticket}, State}
    end;

%% Handles call for starting an iteration of the aco algorithm
handle_call(start_aco, _From, State) ->
    %{_, _, Ticket} = ticket_system:request_ticket(),
    %aco_node:start_aco();
    case gen_server:call(aco_node, start) of
        {success} ->
            gen_server:abcast([node()|nodes()], aco_node, {start_aco, ?ANT_COUNT}),
            {reply, {success}, State};
        _ ->
            {reply, {failure}, State}
    end;

%% Handles call for starting the ACO system
handle_call(start_system, _From, State) ->
    {_, _, Ticket} = ticket_system:start_election(),
    case gen_server:call(aco_node, {start_aco, ?ANT_COUNT, Ticket}) of
        {success, Ticket} ->
            {reply, {success, Ticket}, State};
        _ ->
            {reply, {failure, Ticket}, State}
    end;

handle_call({add_office, OfficeID, OfficeNode} , _From, State) ->
    %io:format("Current office list: ~w~n", [State#state.officelist]),
    {reply, ok, #state{officelist= lists:append(State#state.officelist, [{OfficeID, OfficeNode}])}};

handle_call({remove_office, OfficeID} , _From, State) ->
    {reply, ok, #state{officelist= remove_office_node(OfficeID, State#state.officelist)}};
    

%% Handles call for stopping the whole system
    

handle_call(_, _From, State) ->
    {reply, {failure, unknown_call}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%start_ticket_election() ->
%    case ticket_system:start_election() of 
%        {ok, Pid}
%        {error}.

%%
% Utilities
%%
get_office_node(_, []) ->
    {failure, officenotfound};

get_office_node(Office, [{OffName, OffNode} | OfficeList]) ->
    case Office == OffName of
        true ->
            OffNode;
        false ->
            get_office_node(Office, OfficeList)
    end.

remove_office_node(Office, []) ->
    [];

remove_office_node(Office, [{OffName, OffNode} | OfficeList]) ->
    case Office == OffName of
        true ->
            [];
        false ->
            List = remove_office_node(Office, OfficeList),
            lists:append(List, {OffName, OffNode})
    end.

start_election() ->
    ticket_system:start_election().

add_clients_to_office([], _) ->
    ok;
add_clients_to_office([Client | ClientList], Office) ->
    {_, _, Ticket} = ticket_system:request_ticket(),
    case gen_server:call({aco_node, Office}, {add_local_node_ticket, {#node{name=Client}, Office, Ticket}}) of
        {success, Ticket} ->
            gen_server:multi_call(aco_node, {update_ticket, Ticket}),
            add_clients_to_office(ClientList, Office);
        _ ->
            failure
    end.

