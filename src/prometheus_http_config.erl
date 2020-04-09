%% @private
-module(prometheus_http_config).

-export([path/0,
         valid_path_and_registry/2,
         format/0,
         allowed_formats/0,
         registry/0,
         telemetry_registry/0,
         port/0,
         bind_address/0,
         ipfamily/0,
         socket_type/0,
         profile/0,
         authorization/0]).

%% TODO: remove
-define(PROMETHEUS_REGISTRY_TABLE, prometheus_registry_table).

%% Macros.
-define(DEFAULT_PATH, "/metrics").
-define(DEFAULT_FORMAT, auto).
-define(DEFAULT_REGISTRY, auto).
-define(DEFAULT_TELEMETRY_REGISTRY, default).
-define(DEFAULT_AUTHORIZATION, false).
-define(DEFAULT_PORT, 8081).
-define(DEFAULT_BIND_ADDRESS, any).
-define(DEFAULT_IPFAMILY, inet).
-define(DEFAULT_SOCKET_TYPE, ip_comm).
-define(DEFAULT_PROFILE, default).

-define(DEFAULT_CONFIG, [{path, ?DEFAULT_PATH},
                         {format, ?DEFAULT_FORMAT},
                         {registry, ?DEFAULT_REGISTRY},
                         {telemetry_registry, ?DEFAULT_TELEMETRY_REGISTRY},
                         {port, ?DEFAULT_PORT},
                         {authorization, ?DEFAULT_AUTHORIZATION}]).

%%%===================================================================
%%% API
%%%===================================================================

path() -> get_value(path, ?DEFAULT_PATH).

valid_path_and_registry(URI, RegistryO) ->
  case try_match_path(path(), URI) of
    false -> false;
    undefined ->
      validate_registry(RegistryO, registry());
    Registry0 ->
      case prometheus_registry:exists(Registry0) of
        false ->
          {registry_not_found, Registry0};
        Registry ->
          validate_registry(Registry, registry())
      end
  end.

registry() -> get_value(registry, ?DEFAULT_REGISTRY).

telemetry_registry() ->
  get_value(telemetry_registry, ?DEFAULT_TELEMETRY_REGISTRY).

format() -> get_value(format, ?DEFAULT_FORMAT).

allowed_formats() ->
  [{prometheus_text_format:content_type(), prometheus_text_format},
   {prometheus_protobuf_format:content_type(), prometheus_protobuf_format}].

port() -> get_value(port, ?DEFAULT_PORT).

bind_address() -> get_value(bind_address, ?DEFAULT_BIND_ADDRESS).

ipfamily() -> get_value(ipfamily, ?DEFAULT_IPFAMILY).

socket_type() -> get_value(socket_type, ?DEFAULT_SOCKET_TYPE).

profile() -> get_value(profile, ?DEFAULT_PROFILE).

authorization() ->
  case get_value(authorization, ?DEFAULT_AUTHORIZATION) of
    false ->
      fun(_) ->
          true
      end;
    {basic, Login, Password} ->
      fun(#{headers := Headers}) ->
          call_with_basic_auth(Headers,
                               fun(Login1, Password1) ->
                                   case {Login1, Password1} of
                                     {Login, Password} ->
                                       true;
                                     _ ->
                                       false
                                   end
                               end)
      end;
    {basic, {Module, Fun}}
      when is_atom(Module) andalso is_atom(Fun) ->
      fun (#{headers := Headers}) ->
          call_with_basic_auth(Headers,
                               fun Module:Fun/2)
      end;
    {basic, Module} when is_atom(Module)->
      fun (#{headers := Headers}) ->
          call_with_basic_auth(Headers,
                               fun Module:authorize/2)
      end;
    {Module, Fun}
      when is_atom(Module) andalso is_atom(Fun) ->
      fun Module:Fun/1;
    Module when is_atom(Module) ->
      fun Module:authorize/1;
    C ->
      {invalid_authorize, C}
  end.

%%%===================================================================
%%% Private functions
%%%===================================================================

validate_registry(undefined, auto) ->
  {true, default};
validate_registry(Registry, auto) ->
  {true, Registry};
validate_registry(Registry, Registry) ->
  {true, Registry};
validate_registry(Asked, Conf) ->
  {registry_conflict, Asked, Conf}.

try_match_path(_, true) ->
  undefined;
try_match_path(Path, Path) ->
  undefined;
try_match_path(Path, URI) ->
  PS = Path ++ "/",

  case lists:prefix(PS, URI) of
    true ->
      lists:sublist(URI, length(PS)+1, length(URI));
    false ->
      false
  end.

get_value(Key, Default) -> proplists:get_value(Key, config(), Default).

config() -> application:get_env(prometheus, prometheus_http, ?DEFAULT_CONFIG).

call_with_basic_auth(Headers, Fun) ->
  Authorization =  Headers("authorization", undefined),
  call_with_basic_auth_(Authorization, Fun).

call_with_basic_auth_("Basic " ++ Encoded, Fun) ->
  call_with_basic_auth__(Encoded, Fun);
call_with_basic_auth_(<<"Basic ", Encoded/binary>>, Fun) ->
  call_with_basic_auth__(Encoded, Fun);
call_with_basic_auth_(_Authorization, _Fun) ->
  false.

call_with_basic_auth__(Encoded, Fun) ->
  Params = base64:decode_to_string(Encoded),
  case string:tokens(Params, ":") of
    [Login, Password] ->
      Fun(Login, Password);
    _ ->
      false
  end.
