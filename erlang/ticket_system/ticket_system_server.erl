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
   gen_server:start({global, ?MODULE}, ?MODULE, [], []).

start_link() ->
    {ok, Pid} = gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).
    %register(?MODULE,Pid).


%% Callbacks

init(_Args) ->
    {ok, #state{leader = node(), resp_counter = 0, status = initiator, parent = node()}}.

handle_call(ticket_request, _From, State) ->
    case State#state.leader == node() of
        true ->
            {reply, {ticket, State#state.ticket_counter}, State#state{ticket_counter = State#state.ticket_counter + 1}};
        false ->
            {reply, {not_leader, State#state.leader}, State}
    end;

handle_call(get_leader, _From, State) ->
    {reply, {leader, State#state.leader}, State};

handle_call(Msg, _From, State) ->
    {noreply, State}.

%%% handles start election call
handle_cast({start_election, From}, State) ->
    echo_leader(node(), nodes()), %%% echoes itself to all known nodes
    {noreply, #state{leader = node(), resp_counter = 0, status = initiator, reply_id = From, parent = node()}}; %%% state update

%%% handles general echo message
handle_cast({echo, Leader, Sender}, State) ->
    case Leader > State#state.leader of %%% checks whether the new leader is better than the currently known one
        true -> 
            Nodes = delete_parent(nodes(), Sender),
            echo_leader(Leader, Nodes), %%% echoes new leader
            {noreply, #state{leader = Leader, resp_counter = 1, reply_id = State#state.reply_id, status = waiting, parent = Sender}};
        false -> 
            case Leader == State#state.leader of %%% checks if leader receveid is the same as the known one
                true ->
                    Guard = State#state.resp_counter + 1,
                    Nodes = delete_parent(nodes(), State#state.parent),
                    case Guard == length(Nodes) of %%% checks if we have received the message from all neighbours
                        true -> 
                            case State#state.status == initiator of  %%% if the node is the initiator, election is done
                                true ->
                                    global:send(State#state.reply_id, {success, State#state.leader}), %%% send back the leader
                                    {noreply, #state{leader = State#state.leader, resp_counter = State#state.resp_counter + 1, reply_id = State#state.reply_id, status = done, parent = State#state.parent, ticket_counter = 0}};
                                false ->
                                    gen_server:cast({ticket_system_server, State#state.parent}, {ok, State#state.leader}), %% send to parent that the node is done
                                    {noreply, #state{leader = State#state.leader, resp_counter = State#state.resp_counter + 1, reply_id = State#state.reply_id, status = done, parent = State#state.parent}}
                            end;
                        false -> %%% continue
                            {noreply, #state{leader = State#state.leader, resp_counter = State#state.resp_counter + 1, reply_id = State#state.reply_id, status = State#state.status, parent = State#state.parent}}
                    end;
                false ->
                    {noreply, State}
            end
    end;

%%% handles messages from 'done' nodes, cases are the same as above
%%% might actually not be needed, useful for clarity though
handle_cast({ok, Leader}, State) ->
    case Leader == State#state.leader of
        true ->
            Guard = State#state.resp_counter + 1,
            Nodes = delete_parent(nodes(), State#state.parent),
            case Guard == length(Nodes) of
                true -> 
                    case State#state.status == initiator of 
                        true ->
                            global:send(State#state.reply_id, {success, State#state.leader}),
                            {noreply, #state{leader = State#state.leader, resp_counter = State#state.resp_counter + 1, reply_id = State#state.reply_id, status = done, parent = State#state.parent, ticket_counter = 0}};
                        false ->
                            gen_server:cast({ticket_system_server, State#state.parent}, {ok, State#state.leader}),
                            {noreply, #state{leader = State#state.leader, resp_counter = State#state.resp_counter + 1, reply_id = State#state.reply_id, status = done, parent = State#state.parent}}
                    end;
                false -> 
                 {noreply, #state{leader = State#state.leader, resp_counter = State#state.resp_counter + 1, reply_id = State#state.reply_id, status = State#state.status, parent = State#state.parent}}
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

%%% echoes leader to all known nodes of this type
echo_leader(Leader, Nodes) ->
    gen_server:abcast(Nodes, ticket_system_server, {echo, Leader, node()}). %%% multiple async send

delete_parent(List, Parent) ->
    lists:delete(Parent, List).