import ramjet.parser_builder;
import std.stdio;

string makeParser()
{
	auto builder = new ParserBuilder!char;
	builder.beginGrammarDefinition();
		builder.pushSequence();
			builder.literal('x');
			builder.pushMaybe();
				builder.literal('y');
			builder.pop();
		builder.pop();
	builder.endGrammarDefinition();
	return builder.toDCode("callMe");
}

/+
void main()
{
	import std.stdio;
	import ramjet.internal.reindent;
	auto foo = makeParser();
	writeln("Before reindentation:");
	writeln(foo);
	writeln("");
	writeln("After reindentation:");
	writeln(reindent(0, foo));
}
+/

const foo = makeParser();

pragma(msg, foo);

mixin(foo);


void main()
{
	auto builder = new ParserBuilder!char;
	builder.beginGrammarDefinition();
		builder.pushSequence();
			builder.literal('x');
			builder.pushMaybe();
				builder.literal('y');
			builder.pop();
		builder.pop();
	builder.endGrammarDefinition();
	writefln(builder.toString());
	writefln("");

	auto m = callMe.n0("x",0,1);
	writefln("%s",m.successful);
	m = callMe.n0("xy",0,2);
	writefln("%s",m.successful);
	m = callMe.n0("xyz",0,3);
	writefln("%s",m.successful);
	m = callMe.n0("q",0,1);
	writefln("%s",m.successful);
	m = callMe.n0("",0,0);
	writefln("%s",m.successful);
	//writefln("Now then, let's do this.\n");
	//writeln(foo);
}
