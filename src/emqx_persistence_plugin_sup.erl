%%%-------------------------------------------------------------------
%% @doc emqx_persistence_plugin top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(emqx_persistence_plugin_sup).
-include("emqx_persistence_plugin.hrl").
-define(ECPOOL_WORKER, emqx_persistence_plugin_cli).
-behaviour(supervisor).
-export([start_link/0]).

-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    {ok, {{one_for_one, 10, 100}, []}}.
