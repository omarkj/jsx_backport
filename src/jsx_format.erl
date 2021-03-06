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



-module(jsx_format).


-export([format/2]).


-include("../include/jsx_common.hrl").
-include("jsx_format.hrl").



-spec format(JSON::binary(), Opts::format_opts()) ->
            binary() | iolist()
        ; (Terms::list(jsx_encodeable()), Opts::format_opts()) ->
            binary() | iolist()
        ; (F::jsx_iterator(), Opts::format_opts()) ->
            binary() | iolist().
    
format(JSON, OptsList) when is_binary(JSON) ->
    P = jsx:decoder([iterate] ++ extract_parser_opts(OptsList)),
    format(fun() -> P(JSON) end, OptsList);
format(Terms, OptsList) when is_list(Terms); is_tuple(Terms) ->
    P = jsx:encoder([iterate]),
    format(fun() -> P(Terms) end, OptsList);
format(F, OptsList) when is_function(F) ->
    Opts = parse_opts(OptsList, #format_opts{}),
    {Continue, String} = format_something(F(), Opts, 0),
    case Continue() of
        {jsx, end_json, _} -> encode(String, Opts)
        ; _ -> {error, badarg}
    end.


parse_opts([{indent, Val}|Rest], Opts) ->
    parse_opts(Rest, Opts#format_opts{indent = Val});
parse_opts([indent|Rest], Opts) ->
    parse_opts(Rest, Opts#format_opts{indent = 1});
parse_opts([{space, Val}|Rest], Opts) ->
    parse_opts(Rest, Opts#format_opts{space = Val});
parse_opts([space|Rest], Opts) ->
    parse_opts(Rest, Opts#format_opts{space = 1});
parse_opts([{output_encoding, Val}|Rest], Opts) ->
    parse_opts(Rest, Opts#format_opts{output_encoding = Val});
parse_opts([_|Rest], Opts) ->
    parse_opts(Rest, Opts);
parse_opts([], Opts) ->
    Opts.


extract_parser_opts(Opts) ->
    extract_parser_opts(Opts, []).

extract_parser_opts([], Acc) -> Acc;     
extract_parser_opts([{K,V}|Rest], Acc) ->
    case lists:member(K, [encoding]) of
        true -> [{K,V}] ++ Acc
        ; false -> extract_parser_opts(Rest, Acc)
    end;
extract_parser_opts([K|Rest], Acc) ->
    case lists:member(K, [encoding]) of
        true -> [K] ++ Acc
        ; false -> extract_parser_opts(Rest, Acc)
    end.
    

format_something({jsx, start_object, Next}, Opts, Level) ->
    case Next() of
        {jsx, end_object, Continue} ->
            {Continue, [?start_object, ?end_object]}
        ; Event ->
            {Continue, Object} = format_object(Event, [], Opts, Level + 1),
            {Continue, [?start_object, 
                Object, 
                indent(Opts, Level), 
                ?end_object
            ]}
    end;
format_something({jsx, start_array, Next}, Opts, Level) ->
    case Next() of
        {jsx, end_array, Continue} ->
            {Continue, [?start_array, ?end_array]}
        ; Event ->
            {Continue, Object} = format_array(Event, [], Opts, Level + 1),
            {Continue, [?start_array, Object, indent(Opts, Level), ?end_array]}
    end;
format_something({jsx, {Type, Value}, Next}, _Opts, _Level) ->
    {Next, [encode(Type, Value)]}.
    
    
format_object({jsx, end_object, Next}, Acc, _Opts, _Level) ->
    {Next, Acc};
format_object({jsx, {key, Key}, Next}, Acc, Opts, Level) ->
    {Continue, Value} = format_something(Next(), Opts, Level),
    case Continue() of
        {jsx, end_object, NextNext} -> 
            {NextNext, [Acc, 
                indent(Opts, Level), 
                encode(string, Key), 
                ?colon, 
                space(Opts), 
                Value
            ]}
        ; Else -> 
            format_object(Else, 
                [Acc, 
                    indent(Opts, Level), 
                    encode(string, Key), 
                    ?colon, 
                    space(Opts), 
                    Value, 
                    ?comma, 
                    space(Opts)
                ], 
                Opts, 
                Level
            )
    end.


format_array({jsx, end_array, Next}, Acc, _Opts, _Level) ->
    {Next, Acc};
format_array(Event, Acc, Opts, Level) ->
    {Continue, Value} = format_something(Event, Opts, Level),
    case Continue() of
        {jsx, end_array, NextNext} ->
            {NextNext, [Acc, indent(Opts, Level), Value]}
        ; Else ->
            format_array(Else, 
                [Acc, 
                    indent(Opts, Level),
                    Value, 
                    ?comma, 
                    space(Opts)
                ], 
                Opts, 
                Level
            )
    end.


encode(Acc, Opts) when is_list(Acc) ->
    case Opts#format_opts.output_encoding of
        iolist -> Acc
        ; UTF when ?is_utf_encoding(UTF) -> 
            unicode:characters_to_binary(Acc, utf8, UTF)
        ; _ -> erlang:error(badarg)
    end;
encode(string, String) ->
    [?quote, String, ?quote];
encode(literal, Literal) ->
    erlang:atom_to_list(Literal);
encode(integer, Integer) ->
    erlang:integer_to_list(Integer);
encode(float, Float) ->
    jsx_utils:nice_decimal(Float).


indent(Opts, Level) ->
    case Opts#format_opts.indent of
        0 -> []
        ; X when X > 0 ->
            Indent = [ ?space || _ <- lists:seq(1, X) ],
            indent(Indent, Level, [?newline])
    end.

indent(_Indent, 0, Acc) ->
    Acc;
indent(Indent, N, Acc) ->
    indent(Indent, N - 1, [Acc, Indent]).
    
    
space(Opts) ->
    case Opts#format_opts.space of
        0 -> []
        ; X when X > 0 -> [ ?space || _ <- lists:seq(1, X) ]
    end.
    

%% eunit tests

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

minify_test_() ->
    [
        {"minify object", 
            ?_assert(format(<<"  { \"key\"  :\n\t \"value\"\r\r\r\n }  ">>, 
                    []
                ) =:= <<"{\"key\":\"value\"}">>
            )
        },
        {"minify array", 
            ?_assert(format(<<" [\n\ttrue,\n\tfalse  ,  \n \tnull\n] ">>, 
                    []
                ) =:= <<"[true,false,null]">>
            )
        }
    ].
    
opts_test_() ->
    [
        {"unspecified indent/space", 
            ?_assert(format(<<" [\n\ttrue,\n\tfalse,\n\tnull\n] ">>, 
                    [space, indent]
                ) =:= <<"[\n true, \n false, \n null\n]">>
            )
        },
        {"specific indent/space", 
            ?_assert(format(
                    <<"\n{\n\"key\"  :  [],\n\"another key\"  :  true\n}\n">>, 
                    [{space, 2}, {indent, 3}]
                ) =:= <<"{\n   \"key\":  [],  \n   \"another key\":  true\n}">>
            )
        },
        {"nested structures", 
            ?_assert(format(
                    <<"[{\"key\":\"value\", 
                            \"another key\": \"another value\"
                        }, 
                        [[true, false, null]]
                    ]">>, 
                    [{space, 2}, {indent, 2}]
                ) =:= <<"[\n  {\n    \"key\":  \"value\",  \n    \"another key\":  \"another value\"\n  },  \n  [\n    [\n      true,  \n      false,  \n      null\n    ]\n  ]\n]">>
            )
        },
        {"just spaces", 
            ?_assert(format(<<"[1,2,3]">>, 
                    [{space, 2}]
                ) =:= <<"[1,  2,  3]">>
            )
        },
        {"just indent", 
            ?_assert(format(<<"[1.0, 2.0, 3.0]">>, 
                    [{indent, 2}]
                ) =:= <<"[\n  1.0,\n  2.0,\n  3.0\n]">>
            )
        }
    ].

terms_test_() ->
    [
        {"terms",
            ?_assert(format([start_object,
                {key, <<"key">>},
                {string, <<"value">>},
                end_object
            ], []) =:= <<"{\"key\":\"value\"}">>
        )}
    ].
    
-endif.