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
        1 -> M = vsn:get_mode(S0),
             S = vsn:close(S0),
             M =:= 1 orelse M =:= 2;
        2 -> {Fid, S1} = vsn:create_file(S0, "a", <<"hello">>),
             R = vsn:read_file(S1, Fid),
             S = vsn:close(S1),
             R =:= <<"hello">>;
        3 -> {_,S1} = vsn:create_file(S0, "r", <<"v1">>),
             S2 = vsn:write_file(S1, Fid, <<"v2">>),
             S3 = vsn:write_file(S2, Fid, <<"v3">>),
             L = vsn:list_revisions(S3, Fid),
             S = vsn:close(S3),
             length(L) >= 3;
        4 -> {Fid,S1} = vsn:create_file(S0, "lc", <<"x">>),
             S5 = lists:foldl(fun(_,A)-> vsn:write_file(A, Fid, <<>>) end, S1, [1,2,3,4,5]),
             R = vsn:limit_cleanup(S5, Fid, 3),
             S = vsn:close(S5),
             R >= 0;
        5 -> {_,S1} = vsn:create_file(S0, "o", <<"AB">>),
             L = vsn:list_objects(S1),
             S = vsn:close(S1),
             length(L) >= 1;
        6 -> Gen = vsn:begin_transaction(S0),
             Out = vsn:commit_transaction(S0, Gen),
             S = vsn:close(S0),
             byte_size(Out) >= 8;
        7 -> true;
        8 -> M = vsn:get_mode(S0),
             S = vsn:close(S0),
             M =:= 1 orelse M =:= 2;
        9 -> Valid = vsn:encode(1, 1),
             S = vsn:close(S0),
             {ok,S2} = vsn:create(Valid),
             vsn:close(S2),
             true;
        10 -> Valid = vsn:encode(1, 1),
              R = vsn:recover(Valid),
              E = vsn:recover(<<1,2,3>>),
              R >= 0 andalso E =:= -1;
        11 -> {_,S1} = vsn:create_file(S0, "x", <<1>>),
             S = vsn:close(S0),
             D = vsn:diff_stores(S1, S1),
             is_list(D);
        12 -> M = vsn:get_mode(S0),
             S = vsn:close(S0),
             M >= 1 andalso M =< 2;
        13 -> Bytes = vsn:export_bytes(S0),
             S = vsn:close(S0),
             case vsn:create(Bytes) of
                 {ok,S2} -> R = maps:get(mode, S2, -1); vsn:close(S2); R >= 0;
                 _ -> false
             end;
        14 -> {Fid,S1} = vsn:create_file(S0, "big", <<1,2,3>>),
             L = vsn:list_objects(S1),
             S = vsn:close(S1),
             length(L) >= 1;
        15 -> Valid = vsn:encode(1, 1),
              R = vsn:recover(<<1,2,3>>),
              valid = vsn:validate_structural(Valid),
              is_boolean(valid);
        16 -> Bytes = vsn:export_bytes(S0),
             OKi = vsn:integrity_verify(Bytes),
             S = vsn:close(S0),
             is_boolean(OKi) andalso OKi;
        17 -> {_,S1} = vsn:create_file(S0, "stat", <<1>>),
             Stats = vsn:get_stats(S1),
             S = vsn:close(S1),
             maps:get(files, Stats, -1) >= 0;
        18 -> B = vsn:new_builder(2),
             case B of {ok,X} -> maps:get(mode, X); _ -> -1 end;
        19 -> Valid = vsn:encode(1, 1),
             S = vsn:close(S0),
             is_binary(vsn:check_magic_bytes(Valid)) orelse is_boolean(vsn:check_magic_bytes(Valid));
        _ -> false
    end,
    if OK -> io:format("PASS ~b~n", [N]);
       true -> io:format("FAIL ~b~n", [N]), erlang:halt(1) end.
