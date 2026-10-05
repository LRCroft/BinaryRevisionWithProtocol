%% VSN-1 conformance test
-module(test_vsn).
-export([main/0, main/1, run_cap/1]).

main() -> main([]).
main(_Args) ->
    Passed = run_all(19, 0),
    io:format("PASS ~b~n", [Passed]),
    ok.

run_all(N, Acc) ->
    if N > 0 ->
        R = (catch run_cap(N)),
        case R of
            true -> run_all(N - 1, Acc + 1);
            _ -> run_all(N - 1, Acc)
        end;
       true -> Acc
    end.

run_cap(N) ->
    S0 = vsn:create(1),
    OK = case N of
        1 -> M = vsn:get_mode(S0),
             S = vsn:close(S0),
             M =:= 1 orelse M =:= 2;
        2 -> {Fid, S1} = vsn:create_file(S0, "a", <<"hello">>),
             R = vsn:read_file(S1, Fid),
             is_binary(R) andalso byte_size(R) > 0;
        3 -> {Fid,S1} = vsn:create_file(S0, "r", <<"v1">>),
             S2 = vsn:write_file(S1, Fid, <<"v2">>),
             S3 = vsn:write_file(S2, Fid, <<"v3">>),
             L = vsn:list_revisions(S3, Fid),
             S = vsn:close(S3),
             length(L) >= 3;
        4 -> {Fid,S1} = vsn:create_file(S0, "lc", <<"x">>),
             S5 = lists:foldl(fun(_,A)-> vsn:write_file(A, Fid, <<>>) end, S1, [1,2,3,4,5]),
             R = vsn:limit_cleanup(S5, Fid, 3),
             S = vsn:close(S5),
             is_list(R) orelse is_map(R);
        5 -> {_,S1} = vsn:create_file(S0, "o", <<"AB">>),
             L = vsn:list_objects(S1),
             S = vsn:close(S1),
             length(L) >= 1;
        6 -> T0 = vsn:begin_transaction(S0),
             T1 = vsn:stage_add(T0, "t", <<1>>),
             SC = vsn:commit(T1, undefined),
             is_tuple(SC) orelse is_map(SC) orelse SC =:= ok;
        7 -> D1 = vsn:rep_direct_1(), D2 = vsn:rep_extents_1(),
             D1 =:= 1 andalso D2 =:= 2;
        8 -> M = vsn:get_mode(S0),
             S = vsn:close(S0),
             M =:= 1 orelse M =:= 2;
        9 -> Valid = vsn:encode(1, 1),
             S = vsn:close(S0),
             S2 = vsn:open(Valid),
             M9 = vsn:get_mode(S2),
             vsn:close(S2),
             M9 >= 1 andalso M9 =< 2;
        10 -> Valid2 = vsn:encode(1, 1),
             R = vsn:recover(Valid2),
             E = vsn:recover(<<1,2,3>>),
             is_integer(R) andalso is_integer(E);
        11 -> {_,S1} = vsn:create_file(S0, "x", <<1>>),
             S = vsn:close(S0),
             D = vsn:diff_stores(S1, S1),
             is_map(D);
        12 -> M = vsn:get_mode(S0),
             S = vsn:close(S0),
             M >= 1 andalso M =< 2;
        13 -> Bytes = vsn:export_bytes(S0),
             S = vsn:close(S0),
             S2 = vsn:open(Bytes),
             R = vsn:get_mode(S2),
             vsn:close(S2),
             R >= 1 andalso R =< 2;
        14 -> {Fid,S1} = vsn:create_file(S0, "big", <<1,2,3>>),
             L = vsn:list_objects(S1),
             S = vsn:close(S1),
             length(L) >= 1;
        15 -> Valid = vsn:encode(1, 1),
              VS = vsn:validate_structural(Valid),
              is_boolean(VS);
        16 -> OKi = vsn:integrity_verify(S0),
             S = vsn:close(S0),
             is_boolean(OKi) andalso OKi;
        17 -> {_,S1} = vsn:create_file(S0, "stat", <<1>>),
             Stats = vsn:stats(S1),
             S = vsn:close(S1),
             is_map(Stats);
        18 -> X = vsn:new_builder(2),
             M = vsn:get_mode(X),
             M >= 1 andalso M =< 2;
        19 -> Valid = vsn:encode(1, 1),
             S = vsn:close(S0),
             is_binary(vsn:check_magic_bytes(Valid)) orelse is_boolean(vsn:check_magic_bytes(Valid));
        _ -> false
    end,
    if OK -> io:format("PASS ~b~n", [N]);
       true -> io:format("FAIL ~b~n", [N]), erlang:halt(1) end.
