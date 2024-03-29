/**
This module implements a singly-linked list container.
It can be used as a stack.

This module is a submodule of $(MREF std, container).

Source: $(PHOBOSSRC std/container/slist.d)

Copyright: 2010- Andrei Alexandrescu. All rights reserved by the respective holders.

License: Distributed under the Boost Software License, Version 1.0.
(See accompanying file LICENSE_1_0.txt or copy at $(HTTP
boost.org/LICENSE_1_0.txt)).

Authors: $(HTTP erdani.com, Andrei Alexandrescu)

$(SCRIPT inhibitQuickIndex = 1;)
*/
module ramjet.internal.slist;

///
@safe unittest
{
    import std.algorithm.comparison : equal;
    import std.container : SList;

    auto s = SList!int(1, 2, 3);
    assert(equal(s[], [1, 2, 3]));

    s.removeFront();
    assert(equal(s[], [2, 3]));

    s.insertFront([5, 6]);
    assert(equal(s[], [5, 6, 2, 3]));

    // If you want to apply range operations, simply slice it.
    import std.algorithm.searching : countUntil;
    import std.range : popFrontN, walkLength;

    auto sl = SList!int(1, 2, 3, 4, 5);
    assert(countUntil(sl[], 2) == 1);

    auto r = sl[];
    popFrontN(r, 2);
    assert(walkLength(r) == 3);
}

public import std.container.util;

/**
   Implements a simple and fast singly-linked list.
   It can be used as a stack.

   `SList` uses reference semantics.
 */
