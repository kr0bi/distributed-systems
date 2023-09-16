-module(user_api).
-export([add_client/3, remove_client/1, update_costs/1, add_office/2, remove_office/1]).
-export([system_setup/0, init_add_clients/1, init_add_costs/1, system_start/0, system_setup_simple/0]).


%% Function to easily add a group of clients
%% Needs a list of tuples composed of a list of clients and the related office
%% Only usable while the algorithm is not running
init_add_clients([]) ->
    [];
init_add_clients([{ClientList, OfficeID} | List]) ->
    case gen_server:call(user_node, {add_clients, ClientList, OfficeID}) of
        {success, _} ->
            init_add_clients(List),
            {ok, addition_successful};
        {failure, Reason} ->
            {failure, addition_not_successful}
    end.

init_add_costs(CostList) ->
    case gen_server:call(user_node, {add_edges, CostList}) of
        {success, _} ->
            {ok, addition_successful};
        {failure, Reason} ->
            {failure, addition_not_successful}
    end.

%% Adds a client to the system
%% Needs client id, id of the relative office and the list of costs to go to other clients
add_client(Client1, Office, Costs) ->
    case gen_server:call(user_node, {add_client_running, Client1,  Office, Costs}) of 
        {success, _} ->
            {ok, addition_successful};
        {failure, _} ->
            {failure, addition_not_successful}
    end.

%% Removes a client from the system
remove_client(Client) ->
    case gen_server:call(user_node, {remove_client, Client}) of
        {success, _} ->
            {ok, removal_successful};
        {failure, _} ->
            {failure, removal_not_successful}
    end.

%% Updates the costs of going from client c1 to client c2
update_costs(Costs) ->
    %NewCosts = lists:map(fun({X, Y, Z}) -> {list_to_integer(X), list_to_integer(Y), get_weight(Z)} end, Costs),
    case gen_server:call(user_node, {update_costs, Costs}) of
        {success, _} ->
            io:format("Costs succ"),
            {ok, update_successful};
        {failure, Reason} ->
            io:format("Costs fail, ~w ~n", [Reason]),
            {failure, update_not_successful}
    end.

%% Starts the system by starting the ticket system and the aco algorithm
system_start() ->
    ticket_system:start_election(),
    case gen_server:call(user_node, {start_aco}) of
        {success, _} ->
            {ok, iteration_start_successful};
        {failure, _} ->
            {failure, iteration_start_unsuccessful}
    end.

%% Sets up all the processes for the system
system_setup() ->
    user_node:start_link(),
    ticket_system_server:start_link(),
    aco_node:start_link(),
    flooding:start_link().

%% Starts only the processes strictly necessary for the system
%% does not enable interactions with the system
system_setup_simple() ->
    ticket_system_server:start_link(),
    aco_node:start_link().

%% Adds an office to the system
add_office(OfficeID, OfficeNode) ->
    gen_server:multi_call(user_node, {add_office, OfficeID, OfficeNode}).

%% Removes an office from the system
remove_office(OfficeID) ->
    gen_server:multi_call(user_node, {remove_office, OfficeID}).

system_stop() ->
    case gen_server:call(user_node, {system_stop}) of
        {success, _} ->
            {ok, system_stop_successful};
        {failure, _} ->
            {failure, system_stop_unsuccessful}
    end.