-module(ticket_system_server).
-behaviour(gen_server).

%% API
-export([start/0, start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-record(leader, {pid, resp_counter}).

%% Interface
start(Name) ->
   gen_server:start({global, ?MODULE}, ?MODULE, [], []).

start_link(Name) ->
    gen_server:start_link({local, Name}, ?MODULE, [], []).


%% Callbacks

init(_Args) ->
    {ok, #state{dummy=1}}.

handle_call(start_election, _From, State) ->
    #{leader := Leader} = NewState = start_election(State),
    {reply, Leader, NewState};

handle_call({echo, Pid}, _From, State) ->
    case Pid > State#leader.pid of
        true -> 
            echo_leader(Pid),
            {noreply, #leader{pid = Pid, resp_counter = State#leader.resp_counter}};
        false -> 
            {noreply, State};

handle_call({ok, Pid}, _From, State) ->
    if Pid == State#leader.pid ->
        #leader{resp_counter = State#leader.resp_counter + 1},
        {noreply, #leader{pid = State#leader.pid, resp_counter = State#leader.resp_counter + 1}}
    end.
    {noreply, State}.
    
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%
start_election(State) ->
    gen_server:abcast([node() | nodes()], ticket_system_server, {echo, self()}). %% should send own pid to all connected nodes with name elector

echo_leader(Pid) ->
    gen_server:abcast([node() | nodes()], ticket_system_server, Pid).


%% net_adm, net_kernel, global
%% world, names, register_name
