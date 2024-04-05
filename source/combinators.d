module combinators;

import std.stdio;
import std.algorithm.comparison;
import std.sumtype : SumType, match, tryMatch;
import std.typecons: tuple, Tuple;
import std.conv;
import std.algorithm.iteration : map, reduce;
import std.range;
import std.range : join;
import types;
import parsers;
import std.functional : toDelegate;
import std.meta : staticMap;

/** the result of a successful parser match will be passed to the function. */
Parser!T2 map_p (T1, T2)(Parser!T1 p, T2 delegate(T1) fun)
{
    Parser!T2 f = (Input input) {
        ParseResult!T1 res = p(input);

        return res.match!(
            (ParseSuccess!T1 s) {
            return ParseResult!T2(ParseSuccess!T2(fun(s.result), s.tail));
        },
            (ParseFailure e) { return ParseResult!T2(e); },
        );
    };
    return f;
}


unittest {
    import parsers;
    Parser!string p1 = word("123");
	auto mapped_p1 = map_p!(string, int)(
        p1, 
        (string c) {return c.to!int; }
    )("123456");
    assert(tryMatch!((ParseSuccess!int res) => res.result == 123 && res.tail == "456")(mapped_p1));

	Parser!string p2 = word("f123");
	auto mapped_p2 = map_p!(string, int)(p2, (string c) { return c.to!int; })("123");
    assert(tryMatch!((ParseFailure res) => res.message == "'f123' word was expected, not '123'")(mapped_p2));


}

/** will be successful if both combinators successfully match. */
auto and(T1, T2, ResType = Tuple!(T1, T2))(Parser!T1 p1, Parser!T2 p2)
{
    Parser!(Tuple!(T1, T2)) f = (Input input) {
        ParseResult!T1 res1 = p1(input);

        return res1.match!(
            (ParseSuccess!T1 s) {
            ParseResult!T2 res2 = p2(s.tail);
            return res2.match!(
                (ParseSuccess!T2 s2) {
                    return ParseResult!(ResType)(
                        ParseSuccess!(ResType)(
                            tuple(s.result, s2.result),
                            s2.tail
                        ),
                    );
            },
                (ParseFailure e) { return ParseResult!(ResType)(e); },
            );
        },
            (ParseFailure e) { return ParseResult!(ResType)(e); },
        );
    };
    return f;
}

unittest {
    Parser!string p1 = word("123");
    Parser!string p2 = word("123");
    alias ResType = Tuple!(string, string);

	auto mapped_p1 = and!(string, string)(p1, p2)("123123456");
    assert(tryMatch!((ParseSuccess!ResType res){
        return res.result == tuple("123", "123") && res.tail == "456";
    })(mapped_p1));

	auto mapped_p2 = and!(string, string)(p1, p2)("ddd");
    assert(tryMatch!((ParseFailure res) => res.message == "'123' word was expected, not 'ddd'")(mapped_p2));
}

/** will be successful if first or second parser successfully match. */
Parser!T1 or (T1)(Parser!T1 p1, Parser!T1 p2)
{
    Parser!T1 f = (Input input) {
        ParseResult!T1 res1 = p1(input);

        return res1.match!(
            (ParseSuccess!T1 res1) { return ParseResult!T1(res1); },
            (ParseFailure err1) { 
                ParseResult!T1 res2 = p2(input); 
                return res2.match!(
                    (ParseSuccess!T1 res2) { return ParseResult!T1(res2); },
                    (ParseFailure err2) { 
                        return ParseResult!T1(ParseFailure(err1.message ~ " or " ~ err2.message)); 
                    },
                );
            },
        );
    };
    return f;
}


/** returns an array of parser results, separated by another parser. */
Parser!(T1[]) delimited (T1, TD)(Parser!T1 p, Parser!TD delemiter)
{
    Parser!(T1[]) f = (Input input) {
        Input tail = input;
        T1[] res = [];
        ParseFailure error;
        bool runned = true;
        while(runned) {
            ParseResult!T1 value = p(tail);
            value.match!(
                (ParseSuccess!(T1) s) {
                    res ~= s.result;
                    if (s.tail.empty){
                        runned = false;
                    }
                    ParseResult!TD delemiter_v = delemiter(s.tail);
                    delemiter_v.match!(
                        (ParseSuccess!(TD) delemiter_res) { 
                            tail = delemiter_res.tail; 
                        },
                        (ParseFailure _) {  
                            tail = s.tail; 
                            runned = false; 
                        },
                    );
                },
                (ParseFailure _) { 
                    runned = false; 
                },
            );
        }
        if (error != error.init) {
            return ParseResult!(T1[])(error);
        }
        if(tail.empty){
            return ParseResult!(T1[])(ParseFailure("EOF"));
        }
        return ParseResult!(T1[])(ParseSuccess!(T1[])(res, tail));
    };
    return f;
}


