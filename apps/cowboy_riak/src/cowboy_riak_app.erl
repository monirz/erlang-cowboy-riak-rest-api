%%%-------------------------------------------------------------------
%% @doc cowboy_riak public API
%% @end
%%%-------------------------------------------------------------------

-module(cowboy_riak_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%%====================================================================
%% API
%%====================================================================

start(_Type, _Args) ->
   	Dispatch = cowboy_router:compile([
   		{'_', [
   			{"/users", user_handler, []},
         {"/users/:user_id", user_handler, []}
   		]}
   	]),
   	{ok, _} = cowboy:start_clear(http, [{port, 8080}], #{
   		env => #{dispatch => Dispatch}
   	}),
    cowboy_riak_sup:start_link().


%%--------------------------------------------------------------------
stop(_State) ->
    ok.

%%====================================================================
%% Internal functions
%%====================================================================
