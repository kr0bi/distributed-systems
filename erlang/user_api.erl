-module(user_api).

%% Adds a client to the system
%% Needs client id, id of the relative office and the list of costs to go to other clients
add_client(Client1, Office, [{{Client1, Client2}, Cost}]) ->
    done.

%% Removes a client from the system
remove_client(Client) ->
    done.

%% Updates the costs of going from client c1 to client c2
update_costs([{Client1, Client2}, Cost]) ->
    done.