struct SList(T)
if (!is(T == shared))
{
    import std.exception : enforce;
    import std.range : Take;
    import std.range.primitives : isInputRange, isForwardRange, ElementType;
    import std.traits : isImplicitlyConvertible;

    private struct Node
    {
        Node*  _next;
        T      _payload;
    }

    private struct NodeWithoutPayload
    {
        Node* _next;
    }

    private NodeWithoutPayload* _root;

    private void initialize() @trusted nothrow pure
    {
        if (_root) return;
        _root = new NodeWithoutPayload();
    }

    private ref inout(Node*) _first() @property @safe nothrow pure inout
    {
        assert(_root);
        return _root._next;
    }

    mixin template defineFindNodeWithPredicate(string predicate)
    {
        @trusted Node** findNodeWithPredicate(Node** np)
        {
            if (np is null)
                return null;

            Node* n = *np;

            while(n !is null)
            {
                mixin("if ("~predicate~") return np;");
                np = &n._next;
                n  = *np;
            }

            return null;
        }
    }

    // Returns a pointer to the last node in the linked list.
    private static Node* findLastNode(Node** startAt)
    {
        assert(startAt);
        mixin defineFindNodeWithPredicate!("n._next is null");
        return *findNodeWithPredicate(startAt);
    }

    // Returns a pointer to the last node in the linked list, or a pointer to
    // the node reached after 'limit' nodes have been traversed, whichever
    // happens first.
    private static Node* findLastNode(Node** startAt, size_t limit)
    {
        assert(startAt && limit);
        mixin defineFindNodeWithPredicate!("n._next is null || !--limit");
        return *findNodeWithPredicate(startAt);
    }

    // Returns the address of the pointer to the same node pointed to by the
    // 'findMe' pointer. Returns null if none are found.
    private static Node** findNode(Node** startAt, Node* findMe)
    {
        assert(startAt);
        mixin defineFindNodeWithPredicate!("n is findMe");
        return findNodeWithPredicate(startAt);
    }

    // Returns the address of the pointer to the node that has a _payload
    // equivalent to 'value'. Returns null if none are found.
    private static Node** findNodeByValue(Node** startAt, T value)
    {
        mixin defineFindNodeWithPredicate!("n._payload == value");
        return findNodeWithPredicate(startAt);
    }

    private static size_t insertInto(Stuff)(ref Node* n, Stuff stuff)
    if (isImplicitlyConvertible!(Stuff, T))
    {
        import std.range : only;
        return insertInto(n, only(stuff));
    }
    
    /+
    // Useful for visualizing the list's internal state from a given node.
    private static @trusted void printNodes(Node* startAt)
    {
        import std.stdio;
        Node* printer = startAt;
        writef("%s", printer);
        while(printer)
        {
            writef("->[%s,\"%s\"]", printer._next, printer._payload);
            printer = printer._next;
        }
        writeln("");
    }
    +/

    private static @trusted size_t insertInto(Stuff)(ref Node* n, Stuff stuff)
    if (isInputRange!Stuff && isImplicitlyConvertible!(ElementType!Stuff, T))
    {
        size_t  nInsertions = 0;
        Node**  currentNode = &n;
        
        foreach (item; stuff)
        {
            auto newNode = new Node(*currentNode, item);
            *currentNode = newNode;
            currentNode = &newNode._next;
            nInsertions++;
        }

        return nInsertions;
    }

/**
Constructor taking a number of nodes
     */
    this(U)(U[] values...) if (isImplicitlyConvertible!(U, T))
    {
        insertFront(values);
    }

/**
Constructor taking an $(REF_ALTTEXT input range, isInputRange, std,range,primitives)
     */
    this(Stuff)(Stuff stuff)
    if (isInputRange!Stuff
            && isImplicitlyConvertible!(ElementType!Stuff, T)
            && !is(Stuff == T[]))
    {
        insertFront(stuff);
    }

/**
Comparison for equality.

Complexity: $(BIGOH min(n, n1)) where `n1` is the number of
elements in `rhs`.
     */
    bool opEquals(const SList rhs) const
    {
        return opEquals(rhs);
    }

    /// ditto
    bool opEquals(ref const SList rhs) const
    {
        if (_root is rhs._root) return true;
        if (_root is null) return rhs._root is null || rhs._first is null;
        if (rhs._root is null) return _root is null || _first is null;

        const(Node)* n1 = _first, n2 = rhs._first;

        for (;; n1 = n1._next, n2 = n2._next)
        {
            if (!n1) return !n2;
            if (!n2 || n1._payload != n2._payload) return false;
        }
    }

/**
Defines the container's primary range, which embodies a forward range.
     */
    struct Range
    {
        private Node * _head;
        private this(Node * p) { _head = p; }

        /// Input range primitives.
        @property bool empty() const { return !_head; }

        /// ditto
        @property ref T front()
        {
            assert(!empty, "SList.Range.front: Range is empty");
            return _head._payload;
        }

        /// ditto
        void popFront()
        {
            assert(!empty, "SList.Range.popFront: Range is empty");
            _head = _head._next;
        }

        /// Forward range primitive.
        @property Range save() { return this; }

        T moveFront()
        {
            import std.algorithm.mutation : move;

            assert(!empty, "SList.Range.moveFront: Range is empty");
            return move(_head._payload);
        }

        bool sameHead(Range rhs)
        {
            return _head && _head == rhs._head;
        }
    }

    @safe unittest
    {
        static assert(isForwardRange!Range);
    }

/**
Property returning `true` if and only if the container has no
elements.

Complexity: $(BIGOH 1)
     */
    @property bool empty() const
    {
        return _root is null || _first is null;
    }

/**
Duplicates the container. The elements themselves are not transitively
duplicated.

Complexity: $(BIGOH n).
     */
    @property SList dup()
    {
        return SList(this[]);
    }

/**
Returns a range that iterates over all elements of the container, in
forward order.

Complexity: $(BIGOH 1)
     */
    Range opSlice()
    {
        if (empty)
            return Range(null);
        else
            return Range(_first);
    }

/**
Forward to `opSlice().front`.

Complexity: $(BIGOH 1)
     */
    @property ref T front()
    {
        assert(!empty, "SList.front: List is empty");
        return _first._payload;
    }

    @safe unittest
    {
        auto s = SList!int(1, 2, 3);
        s.front = 42;
        assert(s == SList!int(42, 2, 3));
    }

/**
Returns a new `SList` that's the concatenation of `this` and its
argument. `opBinaryRight` is only defined if `Stuff` does not
define `opBinary`.
     */
    SList opBinary(string op, Stuff)(Stuff rhs)
    if (op == "~" && is(typeof(SList(rhs))))
    {
        import std.range : chain, only;

        static if (isInputRange!Stuff)
            alias r = rhs;
        else
            auto r = only(rhs);

        return SList(this[].chain(r));
    }

    /// ditto
    SList opBinaryRight(string op, Stuff)(Stuff lhs)
    if (op == "~" && !is(typeof(lhs.opBinary!"~"(this))) && is(typeof(SList(lhs))))
    {
        import std.range : chain, only;

        static if (isInputRange!Stuff)
            alias r = lhs;
        else
            auto r = only(lhs);

        return SList(r.chain(this[]));
    }

/**
Removes all contents from the `SList`.

Postcondition: `empty`

Complexity: $(BIGOH 1)
     */
    void clear()
    {
        // TODO: Is this really O(1)? It seems like we are just delegating
        // deallocation of memory resources to the garbage collector for it
        // to handle them at a later time. So this has an immediate O(1), but
        // long-term it has the cost of a mallocator.free (or similar) plus
        // part of the cost of a mark-and-sweep (or however the GC finds the
        // orphaned Node structs).
        //
        // Perhaps the caller should be able to determine the allocator used
        // (probably waiting on std.experimental.allocator to stabilize) and
        // then the manner of cleanup should depend on whether the allocator
        // requires explicit free(*) calls or not.
        //
        if (_root)
            _first = null;
    }

/**
Reverses SList in-place. Performs no memory allocation.

Complexity: $(BIGOH n)
     */
    void reverse()
    {
        if (!empty)
        {
            Node* prev;
            while (_first)
            {
                auto next = _first._next;
                _first._next = prev;
                prev = _first;
                _first = next;
            }
            _first = prev;
        }
    }

/**
Inserts `stuff` to the front of the container. `stuff` can be a
value convertible to `T` or a range of objects convertible to $(D
T). The stable version behaves the same, but guarantees that ranges
iterating over the container are never invalidated.

Returns: The number of elements inserted

Complexity: $(BIGOH m), where `m` is the length of `stuff`
     */
    size_t insertFront(Stuff)(Stuff stuff)
    if (isInputRange!Stuff || isImplicitlyConvertible!(Stuff, T))
    {
        initialize();
        return insertInto(_root._next, stuff);
    }

    /// ditto
    alias insert = insertFront;

    /// ditto
    alias stableInsert = insert;

    /// ditto
    alias stableInsertFront = insertFront;

/**
Picks one value in an unspecified position in the container, removes
it from the container, and returns it. The stable version behaves the same,
but guarantees that ranges iterating over the container are never invalidated.

Precondition: `!empty`

Returns: The element removed.

Complexity: $(BIGOH 1).
     */
    T removeAny()
    {
        import std.algorithm.mutation : move;

        assert(!empty, "SList.removeAny: List is empty");
        auto result = move(_first._payload);
        _first = _first._next;
        return result;
    }
    /// ditto
    alias stableRemoveAny = removeAny;

/**
Removes the value at the front of the container. The stable version
behaves the same, but guarantees that ranges iterating over the
container are never invalidated.

Precondition: `!empty`

Complexity: $(BIGOH 1).
     */
    void removeFront()
    {
        assert(!empty, "SList.removeFront: List is empty");
        _first = _first._next;
    }

    /// ditto
    alias stableRemoveFront = removeFront;

/**
Removes `howMany` values at the front or back of the
container. Unlike the unparameterized versions above, these functions
do not throw if they could not remove `howMany` elements. Instead,
if $(D howMany > n), all elements are removed. The returned value is
the effective number of elements removed. The stable version behaves
the same, but guarantees that ranges iterating over the container are
never invalidated.

Returns: The number of elements removed

Complexity: $(BIGOH howMany * log(n)).
     */
    size_t removeFront(size_t howMany)
    {
        size_t result;
        while (_first && result < howMany)
        {
            _first = _first._next;
            ++result;
        }
        return result;
    }

    /// ditto
    alias stableRemoveFront = removeFront;

/**
Inserts `stuff` after range `r`, which must be a range
previously extracted from this container. Given that all ranges for a
list end at the end of the list, this function essentially appends to
the list and uses `r` as a potentially fast way to reach the last
node in the list. Ideally `r` is positioned near or at the last
element of the list.

`stuff` can be a value convertible to `T` or a range of objects
convertible to `T`. The stable version behaves the same, but
guarantees that ranges iterating over the container are never
invalidated.

Returns: The number of values inserted.

Complexity: $(BIGOH k + m), where `k` is the number of elements in
`r` and `m` is the length of `stuff`.

Example:
--------------------
auto sl = SList!string(["a", "b", "d"]);
sl.insertAfter(sl[], "e"); // insert at the end (slowest)
assert(std.algorithm.equal(sl[], ["a", "b", "d", "e"]));
sl.insertAfter(std.range.take(sl[], 2), "c"); // insert after "b"
assert(std.algorithm.equal(sl[], ["a", "b", "c", "d", "e"]));
--------------------
     */

    size_t insertAfter(Stuff)(Range r, Stuff stuff)
    if (isInputRange!Stuff || isImplicitlyConvertible!(Stuff, T))
    {
        initialize();
        if (!_first)
        {
            enforce(!r._head);
            return insertFront(stuff);
        }
        enforce(r._head);
        Node* n = findLastNode(&r._head._next);
        return insertInto(n._next, stuff);
    }

/**
Similar to `insertAfter` above, but accepts a range bounded in
count. This is important for ensuring fast insertions in the middle of
the list.  For fast insertions after a specified position `r`, use
$(D insertAfter(take(r, 1), stuff)). The complexity of that operation
only depends on the number of elements in `stuff`.

Precondition: $(D r.original.empty || r.maxLength > 0)

Returns: The number of values inserted.

Complexity: $(BIGOH k + m), where `k` is the number of elements in
`r` and `m` is the length of `stuff`.
     */
    size_t insertAfter(Stuff)(Take!Range r, Stuff stuff)
    if (isInputRange!Stuff || isImplicitlyConvertible!(Stuff, T))
    {
        auto orig = r.source;
        if (!orig._head)
        {
            // Inserting after a null range counts as insertion to the
            // front
            return insertFront(stuff);
        }
        enforce(!r.empty);
        // Find the last valid element in the range
        foreach (i; 1 .. r.maxLength)
        {
            if (!orig._head._next) break;
            orig.popFront();
        }
        // insert here
        return insertInto(orig._head._next, stuff);
    }

/// ditto
    alias stableInsertAfter = insertAfter;

/**
Removes a range from the list in linear time.

Returns: An empty range.

Complexity: $(BIGOH n)
     */
    Range linearRemove(Range r)
    {
        if (!_first)
        {
            enforce(!r._head);
            return this[];
        }
        Node** n = findNode(&_root._next, r._head);
        *n = null;
        return Range(null);
    }

/**
Removes a `Take!Range` from the list in linear time.

Returns: A range comprehending the elements after the removed range.

Complexity: $(BIGOH n)
     */
    Range linearRemove(Take!Range r)
    {
        auto orig = r.source;
        // We have something to remove here
        if (orig._head == _first)
        {
            // remove straight from the head of the list
            for (; !r.empty; r.popFront())
            {
                removeFront();
            }
            return this[];
        }
        if (!r.maxLength)
        {
            // Nothing to remove, return the range itself
            return orig;
        }
        // Remove from somewhere in the middle of the list
        enforce(_first);
        Node** n1 = findNode(&_root._next, orig._head);
        Node*  n2 = findLastNode(&orig._head, r.maxLength);
        *n1 = n2._next;
        return Range(*n1);
    }

/// ditto
    alias stableLinearRemove = linearRemove;

/**
Removes the first occurence of an element from the list in linear time.

Returns: True if the element existed and was successfully removed, false otherwise.

Params:
    value = value of the node to be removed

Complexity: $(BIGOH n)
     */
    bool linearRemoveElement(T value)
    {
        Node** n = findNodeByValue(&_root._next, value);

        if (n && *n)
        {
            *n = (*n)._next;
            return true;
        }

        return false;
    }
}

