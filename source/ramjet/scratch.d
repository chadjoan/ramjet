
/+


API design:
How to handle 'tween' matches elegantly? This is useful for pass-through stuff
where you match a grammar but generally don't care about most of it. Maybe
you just rifle through function declarations and add some code to the beginning
and end of every function's statement block, but you couldn't care less what
was inbetween as long as that inbetween text ends up in the output. Also you
want to pass all of the whitespace, but you don't want to iterate over
whitespace nodes, because that's annoying.


Grammar design:

Feature: 'nonrecursive' keyword. Might be necessary for allowing regex alternation in tree-based grammars.

Feature: Allow operator overloading, ex: @whitespaceIsDefault = OpSequence(a,b) <- a WhiteSpace b

Feature: Allow windowing of some kind. This might be useful for things like
	parsing Python code (whitespace indentation levels) or D's ddoc comments
	with inline D code. In the case of DDoc comments: the comments might start
	every line with ///, but that /// is not part of the syntax within the
	comments--we really want some way to see what the comment text looks like
	without the delimiters at the beginning of the line.

Feature: Error rule. This rule indicates that the parse failed due to some
	anticipated user mistake, like forgeting to put a ';' at the end of a
	statement. Such a situation might look like this:

	  Statement <- Expression (';' / Error("Expected ';' after expression [... formatting and context dump ...]"))

	This information would allow the parser to continue parsing as if the ';'
	were present. Why have the ';' at all? It might have been required by older
	computers to make parsing easier, but it almost certainly serves the purpose
	of making mistakes (such as forgetting to place an operator between two
	other expressions, such as function calls) more self-reporting. Having
	self-reporting mistakes is great, but a parser that only presents them
	one-at-a-time can make the concept /really/ frustrating to experience, so
	it is important for parsers to be able to recover from errors like this
	(that is, errors that have more to do with preventing ambiguity or with
	semantic meaning, as opposed to the kind of high-uncertainty syntax-related
	errors that you might expect if you were to run a D compiler on python code
	or an english novel).

Feature: constraints.
- Constraint on DFA sizes. I'm going to shoot for a default of n*log(n), where
	n is the number of initial NFA states (after any augmentation that might
	be required for NFA-only operation). n^2 could happen if n*log(n) proves
	impractical for realistic grammars.
	So whenever the NFA->DFA converter exceeds n*log(n) DFA nodes, it would
	backtrack to any decisions it made that lead to things like exponential
	explosions in DFA nodes, and then it would
	TODO: Consider measuring in edges instead! Or not? Maybe that would be
	a separate constraint... so you'd get a default guarantee of n*log(n)
	nodes and n^2 edges. In principle this is not redundant, since a graph
	with m nodes can have m*(m-1)/2 edges (or O(m^2) edges), which means
	a graph with O(n*log(n)) nodes could have O((n^2)*log(n)) edges.

Feature: Pseudo-inputs:
  // The "version" expression is a pseudo-input. It can be matched or not matched
  // depending on some state that may or may not be related to the input. It
  // does not consume any input.
  //
  // Rule1 matches SomeRuleA if the parser is being generated for the D programming
  // language, but matches SomeRuleB if it is being generated for the C programming
  // language.
  Rule1 <- (version(D_Language) SomeRuleA / version(C_Language) SomeRuleB)

  // It might even make sense to allow pseudo-inputs to perform basic arithemetic:
  NetworkProtocolPacket <- 0xF00D NetworkProtocolVersion
    Ver0_OrLater_NetworkProtocolContents
    if(NetworkProtocolVersion > 5) Ver5_OrLaterNetworkProtocolContents
  // The idea here is to provide a way to change parse results based on basic
  // (pure, not-stateful) calculations in a way that is agnostic to the parser's
  // host (target) language and doesn't affect the parser's algorithmic time or
  // space complexity.
  // TODO: Better arithmetic example that really hammers the use-case? Or does
  // this just never happen in any way that can't already be handled by hackey
  // parse rules or is complicated enough to use semantic actions and become
  // host-language-dependent (while maybe also screwing with time-complexity)?
  //
  // TODO: Do pseudo-inputs produce any outputs in the resulting parse event
  // stream or parse tree? I suspect that they should not produce any in-band
  // output, like generating normal begin/end events or ParseTree nodes. Rather,
  // they should have their own event type (and node type/meta) that makes them
  // easily filtered and excluded by default.
  //
  // TODO: Maybe parsers just need to comprehend integers/numbers?


