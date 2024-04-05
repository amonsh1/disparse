module app;

import std.meta: Filter, staticMap;
import std.stdio;
import std.typecons;

import std.algorithm.iteration : map, reduce;
import std.functional : toDelegate;
import std.conv, std.format, std.functional: partial, curry;
import std.sumtype : This, SumType, match, tryMatch;
import std.array;
import std.meta : AliasSeq;
import std.uni : CodepointSet, unicode;

import types;
import parsers;
import combinators;


struct JsonNull{}
alias Json = SumType!(
    bool,
    double,
    This[],
    This[dstring],
    dstring,
    JsonNull
);
alias JsonBool = Json.Types[0];
alias JsonNumber = Json.Types[1];
alias JsonArray = Json.Types[2];
alias JsonObject = Json.Types[3];
alias JsonString = Json.Types[4];

import std.meta : allSatisfy, staticMap;
import std.traits : ConstOf;


ParseResult!(dchar) digits(string v){
    Parser!(dchar)[] digits_parsers = map!((dchar c){return chr(c);})(['1', '2', '3', '4', '5', '6', '7', '8', '9', '0', ]).array;
    Parser!(dchar) digits_parser = choice!(dchar)(digits_parsers);
    return digits_parser(v);
}

ParseResult!(dchar) digits_no_0(string v){
    Parser!(dchar)[] digits_parsers = map!((dchar c){return chr(c);})(['1', '2', '3', '4', '5', '6', '7', '8', '9']).array;
    Parser!(dchar) digits_parser = choice!(dchar)(digits_parsers);
    return digits_parser(v);
}




ParseResult!(dchar) escaped_chars(string v){
    auto hex_code_set = CodepointSet('0', '9'+1, 'A', 'F'+1, 'a', 'f'+1);
    Parser!(dchar) escaped_chars_parser = choice!(dchar)(
        [
            chr('"'),
            chr('\\'),
            chr('/'),
            map_p!(dchar, dchar)(
                chr('b'), (dchar _) => '\b'
            ),
            map_p!(dchar, dchar)(
                chr('f'), (dchar _) => '\f'
            ),
            map_p!(dchar, dchar)(
                chr('n'), (dchar _) => '\n'
            ),
            map_p!(dchar, dchar)(
                chr('r'), (dchar _) => '\r'
            ),
            map_p!(dchar, dchar)(
                chr('t'), (dchar _) => '\t'
            ),
            map_p!(Tuple!(dchar, dchar, dchar, dchar, dchar), dchar)(
                seqtup!(dchar, dchar, dchar, dchar, dchar)
                (
                    chr('u'),
                    code_set(hex_code_set),
                    code_set(hex_code_set),
                    code_set(hex_code_set),
                    code_set(hex_code_set),
                ), (Tuple!(dchar, dchar, dchar, dchar, dchar) v){
                    return to!dchar(to!int(format("%c%c%c%c"d, v[1], v[2], v[3], v[4]), 16));
                }
            ),
        ]
    );
    return escaped_chars_parser(v);
}

ParseResult!(Json) p1(string v){
    return choice!(Json)(
        [
            map_p!(JsonString, Json)(toDelegate(&jsString), (JsonString v){
                return Json(v);
            }),
            map_p!(JsonNull, Json)(toDelegate(&jsNull), (JsonNull v){
                return Json(v);
            }), 
            map_p!(JsonBool, Json)(ws_skip_before!(JsonBool)(toDelegate(&jsBool)), (JsonBool v){
                return Json(v);
            }), 
            map_p!(JsonNumber, Json)(ws_skip_before!(JsonNumber)(toDelegate(&jsInt)), (JsonNumber v){
                return Json(v);
            }), 
            map_p!(JsonArray, Json)(ws_skip_before!(JsonArray)(toDelegate(&jsArray)), (JsonArray v){
                return Json(v);
            }), 
            map_p!(JsonObject, Json)(ws_skip_before!(JsonObject)(toDelegate(&jsObject)), (JsonObject v){
                return Json(v);
            }), 
        ], 
        
    )(v);
}


ParseResult!(JsonNull) jsNull(string v){
    return map_p!(string, JsonNull)(
        ws_skip_before!(string)(word("null")), 
        (string _){
            return JsonNull();
        }
    )(v);
}


ParseResult!(JsonBool) jsBool(string v){
    return map_p!(string, JsonBool)(
        choice!(string)(
            [
                word("true"),
                word("false"),
            ]
        ), 
        (string v){
            return JsonBool(true);
        }
    )(v);
}

