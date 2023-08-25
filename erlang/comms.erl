-module(comms).

%% Sends a message synchronously
send_sync(Receiver, Msg) ->
    done.

%% Sends a message asynchronously
send_async(Receiver, Msg) ->
    done.

%% Starts an echo to all neighbours
start_echo(Msg, [Neighbour]) ->
    done.

%% Starts an echo with extiction with all neighbours
start_echo_with_extinction(Msg, [Neighbour], ID) ->
    done.




