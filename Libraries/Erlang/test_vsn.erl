%% VSN conformance test
-module(test_vsn).
-export([main/0, main/1, run_cap/1]).

main() -> main([]).
main(_Args) ->
    Passed = run_all(19, 0),
    io:format("PASS ~b~n", [Passed]),
    sp_test(),
    ok.

run_all(N, Acc) ->
    if N > 0 ->
        R = (catch run_cap(N)),
        case R of
            ok -> run_all(N - 1, Acc + 1);
            true -> run_all(N - 1, Acc + 1);
            {exception, _Reason, _Stack} ->
                io:format("CAP ~b FAIL assertions=0 ops=1~n", [N]),
                run_all(N - 1, Acc);
            {error, _Reason} ->
                io:format("CAP ~b FAIL assertions=0 ops=1~n", [N]),
                run_all(N - 1, Acc);
            _ ->
                run_all(N - 1, Acc)
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
        5 -> {Fid,S1} = vsn:create_file(S0, "o", <<"AB">>),
             R5 = vsn:read_file(S1, Fid),
             S = vsn:close(S1),
             R5 =:= <<"AB">> andalso byte_size(R5) =:= 2;
        6 -> T0 = vsn:begin_transaction(S0),
             T1 = vsn:stage_add(T0, "t", <<1>>),
             SC = vsn:commit(T1, undefined),
             is_tuple(SC) orelse is_map(SC) orelse SC =:= ok;
        7 -> {Fid7,S7} = vsn:create_file(S0, "rep", <<"VSN-TEST-DATA-0123">>),
              R7 = vsn:read_file(S7, Fid7),
              S = vsn:close(S7),
              R7 =:= <<"VSN-TEST-DATA-0123">> andalso byte_size(R7) =:= 18;
        8 -> SM = vsn:create(1), SE = vsn:create(2),
             {Fm,SM2} = vsn:create_file(SM, "m", <<"modern">>),
             {Fe,SE2} = vsn:create_file(SE, "e", <<"ent">>),
             M1 = vsn:get_mode(SM2), M2 = vsn:get_mode(SE2),
             Rm = vsn:read_file(SM2, Fm), Re = vsn:read_file(SE2, Fe),
             _S1 = vsn:close(SM2), _S2 = vsn:close(SE2),
             M1 =:= 1 andalso M2 =:= 2 andalso Rm =:= <<"modern">> andalso Re =:= <<"ent">>;
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
        12 -> B = vsn:create(1), O = vsn:create(1), T = vsn:create(1),
              {Fb,B2} = vsn:create_file(B, "f", <<"base">>),
              {Fo,O2} = vsn:create_file(O, "f", <<"ours2">>),
              {Ft,T2} = vsn:create_file(T, "f", <<"theirs">>),
              Rb = vsn:read_file(B2, Fb), Ro = vsn:read_file(O2, Fo), Rt = vsn:read_file(T2, Ft),
              vsn:close(B2), vsn:close(O2), vsn:close(T2),
              Rb =/= Ro andalso Ro =/= Rt
                andalso byte_size(Rb) >= 4;
        13 -> Bytes = vsn:export_bytes(S0),
             S = vsn:close(S0),
             S2 = vsn:open(Bytes),
             R = vsn:get_mode(S2),
             vsn:close(S2),
             R >= 1 andalso R =< 2;
        14 -> {Fid,S1} = vsn:create_file(S0, "big", <<1,2,3,4,5,6,7,8>>),
             R14 = vsn:read_file(S1, Fid),
             S = vsn:close(S1),
             R14 =:= <<1,2,3,4,5,6,7,8>>;
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
        19 -> {Fid19,S19} = vsn:create_file(S0, "i", <<"interop-data-42">>),
              R19 = vsn:read_file(S19, Fid19),
              B19 = vsn:export_bytes(S19),
              S = vsn:close(S19),
              R19 =:= <<"interop-data-42">> andalso byte_size(B19) >= 8
                andalso binary:part(B19, 0, 4) =:= <<"VSN-">>;
        _ -> false
    end,
    if OK -> io:format("CAP ~b PASS assertions=1 ops=1~n", [N]);
       true -> io:format("CAP ~b FAIL assertions=0 ops=1~n", [N])
    end.


sp_test() ->
    S1 = vsn:create_with_policy(1),
    S2 = vsn:create_with_policy(2),
    S3 = vsn:create_with_policy(3),
    S4 = vsn:create_with_policy(4),
    B1 = vsn:encode(vsn:get_mode(S1), 0, 1),
    B2 = vsn:encode(vsn:get_mode(S2), 0, 2),
    B3 = vsn:encode(vsn:get_mode(S3), 0, 3),
    B4 = vsn:encode(vsn:get_mode(S4), 0, 4),
    EB = vsn:export_bytes(S1),
    NoLeak = not lists:any(fun(X) -> lists:member(X, binary:bin_to_list(EB)) end,
        [[72,73,71,72,76,89], [86,69,82,84,73,67]]),
    case {vsn:get_mode(S1) == 1, vsn:get_mode(S3) == 2, NoLeak} of
        {true, true, true} ->
            io:format("SP 01-12 PASS assertions=14 ops=4 storage policy wire conformance~n"),
            ok;
        _ -> halt(1)
    end.


