%% The MIT License

%% Copyright (c) 2010 Alisdair Sullivan <alisdairsullivan@yahoo.ca>

%% Permission is hereby granted, free of charge, to any person obtaining a copy
%% of this software and associated documentation files (the "Software"), to deal
%% in the Software without restriction, including without limitation the rights
%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the Software is
%% furnished to do so, subject to the following conditions:

%% The above copyright notice and this permission notice shall be included in
%% all copies or substantial portions of the Software.

%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
%% THE SOFTWARE.


-module(jsx).


%% the core parser api
-export([parser/0, parser/1]).
-export([decoder/0, decoder/1]).
-export([encoder/0, encoder/1]).
-export([term_to_json/1, term_to_json/2]).
-export([json_to_term/1, json_to_term/2]).
-export([is_json/1, is_json/2]).
-export([format/1, format/2]).


-include("../include/jsx_common.hrl").


-spec parser() -> jsx_decoder().

parser() -> decoder([]).


-spec parser(OptsList::jsx_opts()) -> jsx_decoder().

parser(OptsList) -> decoder(OptsList).    


-spec decoder() -> jsx_decoder().

decoder() -> decoder([]).


-spec decoder(OptsList::jsx_opts()) -> jsx_decoder().


decoder(OptsList) ->
    case parse_opts(OptsList) of
        {error, badarg} -> {error, badarg}
        ; Opts ->
            case Opts#opts.encoding of
                utf8 -> jsx_utf8:decoder(Opts)
                ; utf16 -> jsx_utf16:decoder(Opts)
                ; utf32 -> jsx_utf32:decoder(Opts)
                ; {utf16, little} -> jsx_utf16le:decoder(Opts)
                ; {utf32, little} -> jsx_utf32le:decoder(Opts)
                ; auto -> jsx_utils:detect_encoding(Opts)
                ; _ -> {error, badarg}
            end
    end.


-spec encoder() -> jsx_encoder().

encoder() -> encoder([]).


-spec encoder(OptsList::jsx_opts()) -> jsx_encoder().

encoder(OptsList) ->
    case parse_opts(OptsList) of
        {error, badarg} -> {error, badarg}
        ; Opts -> jsx_encoder:encoder(Opts)
    end.


-spec json_to_term(JSON::binary()) -> jsx_term().

json_to_term(JSON) ->
    try json_to_term(JSON, [])
    %% rethrow exception so internals aren't confusingly exposed to users
    catch error:badarg -> erlang:error(badarg, [JSON])
    end.
    

-spec json_to_term(JSON::binary(), Opts::decoder_opts()) -> jsx_term(). 
    
json_to_term(JSON, Opts) ->
    jsx_terms:json_to_term(JSON, Opts).


-spec term_to_json(JSON::jsx_term()) -> binary().

term_to_json(JSON) ->
    try term_to_json(JSON, [])
    %% rethrow exception so internals aren't confusingly exposed to users
    catch error:badarg -> erlang:error(badarg, [JSON])
    end.


-spec term_to_json(JSON::jsx_term(), Opts::encoder_opts()) -> binary().        

term_to_json(JSON, Opts) ->
    try jsx_terms:term_to_json(JSON, Opts)
    %% rethrow exception so internals aren't confusingly exposed to users
    catch error:badarg -> erlang:error(badarg, [JSON, Opts])
    end.


-spec is_json(JSON::binary()) -> true | false
        ; (Terms::list(jsx_encodeable())) -> true | false.

is_json(JSON) ->
    is_json(JSON, []).
    

-spec is_json(JSON::binary(), Opts::verify_opts()) -> true | false
        ; (Terms::list(jsx_encodeable()), Opts::verify_opts()) -> true | false.

is_json(JSON, Opts) ->
    jsx_verify:is_json(JSON, Opts).


-spec format(JSON::binary()) -> binary() | iolist()
        ; (Terms::list(jsx_encodeable())) -> binary() | iolist().

format(JSON) ->
    format(JSON, []).


-spec format(JSON::binary(), Opts::format_opts()) -> binary() | iolist()
        ; (Terms::list(jsx_encodeable()), Opts::format_opts()) ->
            binary() | iolist().

format(JSON, Opts) ->
    jsx_format:format(JSON, Opts).



