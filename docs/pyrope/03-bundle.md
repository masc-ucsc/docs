# Tuples

Tuples are a basic construct in Pyrope. Tuples are sequences of fields, and a
tuple is either **named** or **unnamed**:

* An **unnamed** tuple has only positional fields. They are ordered and
  accessed by position (`t[0]`).
* A **named** tuple has only named fields. They are accessed by name only
  (`t.a` or `t['a']`, never `t[0]`), and their relative order carries no
  meaning (tools canonicalize named fields alphabetically, but that is a
  convention, not a requirement). Anything that walks a named tuple
  (`for`, `keys()`) visits the fields in field-name order, so reordering the
  fields never changes a program.

A tuple that mixes named and unnamed entries is an error. Where a named tuple
is expected (the arguments of a call, the value of a typed tuple construction),
names may be dropped under the [call naming rules](06-functions.md#argument-naming):
a bare variable whose name matches the field, a single field, a value whose
type is unique among all the fields, or `self`.

Arrays/memories are a subcategory of unnamed tuples
by requiring all the entries to have the same type. Internally, there is
not a difference between tuples and arrays, but it is possible to check
that all the fields are the same (hence array) by using brackets instead of parenthesis.

```pyrope
mut b = (const f1=3, const f2=4) // b is named (field order has no meaning)
mut c = (1, const d=4)           // error: mixes an unnamed entry and a named one

mut d = (1,2,3,4)     // array or unnamed tuple
cassert(d == [1,2,3,4]) // the [] also check that all the fields have same type
cassert(b.f1 == 3 and b.f2 == 4)

assert (true,1) != [true,1]  // error: true is not the same type as 1
```

Named fields are accessed by name with `.` or `['name']`. Integer `[]`
selection is only for unnamed tuples; it never aliases a named field.
```pyrope
mut a = (
  ,const r1 = (const b=1, const c=2)
  ,const r2 = (3,4)
)
cassert(a.r1 == (const b=1, const c=2))
cassert(a.r2 == (3,4))

// different ways to access the same field
cassert(a.r1.c == 2 == a['r1'].c)
cassert(a.r2[1]   == 4)

const named = (const b = 1, const c = 2)
const bad = named[0] // error: a named tuple is accessed by name only
```

There is introspection to check for an existing field with the `has` operator.
Negate with `not (...)` (there is no dedicated `!has` operator).

```pyrope
mut a = (const foo = 3, const bar = 10)
cassert(a has 'foo')
cassert(not (a has 'baz'))

mut u = (10, 20)
cassert(u has 1)        // an unnamed tuple has positions 0 and 1
cassert(not (u has 2))
```

Tuple named fields can have a default type and or contents:

```pyrope
mut val = 4
mut x = (
  ,const field1=1            // field1 with implicit type and 1 value
  ,const field2:String = nil // field2 with explicit type and invalid default value
  ,const field3:Signed = 3   // field3 with explicit type and 3 value
  ,const field4 = val        // field4 copies `val` (4)
)
cassert(x.field1 == 1 and x.field3 == 3 and x.field4 == 4)
```

A typed tuple construction binds its values like a call binds arguments:

```pyrope
type T1 = (a:String, b:Signed)
mut t1:T1 = (3, "hello")         // OK: each value's type is unique, b=3, a="hello"
cassert(t1.a == "hello" and t1.b == 3)

type T2 = (a:Signed, b:Signed)
mut t2:T2 = (1, 2)               // error: two Signed fields, name them
mut t3:T2 = (a=1, b=2)           // OK
```

## Selector expressions

A selector `[...]` takes a single expression. The expression can be an integer,
a string (named field), a range, or any expression that produces one of those
(including a conditional `if ... {} else {}`). Multi-entry tuple indices like
`a[0,1]` or `a['x','y']` are not allowed: write one assignment per field
instead. This keeps the bit/field layout local and avoids ordering ambiguity.

```pyrope
type Person = (const name:String = "", mut age:U32 = 0)
mut a = (
  ,mut one:Person = (name="one", age=0)
  ,mut two:Person = (name="two", age=0)
)

a['one'].age = 10
a['two'].age = 20
cassert(a.one.age == 10 and a.two.age == 20)

const pick = if cond { 'one' } else { 'two' }
a[pick].age = 7   // conditional expression as index is fine
```

## Tuple and scope


Since tuples can be named or unnamed, an entry like `xx=(foo)` creates a tuple `xx`
and copies the current scope variable `foo` contents as the first entry. In many cases
it is required to pass a sequence of strings or identifiers. A solution is to
name all the fields or quote as strings:

```pyrope
mut x=100

mut tup1 = ('x', 4)
mut tup2 = (x, 4)
mut tup3 = (const x=x, const y=4)

cassert(tup1[0] == 'x')
cassert(tup2[0] == 100)
cassert(tup3.x == 100)
```

Some constructs like enumerates and attributes typically pass identifiers
without assigning a value. The problem is that the syntax becomes not so
"nice".  To address these cases, Pyrope does not use a variable reference but a
"string" in the enumerate (`enum E = (a, b=3)`) and attribute set/read forms
(`foo::[attr]` at declaration, `foo.[attr]` to read).

```pyrope
const aa = 3
enum E = (aa, b=3)          // `aa` names a new entry, it does not read the variable
cassert(Signed(E.aa) == 0 and Signed(E.b) == 3)
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
* Complex type declarations are tuples. E.g: `type Xtype = (const f=1, const b:String = "")`

### Dotted Field Expansion

Tuple literals may spell nested named fields in expanded dotted form. This is
the same flattening idea used by [function-call argument expansion](06-functions.md#argument-naming):
`const a.b=1` and `const a.c=2` construct the nested field
`a=(const b=1,const c=2)`.

```pyrope
const compact  = (const a=(const b=1, const c=2), const d=3)
const expanded = (const a.b=1, const a.c=2, const d=3)
cassert(compact == expanded)
```

The expanded form is legal but usually less readable than the compact tuple
form. It is useful when matching flattened hardware interfaces, because the
generated LGraph/Verilog port structure follows the expanded field paths.
A dotted field is a named field, so a tuple that uses one cannot also hold
unnamed entries.

## Tuple mutability

The tuple entries can be mutable/immutable, and the tuple named or unnamed. Tuple entries
follow the variable mutability rules. A named tuple field is a declaration, so
it must use a kind keyword: `(mut a=3)` or `(const a=3)`. Bare `(a=3)` is valid
as a function-call argument and as the value for an explicitly typed
construction, but not as a standalone tuple field declaration.

**The enclosing binding wins.** A field's effective mutability is the
**intersection** of the outer binding's mutability and the field's own
declaration. In particular, **an outer `const` makes every field immutable
regardless of inner `mut` markers** — the binding to the whole tuple is
immutable, so no field can be reassigned through it. Inner `const` on a
field of an outer `mut` tuple still pins that field as read-only.

| Outer | Inner field | Effective |
|-------|-------------|-----------|
| `mut`   | `mut`            | writable |
| `mut`   | `const`          | read-only |
| `const` | `mut`            | **read-only** (outer wins) |
| `const` | `const`          | read-only |

```pyrope
mut c = (mut x=1, const b=2, mut d=3)
c.x = 3   // OK     (mut tuple, default-mut field)
c.b = 10  // error: 'c.b' is immutable (inner const)
c.d = 30  // OK     (mut tuple, mut field)

const D = (mut x=1, const y=2, mut z=3)
D.x = 2   // error: 'D' is immutable — inner `mut` is overridden
D.z = 4   // error: 'D' is immutable — outer `const` wins over inner `mut z`

mut e:D = nil
assert(e.x==1 and e.y==2 and e.z==3)
e.x = 30  // OK
e.y = 30  // error: 'e.y' is immutable (inner const)
e.z = 30  // OK     (outer mut + inner mut)
```

Unnamed tuple entries are ordered (positional). A field
without a name is *positional*; it can still carry a kind keyword
(`const` / `mut`) as a prefix on the value to override the default
mutability inherited from the enclosing tuple.

```pyrope
mut b = 100
mut a = (b, b, const 4) // unnamed: a[0] and a[1] copy b, a[2] is immutable
a[0] = 200
assert(a == (200, 100, 4))
a[2] = 5                // error: `a[2]` is immutable

mut f = (mut b=3, const e=5)
f.b = 4                 // OK
f.e = 10                // error: `f.e` is immutable

const x = (1,2)
x[0] = 3                // error: 'x' is immutable
mut y = (1, const 3)    // 2nd field is positional and immutable
y[0] = 100              // OK
y[1] = 101              // error: `y[1]` is immutable
```


While the tuple entries can be either mutable or immutable, the field
name/types are immutable. New tuples are built with the `...` splice operator,
which inserts a tuple's fields into the surrounding tuple literal:

```pyrope
mut a=(mut a=1, mut b=2)
const b=(const c=3)

const ccat1 = (...a, ...b)
assert(ccat1 == (const a=1, const b=2, const c=3))

mut ccat2 = (...a, const d=20, ...b)
assert(ccat2 == (const a=1, const b=2, const d=20, const c=3))

mut join2 = (...a, ...(const b=20)) // error: 'b' already exists

const p = (1,2)
const q = (3,4)
assert((...p, ...q) == (1,2,3,4))   // unnamed splices append in order
assert((...p, 5) == (1,2,5))

const mix1 = (...p, ...a)           // error: an unnamed and a named splice
const mix2 = (...p, const e=5)      // error: the result mixes unnamed and named entries
```


A `...` splice concatenates, and the result follows the all-named or
all-unnamed rule. Splicing unnamed tuples appends their entries in order.
Splicing named tuples merges them by field name: a field name that is not yet
present creates a new field. If the same field exists in both tuples and both
values are tuples, the splice recursively merges their subfields. If the same
final field exists on both sides, the merge is allowed only when one side is
`nil` or constant propagation proves both sides have the same value; otherwise
it is a compile error instead of accumulating the two values. Mixing a named
and an unnamed tuple in one splice is an error.

```pyrope
assert((...(const cfg=(const lo=2),const c=3), ...(const cfg=(const hi=20),const d=30)) == (const cfg=(const lo=2,const hi=20),const c=3,const d=30))

assert((...(const a=2,const b=nil), ...(const a=2,const b=10)) == (const a=2,const b=10))

const bad = (...(const a=2), ...(const a=20)) // error: 'a' already exists
```

Because `...` splices fields at its position, it can also insert in the middle
of a literal and add arguments to a function call:

```pyrope
comb foo(a, b, c) -> (r) { r = a + b + c }

const rest = (const b=2, mut c=3)
cassert(foo(a=1, ...rest) == 6)   // same as foo(a=1, b=2, c=3)
```

A declared array splices exactly like an unnamed tuple: `...x` on an
`x:[N]T` inserts the `N` entries, it does not insert one array-valued entry.
This is not just a convenience for building tuples. It is also the spelling
that bit packing depends on: `#[..]` is the packed bit vector of a tuple (the
bit packing rules live in [internals](10-internals.md)), and it only ever sees
a flat entry list. An entry of a tuple literal that is itself a tuple or an
array is a compile error, because a nested entry has no obvious place in a
linear bit layout. `...` is how the nesting is removed, at the position where
the reader can see it.