@safe unittest
{
    import std.algorithm.comparison : equal;

    auto e = SList!int();
    auto b = e.linearRemoveElement(2);
    assert(b == false);
    assert(e.empty());
    auto a = SList!int(-1, 1, 2, 1, 3, 4);
    b = a.linearRemoveElement(1);
    assert(equal(a[], [-1, 2, 1, 3, 4]));
    assert(b == true);
    b = a.linearRemoveElement(-1);
    assert(b == true);
    assert(equal(a[], [2, 1, 3, 4]));
    b = a.linearRemoveElement(1);
    assert(b == true);
    assert(equal(a[], [2, 3, 4]));
    b = a.linearRemoveElement(2);
    assert(b == true);
    b = a.linearRemoveElement(20);
    assert(b == false);
    assert(equal(a[], [3, 4]));
    b = a.linearRemoveElement(4);
    assert(b == true);
    assert(equal(a[], [3]));
    b = a.linearRemoveElement(3);
    assert(b == true);
    assert(a.empty());
    a.linearRemoveElement(3);
}

@safe unittest
{
    import std.algorithm.comparison : equal;

    auto a = SList!int(5);
    auto b = a;
    auto r = a[];
    a.insertFront(1);
    b.insertFront(2);
    assert(equal(a[], [2, 1, 5]));
    assert(equal(b[], [2, 1, 5]));
    r.front = 9;
    assert(equal(a[], [2, 1, 9]));
    assert(equal(b[], [2, 1, 9]));
}

