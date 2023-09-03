-module(user_api).

%% Adds a client to the system
%% Needs client id, id of the relative office and the list of costs to go to other clients
add_client(Client1, Office, Costs = [{{Client1, Client2}, Cost}]) ->
    case gen_server:call(user_node, {add_client, Client1,  Office, Costs}) of ->
        {success, _} ->
            {addition_successful};
        {failure, _} ->
            {addition_not_successful}
    end.

%% Removes a client from the system
remove_client(Client) ->
    case gen_server:call(user_node, {remove_client, Client}) of ->
        {success, _} ->
            {addition_successful};
        {failure, _} ->
            {addition_not_successful}
    end.

%% Updates the costs of going from client c1 to client c2
update_costs(Costs = [{Client1, Client2}, Cost]) ->
    case gen_server:call(user_node, {update_costs, Costs}) of ->
        {success, _} ->
            {addition_successful};
        {failure, _} ->
            {addition_not_successful}
    end.