# Tuples

Tuples are a basic construct in Pyrope. Tuples are defined as an "ordered"
sequence fields that can be named. Arrays/memories are a subcategory of tuples
by requiring all the entries to have the same type. Internally, there is
not a difference between tuples and arrays, but it is possible to check
that all the fields are the same (hence array) by using brackets instead of parenthesis.

```pyrope
mut b = (f1=3,f2=4) // b is named and ordered
mut c = (1,d=4)     // c is ordered and unnamed (some entries are not named)

mut d = (1,2,3,4)     // array or tuple
cassert(d == [1,2,3,4]) // the [] also check that all the fields have same type
cassert(b.f1 == 3 and b.f2 == 4)
cassert(c[0] == 1 and c.d == 4)

assert (true,1) != [true,1]  // error: true is not the same type as 1
```

Named fields are accessed by name with `.` or `['name']`. Integer `[]`
selection is only for unnamed positional entries; it never aliases a named
field.
```pyrope
mut a = (
  ,r1 = (b=1,c=2)
  ,(3,4)
)
cassert(a.r1 == (1,2))
cassert(a[0] == (3,4))  // first unnamed entry

// different ways to access the same field
cassert(a.r1.c == 2 == a['r1'].c)
cassert(a[0][1]   == 4)

const named = (b = 1, c = 2)
const bad = named[0] // error: named entries are name-access only
```

There is introspection to check for an existing field with the `has` operator.
Negate with `not (...)` (there is no dedicated `!has` operator).

```pyrope
mut a = (foo = 3)
cassert(a has 'foo')
cassert(not (a has 'bar'))
cassert(a has 0)
cassert(not (a has 1))
```

Tuple named fields can have a default type and or contents:

```pyrope
mut val = 4
mut x = (
  ,field1=1            // field1 with implicit type and 1 value
  ,field2:string = nil // field2 with explicit type and "" default value
  ,field3:int = 3      // field3 with explicit type and 3 value
  ,val                 // unnamed field with value `val` (4)
)
cassert(x.field1 == 1 and x.field3 == 3)
cassert(x[3] == 4)
```

## Selector expressions

A selector `[...]` takes a single expression. The expression can be an integer,
a string (named field), a range, or any expression that produces one of those
(including a conditional `if ... {} else {}`). Multi-entry tuple indices like
`a[0,1]` or `a['x','y']` are not allowed: write one assignment per field
instead. This keeps the bit/field layout local and avoids ordering ambiguity.

```pyrope
type Person = (name:string, age:u32)
mut a = (one:Person, two:Person)

a[0].age = 10
a[1].age = 20
cassert(a.one.age == 10 and a.two.age == 20)

const pick = if cond { 0 } else { 1 }
a[pick].age = 7   // conditional expression as index is fine
```

## Tuple and scope


Since tuples can be named or unnamed, an entry like `xx=(foo)` creates a tuple `xx`
and copies the current scope variable `foo` contents as the first entry. In many cases
it is required to pass a sequence of strings or identifiers. A solution is to
name all the fields or quote as strings:

```pyrope
mut x=100

mut tup1 = ('x',y=4)
mut tup2 = (x,y=4)

cassert(tup1[0] == 'x')
cassert(tup2[0] == 100)
```

Some constructs like enumerates and attributes typically pass identifiers
without assigning a value. The problem is that the syntax becomes not so
"nice".  To address these cases, Pyrope does not use a variable reference but a
"string" in the enumerate (`enum(a,b=3)`) and attribute set/read forms
(`foo::[attr]` at declaration, `foo.[attr]` to read).

```pyrope
const aa = 3
const a = enum(,aa, ,b=3)
cassert(a==b)

```

## Everything is a tuple

In Pyrope everything is a Tuple, and it has some implications that this
section tries to clarify.


A tuple starts with `(` and finishes with `)`. In most languages, the
parentheses have two meanings, operation precedence and/or tuple/record.
In Pyrope, since a single element is a tuple too, the parenthesis always means
a tuple.


A code like `(1+(2),4)` can be read as "Create a tuple of two entries. The
first entry is the result of the addition of `1` (which is a tuple of 1) and a
tuple that has `2` as a unique entry. The second entry in the tuple is `4`".

The tuple entries are separated by comma (`,`). Extra commas do not add meaning.

