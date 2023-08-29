-module(ticket_system).
-export([start/0, start_election/0, request_ticket/0, grant_ticket/2]).

start() ->
    register(?MODULE, Pid=spawn(?MODULE, init, [])),
    Pid.

%% Requests a ticket from the ticket master
request_ticket() ->
    Leader = gen_server:call(ticket_system_server, get_leader),
    Ticket = Leader ! {ticket_request},
    {ok, Ticket}.

%% Grants a ticket to the user
grant_ticket(User, Ticket_Counter) ->
    done.

%% Starts a new election for the ticket master
start_election() ->
    Reply = gen_server:multi_call(ticket_system_server, start_election),
    Reply.

%% Asks for a connection to the ticket master
ask_for_master() ->
    done.