unittest {   
    tryMatch!(
        (ParseSuccess!(dchar[]) result){
            writeln(result.result);
            writeln(result.tail);
        })(delimited!(dchar, dchar)(chr('2'), chr(','))("2,2,2mmm"));
    Parser!(dchar) c2 = chr('1');
    Parser!(dchar) c3 = chr(']');

    Parser!string p1 = word("123");
    Parser!string p2 = word("321");

	auto mapped_p1 = or!string(p1, p2)("123");
    assert(tryMatch!((ParseSuccess!string res) => res.result == "123")(mapped_p1));

    auto mapped_p2 = or!string(p1, p2)("321");
    assert(tryMatch!((ParseSuccess!string res) => res.result == "321")(mapped_p2));

    auto mapped_p3 = or!string(p1, p2)("wef");
    assert(
        tryMatch!(
            (ParseFailure res){
                return res.message == "'123' word was expected, not 'wef' or '321' word was expected, not 'wef'";
            }
        )(mapped_p3)
    );
}


alias ParserByType(T) = Parser!T;
alias ParsersByTypes(T...) = staticMap!(ParserByType, T);

/** returns a tuple of results from all parsers if they are all successfully matched. */
Parser!(Tuple!(T)) seqtup (T...)(ParsersByTypes!T parsers)
{
    alias ResType = Tuple!(T);
    Parser!(Tuple!(T)) f = (Input input) {
        Input tail = input;
        Tuple!(T) res;
        ParseFailure error;
        foreach (i, p; parsers) {
            ParseResult!(T[i]) f = p(tail);
            f.match!(
                (ParseSuccess!(T[i]) s) {
                    res[i] = s.result; 
                    tail = s.tail;
                },
                (ParseFailure e) { error = e; },
            );
            if (error != error.init) {
                return ParseResult!(ResType)(error);
            }
        }

        return ParseResult!(ResType)(ParseSuccess!(ResType)(res, tail));
    };
    return f;
}

unittest {
    Parser!string p1 = word("123");
    Parser!(dchar) left = chr('[');
    Parser!(dchar) right = chr(']');
	auto mapped_p1 = seqtup!(dchar, string, dchar)(left, p1, right)("[123]");

    assert (
        tryMatch!(
            (ParseSuccess!(Tuple!(dchar, string, dchar)) res){
                return res.result[0] == '[';
                return res.result[1] == "123";
                return res.result[2] == ']';
                return true;
            }
        )(mapped_p1)
    );

}


ParseResult!(TS) zero_or_more(T1, TS = T1[])(Parser!T1 p, Input input){
    Input tail = input;
    TS res = [];
    ParseFailure error;
    while(true) {
        ParseResult!T1 f = p(tail);
        f.match!(
            (ParseSuccess!(T1) s) { 
                res ~= s.result; 
                tail = s.tail; 
            },
            (ParseFailure e) { 
                error = e; 
            },
        );
        if (error != error.init || tail.empty) {
            return ParseResult!TS((ParseSuccess!TS(res, tail)));
        }
    }

    return ParseResult!TS(ParseSuccess!TS(res, tail));
}
/** apply the parser until it is successfully matched. */
Parser!TS many (T1, TS = T1[])(Parser!T1 parser)
{
    Parser!TS f = (Input input) {
        return zero_or_more!T1(parser, input);
    };
    return f;
}


unittest {
    Parser!dchar p1 = choice!(dchar)([chr('а'), chr('б')]);

	auto mapped_p1 = many!(dchar)(p1)("абв");

    assert(
        tryMatch!(
            (ParseSuccess!(dchar[]) res){
                return res.result.text == "аб" && res.tail == "в";
            }
        )(mapped_p1)
    );

	auto mapped_p2 = many!(dchar)(p1)("ттт");

    assert(
        tryMatch!(
            (ParseSuccess!(dchar[]) res){
                return res.result.text == "" && res.tail == "ттт";
            }
        )(mapped_p2)
    );

}


/** match all of the combinators one by one and return array of the results. */
Parser!TS many1 (T1, TS = T1[])(Parser!T1 parser)
{
    Parser!TS f = (Input input) {
        ParseResult!T1 first = parser(input);
        return first.match!(
            (ParseSuccess!(T1) res1) { 
                ParseResult!TS more = zero_or_more!T1(parser, res1.tail);
                return more.match!(
                    (ParseSuccess!(TS) res2) { 
                        TS final_res = join([[res1.result], res2.result]);
                        return ParseResult!TS(ParseSuccess!TS(final_res, res2.tail));
                    },
                    (ParseFailure e) { 
                        return ParseResult!TS(e); 
                    },
                );
            },
            (ParseFailure e) { 
                return ParseResult!TS(e); 
            },
        );

    };
    return f;
}


unittest {
    Parser!dchar p1 = choice!(dchar)([chr('а'), chr('б')]);

	auto mapped_p1 = many1!(dchar)(p1)("абв");

    assert(
        tryMatch!(
            (ParseSuccess!(dchar[]) res){
                return res.result.text == "аб" && res.tail == "в";
            }
        )(mapped_p1)
    );

	auto mapped_p2 = many1!(dchar)(p1)("ттт");

    assert(
        tryMatch!(
            (ParseFailure e){
                return e.message == "'а' letter was expected, not 'т' or 'б' letter was expected, not 'т'";
            }
        )(mapped_p2)
    );

}