parse_opts(Opts) ->
    parse_opts(Opts, #opts{}).

parse_opts([], Opts) ->
    Opts;
parse_opts([loose_unicode|Rest], Opts) ->
    parse_opts(Rest, Opts#opts{loose_unicode=true});
parse_opts([iterate|Rest], Opts) ->
    parse_opts(Rest, Opts#opts{iterate=true});
parse_opts([escape_forward_slash|Rest], Opts) ->
    parse_opts(Rest, Opts#opts{escape_forward_slash=true});
parse_opts([{encoding, Encoding}|Rest], Opts)
        when Encoding =:= utf8; Encoding =:= utf16; Encoding =:= utf32;
            Encoding =:= {utf16,little}; Encoding =:= {utf32,little};
            Encoding =:= auto ->
    parse_opts(Rest, Opts#opts{encoding=Encoding});
parse_opts(_, _) ->
    {error, badarg}.


-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").


jsx_decoder_test_() ->
    jsx_decoder_gen(load_tests(?eunit_test_path)).


encoder_decoder_equiv_test_() ->
    [
        {"encoder/decoder equivalency",
            ?_assert(begin {jsx, X, _} = (jsx:decoder())(
                    <<"[\"a\", 17, 3.14, true, {\"k\":false}, []]">>
                ), X end =:= begin {jsx, Y, _} = (jsx:encoder())(
                    [start_array,
                        {string, <<"a">>},
                        {integer, 17},
                        {float, 3.14},
                        {literal, true},
                        start_object,
                        {key, <<"k">>},
                        {literal, false},
                        end_object,
                        start_array,
                        end_array,
                        end_array]
                ), Y end
            )
        }
    ].
    
    
jsx_decoder_gen([]) -> [];    
jsx_decoder_gen(Tests) -> 
    jsx_decoder_gen(Tests, [utf8,
        utf16,
        {utf16, little},
        utf32,
        {utf32, little}
    ]).    
    
jsx_decoder_gen([_Test|Rest], []) ->
    jsx_decoder_gen(Rest);
jsx_decoder_gen([Test|_] = Tests, [Encoding|Encodings]) ->
    Name = lists:flatten(proplists:get_value(name, Test) ++ " :: " ++
        io_lib:format("~p", [Encoding])
    ),
    JSON = unicode:characters_to_binary(proplists:get_value(json, Test),
        unicode,
        Encoding
    ),
    JSX = proplists:get_value(jsx, Test),
    Flags = proplists:get_value(jsx_flags, Test, []),
    {generator,
        fun() ->
            [{Name ++ " iterative",
                ?_assertEqual(iterative_decode(JSON, Flags), JSX)} 
                    | {generator, 
                        fun() -> [{Name ++ " incremental", ?_assertEqual(
                                incremental_decode(JSON, Flags), JSX)
                            } | {generator,
                                fun() ->
                                    [{Name, ?_assertEqual(
                                        decode(JSON, Flags), JSX)
                                    } | jsx_decoder_gen(Tests, Encodings)]
                            end}
                        ]
                    end}
            ]
        end
    }.


load_tests(Path) ->
    %% search the specified directory for any files with the .test ending
    TestSpecs = filelib:wildcard("*.test", Path),
    load_tests(TestSpecs, Path, []).

load_tests([], _Dir, Acc) ->
    lists:reverse(Acc);
load_tests([Test|Rest], Dir, Acc) ->
    case file:consult(Dir ++ "/" ++ Test) of
        {ok, TestSpec} ->
            ParsedTest = parse_tests(TestSpec, Dir),
            load_tests(Rest, Dir, [ParsedTest] ++ Acc)
        ; {error, _Reason} ->
            erlang:error(Test)
    end.


parse_tests(TestSpec, Dir) ->
    parse_tests(TestSpec, Dir, []).
    
parse_tests([{json, Path}|Rest], Dir, Acc) when is_list(Path) ->
    case file:read_file(Dir ++ "/" ++ Path) of
        {ok, Bin} -> parse_tests(Rest, Dir, [{json, Bin}] ++ Acc)
        ; _ -> erlang:error(badarg)
    end;
parse_tests([KV|Rest], Dir, Acc) ->
    parse_tests(Rest, Dir, [KV] ++ Acc);
parse_tests([], _Dir, Acc) ->
    Acc.


decode(JSON, Flags) ->
    P = jsx:decoder(Flags),
    case P(JSON) of
        {error, {badjson, _}} -> {error, badjson}
        ; {jsx, incomplete, More} ->
            case More(end_stream) of
                {error, {badjson, _}} -> {error, badjson}
                ; {jsx, T, _} -> T
            end
        ; {jsx, T, _} -> T
    end.


iterative_decode(JSON, Flags) ->
    P = jsx:decoder([iterate] ++ Flags),
    iterative_decode_loop(P(JSON), []).

iterative_decode_loop({jsx, end_json, _Next}, Acc) ->
    lists:reverse([end_json] ++ Acc);
iterative_decode_loop({jsx, incomplete, More}, Acc) ->
    iterative_decode_loop(More(end_stream), Acc);
iterative_decode_loop({jsx, E, Next}, Acc) ->
    iterative_decode_loop(Next(), [E] ++ Acc);
iterative_decode_loop({error, {badjson, _Error}}, _Acc) ->
    {error, badjson}.

    
incremental_decode(<<C:1/binary, Rest/binary>>, Flags) ->
	P = jsx:decoder([iterate] ++ Flags),
	incremental_decode_loop(P(C), Rest, []).

incremental_decode_loop({jsx, incomplete, Next}, <<>>, Acc) ->
    incremental_decode_loop(Next(end_stream), <<>>, Acc);	
incremental_decode_loop({jsx, incomplete, Next}, <<C:1/binary, Rest/binary>>, Acc) ->
	incremental_decode_loop(Next(C), Rest, Acc);	
incremental_decode_loop({jsx, end_json, _Next}, _Rest, Acc) ->
    lists:reverse([end_json] ++ Acc);
incremental_decode_loop({jsx, Event, Next}, Rest, Acc) ->
	incremental_decode_loop(Next(), Rest, [Event] ++ Acc);
incremental_decode_loop({error, {badjson, _Error}}, _Rest, _Acc) ->
    {error, badjson}.

    
-endif.