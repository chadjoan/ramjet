
import std.range.primitives : ElementType;

template Automata(RangeT, ElementT = ElementType!RangeT)
{
	// TODO: Handle unicode grapheme equivalence correctly.

	// To model some finite automata like so:
	//
	//  .---- a -----.
	//  v            |
	// {1} -- a --> (2) -- a --> ((3))
	//               |             ^
	//               '---- b ------'
	//
	// (With {n} indicating a start state, (n) indicating an intermediate state,
	// and ((n)) indicating a completion and match success state.)
	//
	// We create a table of relationships between transitions (graph edges) and
	// states (graph nodes):
	//
	// /---------+---------------+-------+
	// | fromID  |  transitionOn | toID  |
    // +---------+---------------+-------+
    // |   [1]   |      [a]      |  [2]  |
    // |   [2]   |      [a]      |  [1]  |
    // |   [2]   |     [a,b]     |  [3]  |
    // +---------+---------------+-------/
    //
    // Our objective is to end up with a Deterministic Finite Automata (DFA)
    // with a table like so:
    //
	// /---------+---------------+-------+
	// | fromID  |  transitionOn | toID  |
    // +---------+---------------+-------+
    // |   [1]   |      [a]      |  [2]  |
    // |   [2]   |     [a,b]     | [1,3] |
    // |  [1,3]  |      [a]      |  [2]  |
    // +---------+---------------+-------/
    //
    // Whose visual representation by graph looks like this:
    //
    //               .------ a -----.
    //               v              |
    // {1} -- a --> (2) -- a --> ((1,3))
    //               |              ^
    //               '---- b -------'
    //
    // To accomplish this, we will repeat the following operations, one after
    // another until there are no more duplicate IDs in the fromID column:
    //
    //    (1) For all rows with duplicate IDs:
    //        (a) Concatenate and sort+dedup their transitionOn values.
    //        (b) Iterate over each transitionOn element, concatenate (and
    //              sort+dedup) the toIDs that are associated with that
    //              transition to create a new toID value.
    //        (c) If there are multiple transitions that lead to exactly the
    //              same toID, then concatenate those together into a new
    //              transitionOn value.
    //        (d) Insert the new transitionOn values along with their
    //              corrseponding new toID values into new rows having the
    //              originally selected fromID value.
    //        (NOTE: This might actually just be a matrix transposition, which
    //        would make any sorting steps unnecessary, at least if they aren't
    //        required for the matrix construction.)
    //
   	//        /---------+---------------+-------+
	//        | fromID  |  transitionOn | toID  |
    //        +---------+---------------+-------+
    //        |   [1]   |      [a]      |  [2]  |
    //        |...[2]...|......[a]......|..[1]..| <- Deleted row; redundant with new row
    //        |...[2]...|.....[a,b].....|..[3]..| <- Deleted row; redundant with new row
    //        |   [2]   |      [a]      | [1,3] | <- New row; Along [a]: [1]~[3] -> [1,3]
    //        |   [2]   |      [b]      |  [3]  | <- New row; Along [b]: []~[3] -> [3]
    //        +---------+---------------+-------/
    //
    //    a  b
    // 1  x
    // 3  x  x
    //
    //    1  3
    // a  x  x
    // b     x
    //
    //    (2) Insert new rows having the fromIDs derived from the toID values
    //        created in step 1. To obtain the transitionOn and toID values
    //        for each of these new rows, repeat the substeps of step 1 using
    //        the transitionOn and toID values of all rows with fromIDs
    //        appearing in the new fromID.
    //
   	//        /---------+---------------+-------+
	//        | fromID  |  transitionOn | toID  |
    //        +---------+---------------+-------+
    //        |   [1]   |      [a]      |  [2]  |
    //        |   [2]   |      [a]      | [1,3] |
    //        |   [2]   |      [b]      |  [3]  |
    //        |  [1,3]  |      [a]      |  [2]  | <- New row; [a]~[] -> [a]; [2]~[]-> [2]
    //        +---------+---------------+-------/
    //
    //    (3) Remove any rows whose fromID value (the entire array) does not
    //        exactly match a value in the toID column.
    //
   	//        /---------+---------------+-------+
	//        | fromID  |  transitionOn | toID  |
    //        +---------+---------------+-------+
    //        |   [1]   |      [a]      |  [2]  |
    //        |   [2]   |     [a,b]     | [1,3] |  (No changes in this example.)
    //        |  [1,3]  |      [a]      |  [2]  |
    //        +---------+---------------+-------/
    //
    //    * All tuples/arrays in the cells of the table should be in some
    //    normalized (ex: sorted) form to make it easier to compare them and
    //    fast to index and retrieve them.
    //    TODO: (Is the following necessary?) When inserting arrays into arrays,
    //    as might be necessary on 2nd iteration and beyond, do not flatten --
    //    step 2 will need to know where to find the original fromIDs. (or maybe
    //    it only needs to look back one step, and that information still exists
    //    at that point in time)
    //
    //
    // To see how this handles exponential explosion of DFA states, here is how
    // the process works on the (a|b)*b(a|b)(a|b)(a|b) language
    // (This scenario is given in the Wikipedia article on Powerset Construction,
    // with a graphic for this language's automata at
    // https://en.wikipedia.org/wiki/Powerset_construction#/media/File:NFA_and_blown-up_equivalent_DFA_01.svg) :
    //
    //   .-- a|b --.
    //   v         |  
    //  {1} -------'      .- a --.  .- a --.  .- a --.
    //   |               /       v /       v /       v
    //   '---- b ----> (2)       (3)       (4)     ((5))
    //                   \       ^ \       ^ \       ^
    //                    '- b --'  '- b --'  '- b --'
    //
    //
    // Start
	//   /---------+---------------+-------+
	//   | fromID  |  transitionOn | toID  |
    //   +---------+---------------+-------+
    //   |   [1]   |     [a,b]     |  [1]  |
    //   |   [1]   |      [b]      |  [2]  |
    //   |   [2]   |     [a,b]     |  [3]  |
    //   |   [3]   |     [a,b]     |  [4]  |
    //   |   [4]   |     [a,b]     |  [5]  |
    //   +---------+---------------+-------/
    //
    // Apply rule #1
	//   /---------+---------------+-------+
	//   | fromID  |  transitionOn | toID  |
    //   +---------+---------------+-------+
    //   |...[1]...|.....[a,b].....|..[1]..| <- Deleted
    //   |...[1]...|......[b]......|..[2]..| <- Deleted
    //   |   [1]   |      [a]      |  [1]  | <- New row; Along [a]: [1]~[] -> [1]
    //   |   [1]   |      [b]      | [1,2] | <- New row; Along [b]: [1]~[2] -> [1,2]
    //   |   [2]   |     [a,b]     |  [3]  |
    //   |   [3]   |     [a,b]     |  [4]  |
    //   |   [4]   |     [a,b]     |  [5]  |
    //   +---------+---------------+-------/
	//
	// Apply rule #2
	//   /---------+---------------+-------+
	//   | fromID  |  transitionOn | toID  |
    //   +---------+---------------+-------+
    //   |   [1]   |      [a]      |  [1]  |
    //   |   [1]   |      [b]      | [1,2] |
    //   |  [1,2]  |      [a]      | [1,3] | <- New row; Along [a]: [1]~[]~[3]  -> [1,3]
    //   |  [1,2]  |      [b]      |[1,2,3]| <- New row; Along [b]: []~[1,2]~[3] -> [1,2,3]
    //   |   [2]   |     [a,b]     |  [3]  |
    //   |   [3]   |     [a,b]     |  [4]  |
    //   |   [4]   |     [a,b]     |  [5]  |
    //   +---------+---------------+-------/
    //
    // Apply rule #3 (no change) TODO: This should delete state #2, but do we want that?
    //
    // Apply rule #1 (no change)
    //
    // Apply rule #2
	//   /---------+---------------+---------+
	//   | fromID  |  transitionOn |  toID   |
    //   +---------+---------------+---------+
    //   |   [1]   |      [a]      |   [1]   |
    //   |   [1]   |      [b]      |  [1,2]  |
    //   |  [1,2]  |      [a]      |  [1,3]  |
    //   |  [1,2]  |      [b]      | [1,2,3] |
    //   |  [1,3]  |      [a]      |  [1,4]  | <- New row; Along [a]: [1]~[]~[4] -> [1,4]
    //   |  [1,3]  |      [b]      | [1,2,4] | <- New row; Along [b]: []~[1,2]~[4] -> [1,2,4]
    //   | [1,2,3] |      [a]      | [1,3,4] | <- New row; Along [a]: [1]~[]~[3]~[4] -> [1,3,4]
    //   | [1,2,3] |      [b]      |[1,2,3,4]| <- New row; Along [b]: []~[1,2]~[3]~[4] -> [1,2,3,4]
    //   |   [2]   |     [a,b]     |   [3]   |
    //   |   [3]   |     [a,b]     |   [4]   |
    //   |   [4]   |     [a,b]     |   [5]   |
    //   +---------+---------------+---------/
    //
    // Apply rule #3, #1, no change
    //
    // Apply rule #2
	//   /---------+---------------+-----------+
	//   | fromID  |  transitionOn |   toID    |
    //   +---------+---------------+-----------+
    //   |   [1]   |      [a]      |    [1]    |
    //   |   [1]   |      [b]      |   [1,2]   |
    //   |  [1,2]  |      [a]      |   [1,3]   |
    //   |  [1,2]  |      [b]      |  [1,2,3]  |
    //   |  [1,3]  |      [a]      |   [1,4]   |
    //   |  [1,3]  |      [b]      |  [1,2,4]  |
    //   | [1,2,3] |      [a]      |  [1,3,4]  |
    //   | [1,2,3] |      [b]      | [1,2,3,4] |
    //   |  [1,4]  |      [a]      |   [1,5]   | <- New row; Along [a]: [1]~[]~[5] -> [1,5]
    //   |  [1,4]  |      [b]      |  [1,2,5]  | <- New row; Along [b]: []~[1,2]~[5] -> [1,2,5]
    //   | [1,2,4] |      [a]      |  [1,3,5]  | <- New row; Along [a]: [1]~[]~[3]~[5] -> [1,3,5]
    //   | [1,2,4] |      [b]      | [1,2,3,5] | <- New row; Along [b]: []~[1,2]~[3]~[5] -> [1,2,3,5]
    //   | [1,3,4] |      [a]      |  [1,4,5]  | <- New row; Along [a]: [1]~[]~[4]~[5] -> [1,4,5]
    //   | [1,3,4] |      [b]      | [1,2,4,5] | <- New row; Along [b]: []~[1,2]~[4]~[5] -> [1,2,4,5]
    //   |[1,2,3,4]|      [a]      | [1,3,4,5] | <- New row; Along [a]: [1]~[]~[3]~[4]~[5] -> [1,3,4,5]
    //   |[1,2,3,4]|      [b]      |[1,2,3,4,5]| <- New row; Along [b]: []~[1,2]~[3]~[4]~[5] -> [1,2,3,4,5]
    //   |   [2]   |     [a,b]     |    [3]    |
    //   |   [3]   |     [a,b]     |    [4]    |
    //   |   [4]   |     [a,b]     |    [5]    |
    //   +---------+---------------+-----------/
    //
    //  ...
    //
    // Apply rule #2
	//   /-----------+---------------+-----------+
	//   |  fromID   |  transitionOn |   toID    |
    //   +-----------+---------------+-----------+
    //   |    [1]    |      [a]      |    [1]    |
    //   |    [1]    |      [b]      |   [1,2]   |
    //   |   [1,2]   |      [a]      |   [1,3]   |
    //   |   [1,2]   |      [b]      |  [1,2,3]  |
    //   |   [1,3]   |      [a]      |   [1,4]   |
    //   |   [1,3]   |      [b]      |  [1,2,4]  |
    //   |  [1,2,3]  |      [a]      |  [1,3,4]  |
    //   |  [1,2,3]  |      [b]      | [1,2,3,4] |
    //   |   [1,4]   |      [a]      |   [1,5]   |
    //   |   [1,4]   |      [b]      |  [1,2,5]  |
    //   |  [1,2,4]  |      [a]      |  [1,3,5]  |
    //   |  [1,2,4]  |      [b]      | [1,2,3,5] |
    //   |  [1,3,4]  |      [a]      |  [1,4,5]  |
    //   |  [1,3,4]  |      [b]      | [1,2,4,5] |
    //   | [1,2,3,4] |      [a]      | [1,3,4,5] |
    //   | [1,2,3,4] |      [b]      |[1,2,3,4,5]|
    //   |   [1,5]   |      [a]      |    [1]    | <- New row; Along [a]: [1]~[]~[] -> [1]
    //   |   [1,5]   |      [b]      |   [1,2]   | <- New row; Along [b]: []~[1,2]~[] -> [1,2]
    //   |  [1,2,5]  |      [a]      |   [1,3]   | <- New row; Along [a]: [1]~[]~[3]~[] -> [1,3]
    //   |  [1,2,5]  |      [b]      |  [1,2,3]  | <- New row; Along [b]: []~[1,2]~[3]~[] -> [1,2,3]
    //   |  [1,3,5]  |      [a]      |   [1,4]   | <- New row; Along [a]: [1]~[]~[4]~[] -> [1,4]
    //   |  [1,3,5]  |      [b]      |  [1,2,4]  | <- New row; Along [b]: []~[1,2]~[4]~[] -> [1,2,4]
    //   | [1,2,3,5] |      [a]      |  [1,3,4]  | <- New row; Along [a]: [1]~[]~[3]~[4]~[] -> [1,3,4]
    //   | [1,2,3,5] |      [b]      | [1,2,3,4] | <- New row; Along [b]: []~[1,2]~[3]~[4]~[] -> [1,2,3,4]
    //   |  [1,4,5]  |      [a]      |   [1,5]   | <- New row; Along [a]: [1]~[]~[5]~[] -> [1,5]
    //   |  [1,4,5]  |      [b]      |  [1,2,5]  | <- New row; Along [b]: []~[1,2]~[5]~[] -> [1,2,5]
    //   | [1,2,4,5] |      [a]      |  [1,3,5]  | <- New row; Along [a]: [1]~[]~[3]~[5]~[] -> [1,3,5]
    //   | [1,2,4,5] |      [b]      | [1,2,3,5] | <- New row; Along [b]: []~[1,2]~[3]~[5]~[] -> [1,2,3,5]
    //   | [1,3,4,5] |      [a]      |  [1,4,5]  | <- New row; Along [a]: [1]~[]~[4]~[5]~[] -> [1,4,5]
    //   | [1,3,4,5] |      [b]      | [1,2,4,5] | <- New row; Along [b]: []~[1,2]~[4]~[5]~[] -> [1,2,4,5]
    //   |[1,2,3,4,5]|      [a]      | [1,3,4,5] | <- New row; Along [a]: [1]~[]~[3]~[4]~[5]~[] -> [1,3,4,5]
    //   |[1,2,3,4,5]|      [b]      |[1,2,3,4,5]| <- New row; Along [b]: []~[1,2]~[3]~[4]~[5]~[] -> [1,2,3,4,5]
    //   |    [2]    |     [a,b]     |    [3]    |
    //   |    [3]    |     [a,b]     |    [4]    |
    //   |    [4]    |     [a,b]     |    [5]    |
    //   +-----------+---------------+-----------/
    //
    // Apply rule #3
	//   /-----------+---------------+-----------+
	//   |  fromID   |  transitionOn |   toID    |
    //   +-----------+---------------+-----------+
    //   |    [1]    |      [a]      |    [1]    |
    //   |    [1]    |      [b]      |   [1,2]   |
    //   |   [1,2]   |      [a]      |   [1,3]   |
    //   |   [1,2]   |      [b]      |  [1,2,3]  |
    //   |   [1,3]   |      [a]      |   [1,4]   |
    //   |   [1,3]   |      [b]      |  [1,2,4]  |
    //   |  [1,2,3]  |      [a]      |  [1,3,4]  |
    //   |  [1,2,3]  |      [b]      | [1,2,3,4] |
    //   |   [1,4]   |      [a]      |   [1,5]   |
    //   |   [1,4]   |      [b]      |  [1,2,5]  |
    //   |  [1,2,4]  |      [a]      |  [1,3,5]  |
    //   |  [1,2,4]  |      [b]      | [1,2,3,5] |
    //   |  [1,3,4]  |      [a]      |  [1,4,5]  |
    //   |  [1,3,4]  |      [b]      | [1,2,4,5] |
    //   | [1,2,3,4] |      [a]      | [1,3,4,5] |
    //   | [1,2,3,4] |      [b]      |[1,2,3,4,5]|
    //   |   [1,5]   |      [a]      |    [1]    |
    //   |   [1,5]   |      [b]      |   [1,2]   |
    //   |  [1,2,5]  |      [a]      |   [1,3]   |
    //   |  [1,2,5]  |      [b]      |  [1,2,3]  |
    //   |  [1,3,5]  |      [a]      |   [1,4]   |
    //   |  [1,3,5]  |      [b]      |  [1,2,4]  |
    //   | [1,2,3,5] |      [a]      |  [1,3,4]  |
    //   | [1,2,3,5] |      [b]      | [1,2,3,4] |
    //   |  [1,4,5]  |      [a]      |   [1,5]   |
    //   |  [1,4,5]  |      [b]      |  [1,2,5]  |
    //   | [1,2,4,5] |      [a]      |  [1,3,5]  |
    //   | [1,2,4,5] |      [b]      | [1,2,3,5] |
    //   | [1,3,4,5] |      [a]      |  [1,4,5]  |
    //   | [1,3,4,5] |      [b]      | [1,2,4,5] |
    //   |[1,2,3,4,5]|      [a]      | [1,3,4,5] |
    //   |[1,2,3,4,5]|      [b]      |[1,2,3,4,5]|
    //   |....[2]....|.....[a,b].....|....[3]....| <- Deleted row; no toIDs of [2] exist
    //   |    [3]    |     [a,b]     |    [4]    |
    //   |    [4]    |     [a,b]     |    [5]    |
    //   +-----------+---------------+-----------/
    //
    // ...
    //
    // Apply rule #3
	//   /-----------+---------------+-----------+
	//   |  fromID   |  transitionOn |   toID    |
    //   +-----------+---------------+-----------+
    //   |    [1]    |      [a]      |    [1]    |
    //   |    [1]    |      [b]      |   [1,2]   |
    //   |   [1,2]   |      [a]      |   [1,3]   |
    //   |   [1,2]   |      [b]      |  [1,2,3]  |
    //   |   [1,3]   |      [a]      |   [1,4]   |
    //   |   [1,3]   |      [b]      |  [1,2,4]  |
    //   |  [1,2,3]  |      [a]      |  [1,3,4]  |
    //   |  [1,2,3]  |      [b]      | [1,2,3,4] |
    //   |   [1,4]   |      [a]      |   [1,5]   |
    //   |   [1,4]   |      [b]      |  [1,2,5]  |
    //   |  [1,2,4]  |      [a]      |  [1,3,5]  |
    //   |  [1,2,4]  |      [b]      | [1,2,3,5] |
    //   |  [1,3,4]  |      [a]      |  [1,4,5]  |
    //   |  [1,3,4]  |      [b]      | [1,2,4,5] |
    //   | [1,2,3,4] |      [a]      | [1,3,4,5] |
    //   | [1,2,3,4] |      [b]      |[1,2,3,4,5]|
    //   |   [1,5]   |      [a]      |    [1]    |
    //   |   [1,5]   |      [b]      |   [1,2]   |
    //   |  [1,2,5]  |      [a]      |   [1,3]   |
    //   |  [1,2,5]  |      [b]      |  [1,2,3]  |
    //   |  [1,3,5]  |      [a]      |   [1,4]   |
    //   |  [1,3,5]  |      [b]      |  [1,2,4]  |
    //   | [1,2,3,5] |      [a]      |  [1,3,4]  |
    //   | [1,2,3,5] |      [b]      | [1,2,3,4] |
    //   |  [1,4,5]  |      [a]      |   [1,5]   |
    //   |  [1,4,5]  |      [b]      |  [1,2,5]  |
    //   | [1,2,4,5] |      [a]      |  [1,3,5]  |
    //   | [1,2,4,5] |      [b]      | [1,2,3,5] |
    //   | [1,3,4,5] |      [a]      |  [1,4,5]  |
    //   | [1,3,4,5] |      [b]      | [1,2,4,5] |
    //   |[1,2,3,4,5]|      [a]      | [1,3,4,5] |
    //   |[1,2,3,4,5]|      [b]      |[1,2,3,4,5]|
    //   |....[3]....|.....[a,b].....|....[4]....| <- Deleted row; no toIDs of [3] exist
    //   |    [4]    |     [a,b]     |    [5]    |
    //   +-----------+---------------+-----------/
    //
    // ...
    //
    // Apply rule #3
	//   /-----------+---------------+-----------+
	//   |  fromID   |  transitionOn |   toID    |
    //   +-----------+---------------+-----------+
    //   |    [1]    |      [a]      |    [1]    |
    //   |    [1]    |      [b]      |   [1,2]   |
    //   |   [1,2]   |      [a]      |   [1,3]   |
    //   |   [1,2]   |      [b]      |  [1,2,3]  |
    //   |   [1,3]   |      [a]      |   [1,4]   |
    //   |   [1,3]   |      [b]      |  [1,2,4]  |
    //   |  [1,2,3]  |      [a]      |  [1,3,4]  |
    //   |  [1,2,3]  |      [b]      | [1,2,3,4] |
    //   |   [1,4]   |      [a]      |   [1,5]   |
    //   |   [1,4]   |      [b]      |  [1,2,5]  |
    //   |  [1,2,4]  |      [a]      |  [1,3,5]  |
    //   |  [1,2,4]  |      [b]      | [1,2,3,5] |
    //   |  [1,3,4]  |      [a]      |  [1,4,5]  |
    //   |  [1,3,4]  |      [b]      | [1,2,4,5] |
    //   | [1,2,3,4] |      [a]      | [1,3,4,5] |
    //   | [1,2,3,4] |      [b]      |[1,2,3,4,5]|
    //   |   [1,5]   |      [a]      |    [1]    |
    //   |   [1,5]   |      [b]      |   [1,2]   |
    //   |  [1,2,5]  |      [a]      |   [1,3]   |
    //   |  [1,2,5]  |      [b]      |  [1,2,3]  |
    //   |  [1,3,5]  |      [a]      |   [1,4]   |
    //   |  [1,3,5]  |      [b]      |  [1,2,4]  |
    //   | [1,2,3,5] |      [a]      |  [1,3,4]  |
    //   | [1,2,3,5] |      [b]      | [1,2,3,4] |
    //   |  [1,4,5]  |      [a]      |   [1,5]   |
    //   |  [1,4,5]  |      [b]      |  [1,2,5]  |
    //   | [1,2,4,5] |      [a]      |  [1,3,5]  |
    //   | [1,2,4,5] |      [b]      | [1,2,3,5] |
    //   | [1,3,4,5] |      [a]      |  [1,4,5]  |
    //   | [1,3,4,5] |      [b]      | [1,2,4,5] |
    //   |[1,2,3,4,5]|      [a]      | [1,3,4,5] |
    //   |[1,2,3,4,5]|      [b]      |[1,2,3,4,5]|
    //   |....[4]....|.....[a,b].....|....[5]....| <- Deleted row; no toIDs of [4] exist
    //   +-----------+---------------+-----------/
	//
    // ...
    //
    // Done
	//   /-----------+---------------+-----------+
	//   |  fromID   |  transitionOn |   toID    |
    //   +-----------+---------------+-----------+
    //1  |    [1]    |      [a]      |    [1]    |
    //2  |    [1]    |      [b]      |   [1,2]   |
    //3  |   [1,2]   |      [a]      |   [1,3]   |
    //4  |   [1,2]   |      [b]      |  [1,2,3]  |
    //5  |   [1,3]   |      [a]      |   [1,4]   |
    //6  |   [1,3]   |      [b]      |  [1,2,4]  |
    //7  |  [1,2,3]  |      [a]      |  [1,3,4]  |
    //8  |  [1,2,3]  |      [b]      | [1,2,3,4] |
    //9  |   [1,4]   |      [a]      |   [1,5]   |
    //10 |   [1,4]   |      [b]      |  [1,2,5]  |
    //11 |  [1,2,4]  |      [a]      |  [1,3,5]  |
    //12 |  [1,2,4]  |      [b]      | [1,2,3,5] |
    //13 |  [1,3,4]  |      [a]      |  [1,4,5]  |
    //14 |  [1,3,4]  |      [b]      | [1,2,4,5] |
    //15 | [1,2,3,4] |      [a]      | [1,3,4,5] |
    //16 | [1,2,3,4] |      [b]      |[1,2,3,4,5]|
    //17 |   [1,5]   |      [a]      |    [1]    |
    //18 |   [1,5]   |      [b]      |   [1,2]   |
    //19 |  [1,2,5]  |      [a]      |   [1,3]   |
    //20 |  [1,2,5]  |      [b]      |  [1,2,3]  |
    //21 |  [1,3,5]  |      [a]      |   [1,4]   |
    //22 |  [1,3,5]  |      [b]      |  [1,2,4]  |
    //23 | [1,2,3,5] |      [a]      |  [1,3,4]  |
    //24 | [1,2,3,5] |      [b]      | [1,2,3,4] |
    //25 |  [1,4,5]  |      [a]      |   [1,5]   |
    //26 |  [1,4,5]  |      [b]      |  [1,2,5]  |
    //27 | [1,2,4,5] |      [a]      |  [1,3,5]  |
    //28 | [1,2,4,5] |      [b]      | [1,2,3,5] |
    //29 | [1,3,4,5] |      [a]      |  [1,4,5]  |
    //30 | [1,3,4,5] |      [b]      | [1,2,4,5] |
    //31 |[1,2,3,4,5]|      [a]      | [1,3,4,5] |
    //32 |[1,2,3,4,5]|      [b]      |[1,2,3,4,5]|
    //   +-----------+---------------+-----------/
	//



	// NOTE: (a|b)*b(a|b)* = a*b(a|b)* = (a|b)*ba* ... I think ...
	//   it's pretty much (a|b)* but with the constraint that at least 1 'b'
	//   is found; which 'b' exactly doesn't matter to language theory.
	//
	// This expression creates exponentially large DFAs, or NFAs that execute
	// for a potentially very long time:
	// (a|b)*b(a|b){4}
	//
	// More generally:
	// .*q.{n}
	//
	// This PEG should be equivalent, but chooses the shortest possible
	// capture always and doesn't have exponential running time or storage
	// requirements:
	// Y <- (a/b){4}
	// X <- (b Y) / ((a/b) X)
	//
	// Or, in more general form:
	// Y <- .{4}
	// X <- (q Y) / (. X)
	//
	// We can reduce the number of rules by inlining:
	// X <- (q .{4}) / (. X)

    // To see how this handles exponential explosion of DFA states, here is how
    // the process works on the (a|b)*b(a|b)(a|b)(a|b) language
    // (This scenario is given in the Wikipedia article on Powerset Construction,
    // with a graphic for this language's automata at
    // https://en.wikipedia.org/wiki/Powerset_construction#/media/File:NFA_and_blown-up_equivalent_DFA_01.svg) :
    //
    //   .-- a|b --.
    //   v         |  
    //  {1} -------'      .- a --.               .- a --.               .- a --.
    //   |               /       v              /       v              /       v
    //   '---- b ----> (2)       (3) -- q --> (4)       (5) -- q --> (6)     ((7))
    //                   \       ^              \       ^              \       ^
    //                    '- b --'               '- b --'               '- b --'
    //
    //
    // Start
	//   /---------+---------------+-------+
	//   | fromID  |  transitionOn | toID  |
    //   +---------+---------------+-------+
    //   |   [1]   |     [a,b]     |  [1]  |
    //   |   [1]   |      [b]      |  [2]  |
    //   |   [2]   |     [a,b]     |  [3]  |
    //   |   [3]   |      [q]      |  [4]  |
    //   |   [4]   |     [a,b]     |  [5]  |
    //   |   [5]   |      [q]      |  [6]  |
    //   |   [6]   |     [a,b]     |  [7]  |
    //   +---------+---------------+-------/
    //
    // Apply rule #1
	//   /---------+---------------+-------+
	//   | fromID  |  transitionOn | toID  |
    //   +---------+---------------+-------+
    //   |...[1]...|.....[a,b].....|..[1]..| <- Deleted
    //   |...[1]...|......[b]......|..[2]..| <- Deleted
    //   |   [1]   |      [a]      |  [1]  | <- New row; Along [a]: [1]~[] -> [1]
    //   |   [1]   |      [b]      | [1,2] | <- New row; Along [b]: [1]~[2] -> [1,2]
    //   |   [2]   |     [a,b]     |  [3]  |
    //   |   [3]   |      [q]      |  [4]  |
    //   |   [4]   |     [a,b]     |  [5]  |
    //   |   [5]   |      [q]      |  [6]  |
    //   |   [6]   |     [a,b]     |  [7]  |
    //   +---------+---------------+-------/
	//
	// Apply rule #2
	//   /---------+---------------+-------+
	//   | fromID  |  transitionOn | toID  |
    //   +---------+---------------+-------+
    //   |   [1]   |      [a]      |  [1]  |
    //   |   [1]   |      [b]      | [1,2] |
    //   |  [1,2]  |      [a]      | [1,3] | <- New row; Along [a]: [1]~[]~[3]  -> [1,3]
    //   |  [1,2]  |      [b]      |[1,2,3]| <- New row; Along [b]: []~[1,2]~[3] -> [1,2,3]
    //   |   [2]   |     [a,b]     |  [3]  |
    //   |   [3]   |      [q]      |  [4]  |
    //   |   [4]   |     [a,b]     |  [5]  |
    //   |   [5]   |      [q]      |  [6]  |
    //   |   [6]   |     [a,b]     |  [7]  |
    //   +---------+---------------+-------/
    //
    // Apply rule #3 (no change) TODO: This should delete state #2, but do we want that?
    //
    // Apply rule #1 (no change)
    //
    // Apply rule #2
	//   /---------+---------------+---------+
	//   | fromID  |  transitionOn |  toID   |
    //   +---------+---------------+---------+
    //   |   [1]   |      [a]      |   [1]   |
    //   |   [1]   |      [b]      |  [1,2]  |
    //   |  [1,2]  |      [a]      |  [1,3]  |
    //   |  [1,2]  |      [b]      | [1,2,3] |
    //   |  [1,3]  |      [a]      |   [1]   | <- New row; Along [a]: [1]~[]~[] -> [1]
    //   |  [1,3]  |      [b]      |  [1,2]  | <- New row; Along [b]: []~[1,2]~[] -> [1,2]
    //   |  [1,3]  |      [q]      |   [4]   | <- New row; Along [q]: []~[]~[4] -> [4]
    //   | [1,2,3] |      [a]      |  [1,3]  | <- New row; Along [a]: [1]~[]~[3]~[] -> [1,3]
    //   | [1,2,3] |      [b]      | [1,2,3] | <- New row; Along [b]: []~[1,2]~[3]~[] -> [1,2,3]
    //   | [1,2,3] |      [q]      |   [4]   | <- New row; Along [q]: []~[]~[]~[4] -> [4]
    //   |   [2]   |     [a,b]     |   [3]   |
    //   |   [3]   |      [q]      |   [4]   |
    //   |   [4]   |     [a,b]     |   [5]   |
    //   |   [5]   |      [q]      |   [6]   |
    //   |   [6]   |     [a,b]     |   [7]   |
    //   +---------+---------------+---------/
    //
    // Apply rule #3, #1, no change



// Available alternation operators:
//    |     Regular alternation:  Matches a length of input required for subsequent expressions to match. Nondeterministic.
//    /     PEG alternation:      Attempts its arguments left-to-right. The first one to match causes the parser to emit those captures and advance. Deterministic.
//    |/    Short alternation:    Attempts its arguments simultaneously like regular expression alternation, but halts as soon as one matches. A mixture of PEG and RegEx behaviors. Deterministic.
//    /|    Long alternation:     Attempts its arguments simultaneously like regular expression alternation, but halts as soon as none match; captures the longest match. Another mixture of PEG and RegEx behaviors. Deterministic.
//
// Other:
//  <expr> :short:   - Causes its operand to behave deterministically by chosing the shortest possible string that matches.
//  <expr> :long:    - Causes its operand to behave deterministically by chosing the longest possible string that matches.
//
// NOTE: "(a | b) :short:"  should be equivalent to "(a |/ b)"
//   and "(a | b) :long:"   should be equivalent to "(a /| b)"
//
// TODO: Is lazy alternation a good idea? It could lead to weird results if one of the subexpressions matches 0-length strings. Maybe it is possible to illegalize such expressions (or they are impossible).
// TODO: Are lazy and greedy alternation reversible? Will need to look at RegEx equivalent expression (if one exists) or try reversing DFA fragments. This could be important for efficient look-behind.
//
// PEG repetition already matches the longest possible match, and thus does not have any separate commutative-but-deterministic operators.
// PEG repetition can be implemented by adding a 'quit' state to the end of a regular-repetition's looping state. The transition to the 'quit' state can only be made when the repetition no longer has any other valid transitions.
// This notably makes repetition on '.', as commonly practiced in regular expressions, somewhat difficult to handle: if PEG rep is written **, then you can't just write '(.**?)a' and expect it to match 'xxa' or even 'a'; it will actually never match any strings, much less those ending in 'a'!
// Repetition wish shortest possible match would always match 0 input letters. It would always be a no-op and thus does not require an operator.
// TODO: How to distinguish regular repetition and PEG repitition?
//
// The PEG version of 'a?' would lower to '(a / ε)' or '(a /| ε)', but never '(a |/ ε)'. The latter would always match zero input and thus be a no-op.
//
// TODO: Maybe I should come up with a 'determinism' operator (or operators). Diamond comes to mind for unambiguous determinism: <>
//   So maybe 'a*' would be regex repetition, while 'a*<>' would be PEG repetition, and it would actually be two expressions parsed like so: '((a*)<>)'
//   Likewise, 'a?' would be regex optionality, while 'a?<>' would be PEG optionality, and it would be parsed like so '((a?)<>)'.
//   Short and long versions might be things like <| and |>, <$ and $>, <: and :>, or maybe <. and .>. This gets ugly, so I'd like something better.
//   Alternatively, maybe use elipses. '..' would be short determinism, while '...' would be long determinism.
//   The idea of a verbal pause or a longer verbal pause actually make nice mnemonics for this. I don't like the idea of them being that similar, though!
//   (That levenstein distance is way too short, and they look similar, which is all bad news for ensuring programs are as intentional as possible.)
//
// TODO: "Hopping" DFA (insert silly pic of chinese hopping zombie) that pretty much does the packrat parser trick:
//   if two DFA's have identical substructures and one has already been executed at the parser's current location
//   in input, then, if the execution failed, don't take that transition, otherwise skip (hop) over that part of
//   the DFA to transition directly into the memoized DFA state and advance the parser to the memoized location.
//   The DFA substructures are identified by rules in the grammar (it really is just packrat memoization, but
//   sophisticated enough to handle entire DFAs and not just rule-skipping).
//   This might not work if the start/end states for the DFA substructures do not match and create some complicated
//   combinatorics problem. It'd at least be worth seeing if that actually happens, because we might be able to seamlessly
//   implement regular expression operators as part of a packrat parser /without/ requiring determinism operators
//   (although I still want those short/long alternations). Important note: being able to do this allows us to
//   not only avoid determinism operators when recursion is used, but also to avoid 2^n DFA states by putting a
//   shortest-possible determinizer at the end of regex alternations and at the end of anchors for regex repetitions,
//   then repeatedly calling packrat parser attempts as we expand the scope of the determinizer. The repeated calling
//   could be very bad algorithmically, except that the memoization should turn much of the redundant scanning into
//   no-ops and return it to O(n) time complexity. At least in principle. We'll see.
//
// TODO: Runtime parameterized DFAs (or really this will probably be another packrat integrations with DFAs)
//   to provide the ability to match against strings that are provided while the parser is in flight... important for things like HTML/XML.
//
// TODO: Food for thought: what if the regular expression (?:(ab)c)|(?:a(bc)) is used to match the string "abc"... which capture(s) are triggered?
//   (My suspiscion is that BOTH will be fired off, due to the nondeterministic nature of the expression.)
//
//     .-- a --> (1) -- b --> (3) -- c --> ((5)) 
//    /
//  {0}
//    \
//     '-- a --> (2) -- b --> (4) -- c --> ((6))
//
// /---------+---------------+-------+
// | fromID  |  transitionOn | toID  |
// +---------+---------------+-------+
// |   [0]   |      [a]      |  [1]  |
// |   [0]   |      [a]      |  [2]  |
// |   [1]   |      [b]      |  [3]  |
// |   [2]   |      [b]      |  [4]  |
// |   [3]   |      [c]      |  [5]  |
// |   [4]   |      [c]      |  [6]  |
// +---------+---------------+-------/
//
// /---------+---------------+-------+
// | fromID  |  transitionOn | toID  |
// +---------+---------------+-------+
// |   [0]   |      [a]      |  [1]  | // deleted
// |   [0]   |      [a]      |  [2]  | // deleted
// |   [0]   |      [a]      | [1,2] | // new
// |   [1]   |      [b]      |  [3]  |
// |   [2]   |      [b]      |  [4]  |
// |   [3]   |      [c]      |  [5]  |
// |   [4]   |      [c]      |  [6]  |
// +---------+---------------+-------/
//
// /---------+---------------+-------+
// | fromID  |  transitionOn | toID  |
// +---------+---------------+-------+
// |   [0]   |      [a]      | [1,2] |
// |  [1,2]  |      [b]      | [3,4] | // new
// |   [1]   |      [b]      |  [3]  |
// |   [2]   |      [b]      |  [4]  |
// |   [3]   |      [c]      |  [5]  |
// |   [4]   |      [c]      |  [6]  |
// +---------+---------------+-------/
//
// /---------+---------------+-------+
// | fromID  |  transitionOn | toID  |
// +---------+---------------+-------+
// |   [0]   |      [a]      | [1,2] |
// |  [1,2]  |      [b]      | [3,4] |
// |  [3,4]  |      [c]      | [5,6] | // new
// |   [1]   |      [b]      |  [3]  |
// |   [2]   |      [b]      |  [4]  |
// |   [3]   |      [c]      |  [5]  |
// |   [4]   |      [c]      |  [6]  |
// +---------+---------------+-------/
//
// /---------+---------------+-------+
// | fromID  |  transitionOn | toID  |
// +---------+---------------+-------+
// |   [0]   |      [a]      | [1,2] |
// |  [1,2]  |      [b]      | [3,4] |
// |  [3,4]  |      [c]      | [5,6] |
// |   [1]   |      [b]      |  [3]  | // deleted; not reachable
// |   [2]   |      [b]      |  [4]  | // deleted; not reachable
// |   [3]   |      [c]      |  [5]  | // deleted; not reachable
// |   [4]   |      [c]      |  [6]  | // deleted; not reachable
// +---------+---------------+-------/
//
// /---------+---------------+-------+
// | fromID  |  transitionOn | toID  |
// +---------+---------------+-------+
// |   [0]   |      [a]      | [1,2] |
// |  [1,2]  |      [b]      | [3,4] |
// |  [3,4]  |      [c]      | [5,6] |
// +---------+---------------+-------/
//
// {0} -- a --> ([1,2]) -- b --> ([3,4]) -- c --> (([5,6]))
//
// This makes me realize that if I naively set capture events to fire on the
// "transitioning away from exit state" code, then this mishap can happen:
//
// Step |                       Cause                                       |                    Effect
// -----+-------------------------------------------------------------------+---------------------------------------------------
//   1  | DFA transitions from {0} to ([1,2]), records entry to (ab).        |  Record position of (ab) capture in input at {0}
//   2  | DFA transitions from ([1,2]) to ([3,4]), records entry to (bc).    |  Record position of (bc) capture in input at ([1,2])
//   3  | DFA transitions from ([3,4]) to ([5,6]), records exit from (ab).   |  Fire onBeginCapture(...) and onEndCapture(...) for (ab)
//   4  | DFA transitions from ([5,6]) to halt, records exit from (bc).      |  Fire onBeginCapture(...) and onEndCapture(...) for (bc)
//
// But this violates expectations: instead of this sequence:
//   onBeginCapture(ab), onEndCapture(ab), onBeginCapture(bc), onEndCapture(bc)
// I'd instead expect to see this sequence:
//   onBeginCapture(ab), onBeginCapture(bc), onEndCapture(ab), onEndCapture(bc)
//
// It might not be clear to someone else, so I'll write it:
// Step 3 can't just note that there's a recorded capture-start for (bc) waiting
// to fire and decide that the capture-end for (ab) is a good time for it to
// shoot its load. That's because the DFA hasn't yet confirmed that (bc) actually
// matches completely: it hasn't seen the 'c' until step 4.
//
// This is probably a smaller case of something I've already thought about for
// the packrat-parser side of things: you can't fire end-capture events until
// the parent rule's end-capture event fires, and you can't fire the parent's
// end-capture event until its parent's end-capture event fires, and so on
// until the entire parse must finish before any events fire at all. This is
// kinda unfortunate if you need an online algorithm, so I planned to have a
// grammar attribute (or perhaps even better, a runtime-settable configuration
// parameter in the parser) that allows the designer to have any pending
// captures pushed immediately, without waiting for confirmation that absolutely
// all start-capture events belong to successful parses. That amount of
// uncertainty is reasonably for many things, and just like how humans can
// become fairly certain of a document's nature when they merely begin to read
// it (at the expense of /maybe/ being /wrong/), it is only natural for computers
// to have the same inductive capability. Of course, knowing about this ahead
// of time, we can prepare for it by having different start-capture events:
// confirmed-start-capture and unconfirmed-start-capture (or maybe-start-capture).
// We might also issue parse-failed events to match any unconfirmed-start-capture
// events that might have been pushed out the door a bit too early and proven
// incorrect according to later parses. If this invalidates entire previous
// parses that were fired off whole (as if successful) but were children of the
// failed parse, then we might need yet another strategy for that, but I
// haven't quite considered it yet. (And if the online algorithm has a way
// to discard packrat parser state for "old" input, and perhaps even that
// "old" input has already been discarded, then having the parser backtrack
// to reparse from an earlier rule might be entirely impossible!)
// It might also make sense to give the caller more direct control over the
// event queue. This might be poor default behavior (most callers would end up
// with more events than they know what to do with), but it would allow the
// caller to control memory allocation for the event queue in a more intimate
// way, possibly yielding globally more-efficient solutions, and perhaps even
// coming up with better ways to do it than the author of this library can
// figure.
//
// But, uh, back to DFA considerations. Unless there's some kind of intervention
// from the grammar writer, it is probably a good idea to hold on to all capture
// events, even end-capture events, until there are no more unaccounted-for
// begin-capture events (these will still be in the event stack, but they
// will all have matching end-capture events, and that will tell the DFA that
// it is safe to fire it's lasers, sort of... parent rules need to be in a
// "safe" state as well).
//
// ============================================================================
//
// I want to find some way to track how expensive an NFA->DFA conversion is
// becoming, and instead generate hybrid NFA/DFA outputs that can still operate
// in O(n) time by using memoization as a packrat parser does (instead of using
// O(n^2) time as quoted in some stackoverflow article that I forget the name
// of).
//
// While pondering what this might actually look like, I started to wonder if
// I can look at the different elements of grammars and just consider what
// happens to an NFA->DFA conversion process in all possible cases. It /might/
// be doable. Just tedious.
//
// So...
//
// Write a program to do it for us? Then we don't have to constrain ourselves
// to just binary relationships. We can handle n-deep constructions. Yeah,
// let's science the fuck out of this shit.
//
// This will require some mechanisms to exist first:
// - The ability to convert NFAs to DFAs. It doesn't have to do it intelligently,
//   it just needs to do it at all.
// ... and that might be it for now. But there could be more if we have to care
// about how captures are handled, and things like that.
//
// Maybe start with a trinary alphabet: a, b, and c are the possible symbols.
// This makes distinctions between things like .*b.{4} and (a|b)*b(a|b){4} more
// noticable. (Or constrain it to only generate grammars made of ., 'a', and not-'a',
// and expand . to a full alphabet of choices in a different part of the program.)
//
// For sake of optimizing packrat parsers in the future, it would be nice to
// have a "recursion" construct in this NFA thingie, but it would hardcode the
// maximum number of recursion depths. If N steps of recursion can be unrolled
// into a DFA, it could make parsers more efficient by avoiding the need to
// backtrack when, for example, parsing expressions. Even complicated expressions
// could parse faster: an expression with 17 levels of depth will only require
// a maximum of 2 backtracks if the DFA handles 8 levels at a time, as opposed
// to 16 backtracks if the DFA ends its superposition at the first sign of
// recursion (handling 1 level at a time). Since this is machine-generated,
// we can set the DFA's multiplicity as high as the DFA-complexity constraints
// will suffer, and thus end up with some potentially really big recursion
// backtracking dividers (maybe; assuming recursion doesn't automatically
// exponentiate DFA complexity or something like that).
//
// With this knowledge in hand, we can quite possibly know a-priori which constructs
// are going to explode the number of DFA nodes, and then write an NFA->DFA
// converter that sorts its tasks according to expected outcomes and performs
// the most expensive steps last (and interleaved) so that the best possible
// machines are created whenever there are DFA-complexity constraints.
//
}

