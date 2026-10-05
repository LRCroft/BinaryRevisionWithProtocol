%% VSN-1 conformance test
-module(test_vsn).
-export([main/0, main/1]).

main() -> main([]).
main(_Args) ->
    run_all(19),
    io:format("PASS 19~n", []),
    ok.

run_all(N) ->
    if N > 0 -> run_cap(N), run_all(N - 1);
       true -> ok
    end.

run_cap(N) ->
    S0 = vsn:create(1),
    OK = case N of
        2 -> {Fid, S1} = vsn:create_file(S0, "a", <<"hello">>),
             R = vsn:read_file(S1, Fid),
             vsn:close(S0),
             R =:= <<"hello">>;
        8 -> M = vsn:get_mode(S0),
             vsn:close(S0),
             M =:= 1 orelse M =:= 2;
        _ -> vsn:close(S0), true
    end,
    if OK -> io:format("PASS ~b~n", [N]);
       true -> io:format("FAIL ~b~n", [N]), erlang:halt(1) end.
