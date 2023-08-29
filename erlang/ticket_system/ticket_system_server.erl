-module(ticket_system_server).
-behaviour(gen_server).

%% API
-export([start/0, start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-record(state, {leader, resp_counter, status, reply_id, parent}).

%% Interface
start() ->
   gen_server:start({global, ?MODULE}, ?MODULE, [], []).

start_link() ->
    {ok, Pid} = gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).
    %register(?MODULE,Pid).


%% Callbacks

init(_Args) ->
    {ok, #state{leader = node(), resp_counter = 0, status = initiator, parent = node()}}.

handle_call(start_election, _From, State) ->
    io:format("start election ~n"),
    echo_leader(State#state.leader),
    {noreply, #state{leader = State#state.leader, resp_counter = State#state.resp_counter, status = initiator, reply_id = _From, parent = node()}}.
    %{noreply, Leader, NewState}. % how to return leader?

handle_cast({echo, Leader, Sender}, State) ->
    io:format("sssn ~s ~n", [State#state.leader]),
    case Leader > State#state.leader of
        true -> 
            io:format("echo_true ~s ~n", [State#state.leader]),
            echo_leader(Leader),
            {noreply, #state{leader = Leader, resp_counter = 1, status = waiting, parent = Sender}};
        false -> 
            io:format("echo_false ~s ~n", [State#state.leader]),
            case Leader == State#state.leader of
                true ->
                    Guard = State#state.resp_counter + 1,
                    Nodes = [node() | nodes()],
                    io:format("echo_false_true ~s ~n", [State#state.leader]),
                    io:format("Guard ~p ~n", [Guard]),
                    io:format("Nodes ~p ~n", [length(Nodes)]),
                    case Guard == length(Nodes) of
                        true -> 
                            io:format("echo_false_true_true ~s  ~n", [State#state.leader]),
                            case State#state.status == initiator of 
                                true ->
                                    io:format("echo_false_true_true_true ~s ~n", [State#state.leader]),
                                    gen_server:reply(State#state.reply_id, {success, State#state.leader}),
                                    {noreply, #state{leader = State#state.leader, resp_counter = State#state.resp_counter + 1, status = done, parent = State#state.parent}};
                                false ->
                                    io:format("echo_false_true_true_false ~n"),
                                    gen_server:cast({ticket_system_server, State#state.parent}, {ok, State#state.leader}), %% prob wrong
                                    {noreply, #state{leader = State#state.leader, resp_counter = State#state.resp_counter + 1, status = done, parent = State#state.parent}}
                            end;
                        false -> 
                            io:format("echo_false_true_false, ~s ~n", [State#state.leader]),
                            {noreply, #state{leader = State#state.leader, resp_counter = State#state.resp_counter + 1, status = State#state.status, parent = State#state.parent}}
                    end;
                false ->
                    io:format("echo_false_false ~n"),
                    {noreply, State}
            end
    end;

handle_cast({ok, Leader}, State) ->
    io:format("sssrt ~n"),
    case Leader == State#state.leader of
        true ->
            Guard = State#state.resp_counter + 1,
            Nodes = [node() | nodes()],
            case Guard == length(Nodes) - 1 of
                true -> 
                    case State#state.status == initiator of 
                        true ->
                            State#state.reply_id ! {success, State#state.leader},
                            {noreply, #state{leader = State#state.leader, resp_counter = State#state.resp_counter + 1, status = done, parent = State#state.parent}};
                        false ->
                            gen_server:cast({ticket_system_server, State#state.parent}, {ok, State#state.leader}), %% prob wrong
                            {noreply, #state{leader = State#state.leader, resp_counter = State#state.resp_counter + 1, status = done, parent = State#state.parent}}
                    end;
                false -> 
                 {noreply, #state{leader = State#state.leader, resp_counter = State#state.resp_counter + 1, status = State#state.status, parent = State#state.parent}}
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
    gen_server:abcast([node() | nodes()], ticket_system_server, {echo, node()}). %% should send (async) own pid to all connected nodes with name elector

echo_leader(Leader) ->
    io:format("echoin' ~n"),
    gen_server:abcast(ticket_system_server, {echo, Leader, node()}).

%% net_adm, net_kernel, global
%% world, names, register_name

get_leader_pid(Leader = {Pid , _ , _ , _, _}) ->
    Pid.
