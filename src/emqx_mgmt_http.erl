%%--------------------------------------------------------------------
%% Copyright (c) 2018 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

-module(emqx_mgmt_http).

-author("Feng Lee <feng@emqtt.io>").

-export([start_listeners/0, handle_request/2, stop_listeners/0]).

-export([init/2]).

-define(APP, emqx_management).

-define(EXCEPT, [add_app, del_app, list_apps, lookup_app, update_app]).

%%--------------------------------------------------------------------
%% Start/Stop Listeners
%%--------------------------------------------------------------------

start_listeners() ->
    lists:foreach(fun start_listener/1, listeners()).

stop_listeners() ->
    lists:foreach(fun stop_listener/1, listeners()).

start_listener({Proto, Port, Options}) when Proto == http ->
    Dispatch = [{"/status", emqx_mgmt_http, []},
                {"/api/v2/[...]", minirest, http_handlers()}],
    minirest:start_http(listener_name(Proto), [{port, Port}] ++ Options, Dispatch);

start_listener({Proto, Port, Options}) when Proto == https ->
    Dispatch = [{"/status", emqx_mgmt_http, []},
                {"/api/v2/[...]", minirest, http_handlers()}],
    minirest:start_https(listener_name(Proto), [{port, Port}] ++ Options, Dispatch).

stop_listener({Proto, Port, _}) ->
    minirest:stop_http(listener_name(Proto)).

listeners() ->
    application:get_env(?APP, listeners, []).

listener_name(Proto) ->
    list_to_atom(atom_to_list(Proto) ++ ":management").

http_handlers() ->
    [{"/api/v2", minirest:handler(#{apps => [?APP], except => ?EXCEPT }),
                 [{authorization, fun authorize_appid/1}]}].

%%--------------------------------------------------------------------
%% Handle 'status' request
%%--------------------------------------------------------------------
init(Req, Opts) ->
    Req1 = handle_request(cowboy_req:path(Req), Req),
    {ok, Req1, Opts}.

handle_request(Path, Req) ->
    handle_request(cowboy_req:method(Req), Path, Req).

handle_request(<<"GET">>, <<"/status">>, Req) ->
    {InternalStatus, _ProvidedStatus} = init:get_status(),
    AppStatus = case lists:keysearch(emqx, 1, application:which_applications()) of
        false         -> not_running;
        {value, _Val} -> running
    end,
    Status = io_lib:format("Node ~s is ~s~nemqx is ~s",
                            [node(), InternalStatus, AppStatus]),
    cowboy_req:reply(200, #{<<"content-type">> => <<"text/plain">>}, Status, Req);

handle_request(_Method, _Path, Req) ->
    cowboy_req:reply(400, #{<<"content-type">> => <<"text/plain">>}, <<"Not found.">>, Req).

authorize_appid(Req) ->
    case cowboy_req:parse_header(<<"authorization">>, Req) of
        {basic, AppId, AppSecret} -> emqx_mgmt_auth:is_authorized(AppId, AppSecret);
         _  -> false
    end.
