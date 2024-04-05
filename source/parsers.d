module parsers;

import std.stdio : writeln;
import std.sumtype : SumType, match, tryMatch;
import std.string;
import std.algorithm.searching : canFind;
import std.utf : count;
import std.range : front, take, drop, popFront;
import std.conv : to, text;
import std.uni;
import std.functional : curry, partial;
import types;


Parser!dchar chr (dchar c){
    Parser!dchar f = (Input input) {
        if (input.empty){
            return ParseResult!dchar(ParseFailure("EOF"));
        }
        dchar head = input.front;
        input.popFront();
        if (head == c) {
            return ParseResult!dchar(ParseSuccess!dchar(c, input));
        }
        return ParseResult!dchar(ParseFailure(format("'%c' letter was expected, not '%c'", c, head)));
    };
    return f;
}

unittest {
    ParseResult!dchar p1 = chr('a')("ass");
    assert(tryMatch!((ParseSuccess!dchar res){
        return res.result == 'a';
    })(p1));

    ParseResult!dchar p2 = chr('a')("daa");
    assert(tryMatch!((ParseFailure res) => res.message == "'a' letter was expected, not 'd'")(p2));
}

Parser!dchar not_chr (string unacceptable){
    Parser!dchar f = (Input input) {
        dchar head = input.front;
        input.popFront();
        if (!canFind(unacceptable, head)) {
            return ParseResult!dchar(ParseSuccess!dchar(head, input));
        }
        return ParseResult!dchar(
            ParseFailure(format("'%c' letter is in the list of unacceptable '%s'", head, unacceptable))
        );
    };
    return f;
}

unittest {
    ParseResult!dchar p1 = not_chr("ass")("ddd");
    assert(tryMatch!((ParseSuccess!dchar res) => res.result == 'd')(p1));

    ParseResult!dchar p2 = not_chr("ass")("aaa");
    assert(tryMatch!((ParseFailure res) => res.message == "'a' letter is in the list of unacceptable 'ass'")(p2));
}

Parser!string word (string pref){
    Parser!string f = (Input input) {
        string head = input.take(count(pref)).text;
        if (head == pref) {
            return ParseResult!string(ParseSuccess!string(pref, input.drop(count(pref)).text));
        }
        return ParseResult!string(ParseFailure(format("'%s' word was expected, not '%s'", pref, head)));
    };
    return f;
}

unittest {
    ParseResult!string p1 = word("urmom")("urmom123");
    assert(tryMatch!((ParseSuccess!string res) => res.result == "urmom")(p1));

    ParseResult!string p2 = word("urmom")("qwdqwdurmom123");
    assert(tryMatch!((ParseFailure res) => res.message == "'urmom' word was expected, not 'qwdqw'")(p2));

}


Parser!dchar code_set (ref CodepointSet set){
    Parser!dchar f = (Input input) {
        dchar head = input.front;
        input.popFront();
        if (set[head]) {
            return ParseResult!dchar(ParseSuccess!dchar(head, input));
        }
        return ParseResult!dchar(
            ParseFailure(format("'%c' letter not in the set '%s'", head, set))
        );
    };
    return f;
}