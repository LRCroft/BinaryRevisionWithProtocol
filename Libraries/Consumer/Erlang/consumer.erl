-module(consumer).
-compile([export_all]).

% VSN-1 independent consumer (Erlang) -- Storage Policy round-trip.
% Uses the library's vsn:encode/3 (wire-out) + vsn:parse/1 (wire-in).

sig(B) ->
  N = byte_size(B),
  lists:any(fun(I) ->
    binary:at(B, I) =:= 0 andalso binary:at(B, I + 1) =:= 9 andalso
      binary:at(B, I + 2) =:= 4 andalso binary:at(B, I + 3) =:= 9 andalso
      binary:at(B, I + 4) =:= 1 andalso binary:at(B, I + 5) =:= 1
  end, lists:seq(0, max(0, N - 6))).

main() ->
  Bad = lists:any(fun(P) ->
    B = vsn:encode(1, 0, P),
    M = vsn:parse(B),
    not (sig(B) andalso maps:get(storage_policy, M) =:= P)
  end, [1, 2, 3, 4]),
  case Bad of
    true  -> io:format("CONSUMER ERLANG FAIL~n"), halt(1);
    false -> io:format("CONSUMER ERLANG PASS~n"), halt(0)
  end.
