-module(ticket_system).
-export([start/0, start_election/1, request_ticket/0]).

start() ->
    register(?MODULE, Pid=spawn(?MODULE, init, [])),
    Pid.

%% Requests a ticket from the ticket master
request_ticket() ->
    Reply = gen_server:call(ticket_system_server, get_leader, 5000), 
    case Reply of
        {timeout, _} ->
            Reply;
        {leader, Leader} ->
            Reply2 = gen_server:call({ticket_system_server, Leader}, ticket_request, 5000),
            %io:format("Leader is ~p~n", [Leader]),
            case Reply2 of
                {timeout, _} ->
                    Reply2;
                {ticket, Leader, Ticket} ->
                    {ok, Leader, Ticket}
            end
    end.

%% Starts a new election for the ticket master
start_election(Name) -> %%% NAME ONLY FOR DEBUG PURPOSE
    global:register_name(Name, self()), %%% DEBUG LINE ONLY, needed to know where to send back the leader
                                        %%% in production should be the user_node
    gen_server:abcast(ticket_system_server, {start_election, Name}), %%% NAME ONLY FOR DEBUG PURPOSE
    receive
        {success, Leader} ->
            Leader
    after 10000 ->
        {timeout, nochance}
    end.


%% Asks for a connection to the ticket master
ask_for_master() ->
    Reply = gen_server:call(ticket_system_server, get_leader, 5000), 
    case Reply of
        {timeout, _} ->
            Reply;
        {leader, Leader} ->
            Leader
    end.