```pyrope
const stages:[4]U8 = (1,2,3,4)
const inp:U8 = 5

const regw:U40 = (...stages, inp)#[..]  // 5 flat entries: stages[0] at bit 0
const bad:U40  = (stages, inp)#[..]     // error: splice the array entry -- `...stages`
const all:U32  = stages#[..]            // OK: `stages` IS the tuple being packed
```

## Field access

Since everything is a tuple, any scalar or unnamed variable can do
`variable[0][0][0]` because it literaly means, return the tuple first entry
for three times.


Another useful shortcut is when a tuple has a single field or entry, the tuple
contents can be accessed without requiring the individual position or field
entry name. This is quite useful for function return tuples with a single
entry. A named tuple is still never indexed by position.

```pyrope
const x = (const first=(const second=3))

cassert(x.first.second == 3)
cassert(x.first        == 3)
cassert(x              == 3)
cassert(x[0]           == 3)  // error: `x` is a named tuple, use `x.first`

const s = ((3))
cassert(s[0][0] == 3 and s == 3)
```


Tuples can also use structural binding to unpack a tuple multiple fields into
separate variables. A named tuple binds by name (see
[named-tuple destructuring](#named-tuple-destructuring)), an unnamed one by
position.

```pyrope
const x = (const f1=(const f1a=1, const f1b=3), const f2=4)

const (f1,f2) = x
cassert(f1.f1a == 1 and f1.f1b == 3 and f2 == 4)
cassert(f1 == (const f1a=1, const f1b=3))

const (y,z) = x   // error: `y` and `z` are not fields of `x`

const w = ((1,3), 4)
const (w1,w2) = w
cassert(w1 == (1,3) and w2 == 4)
```

## Tuples vs arrays

Tuples are ordered, as such, it is possible to use them as arrays. Tuples and
arrays share most behavior/operations, the key difference is that arrays are
unnamed with the same type for all the entries. That same order is the bit
order: `t#[..]` places entry 0 at bit 0 and stacks each later entry above it
(see [internals](10-internals.md)).

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
  res2 = array[index]     // OK
}
```

Pyrope compiler will allow an index of an array/tuple with unknowns. If the
index has unknown bits (`0sb?` or `0ub1?0`) but the compiler can not know, the
result will have unknowns (see [internals](10-internals.md) for more details).
Notice that the only way to have unknowns is that somewhere else a variable or
a memory was explicitly initialized with unknowns. Unlike Verilog, Pyrope has
no implicit unknown initialization: every declaration supplies its value.


### Concatenate fields

Each tuple field must be unique. Inside a tuple literal a field may only be
introduced once, and only with a plain `=`. Repeating a field name is an
error, and so is a compound assignment (`+=`, `-=`, ...) inside the literal —
there is no prior value to update while the tuple is still being built.

```pyrope
mut x = (
  ,mut ff = 1
  ,mut ff = 2   // error: 'ff' already declared in the tuple
)

mut y = (
  ,mut ff = 1
  ,ff += 2  // error: compound assignment is not allowed inside a tuple literal
  ,zz += 3  // error: compound assignment is not allowed inside a tuple literal
)
```

To extend a tuple — adding fields or growing an overload set — splice the
original into a new tuple with `...`:

```pyrope
const y  = (const ff=1, const zz=3)
const y2 = (...y, const qq=2)    // y2 == (ff=1, zz=3, qq=2)

const ops  = [add1, add2]
const ops2 = (...ops, add3)      // extend the overload set into a new binding
```

A `mut` variable that is *already* a tuple may also self-assign — the base
type does not change, only the arity grows. This is the array-comprehension
idiom:

```pyrope
mut acc:[] = nil
for i in 0..<3 { acc = (...acc, i) }
cassert(acc == (0,1,2))
```

Self-splicing a non-tuple value is the one case that fails: `mut s = 5; s =
(...s, 1)` would redefine `s`'s base type from a scalar to a tuple, a compile
error. Use a fresh binding (`mut xx = (...s, 1)`) when the source is not
already a tuple.




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
y2 = match mut one=1 ; (one, ...z) {  // same as: y2 = match (1,z) {
  == (1,2) { 4 }
  else     { 0 }
}

comb addb(a, b:U32) -> (a:U32) {
  wrap a = a + b
}
```

A tuple on the left-hand side of an assignment mutates or declares multiple
variables at once. Its parenthesis can not be omitted, and neither can the
parenthesis of the tuple on the right-hand side. The reason is that it is a
bit confusing.

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
* A slot is a bare name or a `local = source.path` rename, never a typed
  name: `const (a:U32, b) = r` is an error.

```pyrope
comb dox(a) -> (b, c) { b = a + 1; c = a + 2 }
comb deep(a) -> (payload, code) { payload = (const inner = (const value = a + 1)); code = a + 10 }

(b, c) = dox(a=3)        // local `b` ← dox.b, local `c` ← dox.c
(c, b) = dox(a=3)        // same: order doesn't matter
(x=dox.b, y=dox.c) = dox(a=3)  // rename: dox.b → x, dox.c → y
(v=deep.payload.inner.value) = deep(a=3) // nested field selection
(y, x) = dox(a=3)        // error: `y` is not a field of dox's return
```

When the RHS is an **unnamed** tuple (no field labels — e.g. a literal
`(2, 3)`), there are no names to match against, so destructuring
falls back to positional binding by tuple index:

```pyrope
mut (a, b) = (2, 3)      // a=2, b=3 (positional — RHS has no names)
mut (b, a) = (2, 3)      // a=3, b=2 (still positional)
```

An assignment target is a name, a field (`a.b`), a selector (`a[i]`), a
bit-select (`a#[3]`), or a tuple of names for destructuring; `(a, b) = fcall()`
is a statement. A destructuring tuple holds only names and
`local = source.path` slots, never a field, selector, or bit-select target.
A call, an operator expression, or a literal is not a target, nor the root of
one, inside a left-hand tuple or not. An assignment used as a value is an
error, and so is a destructuring inside an expression or an init clause:

```pyrope
f(x) = 3                  // error: `f(x)` is not an assignment target
a + b = 3                 // error: `a + b` is not an assignment target
f(x).a = 3                // error: a target cannot be rooted at a call
(a + b).c = 3             // error: a target cannot be rooted at an expression
(a, f(x)) = g()           // error: `f(x)` is not an assignment target
(a.b, c[1]) = g()         // error: destructuring slots are names only
(self.c, self.d) = g()    // error: destructuring slots are names only
(1) = 2                   // error: a literal is not an assignment target
const q = ((a, b) = g())  // error: an assignment is a statement, not a value
const r = (f(x) = 1)      // error: an assignment is a statement, not a value
if (a, b) = g(); a { }    // error: no destructuring in an init clause
```

One thing to remember is that the `=` separates the statement in two parts
(left and right), this is not the case with type or attributes that always
apply to the immediatly declared variable or item.

```pyrope
const c = 4
cassert(c does U3) // type check on 'c' is a separate statement
const (x, b) = (true, c)           // assign x=true, b=4

cassert(x == true)
cassert(b == 4)
```

### Destructuring is not a bit layout

A destructuring pattern binds names, it does not describe a bit layout. The
layout of a bit unpack must come from a declared *type*, never from how many
names happen to appear on the left of an `=`. Otherwise renaming a local, or
adding one more, would silently re-cut the bits of the right-hand side, and
nothing on the line would say that it had happened.

```pyrope
const b:U8 = 0xA5

const x:[2]U4 = b#[..]         // OK: the array type states the layout
const (lo:U4, hi:U4) = b#[..]  // error: slots never carry a type, names are not a layout
```

A uniform-width unpack is therefore spelled with an array destination, where
every entry width comes from the one declared entry type. Mixed widths have no
packing spelling by design: when the pieces are not all the same size, say the
ranges yourself.

```pyrope
const lo3 = b#[0..=2]    // 3 bits
const hi5 = b#[3..=7]    // 5 bits
```

## Enumerate (`enum`)

Enumerates, or enums for short, use the familiar tuple structure, but there is
a significant difference in initialization. Enums require named tuples, but in
most cases the named tupled should not have a set value. Enums automatically
assigns values, tuples need explicit value initialization. Each entry is a
field of the enum (`E.a`), so like any field it can not be spelled as a bare
type word: `enum E = (a, U8)` is an error (write `` `U8` ``).

```pyrope
const b = "foo"
const c = 1
enum Test1 = (a=c, b)            // OK
const something = (b)            // OK
cassert(something == "foo")
cassert(Test1.a != Test1.b)
cassert(Signed(Test1.a)==1 and Signed(Test1.b)==2)

const test2 = enum(a, b)         // error: no expression form, write `enum Test2 = (a, b)`
```

The `enum` keyword does not reference scope variables unless the reference is
on the right-hand-side.


If an external variable wants to be used as a field, there has to be an explicit
expression with a string type or a named tuple.

```pyrope
const a = "field"
const c = (const foo=4)
enum Other = (...a, b=3, ...c)
cassert(Other.field != Other.b)
cassert(Other.b   == 3)
cassert(Other.foo == 4)
cassert(Other.foo != Other.b)
```

The enum default values are NOT like typical non-hardware languages. The enum
auto-created values use a one-hot encoding. The first entry has the first bit
set, the 2nd the 2nd bit set. If any entry is given an explicit value (or the
enum has an integer type), the whole enumerate switches to a traditional
sequential numbering.

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
cassert(Signed(V3.a) == 1)
cassert(Signed(V3.b) == 2)
cassert(Signed(V3.c) == 4)

// Always compare against enum entries, not raw values:
mut state:V3 = V3.a
cassert(state == V3.a) // correct
// cassert(state == 1)      // discouraged: relies on encoding details

enum V4 = (
   ,a
   ,b=5
   ,c
)
cassert(Signed(V4.a) == 0)
cassert(Signed(V4.b) == 5)
cassert(Signed(V4.c) == 6)
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

cassert(Signed(Animal.bird        ) == 0ub000001)
cassert(Signed(Animal.bird.eagle  ) == 0ub000011)
cassert(Signed(Animal.bird.parrot ) == 0ub000101)
cassert(Signed(Animal.mammal      ) == 0ub001000)
cassert(Signed(Animal.mammal.rat  ) == 0ub011000)
cassert(Signed(Animal.mammal.human) == 0ub101000)
```

In general, for each leaf enum, the number of bits is equivalent to the number
of entries in the leaf tuple.

An enum used as a TYPE (a `mod`/`pipe` port `c:Color`, a `reg st:Color`, a
typed local) is an unsigned integer as wide as its widest entry value needs,
so every entry value crosses it unchanged: a default one-hot enum of N
entries is N bits (`V3` above is 3 bits, `V3.a == 0ub001`), an enum with
explicit values numbers sequentially and takes the width of its largest value
(`V4` is 3 bits), and a hierarchical enum takes one bit per node (`Animal` is
6 bits). An integer level type is the type itself, spelled any way an
integer type can be (`enum Op:U8 = (…)`, `enum Op:Unsigned(bits=4) = (…)`, or
through a `type Nib = U4` alias). An enum is only declared with
`enum E = (…)` or `enum E:T = (…)`; there is no expression form, so
`const Color = enum(…)` and `type V = enum(…)` are errors. A one-hot enum holds at most 63 entries (give it an
integer level type for more), and an enum with payloads has no integer
encoding, so it cannot type a port.


It is possible to use a sequence that is more consistent with traditional
programming languages, but this only works with non-hierarchical enumerates
when an integer type (`:Signed`, `:U32`, `:S4` ...) is used. The `=` between the
enum name (or its integer type) and the tuple is required.

```pyrope
enum V5:U8 = (
   ,a
   ,b=5
   ,c
)
cassert(Signed(V5.a) == 0)
cassert(Signed(V5.b) == 5)
cassert(Signed(V5.c) == 6)

enum V6:U8 (a, b)   // error: missing '=', write `enum V6:U8 = (a, b)`
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
cassert(String(E3.l1.l1a) == "E3.l1.l1a")
cassert(String(E3.l1) == "E3.l1")
cassert(E3("l1.l1b") == E3.l1.l1b)
```

### Payload enumerates (tagged unions)

Enum cases can carry a typed payload, which makes the enum a tagged union.
Only the active case can be read; reading any other case is a compile error.

```pyrope
enum Vtype = (str:String, num:Signed, b:Bool)

mut vv:Vtype = (num=0x65)
cassert(vv.num == 0x65)
const xx = vv.str                // error: active case is `num`

const x1a:Vtype = "hello"        // implicit case selection by payload type
const x1b:Vtype = (str="hello")  // explicit case
cassert(x1a.str == "hello" and x1a == "hello")
const err = x1a.num              // error: active case is `str`
```

Recursive enum payloads and recursive-enum algebraic data types are not part
of the language. Nested enums remain supported as described above.