TODO: Make sure things like HTML can be parsed. That backreference shit needs
to work (kinda) or be replaced by something useful but faster.

Maybe capture filtering should be done outside of the grammar?
So instead of

Expr :shallow ignore: <- '('? :deep keep: LExpr Operator :deep keep: RExpr ')'?

We would have
Expr <- '('? LExpr Operator RExpr ')'?
keep Expr, LExpr, RExpr
ignore Operator, WhiteSpace

Namespacing:

Namespacing in programming languages sucks in general. I'm not talking about
a "namespace" feature. I'm talking about how we distinguish between different
types of named entities in our languages, things like keywords, user-defined
types, functions, variables appear within expressions, and so on.

Why?

Most languages will have multiple named entities competing for the "top-level"
namespace. This is the namespace in which the named entities are not required
to be "sigilized" to appear and are not required to have any other exotic
prologue or epilogue. Typically we have these things in competition:
- Reserved keywords for the language
- User-defined type names
- Variable names, especially when appearing in expressions (where multiple
    variable names appear in a short span of text)
- User-defined attributes

We might even have trouble deciding if user-defined type names should occupy
the same namespace as language-defined types. Usage would look consistent
if they appeared the same way (ex: int and MyType both appear bare and unsigilized)
(eg: it is easier to understand and spot what a declaration involving a type
looks like in the language). But if they appear the same way, then some names
are off-limits for library writers, but even worse, addition of new language-defined
types becomes always a breaking change for the language. We could put these
in separate namespaces, such as by leaving language-defined types bare while
sigilizing user-defined types, so we have 'int' and '%MyType' instead of 'int'
and 'MyType' or '%int' and '%MyType'. This makes it easier to make language
changes, but it's also less clear what a 'type' looks like in the language,
since it could be written one of two ways instead of just in one way.

Changing subject a bit: how about those reserved keywords?

We could sigilize keywords, but then we'd have stuff like
@private @static @pure @nothrow @const myUDA
	myFunction( @const @ref MyType myParam1, @inout @int myParam2)
{
	@enum OtherType myConstant = @new OtherType;
	...
	@return (foo[i] + bar[j+k]) % baz / (qux + otherFunction(boop));
}

Keywords can appear quite often. The eye-brain parser tends to see symbols
as more prominent then text. Soon everything looks like alphabet soup, but
without the alphabet. Not cool.

We could sigilize all of our user-defined names:
private static pure nothrow const @myUDA
	@myFunction( const ref @MyType @myParam1, inout int @myParam2)
{
	enum @OtherType @myConstant = new @OtherType;
	...
	return (@foo[@i] + @bar[@j+@k]) % @baz / (@qux + @otherFunction(@boop));
}

Still pretty awful. Expressions get especially bad, even moreso with
surrogate-y things like i, j, and k.

This is a simplification still, and we could always do more complex things
like give different symbols to different classes of user-named things, like
$ for variables, % for types, @ for function (calls), and so on. Perl is like
this, only it tends to use differences in sigils as a way to distinguish
between different kinds of variables (well, different ways to /access/
variables, really, but usually you want to be consistent within the same
variable or Bad Things (tm) happen), while many other language constructs
(such as subroutine names) remain bare.

