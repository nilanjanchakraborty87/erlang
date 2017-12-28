-module(life).
-export([neighbours/1, next_step/1, frequencies/1]).

neighbours({X, Y}) ->
    [{X + DX, Y + DY} || DX <- [-1, 0, 1], DY <- [-1, 0, 1], {DX, DY} =/= {0, 0}].

next_step(Cells) ->
    Nbs = lists:flatmap(fun neighbours/1, sets:to_list(Cells)),
    NewCells = [C || {C, N} <- maps:to_list(frequencies(Nbs)),
                     (N == 3) orelse ((N == 2) andalso sets:is_element(C, Cells))],
    sets:from_list(NewCells).

frequencies(List) ->
    lists:foldl(fun update_count/2, #{}, List).

update_count(X, Map) ->
    maps:update_with(X, fun(C) -> C + 1 end, 1, Map).

%
% Unit tests
%

-include_lib("eunit/include/eunit.hrl").

frequencies_test() ->
    ?assertEqual(#{1=>2, 2=>2, 3=>3, 4=>1},
        frequencies([1, 2, 3, 2, 3, 4, 1, 3])).

neighbours_test() ->
    ?assertEqual([{0,1}, {0,2}, {0,3}, {1,1}, {1,3}, {2,1}, {2,2}, {2,3}],
        neighbours({1, 2})).

blinker_test() ->
    assert_next_step([{2,3}, {3,3}, {4,3}], [{3,2}, {3,3}, {3,4}]),
    assert_next_step([{3,2}, {3,3}, {3,4}], [{2,3}, {3,3}, {4,3}]).

beehive_test() ->
    assert_next_step([{3,2}, {2,3}, {2,4}, {3,5}, {4,4}, {4,3}],
        [{3,2}, {2,3}, {2,4}, {3,5}, {4,4}, {4,3}]).

assert_next_step(ListAfter, ListBefore) ->
    ?assertEqual(sets:from_list(ListAfter), next_step(sets:from_list(ListBefore))).
