% depends: https://github.com/talentdeficit/jsx

-module(coolspace).
-export([gen_temps/0, process_space/3]).

-record(temp, {space, location, c_binary, c_float}).

gen_temps() ->
	Temps = lists:sort(fun (#temp{c_float=A}, #temp{c_float=B}) -> A =< B end, gen_temperatures()),
	Lengths = lists:foldl(fun update_len/2, #temp{space=0, location=0, c_binary=0}, Temps),
	Table = [format_row(Lengths, Row) || Row <- Temps],
	file:write_file("coolspace.txt", Table).

format_row(#temp{space=S1, location=L1, c_binary=C1},
		#temp{space=S2, location=L2, c_binary=C2, c_float=F2}) ->
	Gauge = repeat($=, round(F2 * 2)),
	[ljust(S1, S2), "   ", ljust(L1, L2), "   ", ljust(C1, C2), "   ", Gauge, $\n].

repeat(Char, Number) when Number >= 1 -> [Char || _ <- lists:seq(1, Number)];
repeat(_, _) -> "".

ljust(Width, Value) ->
	Current = length(unicode:characters_to_list(Value)),
	<<Value/binary, (list_to_binary(repeat($ , Width - Current)))/binary>>.

update_len(#temp{space=S1, location=L1, c_binary=C1},
		#temp{space=S2, location=L2, c_binary=C2}) ->
	#temp{space=max(S2, length(unicode:characters_to_list(S1, utf8))),
		  location=max(L2, length(unicode:characters_to_list(L1, utf8))),
		  c_binary=max(C2, byte_size(C1))}.

gen_temperatures() ->
	Spaces = fetch_json("https://spaceapi.fixme.ch/directory.json"),
	maps:map(fun process_space/2, Spaces),
	recv_loop([]).

recv_loop(Temps) ->
	receive
		Data -> recv_loop([Data | Temps])
	after 5000 -> Temps end.

process_space(Name, URL) ->
	spawn(?MODULE, process_space, [self(), Name, URL]).

process_space(Parent, Name, URL) ->
	parse_temps(Parent, Name, fetch_json(binary_to_list(URL))).

parse_temps(Parent, Name, #{<<"api">> := <<"0.13">>,
		<<"sensors">> := #{<<"temperature">> := TempSensors}})
		when is_list(TempSensors), length(TempSensors) > 0 ->
	[Parent ! process_temp(Name, T) || T <- TempSensors];
parse_temps(Parent, Name, #{<<"api">> := <<"0.12">>, <<"sensors">> := Sensors}) ->
	NormSensors = if is_list(Sensors) -> hd(Sensors); true -> Sensors end,
	maps:map(fun (K, V) -> parse_v12_sensor(Parent, Name, K, V) end, NormSensors).

parse_v12_sensor(Parent, Name, <<"temp", _/binary>>, V) ->
	maps:map(fun (TK, TV) -> parse_v12_temp(Parent, Name, TK, TV) end, V);
parse_v12_sensor(_, _, _, _) -> ignore.

parse_v12_temp(Parent, Name, TK, TV) ->
	ValueLen = byte_size(TV) - 1,
	<<Value:ValueLen/binary, Unit:1/binary>> = TV,
	Parent ! process_temp(Name, #{<<"location">> => TK, <<"value">> => Value, <<"unit">> => Unit}).

process_temp(Space, #{<<"value">> := Value} = T) when is_binary(Value) ->
	process_temp(Space, T#{<<"value">> := binary_to_float(Value)});
process_temp(Space, #{<<"name">> := Name, <<"location">> := Location} = T) when is_binary(Name) ->
	TempWithoutName = maps:remove(<<"name">>, T),
	process_temp(Space, TempWithoutName#{<<"location">> := if
		Location =:= <<>> -> Name;
		true -> <<Location/binary, " (", Name/binary, ")">>
	end});
process_temp(Space, #{<<"value">> := Value, <<"unit">> := Unit} = T)
		when binary_part(Unit, byte_size(Unit), -1) =:= <<$F>> ->
	TempWithoutUnit = maps:remove(<<"unit">>, T),
	process_temp(Space, TempWithoutUnit#{<<"value">> := (Value - 32) * 5 / 9});
process_temp(Space, #{<<"value">> := Value, <<"location">> := Location}) ->
	% pad numbers without a leading '-' with a space
	CB = case list_to_binary(io_lib:format("~p", [Value])) of
		<<$-, _/binary>> = Minus -> Minus;
		Plus -> <<" ", Plus/binary>>
	end,
	#temp{space=Space, location=Location, c_float=float(Value), c_binary=CB}.

fetch_json(URL) ->
	{ok, {_, _, JSON}} = httpc:request(get, {URL,
		[{"User-Agent", "https://github.com/dnet/coolspace"}]},
		[], [{body_format, binary}]),
	jsx:decode(JSON, [return_maps]).