Observations:
- Long runs of sigilized names are difficult to read.
- Keywords tend to appear next to each other.
- Expressions are often rich with variable names, not so much keywords.
- Expressions can still contain keywords (ex: 'new' in many OOP languages, or
	'ref' and 'out' in C# method arguments).
- Keywords tend to appear next to type names in declarations.
- Some type names ARE keywords.
- In fact, declarations are where a lot of mess lies: you have keywords, types,
    and variable names, all in close proximity.

I am intending to solve this as I make a grammar for defining grammars. Seems
odd that I would run into this issue, but I want to provide my parser-generator
with user-defined-attributes to provide some delicious aspect-oriented stuff.
It also needs keywords to implement non-trivial pattern matching and capture
control without looking cryptic as all hell (ex: should use keywords "deep"
and "shallow" instead of switching between two, possibly large, sets of
symbols (or compound symbols) to distinguish between this one difference).

To this end, I at least need to deal with keywords vs attributes.
Both can appear with multiplicity in various declarations:

Expr shallow ignore <- '('? deep keep LExpr Operator deep keep RExpr ')'?

within NewExpr
	with DotPath as path
	on TypeIdentifier deep ignore <- 'ParserBuilder'
		{ p => writefln("Found %s! ParseTree:\n%s", p.findSymbol('path'), p); }

Thins are already getting ugly.

How about making language-defined attributes be enclosed in some list
delimiters? ... like this:

Expr :shallow ignore: <- '('? :deep keep: LExpr Operator :deep keep: RExpr ')'?

within NewExpr
	with DotPath as path
	on TypeIdentifier :deep ignore: <- 'ParserBuilder'
		{ p => writefln("Found %s! ParseTree:\n%s", p.findSymbol('path'), p); }

It probably seemed better in my head. But it would be useful for lists of
3 or more language-defined attributes.
I do think it's at least easier to read than what came before; the sigils give
the eye a good stopping point to know where different language elements
begin and end. And this is where the list idea might still be better than
individual sigils at each keyword: the last keyword's sigil being at its
right-side might be really useful for the human eye-brain-parser, because
it also indicates where the keywords end, not just where they begin.

Well, let's see what it looks like with various kinds of prefix sigils:

Expr @shallow @ignore <- '('? @deep @keep LExpr Operator @deep @keep RExpr ')'?

within NewExpr
	with DotPath as path
	on TypeIdentifier @deep @ignore <- 'ParserBuilder'
		{ p => writefln("Found %s! ParseTree:\n%s", p.findSymbol('path'), p); }

(oh god no. Maybe it's the character choice?)

Expr :shallow :ignore <- '('? :deep :keep LExpr Operator :deep :keep RExpr ')'?

within NewExpr
	with DotPath as path
	on TypeIdentifier :deep :ignore <- 'ParserBuilder'
		{ p => writefln("Found %s! ParseTree:\n%s", p.findSymbol('path'), p); }

(Better, but I still prefer the first attempt...)

Now let's see if we can distinguish between (user-defined) rule names and
keywords for declarations like the "within" declaration:

$Expr :shallow ignore: <- '('? :deep keep: $LExpr $Operator :deep keep: $RExpr ')'?

within $NewExpr
	with $DotPath as path
	on $TypeIdentifier :deep ignore: <- 'ParserBuilder'
		{ p => writefln("Found %s! ParseTree:\n%s", p.findSymbol('path'), p); }

I'm tired. Let's finish later.





TODO: construct RDPs of NFAs.  The NFAs will periodically need to be converted
to DFAs to allow for operations like complementation/intersection.

Once the desired parser is attained, convert it to a PDA with memoization.



X <- "(xxXxxXxxXxx)" / "(xxXxx" BAR ")" / "(xxXxx" BAZ ")"

Bar <- "a" X "+"

Baz <- "a" X "-"

Foo <- Bar / Baz

int[] X_cache;

bool X(string s, int pos)
{
	if ( X_cache[pos] > 0 ) return true;
	if ( X_cache[pos] < 0 ) return false;
	if ( s[pos..pos+13] == "(xxXxxXxxXxx)" )
	{
		X_cache[pos] = 1;
		return true;
	}
	else if ( Bar(s,pos) || Baz(s,pos) )
	{
		X_cache[pos] = 1;
		return true;
	}

	X_cache[pos] = -1;
	return false;
}

bool Bar(string s, int pos)
{
	if ( s[pos] != 'a' ) return false;
	if ( !X(s, pos+1)  ) return false;
	if ( s[pos] != '+' ) return false;
	return true;
}

bool Baz(string s, int pos)
{
	if ( s[pos] != 'a' ) return false;
	if ( !X(s, pos+1)  ) return false;
	if ( s[pos] != '-' ) return false;
	return true;
}

bool Foo(string s, int pos)
{
	X_cache = new byte[s.length];
	foreach( ref xres; X_cache ) xres = 0;
	return Bar(s, pos) || Baz(s, pos);
}

Foo("a(xxXxxa(xxXxxXxxXxx)-)-");
+/

/+
alias void* AutomatonLabel;

const int stackSymbolBacktrack = -2;
const int stackSymbolPop  = -1;
const int stackSymbolNull = 0;
const int recurseSymbolNull = 0;

enum TransitionDir
{
	uninitialized,
	forward,
	backward,
}

final class Transition(ElemType)
{
	private alias AutomatonState!ElemType State;

	string          recurseLabel = null;

	int             stackSymbolToMatch = stackSymbolNull;
	int             stackSymbolToPush = stackSymbolNull;
	Label           backtrackLabel; /* Used both when pushing/popping a backtrace symbol. */
	bool            complementStackSymbol = false;
	bool            matchAllInputSymbols = true;
	bool            complementInputSymbol = false;
	ElemType         inputSymbolToMatch;
	int             recurseSymbol = recurseSymbolNull;

	State           nextState = null;
	TransitionDir   direction = TransitionDir.uninitialized;

	@property bool matchAllStackSymbols() const
	{
		return (stackSymbolToMatch == stackSymbolNull);
	}

	@property bool useRecurseSymbol() const
	{
		return (recurseSymbol != recurseSymbolNull);
	}

	int opCmp( ref const Transition t ) const
	{
		return .opCmp(this.inputSymbolToMatch, t.inputSymbolToMatch);
	}

	bool attempt(R)( size_t* pos, R input ) if ( isRandomAccessRange!(R) )
	{
		auto c = input[*pos];
		if ( useRecurseSymbol )
		{
		}
		else if (
			(matchAllInputSymbols || c == inputSymbolToMatch) &&
			(matchAllStackSymbols || stackSymbolToMatch == symbolStack.front) &&
			(!useRecurseSymbol) )
		{
			if ( stackSymbolToPush == stackSymbolPop )
				symbolStack.pop();
			else if ( stackSymbolToPush != stackSymbolNull )
				symbolStack.push(stackSymbolToPush);

			(*pos)++;

			return true;
		}
		else
			return false;
	}

	@property bool isFiniteTransition() const
	{
		return (useInputSymbol && !useStackSymbol && !useRecurseSymbol);
	}
}

final class AutomatonState(SymbolType)
{
	private alias Transition!ElemType Transition;

	// This is usually the NFA state tuple that this DFA state comes from.
	// This gives us fast comparisons and the ability to use it as a hash key.
	AutomatonLabel[] nfaStateTuple;

	// This describes which symbols transition the automaton into which next
	//   state.
	// This should also be sorted to make matching faster by making it faster
	//   to determine which state to transition into next.
	Transition[] transitions;

	// An integer that uniquely identifies this state within the automaton
	//   it occupies.
	@property AutomatonLabel label() const
	{
		return (AutomatonLabel)(void*)this;
	}

	// Does ending on this node mean that the input is recognized by the
	//   automaton?
	bool isFinal = false;

	this()
	{
		nfaStateTuple = new AutomatonLabel[0];
		transitions = new Transition[0];
	}

	void addTransition( Transition t )
	{
		transitions ~= t;
	}
}

struct AutomatonFragment(ElemType)
{
	private alias Transition!ElemType     Transition;
	private alias AutomatonFragment!ElemType Fragment;
	private alias AutomatonState!ElemType State;

	State        startNode;
	Transition[] danglingArrows;

	Fragment toDfa()
	{
		// Create a final node to tie all of the dangling arrows into.
		// This is necessary for performing the NFA->DFA conversion, as it
		//   allows the DFA to use the final state in its constructions.
		// We will later remove final states from the DFA and make their
		//   arrows/transitions be the new danglingArrows list.
		auto acceptState = new State();
		acceptState.isFinal = true;

		foreach( ref transition; danglingArrows )
			transition.nextState = acceptState;

		// Create another final node that things travel to when they aren't
		//   recognized.  This will turn into some important nodes in the DFA
		//   because they are accepting states under complementation.
		auto rejectState = new State();
		// TODO: walk all nodes and create complementary transitions going to
		//   the reject state.  It may also need an arrow going back into itself.
		//   See: http://www.cs.odu.edu/~toida/nerzic/390teched/regular/fa/complement.html


	}
}

template AutomatonFuncs(ElemType)
{
	private alias Transition!ElemType        Transition;
	private alias AutomatonFragment!ElemType Fragment;
	private alias AutomatonState!ElemType    State;

	private void epsilonClosureRecurse( const Transition transition, ref State[Label] reachableStates )
	{
		if ( transition is null )
			return;

		// It's an epsilon closure, so non-epsilon transitions cannot be taken.
		// Only transitions that require no symbol consumption are allowed.
		if ( transition.isEpsilon )
			epsilonClosureFork(startState, reachableStates);
	}

	// Same as epsilonClosure below, but done for a single start state.
	private void epsilonClosureFork( const State startState, ref State[Label] reachableStates )
	{
		if ( startState is null )
			return;

		Label label = startState.label;
		if ( label in reachableStates )
			return; // Break cycles.

		reachableStates[label] = startState;

		foreach( transition; startState.transitions )
			epsilonClosureRecurse( transition, reachableStates );
	}

	/// Returns which states can be reached from the startStates without
	///   consuming any tokens at all (that is, by consuming the 'epsilon' token).
	pure State[Label] epsilonClosure( const State[] startStates )
	{
		assert(startStates !is null);
		State[Label] reachableStates;
		foreach ( startState; startStates )
			epsilonClosureFork(startState, reachableStates);
		return reachableStates;
	}

	pure Transition newEpsilonTransition()
	{
		return new Transition();
	}

	pure Transition newEpsilonTo( const State state )
	{
		auto trans = newEpsilonTransition();
		trans.nextState = state;
		return trans;
	}

	pure Fragment newEmptyFragment()
	{
		Fragment result = new Fragment();
		result.startState = new State();
		result.startState.addTransition(newEpsilonTransition());
		return result;
	}
}
+/



/+
	private Fragment assembleSeq( SList!Fragment operands )
	{
		return reduce!assembleSeq( operands );
	}

	Fragment assembleSeq( inout Fragment a, inout Fragment b )
	{
		auto result = new Fragment();
		result.startState = a.startState;
		foreach( ref transition; a.danglingArrows )
		{
			transition.nextState = b.startState;
			transition.direction = TransitionDir.forward;
		}
		result.danglingArrows = b.danglingArrows;
		return result;
	}

	private Fragment assembleOr( SList!Fragment operands )
	{
		return reduce!assembleOr( operands );
	}

	string          recurseLabel = null;

	int             stackSymbolToMatch = stackSymbolNull;
	int             stackSymbolToPush = stackSymbolNull;
	bool            useInputSymbol = false;
	SymbolT         inputSymbolToMatch;
	int             recurseSymbol = recurseSymbolNull;

	State           nextState = null;
	TransitionDir   direction = TransitionDir.uninitialized;


	private Fragment assembleUnorderedChoice( inout Fragment a, inout Fragment b )
	{
		auto result = new Fragment();
		result.startState = new State();
		foreach ( frag; operands )
		{
			auto regularFrag = frag.toRegularFragment();
			if ( regularFrag is null )
				throw new Exception("Non-regular expressions cannot appear within unordered choice.");

			result.startState.addTransition(newEpsilonTo(regularFrag.startState));
			result.danglingArrows ~= regularFrag.danglingArrows;
		}
		return result;
	}

	// Complementation distributes over ordered choice in regular grammars:
	// Given (a/b) == (a|(^a&b))
	// Then ^(a/b) == ^(a|(^a&b)) == (^a|^(^a&b)) == (^a|(a&^b)) == (^a/^b)

	// The working conjecture is that (uv/xy)c == (uv|(^(uv)&xy))c
	//   (or, by De Morgan's law: (uv/xy)c == (uv|(^(uv|^(xy))))c )
	// It makes some amount of sense: xy is only chosen if uv is never chosen,
	//   therefore that branch of the NFA must recognize strings that are uv
	//   but not xy.  Put another way: when matching uv, ignore any xy because
	//   any string matching xy would have taken the other path.
	// More complex expressions expand like so:
	//   (a/b/c)x == (a|(^a&b)|(^(^a&b)&c))x
	//   (a/b/c/d)x == (a|(^a&b)|(^(^a&b)&c)|(^(^(^a&b)&c)&d))x
	// Let's use that for now with operands that are regular.
	// operands including non-regular elements will need different treatment.
	private Fragment assembleOrderedChoice( SList!Fragment operands )
	{
		A <- (x B / x C) z D
		((x B) | (^(x B) & (x C))) z D



		A <- x B x C x / x
		B <- A C / q
		C <- A B / p

		derive!
		B <- A (A B / p) q
		B <- A (A B q / pq)
		B <- A (A A (A B q / pq) q / pq)
		B <- A (A A (A B qq / pqq) / pq)
		B <- A (A A (A B qq / pqq / pq))
		B <- A+ (q+ / pq+)
		C <- A B / p
		C <- A A+

		A <- x (A A)** x A (A A)** x / x


    Term     < Factor (Add / Sub)*
    Add      < "+" Factor
    Sub      < "-" Factor
    Factor   < Primary (Mul / Div)*
    Mul      < "*" Primary
    Div      < "/" Primary
    Primary  < Parens / Neg / Number / Variable
    Parens   < :"(" Term :")"
    Neg      < "-" Primary
    Number   < ~([0-9]+)
    Variable <- identifier


		Term < (Primary (Mul / Div)*) (Add / Sub)*
		Term < (Primary (Mul / Div)*) ("+" Factor / "-" Factor)*
		Term < (Primary (Mul / Div)*) ("+" (Primary (Mul / Div)*) / "-" (Primary (Mul / Div)*))*
		Term < (Primary ("*" Primary / "/" Primary)*) ("+" (Primary ("*" Primary / "/" Primary)*) / "-" (Primary ("*" Primary / "/" Primary)*))*

		Primary  < Parens / Neg / Number / Variable
		Primary  < :"(" Term :")" / "-" Primary / ~([0-9]+) / identifier


		Term < ((Parens / Neg / Number / Variable) ("*" (Parens / Neg / Number / Variable) / "/" (Parens / Neg / Number / Variable))*) ("+" ((Parens / Neg / Number / Variable) ("*" (Parens / Neg / Number / Variable) / "/" (Parens / Neg / Number / Variable))*) / "-" ((Parens / Neg / Number / Variable) ("*" (Parens / Neg / Number / Variable) / "/" (Parens / Neg / Number / Variable))*))*
		Term < ((:"(" Term :")" / "-" Primary / Number / Variable) ("*" (Parens / Neg / Number / Variable) / "/" (Parens / Neg / Number / Variable))*) ("+" ((Parens / Neg / Number / Variable) ("*" (Parens / Neg / Number / Variable) / "/" (Parens / Neg / Number / Variable))*) / "-" ((Parens / Neg / Number / Variable) ("*" (Parens / Neg / Number / Variable) / "/" (Parens / Neg / Number / Variable))*))*


		Term < (Primary ("*" Primary / "/" Primary)*) ("+" (Primary ("*" Primary / "/" Primary)*) / "-" (Primary ("*" Primary / "/" Primary)*))*
		Primary  < :"(" Term :")" / "-" Primary / ~([0-9]+) / identifier



		rpeg <- "long expression #1" foo / "long expression #2" bar
		foo <- nontrivial "x"
		bar <- nontrivial "y"
		nontrivial <- "ooga booga"

		rpeg <- "long expression #1" foo / "long expression #2" bar
		foo <- "ooga booga" "x"
		bar <- "ooga booga" "y"

		q <- a{0,30} a{30}


		p** a == ???
		p** a == (p p** / e0) a == (p p** | ^(p p**)&e0) a == (p p** | e0) a ==
		  (p (p p** | e0) | e0) == ((p p p** | p) | e0) == (p p p** | p | e0) == ...

		p* == (p p* | e0)

		a** a == ???
		a** a == (a a** / e0) a == A <- a A / e0, B <- A a
		a* a == a+ (regular expressions)


		B <- A / 0 / 1 / e0
		A <- 0 B 0 / 1 B 1

		0110

		000010000
	}

	private Fragment assembleAnd( SList!Fragment operands )
	{

	}
+/



/+
	/** Returns the unoptimized automaton that is being built by this
	ParserBuilder object. */
	@property automaton

// Foo <- 'x' Bar?
// Bar <- ('ab'|'ac')|('q'+)|(Foo)
// (Bar) -> savedNfa3
builder.initialize();
builder.define!"Foo"();
	builder.push!"seq"();
		builder.operand('x');
		builder.push!("maybe");
			builder.call!("Bar");
		builder.pop();
	builder.pop();
builder.pop();
builder.define!"Bar"();
	builder.push!"or"();
		builder.operand(savedNfa1);
		builder.operand(savedNfa2);
		builder.call!("Foo");
	builder.pop();
builder.pop();
builder.call!("Bar"); // This bit defines the start/end points for the grammar.

auto savedNfa3 = builder.toNfa();

// Advanced stuff:
// ('ab'|'ac')&('q'+)
builder.initialize();
builder.push!("and");
	builder.operand(savedNfa1);
	builder.operand(savedNfa2);
builder.pop();
+/