@safe unittest
{
    auto s = SList!int(1, 2, 3);
    auto n = s.findLastNode(&s._root._next);
    assert(n && n._payload == 3);
}

@safe unittest
{
    import std.range.primitives;
    auto s = SList!int(1, 2, 5, 10);
    assert(walkLength(s[]) == 4);
}

@safe unittest
{
    import std.range : take;
    auto src = take([0, 1, 2, 3], 3);
    auto s = SList!int(src);
    assert(s == SList!int(0, 1, 2));
}

@safe unittest
{
    auto a = SList!int();
    auto b = SList!int();
    auto c = a ~ b[];
    assert(c.empty);
}

@safe unittest
{
    auto a = SList!int(1, 2, 3);
    auto b = SList!int(4, 5, 6);
    auto c = a ~ b[];
    assert(c == SList!int(1, 2, 3, 4, 5, 6));
}

@safe unittest
{
    auto a = SList!int(1, 2, 3);
    auto b = [4, 5, 6];
    auto c = a ~ b;
    assert(c == SList!int(1, 2, 3, 4, 5, 6));
}

@safe unittest
{
    auto a = SList!int(1, 2, 3);
    auto c = a ~ 4;
    assert(c == SList!int(1, 2, 3, 4));
}

@safe unittest
{
    auto a = SList!int(2, 3, 4);
    auto b = 1 ~ a;
    assert(b == SList!int(1, 2, 3, 4));
}