import std.algorithm.iteration : filter;
ParseResult!(JsonNumber) jsInt(string v){
    alias RT = AliasSeq!(
        Nullable!(dchar), 
        dstring, 
        Nullable!(Tuple!(dchar, dchar[])),
        Nullable!(Tuple!(dchar, Nullable!(dchar), dchar[])),
    );
    return map_p!(Tuple!(RT),JsonNumber)(
        seqtup!(RT)(
            ws_skip_before!(Nullable!(dchar))(optional!(dchar)(chr('-'))),
            ws_skip_before!(dstring)(
                choice!(dstring)(    
                    [
                        map_p!(dchar, dstring)(chr('0'), (v => "0"d)),
                        map_p!(dchar[], dstring)(many1!(dchar)(toDelegate(&digits)), (v => v.idup))
                    ]
                    
                ),
            ),
            optional!(Tuple!(dchar, dchar[]))(
                seqtup!(dchar, dchar[])(chr('.'), many!(dchar)(toDelegate(&digits)))
            ),
            optional!(Tuple!(dchar, Nullable!(dchar), dchar[]))(
                seqtup!(dchar, Nullable!(dchar), dchar[])(
                    or!(dchar)(chr('e'), chr('E')),
                    optional!(dchar)(or!(dchar)(chr('+'), chr('-'))),
                    many!(dchar)(toDelegate(&digits)),
                )
            ),
        ), 
        (Tuple!(RT) v){
            dstring r = "";
            if (!v[0].isNull){
                r ~= '-';
            }
            r ~= v[1];
            if (!v[2].isNull){
                r ~= v[2].get()[0];
                r ~= v[2].get()[1].idup;
            }
            if (!v[3].isNull){
                r ~= v[3].get()[0];
                if (!v[3].get()[1].isNull){
                    r ~= v[3].get()[1].get();
                }
                r ~= v[3].get()[2].idup;
            }
            return JsonNumber(to!double(r));
        }
    )(v);
}



ParseResult!(JsonString) jsString(string v){
    auto unicode_chars =
		unicode.Cc.add('"', '"'+1).add('\\', '\\'+1);
    auto unicode_chars_inv = unicode_chars.inverted;
    return map_p!((Tuple!(dchar, dchar[], dchar)), JsonString)(
        seqtup!(dchar, dchar[], dchar)(
            toDelegate(chr('"').ws_skip_before!(dchar)),
            many!(dchar)(
                or!(dchar)(
                    code_set(unicode_chars_inv),
                    map_p!(Tuple!(dchar, dchar))(
                        (seqtup!(dchar, dchar)(
                                chr('\\'),
                                toDelegate(&escaped_chars)
                            )
                        ),
                        (Tuple!(dchar, dchar) v){
                            return v[1];
                        }
                    ),
                )
            ),
            toDelegate(chr('"').ws_skip_before!(dchar)),
        ),
        (Tuple!(dchar, dchar[], dchar) v){
            return v[1].idup;
        }
    )(v);
}

ParseResult!(JsonArray) jsArray(string v){

    return map_p!((Tuple!(dchar, JsonArray, dchar)), JsonArray)(
        seqtup!(dchar, JsonArray, dchar)(
            toDelegate(chr('[')),
            delimited!(Json, dchar)(toDelegate(&p1), chr(',').ws_skip_before!(dchar)),
            toDelegate(chr(']').ws_skip_before!(dchar)),
        ),
        (Tuple!(dchar, JsonArray, dchar) v){
            return v[1];
        }
    )(v);
}


ParseResult!(JsonObject) jsObject(string v){
    auto pair = ws_skip_before!(Tuple!(JsonString, dchar, Json))((
            seqtup!(JsonString, dchar, Json)(
                toDelegate(&jsString),
                chr(':').ws_skip_before!(dchar),
                toDelegate(&p1),
            )
        )
    );
    
    return map_p!((Tuple!(dchar, JsonObject, dchar)), JsonObject)(
        seqtup!(dchar, JsonObject, dchar)(
            chr('{').ws_skip_before!(dchar),
            map_p!(Tuple!(JsonString, dchar, Json)[], JsonObject)(
                (delimited!(Tuple!(JsonString, dchar, Json), dchar)(pair, chr(','))),
                (Tuple!(JsonString, dchar, Json)[] v){
                    JsonObject g;
                    foreach (val; v)
                    {
                        g[val[0]] = val[2];
                    }
                    return g;
                }
            ),
            chr('}').ws_skip_before!(dchar),
        ),
        (Tuple!(dchar, JsonObject, dchar) v){
            return v[1];
        }
    )(v);
}

void print_json(Json v){
    v.match!(
        (JsonBool f){
            write(f);
        },
        (JsonNumber i){write(i);},
        (JsonArray f){
            write("[");
            foreach (Json key2; f){
                print_json(key2);
                write(",");
            }
            write("]");
        },
        (JsonObject f){
            write("{");
            foreach (dstring key2, Json val; f){
                write(format("\"%s\":", key2));
                print_json(val);
                write(",");
            }
            write("}");
        },
        (JsonString f){
            write("\"");
            write(f);
            write("\"");
        },
        (JsonNull f){
            write("null");
        },
    );
}

void main(){
    import std.file : readText;


    auto data = readText("example.json");
    tryMatch!(
        (ParseSuccess!(Json) result){
            print_json(result.result);
        }
    )(p1(data));

}