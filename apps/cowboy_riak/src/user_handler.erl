
-module(user_handler).

-export([init/2]).
-export([get_json/2]).
-export([content_types_provided/2]).
-export([allowed_methods/2]).
-export([content_types_accepted/2]).
-export([put_json/2]).
-export([delete_resource/2]).
-export([list_from_db/2]).

init(Req, Opts) ->
  {cowboy_rest, Req, Opts}.

allowed_methods(Req, State) ->

  Methods = [<<"GET">>, <<"POST">>, <<"DELETE">>],
  {Methods, Req, State}.


content_types_provided(Req, State) ->
    {[{<<"application/json">>, list_from_db}], Req, State}.

content_types_accepted(Req, State) ->
  {[
  {<<"text/html">>, put_json},
  {<<"application/json">>, put_json},
  {<<"application/x-www-form-urlencoded">>, put_json}
], Req, State}.



put_json(Req, State) ->
    io:fwrite("debug"),
   {ok, Body} = save_to_db(Req, State),

    % Doc = {[{message, <<"successful">>}]},
    % Body = jiffy:encode(#{success => Doc}),

    Req0 = cowboy_req:reply(201,
    #{<<"content-type">> => <<"application/json">>},
    Body,
    Req),

    {true, Req0, State}.

%--------------------------------------- Save data to Riak DB ------------------
  save_to_db(Req, State) ->
    {ok, KeyValues, _} = cowboy_req:read_urlencoded_body(Req,
      #{length => 4096, period => 3000}),
    {_, UserName} = lists:keyfind(<<"user_name">>, 1, KeyValues),
    {_, Email} = lists:keyfind(<<"email">>, 1, KeyValues),

%   create json for user data
%
     Message = <<"User created successfully">>,
     UuId = uuid:to_string(uuid:uuid4()),

     RecordId = erlang:iolist_to_binary(UuId),

     {Body2, _, _} = time_to_json(Req, State),
    %  RecordId = <<"147ffc2f-3e79-43a2-99ba-25d35db88a1b">>,
     D = {[{id, RecordId},{user_name, UserName}, {emai, Email}, {created_at, Body2}]},
     Doc = {[{message, Message}, {data, D }, {status, 201}]},

     Body = jiffy:encode(#{success => Doc}),

    %--------------------------------------

      {ok, Pid} = riakc_pb_socket:start_link("127.0.0.1", 8087),

      % JsonString = jiffy:decode(#{success => Doc}),

      % io:fwrite("~p~n", [JsonString]),

      Object = riakc_obj:new(<<"userdata">>, RecordId, D),
      riakc_pb_socket:put(Pid, Object),
      riakc_pb_socket:stop(Pid),

      {ok, Body}.

%------------------------------------ ------------------------------------------
get_json(Req, State) ->
  Body = <<"{\"rest\": \"Hello World!\"}">>,
  {Body, Req, State}.


%--------------------Fetch data from Riak DB -----------------------------------
list_from_db(Req, State) ->

  %
  % QsVals = cowboy_req:parse_qs(Req),
  % {_, Id} = lists:keyfind(<<"user_id">>, 1, QsVals),

try
  UserId = cowboy_req:binding(user_id, Req),
  UserId1 = binary_to_list(UserId),

  io:fwrite("id ~p", [UserId]),

  {ok, Pid} = riakc_pb_socket:start_link("127.0.0.1", 8087),
  {ok, FetchedUser} = riakc_pb_socket:get(Pid,
                                       <<"userdata">>,
                                       UserId),

 % Data = riakc_obj:get_value(FetchedUser),

  {Data} = binary_to_term(riakc_obj:get_value(FetchedUser)),
  riakc_pb_socket:stop(Pid),
  io:fwrite("~p", [Data]),
  User = #{<<"user">> => {Data}, status => 200},
  Body = jiffy:encode(User),
  {Body, Req, State}

catch
  error:Reason ->
    io:format("errorrrrrrrrrrrrrrrrrrr ~p~n", [Reason]),
    case Reason of
      {badmatch,{error,notfound}} ->
        ERR = #{<<"error">> => <<"not found">>, status => 404},
        B = jiffy:encode(ERR),
        Req0 = cowboy_req:set_resp_body(B, Req),
        Req2 = cowboy_req:reply(400, Req0),
        {stop, Req2, State};

      badarg ->
        ERR = #{<<"error">> => <<"no user id provided">>, status => 400},
        B = jiffy:encode(ERR),
        Req1 = cowboy_req:set_resp_body(B, Req),
        % Set the http status code to 400
        Req2 = cowboy_req:reply(400, Req1),
        {stop, Req2, State}
      end;

    _:_ ->
      ERR = #{<<"error">> => <<"processing error">>, status => 405},
      Req1 = cowboy_req:set_resp_body(ERR, Req),
      Req3 = cowboy_req:reply(405, Req1),
      {stop, Req3, State}

    end.


delete_resource(Req, State) ->
  try
    UserId = cowboy_req:binding(user_id, Req),
    {ok, Pid} = riakc_pb_socket:start_link("127.0.0.1", 8087),
    Result =  riakc_pb_socket:delete(Pid, <<"userdata">>, UserId),
    io:fwrite("Result ~p", [Result]),
    riakc_pb_socket:stop(Pid),

    case Result of
      ok ->
        Message = <<"user deleted successfully">>,
        Doc = {[{message, Message}, {status, 201}]},
        Body = jiffy:encode(#{success => Doc}),
        Req3 = cowboy_req:reply(201,
        #{<<"content-type">> => <<"application/json">>},
        Body,
        Req),
        {true, Req3, State};
      {error, _Reason} ->
        false
      end
      catch
        error:Reason ->
          case Reason of
            {badmatch,{error,notfound}} ->
              ERR = #{<<"error">> => <<"not found">>, status => 404},
              B = jiffy:encode(ERR),
              Req0 = cowboy_req:set_resp_body(B, Req),
              Req2 = cowboy_req:reply(404, Req0),
              {stop, Req2, State};
            badarg ->
              ERR = #{<<"error">> => <<"no user id provided">>, status => 400},
              B = jiffy:encode(ERR),
              Req1 = cowboy_req:set_resp_body(B, Req),
              % Set the http status code to 400
              Req2 = cowboy_req:reply(400, Req1),
              {stop, Req2, State}
            end
          end.



%----------------------Format time for JSON ----------------------------------
time_to_json(Req, State) ->
  {Hour, Minute, Second} = erlang:time(),
  {Year, Month, Day} = erlang:date(),
  Body = "~4..0B-~2..0B-~2..0B, ~2..0B:~2..0B:~2..0B",
  Body1 = io_lib:format(Body, [
  Year, Month, Day,
  Hour, Minute, Second
  ]),
  Body2 = list_to_binary(Body1),
  {Body2, Req, State}.