```pyrope
mut a = (1,2)   // tuple of 2 entries, 1 and 2
mut b = (1)     // tuple of 1 entry, 1
mut c = 1       // tuple of 1 entry, 1
mut d = (,,1,,) // tuple of 1 entry, 1
cassert(a[0] == b[0] == c[0] == d[0])
cassert(a!=b)
cassert(b == c == d)
```

A tuple with a single entry element is called a scalar.

Tuples are used in many places:

* The arguments for a function call are a tuple. E.g: `fcall(a=1,b=2)`
* The return of a function call is always a tuple. E.g: `foo = fcall()`
* The index for a selector `[...]` is a single expression (integer, string, range, or conditional). Integer indices select unnamed positional entries only; named fields use strings or dot syntax. Multi-entry tuple indices are not allowed.
* The complex type declaration are a tuple. E.g: `const Xtype = (f=1,b:string)`

### Dotted Field Expansion

Tuple literals may spell nested named fields in expanded dotted form. This is
the same flattening idea used by [function-call argument expansion](06-functions.md#argument-naming):
`a.b=1` and `a.c=2` construct the nested field `a=(b=1,c=2)`.

```pyrope
const compact  = (a=(b=1,c=2), 7, 3, d=3)
const expanded = (a.b=1, a.c=2, d=3, 7, 3)
cassert(compact == expanded)
```

The expanded form is legal but usually less readable than the compact tuple
form. It is useful when matching flattened hardware interfaces, because the
generated LGraph/Verilog port structure follows the expanded field paths.
Unnamed entries keep their normal positional order among the other entries.

## Tuple mutability

The tuple entries can be mutable/immutable and named/unnamed. Tuple entries
follow the variable mutability rules with the exception that `=` can be
used to declare a mutable field. `(a=3)` is equivalent to `(mut a=3)`.

**The enclosing binding wins.** A field's effective mutability is the
**intersection** of the outer binding's mutability and the field's own
declaration. In particular, **an outer `const` makes every field immutable
regardless of inner `mut` markers** — the binding to the whole tuple is
immutable, so no field can be reassigned through it. Inner `const` on a
field of an outer `mut` tuple still pins that field as read-only.

| Outer | Inner field | Effective |
|-------|-------------|-----------|
| `mut`   | `mut` / unmarked | writable |
| `mut`   | `const`          | read-only |
| `const` | `mut` / unmarked | **read-only** (outer wins) |
| `const` | `const`          | read-only |

```pyrope
mut c = (x=1, const b=2, mut d=3)
c.x = 3   // OK     (mut tuple, default-mut field)
c.b = 10  // error: 'c.b' is immutable (inner const)
c.d = 30  // OK     (mut tuple, mut field)

const d = (x=1, const y=2, mut z=3)
d.x = 2   // error: 'd' is immutable — inner `mut` is overridden
d.z = 4   // error: 'd' is immutable — outer `const` wins over inner `mut z`

mut e:d = nil
assert(e.x==1 and e.y==2 and e.z==3)
e.x = 30  // OK
e.y = 30  // error: 'e.y' is immutable (inner const)
e.z = 30  // OK     (outer mut + inner mut)
```

Tuples are always ordered, but they can have unnamed entries. A field
without a name is *positional*; it can still carry a kind keyword
(`const` / `mut`) as a prefix on the value to override the default
mutability inherited from the enclosing tuple.

```pyrope
mut b = 100
mut a = (b:u8, b, b:u8 = nil, const c=4) // a[0] and a[1] are unnamed, a[2]==a.b
a.b = 200
assert(a == (100, 100, 200, 4))

mut f = (b=3, const e=5)
f.b = 4                 // OK
f.e = 10                // error: `f.e` is immutable

const x = (1,2)
x[0] = 3                // error: 'x' is immutable
mut y = (1, const 3)    // 2nd field is positional and immutable
y[0] = 100              // OK
y[1] = 101              // error: `y[1]` is immutable
```


While the tuple entries can be either mutable or immutable, the field
name/types are immutable. It is possible to construct new tuples with the `++`
(concatenate) and `...` (in-place operator):

```pyrope
mut a=(a=1,b=2)
const b=(c=3)

const ccat1 = a ++ b
assert(ccat1 == (a=1,b=2,c=3))
assert(ccat1 == (1,2,3))

mut ccat2 = a ++ (b=20) ++ b
assert(ccat2 == (a=1,b=(2,20),c=3))
assert(ccat2 == (1,(2,20),3))

mut join1 = (...a,...b)
assert(join1 == (a=1,b=2,c=3))
assert(join1 == (1,2,3))

mut join2 = (...a,...(b=20)) // error: 'b' already exists
```


The `a ++ b` concatenates two tuples. If the same field exists in both tuples,
the resulting field will have a tuple with the entries of `a` and `b`.  The
concat tries to match by field name, if the field names do not match or have no
name a new entry is created. The algorithm starts with tuple `a` and starts
from tuple field 0 upwards.

```pyrope
assert(((1,a=2,c=3) ++ (a=20,33,c=30,4)) == (1,a=(2,20),c=(3,30),33,4))
```

The `...` also concatenates, but it is an "inline concatenate". The difference
is where the fields are concatenated and that it triggers a compile error if
the same entry already exists.



## Field access

Since everything is a tuple, any variable can do `variable[0][0][0]` because it
literaly means, return the tuple first entry for four times.


Another useful shortcut is when a tuple has a single field or entry, the tuple
contents can be accessed without requiring the individual position or field
entry name. This is quite useful for function return tuples with a single
entry.

```pyrope
const x = (first=(second=3))

cassert(x.first.second == 3)
cassert(x.first        == 3)
cassert(x              == 3)
cassert(x[0].second    == 3)
cassert(x.first[0]     == 3)
cassert(x[0]           == 3)
```


Tuples can also use structural binding to unpack a tuple multiple fields into separate variables.

```pyrope
const x = (f1=(f1a=1,f1b=3), f2=4)

const (y,z) = x
cassert(y == (1,3) and z == 4)
cassert(y.f1a == 1 and y.f1b == 3)
cassert(y == (f1a=1,f1b=3))
```

## Tuples vs arrays

Tuples are ordered, as such, it is possible to use them as arrays. Tuples and
arrays share most behavior/operations, the key difference is that arrays are
unnamed with the same type for all the entries.

```pyrope
mut bund1 = (0,1,2,3,4) // ordered and can be used as an array

mut array1 = [0,1,2,3,4]  // [] force array, so all the entries have same type

mut bund2 = (bund1,bund1,((10,20),30))
cassert(bund2[0][1] == 1)
cassert(bund2[1][1] == 1)
cassert(bund2[2][0] == (10,20))
cassert(bund2[2][0][1] == 20)
cassert(bund2[2][1] == 30)
```

Pyrope tries to be compatible with synthesizable Verilog. In Verilog, when an
out of bounds, access is performed in a packed array (unpacked arrays are not
synthesizable), or an index has unknown bits (`?`), a runtime warning can be
generated and the result is an unknown (`0sb?`). Notice that this is a
pessimistic assumption because maybe all the entries have the same value when
the index has unknowns.


The Pyrope compile will trigger compile errors for out-of-bound access. It is not
possible to create an array index that may perform an out of bounds access.

```pyrope
mut array = (0,1,2)       // size 3, not 4
const tmp = array[3]        // error: out of bounds access
mut index = 2
if runtime {
  index = 4
}
// Index can be 2 or 4

mut res1 = array[index]   // error: out of bounds access

mut res2 = 0sb?           // Possible code to be compatible with Verilog
if index<3 {
  res = array[index]      // OK
}
```

Pyrope compiler will allow an index of an array/tuple with unknowns. If the
index has unknown bits (`0sb?` or `0ub1?0`) but the compiler can not know, the
result will have unknowns (see [internals](10-internals.md) for more details).
Notice that the only way to have unknowns is that somewhere else a variable or
a memory was explicitly initialized with unknowns. The default initialization
in Pyrope is 0, not unknown like Verilog.


### Concatenate fields

Each tuple field must be unique. Inside a tuple literal a field may only be
introduced once, and only with a plain `=`. Repeating a field name is an
error, and so is a compound assignment (`++=`, `+=`, ...) inside the literal —
there is no prior value to update while the tuple is still being built.

```pyrope
mut x = (
  ,ff = 1
  ,ff = 2   // error: 'ff' already declared in the tuple
)

mut y = (
  ,ff = 1
  ,ff ++= 2 // error: compound assignment is not allowed inside a tuple literal
  ,zz ++= 3 // error: compound assignment is not allowed inside a tuple literal
)
```

It is still practical to append or concatenate into an existing field — this
is the case for overloading. Do it as a separate statement *after* the tuple
is declared (the variable must be `mut`), using `++=` on the field path. This
concatenates `2` into `ff`, so `y.ff` becomes the tuple `(1, 2)`:

```pyrope
mut y = (
  ,ff = 1
  ,zz = 3
)
y.ff ++= 2   // OK: 'y' is mut, so the field can be concatenated afterwards
```




## Optional tuple parenthesis

Parenthesis marks the beginning and the end of a tuple. Tuple parentheses
can be omitted in only one place:

* A single element lambda return value.

Everywhere else — function calls, selectors `[...]`, `for ... in`, `match`
case patterns — tuples are always parenthesized. Bare-tuple sugar inside
`in`, `[…]`, and call arguments has been removed.

```pyrope
for a in (1,2,3) {
  x = a
}
y = match z {
  in (1,2) { 4 }
  else { 5 }
}
y2 = match mut one=1 ; one ++ z {  // same as: y2 = match (1,z) {
  == (1,2) { 4 }
  else     { 0 }
}

comb addb(a, b:u32) -> (a:u32) {
  a = a + b
}
```

A named tuple parenthesis can be omitted on the left-hand side of an
assignment. This is to mutate or declare multiple variables at once.  It is not
allowed to avoid the parenthesis at the right-hand-side of the statement. The
reason is that it is a bit confusing.

```pyrope
mut a,b = (2,3)    // error: left-hand-side must be a tuple (a,b)
mut (a,b) = 2,3    // error: right-hand-side must be a tuple (2,3)
mut (a,b) = (2,3)
cassert(a==2 and b==3)

mut (c,d) = 1..=2  // error: range is a single entry assignment
mut c = 1..=2      // OK
mut (c,d) = 1      // error: 2 entry tuple in lhs, same in rhs
mut (c,d) = (1,2)  // OK
cassert(c == 1 and d == 2)
```

### Named-tuple destructuring

When the RHS is a **named** tuple (e.g. a lambda return whose outputs are
declared by name, or any tuple literal with named fields), destructuring on
the LHS matches **by name**, not by position. This mirrors the call-site
rule for named arguments and prevents the silent-rebind footgun where two
outputs are swapped in the declaration.

* A bare LHS name like `b` matches the RHS field whose name is also `b`.
  If no such field exists, it is a compile error.
* An explicit `local = source.path` slot binds the selected RHS field path to
  local `local`. Use this when you want a different local name from the field
  name, when selecting a nested field, or when a RHS tuple contains multiple
  lambda-call results and the lambda name disambiguates the source.
* LHS order is irrelevant under named binding: `(b, c) = r` and
  `(c, b) = r` are the same.

```pyrope
comb dox(a) -> (b, c) { b = a + 1; c = a + 2 }
comb deep(a) -> (payload, code) { payload = (inner = (value = a + 1)); code = a + 10 }

(b, c) = dox(a=3)        // local `b` ← dox.b, local `c` ← dox.c
(c, b) = dox(a=3)        // same: order doesn't matter
(x=dox.b, y=dox.c) = dox(a=3)  // rename: dox.b → x, dox.c → y
(v=deep.payload.inner.value) = deep(a=3) // nested field selection
(y, x) = dox(a=3)        // error: `y` is not a field of dox's return
```

When the RHS is an **unnamed** tuple (no field labels — e.g. a literal
`(2, 3)` or `1..=2`), there are no names to match against, so destructuring
falls back to positional binding by tuple index:

```pyrope
mut (a, b) = (2, 3)      // a=2, b=3 (positional — RHS has no names)
mut (b, a) = (2, 3)      // a=3, b=2 (still positional)
```

One thing to remember is that the `=` separates the statement in two parts
(left and right), this is not the case with type or attributes that always
apply to the immediatly declared variable or item.

```pyrope
const c = 4
cassert(c does u3) // type check on 'c' is a separate statement
const (x, b) = (true, c)           // assign x=true, b=4

cassert(x == true)
cassert(b == 4)
```

## Enumerate (`enum`)

Enumerates, or enums for short, use the familiar tuple structure, but there is
a significant difference in initialization. Enums require named tuples, but in
most cases the named tupled should not have a set value. Enums automatically
assigns values, tuples need explicit value initialization.

```pyrope
const b = "foo"
const c = 1
const test1     = enum(a=c,b)    // OK
const something = (b)            // OK
cassert(something == "foo")
cassert(test1.a != test1.b)
cassert(test1.a==1 and test1.b==2)
```

The `enum` keyword does not reference scope variables unless the reference is
on the right-hand-side.


If an external variable wants to be used as a field, there has to be an explicit
expression with a string type or a named tuple.

```pyrope
const a = "field"
const c = (foo=4)
const my_other_enum = enum(...a,b=3,...c)
cassert(my_other_enum.field != my_other_enum.b)
cassert(my_other_enum.b   == 3)
cassert(my_other_enum.foo == 4)
cassert(my_other_enum.foo != my_other_enum.b)
```

The enum default values are NOT like typical non-hardware languages. The enum
auto-created values use a one-hot encoding. The first entry has the first bit
set, the 2nd the 2nd bit set. If an entry has a value, the next entry uses
the next free bit. If any field is set, then the enumerate behaves like a
traditional enumerate sequence.

!!! WARNING

    Enum values should always be compared against named enum entries, never
    against raw integer literals. The underlying numeric encoding (one-hot by
    default) is an implementation detail. Use `state == MyEnum.idle`, not
    `state == 0` or `state == 1`. To inspect the raw bit representation, use
    `state#[..]`.


```pyrope
enum V3 = (
   ,a
   ,b
   ,c
)
cassert(V3.a == 1)
cassert(V3.b == 2)
cassert(V3.c == 4)

// Always compare against enum entries, not raw values:
mut state:V3 = V3.a
cassert(state == V3.a) // correct
// cassert(state == 1)      // discouraged: relies on encoding details

enum V4 = (
   ,a
   ,b=5
   ,c
)
cassert(V4.a == 0)
cassert(V4.b == 5)
cassert(V4.c == 6)
```

### Hierarchical enumerates

Enum can accept hierarchical tuples. Each enum level follows the same algorithm.
Each entry tries to find a new bit. In the case of the hierarchy, the lower
hierarchy level bits are kept.

```pyrope
enum Animal = (
  ,bird  =(,eagle, ,parrot)
  ,mammal=(,rat  , ,human )
)

cassert(Animal.bird.eagle != Animal.mammal)
cassert(Animal.bird != Animal.mammal.human)
cassert(Animal.bird == Animal.bird.parrot)

cassert(int(Animal.bird        ) == 0ub000001)
cassert(int(Animal.bird.eagle  ) == 0ub000011)
cassert(int(Animal.bird.parrot ) == 0ub000101)
cassert(int(Animal.mammal      ) == 0ub001000)
cassert(int(Animal.mammal.rat  ) == 0ub011000)
cassert(int(Animal.mammal.human) == 0ub101000)
```

In general, for each leaf enum, the number of bits is equivalent to the number
of entries in the leaf tuple.


It is possible to use a sequence that is more consistent with traditional
programming languages, but this only works with non-hierarchical enumerates
when an integer type (`:int`, `:u32`, `:i4` ...) is used.

```pyrope
enum V5 = (
   ,a
   ,b=5
   ,c
)
cassert(int(V5.a) == 0)
cassert(int(V5.b) == 5)
cassert(int(V5.c) == 6)
```

The same syntax is used for enums to different objects. The hierarchy is not
allowed when an ordered numbering is requested.



Enumerates of the same type can perform bitwise binary operations
(and/or/xor) and the set operator `in` (negate with `not (...)`).

```pyrope
const human_rat = Animal.mammal.rat | Animal.mammal.human  // union op

assert(Animal.mammal      in human_rat)
assert(Animal.mammal.rat  in human_rat)
assert(not (Animal.bird   in human_rat))
```

### Enumerate typecast


To convert a string back and forth to an enumerate, explicit typecast is needed
but possible.

```pyrope
enum E3 = (
  ,l1=(
    ,l1a
    ,l1b
    )
  ,l2
  )
cassert(string(E3.l1.l1a) == "E3.l1.l1a")
cassert(string(E3.l1) == "E3.l1")
cassert(E3("l1.l2") == E3.l1.l2)
```
