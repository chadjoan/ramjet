Ramjet
====

Ramjet is a library that generates very fast parsers from parsing expression
grammars (PEGs) and regular expressions.

Right now it is in development and not very usable.

Intended features and wishlist:
* Parsers will not allocate any more memory than they need to.
	* Parsers will not output a parse tree, but an event stream instead.
	* An event stream handler can be provided that converts the event stream
		into a parse tree with a generic structure.
	* This makes allocations of a parse tree optional, since callers are likely
		to output something more specific (like an AST, or perform computations
		that don't allocate memory at all).
	* Some internal memory allocation will be necessary:
		* Packrat parsers need to cache symbol match results somewhere
		* Error handling and symbol stack unwinding
* Parsers will attempt to parse input in O(n) time whenever possible
	* Packrat parsing for Parsing Expression Grammars
	* Some features (ex: regular expression backtracking) may exceed O(n),
		but parsers not using these features shouldn't have to pay for that.
* Enable regular expressions to be embedded within parsing expression grammars.
	* This should be possible to do efficiently (O(n) global time complexity)
		by constraining the types of matches that the regexes produce so that
		they are not sensitive to the success or failure of subsequent parsing
		constructs later in the input.
* Parsers amenable to parallel execution to improve throughput when thread
	pools are available.
* Parsers can be interrupted and return partial parse results before completely
	processing input and then resumed later.
	*  Of course, this will probably have caveats: Either
		* The partial match might not be accurate, because it needs to reach
			some terminal near the end of input to choose between multiple
			possible sequences of symbol entrance/exit events, or...
		* More likely, the partial match could cover a much shorter portion
			of text than what the parser has covered, because it will refuse
			to emit any events/matches that aren't 100% guaranteed to be
			correct if the rest of the input parses successfully.
* Parsers can be operated as online algorithms. That is, they should be able
	to take an indefinitely long stream of input and continuously parse it
	while emiting matches and exceptions.
	* This should be compatible with use of parallelism and thread pools.
	* The caller (and/or grammar author) may need to provide a means to "firm"
		past input so that the parser may release memory resources used for any
		packrat parsing or backtracking information related to the past input.
* To acheive continuous operation and interruptibility:
	* This library may introduce a "confidence" notation that allows grammar
		authors to pick symbols or conditions that indicate safe points to emit
		matches and results without needing to parse subsequent input.
	* As well, there may be some notation plus runtime configuration for
		"firming" previous matches when a symbol is reached or condition is met.
		For example: if there is a symbol stack `{A,B,C,X,Y,Z}` such that
		`A <- ... B ..., B <- ... C ..., C <- ... X ...`, and so on, then
		entrance into symbol *Y* might indicate an opportunity to free memory
		(or other resources) related to matches of symbol *B*
		(and contained matches) outside of the current symbol stack.
* Aspect-oriented features:
	* The ability to say, "Whichever symbols have the @whitespace attribute,
		match the 'whitespace' rule between any two adjacent grammar (PEG)
		elements."
	* Attributes should be able to control things like which symbols and
		matches are included in the output event stream, and which are
		parsed silently.
* Good error messages
	* Configurable delimiters (`{\n, \r, \r\n} == "newline"` by default) are
		always counted and the count returned in the error message. A parser
		should never return errors without line numbers unless the error is
		hopelessly non-locatable.
	* Column numbers
	* Allow use of rules/symbols for specifically matching common mistakes,
		so that the parser or caller can print humane explanations of what
		went wrong and how to fix it.
	* Ability to record multiple errors before halting.
	* Error recovery logic should be possible: when an error occurs, the parser
		should not just pee its pants and jump off a cliff, leaving the caller
		holding a urine-soaked exception and a trail of tears. Rather, the
		parser should remember where it encountered that error, and be
		prepared to backtrack and try again with slightly altered input,
		or to consider the error "non-critical" and insert placeholder
		symbols where needed to fill in for missing input (ex: like when
		you forget the semicolon at the end of a statement in a curly-braces
		language; it would be reasonable for the parser to "guess" that you
		intended to put a semicolon there and then continue parsing, after
		emiting a failure-level error, of course).
* Testing
	* Unittesting wherever possible
	* Accompanying test suite of grammars, along with typical inputs and
		expected outputs, including some failure modes.
* Ability to generate parsers in multiple programming languages; I envision
	prioritizing D, C, and Javascript, in that order. Later there could be
	support for other languages like C#, Java, Go, Rust, and so on. Without
	any monetary incentive, I might stick to implementing the ones that I
	need or strongly anticipate needing for other projects.
	* Caveat: some more advanced features like parallelism and continuous
		operation might not be available in all targeted languages, since
		these things would require additional implementation complexity
		specifically tailored to those languages. For instance, C might end
		up with parsers that are re-entrant and thread-safe, but any
		thread-pooling logic would be left for the caller to implement due
		to the large number of threading library possibilities in the C
		programming language (it might be hard to guess what the majority of
		users would want or expect).
* CTFE-friendly in the D programming language: it should be possible to
	generate and run parsers at compile-time, or to generate parsers at
	compile-time and then use `mixin(...);` statements to compile them into
	fast native machine code (and all without extra compilation passes in the
	caller's build scripts).