@safe unittest
{
    auto a = [1, 2, 3];
    auto b = SList!int(4, 5, 6);
    auto c = a ~ b;
    assert(c == SList!int(1, 2, 3, 4, 5, 6));
}

@safe unittest
{
    auto s = SList!int(1, 2, 3, 4);
    s.insertFront([ 42, 43 ]);
    assert(s == SList!int(42, 43, 1, 2, 3, 4));
}

@safe unittest
{
    auto s = SList!int(1, 2, 3);
    assert(s.removeAny() == 1);
    assert(s == SList!int(2, 3));
    assert(s.stableRemoveAny() == 2);
    assert(s == SList!int(3));
}

@safe unittest
{
    import std.algorithm.comparison : equal;

    auto s = SList!int(1, 2, 3);
    s.removeFront();
    assert(equal(s[], [2, 3]));
    s.stableRemoveFront();
    assert(equal(s[], [3]));
}

@safe unittest
{
    auto s = SList!int(1, 2, 3, 4, 5, 6, 7);
    assert(s.removeFront(3) == 3);
    assert(s == SList!int(4, 5, 6, 7));
}

@safe unittest
{
    auto a = SList!int(1, 2, 3);
    auto b = SList!int(1, 2, 3);
    assert(a.insertAfter(a[], b[]) == 3);
}