/** returns result of the right parser if both parser matched successfully. */
Parser!T2 skip_left(T1, T2)(Parser!T1 p1, Parser!T2 p2)
{
    Parser!(Tuple!(T1, T2)) and_p = and!(T1, T2)(p1, p2);
    return map_p!(Tuple!(T1, T2), T2)(and_p, (Tuple!(T1, T2) res) => res[1]);

}

unittest {
    Parser!string p1 = word("123");
    Parser!string p2 = word("321");

	auto mapped_p1 = skip_left!(string, string)(p1, p2)("123321");

    assert(
        tryMatch!(
            (ParseSuccess!(string) res){
                return res.result == "321" && res.tail == "";
                }
        )(mapped_p1)
    );
}

/** returns result of the left parser if both parser matched successfully. */
Parser!T2 skip_right(T1, T2)(Parser!T1 p1, Parser!T2 p2)
{
    Parser!(Tuple!(T1, T2)) and_p = and!(T1, T2)(p1, p2);
    return map_p!(Tuple!(T1, T1), T2)(and_p, (Tuple!(T1, T2) res) => res[0]);

}
unittest {
    Parser!string p1 = word("123");
    Parser!string p2 = word("321");

	auto mapped_p1 = skip_right!(string, string)(p1, p2)("123321");

    assert(
        tryMatch!(
            (ParseSuccess!(string) res){return res.result == "123";}
        )(mapped_p1)
    );
}
/** returns result of the first successfully matched combinator. */
Parser!T1 choice(T1)(Parser!(T1)[] parsers)
{
    return reduce!((p1, p2) => or!T1(p1, p2))(parsers[0], parsers.drop(1));

}

unittest {
	auto mapped_p1 = choice!(string)([word("1"), word("2"), word("3"), word("1")])("3");

    assert(
        tryMatch!(
            (ParseSuccess!(string) res){
                return res.result == "3";
            }
        )(mapped_p1)
    );

    auto mapped_p2 = choice!(string)([word("1"), word("2"), word("3"), word("3")])("6");

    assert(
        tryMatch!(
            (ParseFailure err){
                return true;
            }
        )(mapped_p2)
    );
}

import std.typecons : Nullable, nullable;

/** returns Nullable type result of the parser*/
Parser!(Nullable!T1) optional(T1)(Parser!(T1) parser){
    Parser!(Nullable!T1) f = (Input input) {
        ParseResult!T1 res = parser(input);

        Nullable!(T1) nullable_res = Nullable!(T1).init;

        return res.match!(
            (ParseSuccess!T1 s) {
                nullable_res = s.result;
                return ParseResult!(Nullable!T1)(ParseSuccess!(Nullable!T1)(nullable_res, s.tail));
            },
            (ParseFailure _) { return ParseResult!(Nullable!T1)(ParseSuccess!(Nullable!T1)(nullable_res, input)); },
        );
    };
    return f;
}

unittest {
	auto mapped_p1 = optional!(string)(word("1"))("123");
    assert(
        tryMatch!(
            (ParseSuccess!(Nullable!(string)) res){
                return res.result.get() == "1" && res.tail == "23";
            }
        )(mapped_p1)
    );

    auto mapped_p2 = optional!(string)(word("1"))("333");
    assert(
        tryMatch!(
            (ParseSuccess!(Nullable!(string)) res){
                return res.result.isNull && res.tail == "333";
            }
        )(mapped_p2)
    );
}


Parser!T1 literal(T1)(T1 value){
    Parser!T1 f = (Input input) {
        return ParseResult!T1(ParseSuccess!T1(value, input));
    };
    return f;
}


/** skip the parser result until it is successfully matched and then apply another parser */
Parser!T1 skip_before (T1, T2)(Parser!T1 p1, Parser!T2 skip)
{
    Parser!T1 f = (Input input) {
        bool skiping = true;
        string tail = input;
        while(skiping){
            ParseResult!T2 to_skip = skip(tail);
            to_skip.match!(
                (ParseSuccess!T2 res1) {
                    tail = res1.tail;
                },
                (ParseFailure _) {
                    skiping = false;
                },
            );
        }
        return p1(tail);
    };
    return f;
}

auto ws(Input input){
    return choice!(dchar)([chr('\n'), chr(' '), chr('\t')])(input);
}

/** skip white space and \n then apply parser */
Parser!T1 ws_skip_before (T1)(Parser!T1 p1)
{
    return skip_before!(T1, dchar)(p1, toDelegate(&ws));
}


unittest {
    tryMatch!(
        (ParseSuccess!(dchar) result){
            return result.result == 'a' && result.tail == "123";
        }
    )((toDelegate(chr('a').ws_skip_before!(dchar)))("    a123"));

    Parser!dchar skip = chr(' ');
    Parser!dchar p2 = chr('a');
    assert(
        tryMatch!(
            (ParseSuccess!(dchar) result){
                return result.result == 'a' && result.tail == "123";
            }
        )(skip_before!(dchar, dchar)(p2, skip)("    a123"))
    );
}

