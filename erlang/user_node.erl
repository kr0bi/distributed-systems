-module(user_node).
-behaviour(gen_server).

%% API
-export([start/1, stop/1, start_link/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-record(state, {dummy}).
start(Name) ->
    _sup:start_child(Name).

stop(Name) ->
    gen_server:call(Name, stop).

start_link(Name) ->
    gen_server:start_link({local, Name}, ?MODULE, [], []).

init(_Args) ->
    {ok, #state{dummy=1}}.

handle_call(stop, _From, State) ->
    {stop, normal, stopped, State};

handle_call(start, _From, State) ->
    Ticket = ticket_system:request_ticket(),
    case gen_server:call(aco_node, {start, Ticket}) of
        {success, Ticket} ->
            {reply, {success, Ticket}, State};
        _ ->
            {reply, {failure, Ticket}, State}
    end;

handle_call({add_client, Client,  Office, Costs}, _From, State) ->
    Ticket = ticket_system:request_ticket(),
    case gen_server:call(aco_node, {add_local_node, #node{Client}, Office, Costs, Ticket}) of
        {success, Ticket} ->
            {reply, {success, Ticket}, State};
        _ ->
            {reply, {failure, Ticket}, State}
    end;

handle_call({update_costs, Costs}, _From, State) ->
    Ticket = ticket_system:request_ticket(),
    case gen_server:call(aco_node, {update_edges, Costs, Ticket}) of
        {success, Ticket} ->
            {reply, {success, Ticket}, State};
        _ ->
            {reply, {failure, Ticket}, State}
    end;

handle_call{{remove_client, Client}, _From, State} ->
    Ticket = ticket_system:request_ticket(),
    case gen_server:call(aco_node, {remove_local_node, Client, Ticket}) of
        {success, Ticket} ->
            {reply, {success, Ticket}, State};
        _ ->
            {reply, {failure, Ticket}, State}
    end.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

start_ticket_election() ->
    case ticket_system:start_election() of 
        {ok, Pid}
        {error}.

%% Call to add node to the graph
%% Need to add 
add_node()