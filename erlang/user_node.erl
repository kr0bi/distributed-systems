-module(user_node).
-behaviour(gen_server).

%% API
-export([start/0, stop/1, start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([start_election/0]).
-record(edge, {from, to, weight, tau}).
-record(node, {name}).
-record(office, {name, node}).
-record(state, {officelist}).

-define(ANT_COUNT, 3).

start() ->
   gen_server:start({local, ?MODULE}, ?MODULE, [], []).

stop(Name) ->
    gen_server:call(Name, stop).

start_link() ->
    gen_server:start_link({local, user_node}, ?MODULE, [], []).

init(_Args) ->
    {ok, _Args}.

%% Handles call for stopping the user node
handle_call(stop, _From, State) ->
    {stop, normal, stopped, State};

%% Handles call for adding clients
handle_call({add_client, Client,  Office, Costs}, _From, State) ->
    Ticket = ticket_system:request_ticket(),
    EdgeList = lists:map(fun({{Client1, Client2}, Cost}) -> #edge{from=Client1, to=Client2, weight=Cost} end, Costs),
    OfficeNode = get_office_node(Office, State#state.officelist),
    case gen_server:call({aco_node, OfficeNode}, {add_local_node_ticket, {#node{name=Client}, Ticket}}) of
        {success, Ticket} ->
            case gen_server:multi_call(aco_node, {add_local_edges_ticket, EdgeList, Ticket}) of
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
        _ ->
            {reply, {failure, Ticket}, State}
    end;

%% Handles call for updating edge costs and/or adding new edges
handle_call({update_costs, Costs}, _From, State) ->
    Ticket = ticket_system:request_ticket(),
    EdgeList = lists:map(fun({{Client1, Client2}, Cost}) -> #edge{from=Client1, to=Client2, weight=Cost} end, Costs),
    case gen_server:multi_call(aco_node, {update_edges, EdgeList, Ticket}) of
        {success, Ticket} ->
            {reply, {success, Ticket}, State};
        _ ->
            {reply, {failure, Ticket}, State}
    end;

%% Handles call for removing a client
handle_call({remove_client, Client}, _From, State) ->
    Ticket = ticket_system:request_ticket(),
    case gen_server:multi_call(aco_node, {remove_node_ticket, #node{name=Client}, Ticket}) of
        {success, Ticket} ->
            {reply, {success, Ticket}, State};
        _ ->
            {reply, {failure, Ticket}, State}
    end;

%% Handles call for starting an iteration of the aco algorithm
handle_call({start_aco}, _From, State) ->
    Ticket = ticket_system:request_ticket(),
    aco_node:start_aco();
    %case gen_server:call(aco_node, {start_aco, ?ANT_COUNT, Ticket}) of
    %    {success, Ticket} ->
    %        {reply, {success, Ticket}, State};
    %    _ ->
    %        {reply, {failure, Ticket}, State}
    %end;

%% Handles call for starting the ACO system
handle_call({start_system}, _From, State) ->
    Ticket = ticket_system:start_election(),
    case gen_server:call(aco_node, {start_aco, ?ANT_COUNT, Ticket}) of
        {success, Ticket} ->
            {reply, {success, Ticket}, State};
        _ ->
            {reply, {failure, Ticket}, State}
    end;

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

get_office_node(Office, [{OffName, OffNode} | OfficeList]) ->
    case Office == OffName of
        true ->
            OffNode;
        false ->
            get_office_node(Office, OfficeList)
    end.

start_election() ->
    ticket_system:start_election().