@safe unittest
{
    import std.range : take;
    auto s = SList!int(1, 2, 3, 4);
    auto r = take(s[], 2);
    assert(s.insertAfter(r, 5) == 1);
    assert(s == SList!int(1, 2, 5, 3, 4));
}

@safe unittest
{
    import std.algorithm.comparison : equal;
    import std.range : take;

    // insertAfter documentation example
    auto sl = SList!string(["a", "b", "d"]);
    sl.insertAfter(sl[], "e"); // insert at the end (slowest)
    assert(equal(sl[], ["a", "b", "d", "e"]));
    sl.insertAfter(take(sl[], 2), "c"); // insert after "b"
    assert(equal(sl[], ["a", "b", "c", "d", "e"]));
}

@safe unittest
{
    import std.range.primitives;
    auto s = SList!int(1, 2, 3, 4, 5);
    auto r = s[];
    popFrontN(r, 3);
    auto r1 = s.linearRemove(r);
    assert(s == SList!int(1, 2, 3));
    assert(r1.empty);
}

@safe unittest
{
    auto s = SList!int(1, 2, 3, 4, 5);
    auto r = s[];
    auto r1 = s.linearRemove(r);
    assert(s == SList!int());
    assert(r1.empty);
}

@safe unittest
{
    import std.algorithm.comparison : equal;
    import std.range;

    auto s = SList!int(1, 2, 3, 4, 5, 6, 7, 8, 9, 10);
    auto r = s[];
    popFrontN(r, 3);
    auto r1 = take(r, 4);
    assert(equal(r1, [4, 5, 6, 7]));
    auto r2 = s.linearRemove(r1);
    assert(s == SList!int(1, 2, 3, 8, 9, 10));
    assert(equal(r2, [8, 9, 10]));
}

@safe unittest
{
    import std.range.primitives;
    auto lst = SList!int(1, 5, 42, 9);
    assert(!lst.empty);
    assert(lst.front == 1);
    assert(walkLength(lst[]) == 4);

    auto lst2 = lst ~ [ 1, 2, 3 ];
    assert(walkLength(lst2[]) == 7);

    auto lst3 = lst ~ [ 7 ];
    assert(walkLength(lst3[]) == 5);
}

@safe unittest
{
    auto s = make!(SList!int)(1, 2, 3);
}

@safe unittest
{
    // 5193
    static struct Data
    {
        const int val;
    }
    SList!Data list;
}

@safe unittest
{
    auto s = SList!int([1, 2, 3]);
    s.front = 5; //test frontAssign
    assert(s.front == 5);
    auto r = s[];
    r.front = 1; //test frontAssign
    assert(r.front == 1);
}

@safe unittest
{
    // issue 14920
    SList!int s;
    s.insertAfter(s[], 1);
    assert(s.front == 1);
}

@safe unittest
{
    // issue 15659
    SList!int s;
    s.clear();
}

@safe unittest
{
    SList!int s;
    s.reverse();
}

@safe unittest
{
    import std.algorithm.comparison : equal;

    auto s = SList!int([1, 2, 3]);
    assert(s[].equal([1, 2, 3]));

    s.reverse();
    assert(s[].equal([3, 2, 1]));
}

@safe unittest
{
    auto s = SList!int([4, 6, 8, 12, 16]);
    auto d = s.dup;
    assert(d !is s);
    assert(d == s);
}
