-module(ticket_system_server).
-behaviour(gen_server).

%% API
-export([start/0, start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-record(state, {leader, resp_counter, status, reply_id}).

%% Interface
start() ->
   gen_server:start({global, ?MODULE}, ?MODULE, [], []).

start_link() ->
    {ok, Pid} = gen_server:start_link({global, ?MODULE}, ?MODULE, [], []),
    register(?MODULE,Pid).


%% Callbacks

init(_Args) ->
    {ok, #state{leader = self(), resp_counter = 0, status = initiator}}.

handle_call(start_election, _From, State) ->
    start_election(State),
    {noreply, #state{leader = State#state.leader, resp_counter = State#state.resp_counter + 1, status = initiator, reply_id = _From}}.
    %{noreply, Leader, NewState}. % how to return leader?

handle_cast({echo, Leader}, State) ->
    case Leader > State#state.leader of
        true -> 
            echo_leader(Leader),
            {noreply, #state{leader = Leader, resp_counter = State#state.resp_counter, status = waiting}};
        false -> 
            {noreply, State}
    end;

handle_cast({ok, Leader}, State) ->
    case Leader == State#state.leader of
        true ->
            Guard = State#state.resp_counter + 1,
            Nodes = [node() | nodes(ticket_system_server)],
            case Guard == length(Nodes) of
                true -> 
                    State#state.leader ! State#state.reply_id, %% prob wrong
                    {noreply, #state{leader = State#state.leader, resp_counter = State#state.resp_counter + 1, status = done}};
                false -> 
                 {noreply, #state{leader = State#state.leader, resp_counter = State#state.resp_counter + 1, status = State#state.status}}
            end;
        false ->
            {noreply, State}
    end;

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%
start_election(State) ->
    gen_server:abcast([node() | nodes()], ticket_system_server, {echo, self()}). %% should send (async) own pid to all connected nodes with name elector

echo_leader(Leader) ->
    Replies = gen_server:abcast([node() | nodes(ticket_system_server)], ticket_system_server, {echo, Leader}).

%% net_adm, net_kernel, global
%% world, names, register_name

get_leader_pid(Leader = {Pid , _ , _ , _, _}) ->
    Pid.
