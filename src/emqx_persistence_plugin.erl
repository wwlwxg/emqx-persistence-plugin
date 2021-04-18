-module(emqx_persistence_plugin).

-include("emqx_persistence_plugin.hrl").
-include_lib("emqx/include/emqx.hrl").

-export([ register_metrics/0, load/0, unload/0]).
-export([ on_message_publish/2]).
-define(LOG(Level, Format, Args), emqx_logger:Level("emqx_persistence_plugin: " ++ Format, Args)).

register_metrics() ->
    [emqx_metrics:new(MetricName)
    || MetricName <- ['emqx_persistence_plugin.message_publish']].

load() ->
    lists:foreach(
        fun({Hook, Fun, Filter}) ->
            load_(Hook, binary_to_atom(Fun, utf8), {Filter})
        end, parse_rule(application:get_env(?APP, hooks, []))).

unload() ->
    lists:foreach(
        fun({Hook, Fun, _Filter}) ->
            unload_(Hook, binary_to_atom(Fun, utf8))
        end, parse_rule(application:get_env(?APP, hooks, []))).

%%--------------------------------------------------------------------
%% Message publish
%%--------------------------------------------------------------------
on_message_publish(Message = #message{topic = <<"$SYS/", _/binary>>}, _Env) ->
    {ok, Message};
% point to point
on_message_publish(Message = #message{ topic =  <<"$P2P/", PeerClientId/binary>>,
                                          qos = QOS ,
                                          payload = Payload ,
                                          from = From},
                                            _Env) ->
      case erlang:byte_size(PeerClientId) > 0 of 
        true ->
          case rpc:multicall([node() | nodes()], ets,lookup, [emqx_channel, PeerClientId]) of
            {[[{_, ChannelPid}] | _] ,_} ->
              P2PMessage = emqx_message:make(From, QOS, <<"$P2P/", PeerClientId/binary >> , Payload),
              ChannelPid ! {deliver, <<"$P2P/", PeerClientId/binary>>, P2PMessage},
              {ok, Message};
            _ ->
              {stop, #message{headers = #{allow_publish => false}}}
          end;
        _ ->
          {stop, #message{headers = #{allow_publish => false}} }
      end;

%%on_message_publish(Message = #message{ topic =  <<"$P2P/", PeerClientId/binary>>,
%%                                        qos = QOS ,
%%                                        payload = Payload ,
%%                                        from = From},
%%                                    _Env) ->
%%    if erlang:byte_size(PeerClientId) > 0 ->
%%            case string:str(erlang:binary_to_list(PeerClientId), "/") of
%%                0 ->
%%                  case rpc:multicall([node() | nodes()], ets, lookup, [emqx_channel, PeerClientId]) of
%%                    {[[{_, ChannelPid}] | _], _} ->
%%                      P2PMessage = emqx_message:make(From, QOS, <<"$P2P/", PeerClientId/binary >> , Payload),
%%                      ChannelPid ! {deliver, <<"$P2P/", PeerClientId/binary>>, P2PMessage},
%%                      {ok, Message};
%%                    _ ->
%%                      {stop, #message{headers = #{allow_publish => false}}}
%%                  end;
%%                _ ->
%%                    {stop, #message{headers = #{allow_publish => false}} }
%%            end
%%    end;

on_message_publish(Message , _Env) ->
    {ok, Message}.
%%--------------------------------------------------------------------
%% Internal functions
%%--------------------------------------------------------------------
parse_rule(Rules) ->
    parse_rule(Rules, []).
parse_rule([], Acc) ->
    lists:reverse(Acc);
parse_rule([{Rule, Conf} | Rules], Acc) ->
    Params = emqx_json:decode(iolist_to_binary(Conf)),
    Action = proplists:get_value(<<"action">>, Params),
    Filter = proplists:get_value(<<"topic">>, Params),
    parse_rule(Rules, [{list_to_atom(Rule), Action, Filter} | Acc]).

%%with_filter(Fun, _, undefined) ->
%%    Fun(), ok;
%%with_filter(Fun, Topic, Filter) ->
%%    case emqx_topic:match(Topic, Filter) of
%%        true  -> Fun(), ok;
%%        false -> ok
%%    end.

load_(Hook, _Fun, Params) ->
    case Hook of
        'message.publish'     -> emqx:hook(Hook, fun emqx_persistence_plugin:on_message_publish/2, [Params])
    end.

unload_(Hook, _Fun) ->
    case Hook of
        'message.publish'     -> emqx:unhook(Hook, fun emqx_persistence_plugin:on_message_publish/2)
    end.
