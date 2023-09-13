-module(user_api).
-export([add_client/3, remove_client/1, update_costs/1, start_iteration/0, system_start/0, add_office/2, remove_office/1]).

%% Adds a client to the system
%% Needs client id, id of the relative office and the list of costs to go to other clients
add_client(Client1, Office, Costs = [{{_, _}, _} | _]) ->
    case gen_server:call(user_node, {add_client, Client1,  Office, Costs}) of 
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
update_costs(Costs = [{{_, _}, _} | _]) ->
    case gen_server:call(user_node, {update_costs, Costs}) of
        {success, _} ->
            {ok, update_successful};
        {failure, _} ->
            {failure, update_not_successful}
    end.

start_iteration() ->
    case gen_server:call(user_node, {start_aco}) of
        {success, _} ->
            {ok, iteration_start_successful};
        {failure, _} ->
            {failure, iteration_start_unsuccessful}
    end.

system_start() ->
    user_node:start_link(),
    ticket_system_server:start_link(),
    aco_node:start_link(),
    flooding:start_link(),
    something_for_pinging(),
    case gen_server:call(user_node, {system_start}) of
        {success, _} ->
            {ok, system_start_successful};
        {failure, _} ->
            {failure, system_start_unsuccessful}
    end.

add_office(OfficeID, OfficeNode) ->
    case gen_server:call(user_node, {add_office, OfficeID, OfficeNode}) of
        {success, _} ->
            {ok, addition_successful};
        {failure, _} ->
            {failure, addition_failure}
    end.

remove_office(OfficeID) ->
    case gen_server:call(user_node, {remove_office, OfficeID}) of
        {success, _} ->
            {ok, removal_successful};
        {failure, _} ->
            {failure, removal_failure}
    end.

system_stop() ->
    case gen_server:call(user_node, {system_stop}) of
        {success, _} ->
            {ok, system_stop_successful};
        {failure, _} ->
            {failure, system_stop_unsuccessful}
    end.

something_for_pinging() ->
    ok.