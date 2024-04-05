module types;

import std.sumtype : SumType, match, isSumType;
import std.range : isInputRange;
import std.traits : TemplateOf, TemplateArgsOf;

struct ParseFailure {
    string message;
    string forward_value;
    string expected;
}

struct ParseSuccess(T) {
    T result;
    string tail;
    @disable this();
    this(T result, string tail){
        this.result = result;
        this.tail = tail;
    }
}

alias ParseResult(T) = SumType!(ParseSuccess!T, ParseFailure);
alias Input = string;
alias Parser(T) = ParseResult!T delegate(Input);

enum isParser(Parserr, T) = is(typeof({
	auto g = Parserr("");
    pragma(msg, isSumType!(typeof(g)));
    static assert (__traits(isSame, TemplateOf!(g.Types[0]), ParseSuccess), "asdad");
}));
