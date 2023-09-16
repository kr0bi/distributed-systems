-module(ticket_system).
-export([start/0, start_election/0, request_ticket/0, connect_to_system/0, ask_for_master/0]).

start() ->
    register(?MODULE, Pid=spawn(?MODULE, init, [])),
    Pid.

%% Requests a ticket from the ticket master
request_ticket() ->
    Reply = gen_server:call(ticket_system_server, get_leader, 5000),
    case Reply of
        {leader, Leader} ->
            try Reply2 = gen_server:call({ticket_system_server, Leader}, ticket_request, 5000) of 
                _ ->
                    case Reply2 of
                        {ticket, Leader, Ticket} ->
                            {ok, Leader, Ticket};
                        _ -> %% re-elect leader and restart
                        start_election(),
                        request_ticket()
                    end       
                catch
                    _:_ ->
                        start_election(),
                        request_ticket()
                end;                     
        _ -> %% re-elect leader and restart
            start_election(),
            request_ticket()
    end.

%% Starts a new election for the ticket master
start_election() -> 
    case gen_server:call(ticket_system_server, {start_election}, 20000) of
        timeout ->
            {failed, electiontimeout};
        _ ->
            election_successful
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

connect_to_system() ->
    gen_server:call(ticket_system_server, connect, 5000).