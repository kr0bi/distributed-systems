-module(ticket_system_server).
-behaviour(gen_server).

%% API
-export([start/0, start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

%%% Record used by the process for election
%%% leader -> current leader for the process
%%% resp_counter -> amount of messages containg the current leader received up until now
%%% status -> status in the election [initiator, waiting, done]
%%% reply_id -> global name for the node calling for the election
%%% parent -> parent for the echo with extinction algorithm
-record(state, {leader, resp_counter, status, reply_id, parent, ticket_counter}).

%% Interface
start() ->
   gen_server:start({local, ?MODULE}, ?MODULE, [], []).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).
    %register(?MODULE,Pid).


%% Callbacks

init(_Args) ->
    {ok, #state{leader = node(), resp_counter = 0, status = initiator, parent = node(), ticket_counter = 0}}.

handle_call(ticket_request, _From, State) ->
    case State#state.leader == node() of
        true ->
            {reply, {ticket, node(), State#state.ticket_counter}, State#state{ticket_counter = State#state.ticket_counter + 1}};
        false ->
            {reply, {not_leader, State#state.leader}, State}
    end;

handle_call(get_leader, _From, State) ->
    {reply, {leader, State#state.leader}, State};

handle_call(connect, _From, State) ->
    Node = lists:nth(rand:uniform(length(nodes())), nodes()),
    {leader, Leader} = gen_server:call({ticket_system_server, Node}, get_leader, []),
    {reply, ok, State#state{leader = Leader, resp_counter = 0, status = done, reply_id = undefined, parent = Node, ticket_counter = 0}};


%%% handles start election call
handle_call({start_election}, From, State) ->
    io:format("startin~w~n", [node()]),
    gen_server:abcast(nodes(), ticket_system_server, {start_election, From}),
    case nodes() of 
        [] -> {success, State#state.leader};
        _ -> echo_leader(node(), nodes()) %%% echoes itself to all known nodes
    end,
    {noreply, State#state{leader = node(), resp_counter = 0, status = initiator, reply_id = From, parent = node(), ticket_counter = State#state.ticket_counter}}; %%% state update

handle_call(_, _From, State) ->
    {noreply, State}.

handle_cast({start_election, From}, State) ->
    io:format("starting after cast~w~n", [node()]),
    echo_leader(node(), nodes()), %%% echoes itself to all known nodes
    {noreply, State#state{leader = node(), resp_counter = 0, status = initiator, reply_id = From, parent = node(), ticket_counter = State#state.ticket_counter}}; %%% state update

%%% handles general echo message
handle_cast({echo, Leader, Sender}, State) ->
    io:format("startin in the castin~w~n", [node()]),
    case Leader > State#state.leader of %%% checks whether the new leader is better than the currently known one
        true -> 
            io:format("true, Leader recieved is ~w i'm ~w ~n", [Leader, node()]),
            echo_leader(Leader, nodes()), %%% echoes new leader
            {noreply, State#state{leader = Leader, resp_counter = 1, reply_id = State#state.reply_id, status = waiting, parent = Sender, ticket_counter = State#state.ticket_counter}};
        false -> 
            io:format("false, Leader recieved is ~w i'm ~w ~n", [Leader, node()]),
            case Leader == State#state.leader of %%% checks if leader receveid is the same as the known one
                true ->
                    io:format("false true, Leader recieved is ~w i'm ~w ~n", [Leader, node()]),
                    Guard = State#state.resp_counter + 1,
                    case Guard == length(nodes()) of %%% checks if we have received the message from all neighbours
                        true -> 
                            io:format("false true true, Leader recieved is ~w i'm ~w ~n", [Leader, node()]),
                            case State#state.status == initiator of  %%% if the node is the initiator, election is done
                                true ->
                                    io:format("false true true true, Leader recieved is ~w i'm ~w ~n", [Leader, node()]),
                                    {Replies, _} = gen_server:multi_call(aco_node, ticket_counter),
                                    TicketCounter = get_highest_counter(Replies),
                                    gen_server:reply(State#state.reply_id, {success, State#state.leader}), %%% send back the leader
                                    {noreply, State#state{leader = State#state.leader, resp_counter = State#state.resp_counter + 1, reply_id = State#state.reply_id, status = done, parent = State#state.parent, ticket_counter = TicketCounter}};
                                false ->
                                    io:format("false true true false, Leader recieved is ~w i'm ~w ~n", [Leader, node()]),
                                    gen_server:cast({ticket_system_server, State#state.parent}, {ok, State#state.leader}), %% send to parent that the node is done
                                    {noreply, State#state{leader = State#state.leader, resp_counter = State#state.resp_counter + 1, reply_id = State#state.reply_id, status = done, parent = State#state.parent, ticket_counter = State#state.ticket_counter}}
                            end;
                        false -> %%% continue
                            io:format("false true false, Leader recieved is ~w i'm ~w ~n", [Leader, node()]),
                            {noreply, State#state{leader = State#state.leader, resp_counter = State#state.resp_counter + 1, reply_id = State#state.reply_id, status = State#state.status, parent = State#state.parent, ticket_counter = State#state.ticket_counter}}
                    end;
                false ->
                    io:format("false false, Leader recieved is ~w i'm ~w ~n", [Leader, node()]),
                    {noreply, State}
            end
    end;

%%% handles messages from 'done' nodes, cases are the same as above
%%% might actually not be needed, useful for clarity though
handle_cast({ok, Leader}, State) ->
    io:format("received ok ~w i'm ~w~n", [Leader, node()]),
    case Leader == State#state.leader of
        true ->
            io:format("true ok ~w i'm ~w~n", [Leader, node()]),
            Guard = State#state.resp_counter + 1,
            case (Guard == length(nodes())) or (length(nodes()) == 0) of
                true -> 
                    io:format("true true ok ~w i'm ~w~n", [Leader, node()]),
                    case State#state.status == initiator of 
                        true ->
                            io:format("elected ok ~w i'm ~w~n", [Leader, node()]),
                            {Replies, _} = gen_server:multi_call(aco_node, ticket_counter),
                            TicketCounter = get_highest_counter(Replies),
                            gen_server:reply(State#state.reply_id, {success, State#state.leader}),
                            {noreply, State#state{leader = State#state.leader, resp_counter = State#state.resp_counter + 1, reply_id = State#state.reply_id, status = done, parent = State#state.parent, ticket_counter = TicketCounter}};
                        false ->
                            io:format("not elected ok ~w i'm ~w~n", [Leader, node()]),
                            gen_server:cast({ticket_system_server, State#state.parent}, {ok, State#state.leader}),
                            {noreply, State#state{leader = State#state.leader, resp_counter = State#state.resp_counter + 1, reply_id = State#state.reply_id, status = done, parent = State#state.parent, ticket_counter = State#state.ticket_counter}}
                    end;
                false -> 
                    io:format("true false ok ~w i'm ~w~n", [Leader, node()]),
                 {noreply, #state{leader = State#state.leader, resp_counter = State#state.resp_counter + 1, reply_id = State#state.reply_id, status = State#state.status, parent = State#state.parent, ticket_counter = State#state.ticket_counter}}
            end;
        false ->
            io:format("false ok ~w i'm ~w~n", [Leader, node()]),
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

%%% echoes leader to all known nodes of this type
echo_leader(Leader, Nodes) ->
    io:format("echoin ~w i'm ~w~n", [Leader, node()]),
    gen_server:abcast(Nodes, ticket_system_server, {echo, Leader, node()}). %%% multiple async send

delete_parent(List, Parent) ->
    lists:delete(Parent, List).

%%% Returns highest ticket counter from multi_call replies
get_highest_counter([]) ->
    0;
get_highest_counter([{_, {ticket_counter, Counter}} | Replies]) ->
    Res = get_highest_counter(Replies),
    case Counter >= Res of
        true ->
            Counter;
        false ->
            Res
    end.
