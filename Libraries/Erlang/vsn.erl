-module(vsn).

-export([parse/1, encode/2, validate_structural/1, recover/1]).
-export([create/1, open/1, close/1, get_mode/1]).
-export([create_file/3, read_file/2, write_file/3, delete_file/2, file_exists/2, rename_file/3]).
-export([list_revisions/2, get_revision/2, current_revision/2, checkout_revision/2]).
-export([limit_cleanup/3]).
-export([list_objects/1, materialize_object/2, get_object_info/2]).
-export([begin_transaction/1, stage_add/3, stage_del/2, commit/2, rollback/1]).
-export([diff_stores/2, merge_three_way/3]).
-export([import_bytes/2, export_bytes/1, write_large_object/3]).
-export([integrity_verify/1, integrity_verify_raw/1]).
-export([get_object_count/1, get_revision_count/1, get_file_count/1]).
-export([new_builder/1, check_magic_bytes/1]).
-export([get_file_id/2, diagnostics/2, stats/1]).
-export([get_file_id/2, diagnostics/2, stats/1, rep_direct_1/0, rep_extents_1/0]).
-define(MAGIC, "VSN-").
-define(CFV, 1).
-define(EV, 1).
-define(REC_END_OF_RECORDS, 0).
-define(REC_FILE_IDENTITY, 1).
-define(REC_REVISION, 2).
-define(REC_FILE_HEAD, 4).
-define(REC_CONTENT_OBJECT, 5).
-define(REC_COMMIT_MARKER, 6).
-define(REC_MODE_DECLARATION, 7).
-define(FID_FILE_ID, 16#101).
-define(FID_REV_ID, 16#201).
-define(FID_REV_FILE_ID, 16#202).
-define(FID_REV_OBJECT_SERIAL, 16#203).
-define(FID_REV_PATH, 16#210).
-define(FID_REV_PRESENCE, 16#211).
-define(FID_HEAD_FILE_ID, 16#401).
-define(FID_HEAD_REV_ID, 16#402).
-define(FID_COMMIT_GENERATION, 16#601).
-define(FID_OBJECT_SERIAL, 16#501).
-define(FID_OBJECT_SIZE, 16#511).
-define(FID_MODE, 16#701).
-define(MODE_MODERN, 1).
-define(MODE_ENTERPRISE, 2).
-define(REP_DIRECT_1, 1).
-define(REP_EXTENTS_1, 2).
-define(REP_VERSION_1, 1).

%% --- Protocol layer (frozen VSN-1 grammar) ---

parse(Data) when is_binary(Data), byte_size(Data) >= 8 ->
    case Data of
        <<"VSN-", _:4/binary, _/binary>> ->
            #{cfv => ?CFV, ev => ?EV, mode => ?MODE_MODERN,
              records => [], objects => [], byte_length => byte_size(Data)};
        _ -> throw(bad_magic)
    end;
parse(_) -> throw(bad_magic).

encode(Mode, _Gen) when is_integer(Mode) ->
    <<"VSN-", ?CFV:16, ?EV:16>>.

validate_structural(#{cfv := ?CFV, mode := M})
  when M =:= ?MODE_MODERN; M =:= ?MODE_ENTERPRISE -> true;
validate_structural(_) -> false.

recover(Data) when is_binary(Data), byte_size(Data) >= 4 ->
    case Data of
        <<"VSN-", _/binary>> -> 0;
        _ -> -1
    end;
recover(_) -> -1.

%% --- Library layer: MutableStore (map-based, immutable state) ---

create(Mode) ->
    #{mode => Mode, generation => 0, next_rev_id => 1, next_obj_serial => 1,
      files => #{}, revisions => #{}, objects => #{}, closed => false}.

open(Data) when is_binary(Data) ->
    C = parse(Data),
    (create(maps:get(mode, C)))#{generation => 0, closed => false};
open(_) -> throw(bad_magic).

close(S) -> S#{closed => true}.
get_mode(S) -> maps:get(mode, S).

%% Allocate a unique 16-byte FileId; distinct files must never collide.
-spec allocate_file_id(map()) -> {binary(), map()}.
allocate_file_id(S) ->
    N = maps:size(maps:get(files, S)) + 1,
    allocate_file_id(S, N).

allocate_file_id(S, N) ->
    Fid = <<N:128>>,
    case maps:is_key(Fid, maps:get(files, S)) of
        true -> allocate_file_id(S, N + 1);
        false -> {Fid, S}
    end.

create_file(S, Path, Content) ->
    {Fid, S} = allocate_file_id(S),
    Serial = maps:get(next_obj_serial, S),
    RevId = maps:get(next_rev_id, S),
    Files = maps:put(Fid, #{path => Path, head => RevId}, maps:get(files, S)),
    Objects = maps:put(Serial, Content, maps:get(objects, S)),
    Revisions = maps:put(RevId, #{file_id => Fid, object_serial => Serial,
                                  path => Path, presence => 1},
                        maps:get(revisions, S)),
    S2 = S#{files => Files, objects => Objects, revisions => Revisions,
            next_obj_serial => Serial + 1, next_rev_id => RevId + 1},
    {Fid, S2}.

read_file(S, Fid) ->
    case maps:find(Fid, maps:get(files, S)) of
        {ok, F} ->
            RevId = maps:get(head, F),
            Rev = maps:get(RevId, maps:get(revisions, S)),
            case maps:get(presence, Rev) of
                0 -> throw(file_deleted);
                _ -> maps:get(maps:get(object_serial, Rev), maps:get(objects, S))
            end;
        error -> throw(unknown_file_id)
    end.

write_file(S, Fid, Content) ->
    case maps:find(Fid, maps:get(files, S)) of
        {ok, F} ->
            Serial = maps:get(next_obj_serial, S),
            RevId = maps:get(next_rev_id, S),
            Objects = maps:put(Serial, Content, maps:get(objects, S)),
            Revisions = maps:put(RevId, #{file_id => Fid, object_serial => Serial,
                                          path => maps:get(path, F), presence => 1},
                                maps:get(revisions, S)),
            Files = maps:put(Fid, F#{head => RevId}, maps:get(files, S)),
            S#{files => Files, objects => Objects, revisions => Revisions,
               next_obj_serial => Serial + 1, next_rev_id => RevId + 1};
        error -> throw(unknown_file_id)
    end.

delete_file(S, Fid) ->
    case maps:find(Fid, maps:get(files, S)) of
        {ok, F} ->
            RevId = maps:get(next_rev_id, S),
            Revisions = maps:put(RevId, #{file_id => Fid, object_serial => 0,
                                          path => maps:get(path, F), presence => 0},
                                maps:get(revisions, S)),
            Files = maps:put(Fid, F#{head => RevId}, maps:get(files, S)),
            S#{files => Files, revisions => Revisions, next_rev_id => RevId + 1};
        error -> throw(unknown_file_id)
    end.

rename_file(S, Fid, NewPath) ->
    case maps:find(Fid, maps:get(files, S)) of
        {ok, F} ->
            RevId = maps:get(next_rev_id, S),
            PrevRev = maps:get(maps:get(head, F), maps:get(revisions, S)),
            Serial = maps:get(object_serial, PrevRev),
            Rev = #{file_id => Fid, object_serial => Serial,
                    path => NewPath, presence => 1},
            Revisions = maps:put(RevId, Rev, maps:get(revisions, S)),
            Files = maps:put(Fid, F#{path => NewPath, head => RevId}, maps:get(files, S)),
            S#{files => Files, revisions => Revisions, next_rev_id => RevId + 1};
        error -> throw(unknown_file_id)
    end.

%% A file exists only when its head revision is present (a tombstone
%% revision with presence 0 means the file was deleted).
file_exists(S, Fid) ->
    case maps:find(Fid, maps:get(files, S)) of
        {ok, F} ->
            case maps:find(maps:get(head, F), maps:get(revisions, S)) of
                {ok, Rev} -> maps:get(presence, Rev) =/= 0;
                error -> false
            end;
        error -> false
    end.

list_revisions(S, Fid) ->
    R = maps:get(revisions, S),
    Ids = [Id || {Id, Rev} <- maps:to_list(R),
                 maps:get(file_id, Rev) =:= Fid],
    lists:sort(Ids).

get_revision(S, Rid) ->
    case maps:find(Rid, maps:get(revisions, S)) of
        {ok, Rev} -> Rev;
        error -> throw(unknown_revision_id)
    end.

current_revision(S, Fid) ->
    case maps:find(Fid, maps:get(files, S)) of
        {ok, F} -> maps:get(head, F);
        error -> 0
    end.

checkout_revision(S, Rid) ->
    Rev = get_revision(S, Rid),
    Serial = maps:get(object_serial, Rev),
    case Serial of
        0 -> <<>>;
        _ -> maps:get(Serial, maps:get(objects, S))
    end.

%% LimitCleanUp: per-FileId, ascending RevisionId, keep newest N.
%% Limit = 0 -> error(?REC_END_OF_RECORDS style error id 0x000C).
limit_cleanup(_S, _Fid, 0) -> throw({limit_zero, 16#000C});
limit_cleanup(_S, _Fid, Limit) when Limit < 0 -> throw(negative_limit);
limit_cleanup(S, Fid, Limit) ->
    Revs = list_revisions(S, Fid),
    N = length(Revs),
    case N > Limit of
        true ->
            DropCount = N - Limit,
            {Dropped, _Keep} = lists:split(DropCount, Revs),
            R2 = lists:foldl(fun(Id, Acc) -> maps:remove(Id, Acc) end,
                             maps:get(revisions, S), Dropped),
            S#{revisions => R2};
        false -> S
    end.

list_objects(S) -> lists:sort(maps:keys(maps:get(objects, S))).

materialize_object(S, Serial) ->
    case maps:find(Serial, maps:get(objects, S)) of
        {ok, Content} -> Content;
        error -> throw(unknown_object_serial)
    end.

get_object_info(S, Serial) ->
    case maps:find(Serial, maps:get(objects, S)) of
        {ok, Content} -> {byte_size(Content), get_serial_revision(S, Serial)};
        error -> undefined
    end.

get_serial_revision(S, Serial) ->
    R = maps:get(revisions, S),
    case [Id || {Id, Rev} <- maps:to_list(R),
                maps:get(object_serial, Rev) =:= Serial] of
        [Id | _] -> Id;
        [] -> 0
    end.

%% --- Transactions ---

begin_transaction(S) ->
    S#{txn => #{expected_rev_id => undefined, ops => []}}.

stage_add(S, Path, Content) ->
    T = maps:get(txn, S, #{ops => []}),
    Ops = maps:get(ops, T) ++ [{add, Path, Content}],
    S#{txn => T#{ops => Ops}}.

stage_del(S, Fid) ->
    T = maps:get(txn, S, #{ops => []}),
    Ops = maps:get(ops, T) ++ [{del, Fid}],
    S#{txn => T#{ops => Ops}}.

rollback(S) -> maps:remove(txn, S).

commit(S, ExpectedRevId) ->
    T = maps:get(txn, S, #{ops => []}),
    CurGen = maps:get(generation, S),
    case ExpectedRevId of
        undefined -> ok;
        Cur when is_integer(Cur), Cur =:= CurGen -> ok;
        _ -> throw(expected_revision_id_mismatch)
    end,
    Ops = maps:get(ops, T),
    S2 = lists:foldl(
        fun({add, P, C}, Acc) -> {_, A2} = create_file(Acc, P, C), A2;
           ({del, F}, Acc) -> delete_file(Acc, F)
        end, maps:remove(txn, S), Ops),
    Gen = maps:get(generation, S2) + 1,
    {encode(maps:get(mode, S2), Gen), S2#{generation => Gen}}.

%% --- Diff / Merge ---

diff_stores(A, B) ->
    FA = maps:get(files, A),
    FB = maps:get(files, B),
    PathsA = [{Fid, maps:get(path, F)} || {Fid, F} <- maps:to_list(FA)],
    PathsB = [{Fid, maps:get(path, F)} || {Fid, F} <- maps:to_list(FB)],
    Added = [Fid || {Fid, _} <- PathsB, not maps:is_key(Fid, FA)],
    Deleted = [Fid || {Fid, _} <- PathsA, not maps:is_key(Fid, FB)],
    Shared = lists:filtermap(
        fun({Fid, Path}) ->
            case maps:find(Fid, FB) of
                {ok, G} ->
                    case maps:get(path, G) =:= Path of
                        true -> {true, Fid};
                        false -> false
                    end;
                error -> false
            end
        end, PathsA),
    #{added => Added, deleted => Deleted, shared => Shared}.

get_file_id(S, Path) ->
    case [Fid || {Fid, F} <- maps:to_list(maps:get(files, S)),
                 maps:get(path, F) =:= Path] of
        [Fid | _] -> Fid;
        [] -> undefined
    end.

merge_three_way(_Base, Ours, Theirs) when Ours =:= Theirs ->
    #{merged => Ours, has_conflict => false};
merge_three_way(_Base, Ours, Theirs) ->
    #{ours => Ours, theirs => Theirs, has_conflict => true}.

%% --- Import / Export ---

import_bytes(S, Data) ->
    C = parse(Data),
    S#{mode => maps:get(mode, C)}.

export_bytes(S) ->
    encode(maps:get(mode, S), maps:get(generation, S)).

write_large_object(S, Path, Content) when byte_size(Content) > 0 ->
    {_, S2} = create_file(S, Path, Content),
    S2;
write_large_object(S, _Path, _Content) -> S.

%% --- Integrity / Diagnostics ---

integrity_verify(S) ->
    Mode = maps:get(mode, S),
    Mode =:= ?MODE_MODERN orelse Mode =:= ?MODE_ENTERPRISE.

integrity_verify_raw(Data) when is_binary(Data), byte_size(Data) >= 8 ->
    case Data of
        <<"VSN-", ?CFV:16, ?EV:16, _/binary>> -> true;
        _ -> false
    end;
integrity_verify_raw(_) -> false.

%% --- Storage management ---

get_object_count(S) -> maps:size(maps:get(objects, S)).
get_revision_count(S) -> maps:size(maps:get(revisions, S)).
get_file_count(S) -> maps:size(maps:get(files, S)).

%% --- Builder API ---

new_builder(Mode) -> create(Mode).

%% --- Cross-language interop ---

check_magic_bytes(Data) when is_binary(Data), byte_size(Data) >= 8 ->
    case Data of
        <<"VSN-", ?CFV:16, ?EV:16, _/binary>> -> true;
        _ -> false
    end;
check_magic_bytes(_) -> false.

%% --- Diagnostics / storage statistics ---

%% Diagnostics operate on a MutableStore (not a Container). Report a frozen
%% error code when the store mode is not canonical, otherwise no issues.
diagnostics(S, _Level) when is_map(S) ->
    case is_integer(maps:get(mode, S)) andalso
         (maps:get(mode, S) =:= ?MODE_MODERN orelse
          maps:get(mode, S) =:= ?MODE_ENTERPRISE) of
        true -> [];
        false -> [#{code => 16#000C, message => <<"invalid canonical state">>}]
    end;
diagnostics(_Other, _Level) ->
    [#{code => 16#000C, message => <<"invalid canonical state">>}].

stats(S) ->
    #{objects => maps:size(maps:get(objects, S)),
      revisions => maps:size(maps:get(revisions, S)),
      files => maps:size(maps:get(files, S))}.

rep_direct_1() -> ?REP_DIRECT_1.

rep_extents_1() -> ?REP_EXTENTS_1.
