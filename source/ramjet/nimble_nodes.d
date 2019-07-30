/+
// This module is mostly just design notes for now.
// The idea is to create a decent default parse tree / AST representation
// that ramjet can use for itself to represent its own grammar and perform
// lowerings before finally converting the tree representation into NFA/DFA/packrat
// things.

enum Arity : int
{
	nullary  = 0,
	unary    = 1,
	binary   = 2,
	ternary  = 3,
	variable = -1,
}

enum ParentArity : int
{
	nullary  = Arity.nullary,
	unary    = Arity.unary,
	binary   = Arity.binary,
	ternary  = Arity.ternary,
	variable = Arity.variable,
}

enum ChildArity : int
{
	nullary  = Arity.nullary,
	unary    = Arity.unary,
	binary   = Arity.binary,
	ternary  = Arity.ternary,
	variable = Arity.variable,
}


string generateGrammarGraphCode(MyNodeMeta)(string name)
{
	auto graphDef = new GraphDefiner!MyNodeMeta(name, ChildArity.nullary, ParentArity.unary);

	graphDef.defineAbstractNodeT("GrammarNode");
	graphDef.defineAbstractNodeT("GrammarLeaf",  "GrammarNode");
	graphDef.defineAbstractNodeT("GrammarParent","GrammarNode");
	graphDef.defineFinalNodeT("Sequence",      "GrammarParent", ChildArity.unary);
	graphDef.defineFinalNodeT("Epsilon",       "GrammarLeaf",   ChildArity.nullary);
	graphDef.defineFinalNodeT("Literal",       "GrammarLeaf",   ChildArity.nullary);
	graphDef.defineFinalNodeT("OrderedChoice", "GrammarParent", ChildArity.binary);
	graphDef.defineFinalNodeT("Maybe",         "GrammarParent", ChildArity.unary);
	graphDef.defineFinalNodeT("PosLookAhead",  "GrammarParent", ChildArity.unary);
	graphDef.defineFinalNodeT("NegLookAhead",  "GrammarParent", ChildArity.unary);
	... etc ...

	return graphDef.toDCode();
}

mixin(generateGrammarGraphCode!MyNodeMeta("RamjetGrammarNodes"));

auto pool = RamjetGrammarNodes.newPool();

auto root     = pool.createRoot!"Sequence";
auto chooseAB = pool.withParent(root).insertNew!"OrderedChoice";
auto choiceA  = pool.withParent(chooseAB).insertNew!"Literal"("A");
auto choiceB  = pool.withParent(chooseAB).insertNew!"Literal"("B");

assert(root.id == RamjetGrammarNodes.typeIds.Sequence);
assert(root.id.isA(RamjetGrammarNodes.typeIds.GrammarParent));
assert(root.id.isA(RamjetGrammarNodes.typeIds.GrammarNode));
assert(!root.id.isA(RamjetGrammarNodes.typeIds.GrammarLeaf));

// Creates a (possibly const/immutable) memory-optimized chunk of memory for
// these nodes. Might not be immediate; the pool might wait for a number of firm
// nodes before actually allocating regions of memory. Though the root's firming
// implies that EVERYTHING is firm in that tree, so this particular invocation
// should immediately shuffle things into place.
pool.firm(root);

+/
