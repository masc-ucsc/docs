
# LNAST

This document is to showcase some of the Pyrope to LNAST translation. This is
useful to have a more "formal" description of the language semantics.


## Variable names

LNAST does not rename variables to be SSA, it relies in a symbol table to track
past entries. Nevertheless, to reduce amount of tracking information when a
variable starts with underscores (`___foo` or `_._foo`), the variable can not
be updated, BUT it is still legal to update tuple fields inside `___foo` like
`___foo.bar = 3`. Program variables names that do not need SSA (`const`) can use
`_._foo` to reduce tracking. Special variable names like the ones needing an
underscore use double tick in the name `_foo here`. Those are special variables
names that do not allow to use compact tuple representation like `foo here.field`.

=== "Pyrope"
    ```pyrope
    const x = 3 + 1
    mut z = 4
    `foo x` = x + z + 2
    ```

=== "LNAST direct"
    ```lnast
    plus
      ref ___1
      const 3
      const 1
    declare
      ref  x
      prim_type_none
      const "const"
      ref  ___1
    declare
      ref z
      prim_type_none
      const "mut"
      const 4
    plus
      ref ___2
      ref x
      ref z
      const 2
    store
      ref `foo x`
      ref ___2
    ```

=== "LNAST optimized"
    ```lnast
    plus
      ref ___1
      const 3
      const 1
    declare
      ref  x
      prim_type_none
      const "const"
      ref  ___1
    declare
      ref z
      prim_type_none
      const "mut"
      const 4
    plus
      ref `foo x`
      ref x
      ref z
      const 2
    ```

The two LNAST nodes to declare and to set values in variables are `declare` and
`store`. A `declare` carries the type and the storage qualifier (`"const"`,
`"mut"`, `"reg"`, ...) plus an optional initial value; a `store` writes a value
into an already declared variable. A type on a plain `store` write is a separate
`type_spec` statement. Attributes are never sub-nodes of `ref`; they are set
with separate `attr_set` statements.

=== "Pyrope"
    ```pyrope
    const a:u2:[foo] = b

    x:u2:[foo] = y
    ```

=== "LNAST"
    ```lnast
    declare
      ref a
      prim_type_int
        const 3
        const 0
      const "const"
      ref b
    attr_set
      ref a
      const foo
      const true

    store
      ref x
      ref y
    type_spec
      ref x
      prim_type_int
        const 3
        const 0
    attr_set
      ref x
      const foo
      const true
    ```

## Tuples

Tuples are sequences of fields that can be named. Unnamed (positional)
fields are ordered; named fields are unordered and accessed by name only
(tools may canonicalize named fields alphabetically, but that is a
convention, not a requirement). There are LNAST tuple
specific nodes (`tuple_add`, `tuple_get`, `tuple_concat`) but in many
cases the direct LNAST operations can handle tuples directly.

* `tuple_add` creates a new tuple with entries
* `store` adds/updates a field to an existing tuple. A `store` with 3 or more
  children is a field write (the tuple, one or more field levels, and the
  value); with 2 children it is a plain scalar write.
* `tuple_get` gets the contents of a tuple entry
* `tuple_concat` concatenates two or more tuples

Direct access in operations like `plus` behave like a `store` or `tuple_get`.


=== "Tuple in Pyrope"
    ```pyrope
    x = 3
    a = (mut b=2, mut x=x+1, mut y=b+1)
    ```

=== "LNAST direct"
    ```lnast
    store
      ref      x
      const    3
    store
      ref      ___t1
      const    2
    plus
      ref      ___t2
      ref      x
      const    1
    plus
      ref      ___t3
      ref      ___t1
      const    1
    tuple_add
      ref      a
      store
        ref      b
        ref      ___t1
      store
        ref      x
        ref      ___t2
      store
        ref      y
        ref      ___t3
    ```

=== "LNAST optimized"
    ```lnast
    store
      ref      x
      const    3
    plus
      ref      ___t2
      ref      x
      const    1
    plus
      ref      ___t3
      const    2
      const    1
    tuple_add
      ref      a
      store
        ref      b
        const   2
      store
        ref      x
        ref      ___t2
      store
        ref      y
        ref      ___t3
    ```

=== "LNAST Alternative"
    ```lnast
    store
      ref      x
      const    3
    declare
      ref      a
      prim_type_none
      const    "mut"
      ref      2
    plus
      ref      ___t1
      ref      x
      const    1
    declare
      ref      a.1x
      prim_type_none
      const    "mut"
      ref      ___t1
    plus
      ref      ___t2
      const    a
      const    1
    declare
      ref     a.2y
      prim_type_none
      const    "mut"
      ref     ___t2
    ```

`store` and `tuple_get` can access through several levels in one command.
`tuple_add` does not allow recursive entrances, it requires intermediate tuple
construction. `attr_get` and `attr_set` follow the same syntax as
`tuple_get`/`store`.

=== "Pyrope"
    ```pyrope
    x = tup[1].foo[xx]
    tup[4].foo[yy] = y

    z = (mut foo=(mut bar=1))
    ```

=== "LNAST"
    ```lnast
    tuple_get
      ref x
      ref tup
      const 1
      const foo
      ref xx

    store
      ref tup
      const 4
      const foo
      ref yy
      ref y

    tuple_add
      ref ___1
      store
        ref bar
        const 1

    tuple_add
      ref z
      store
        ref foo
        ref ___1
    ```


Tuples can use `const` in a field declaration to indicate that the field is
immutable.

=== "Tuple in Pyrope"
    ```pyrope
    mut a = (mut b=2, const x=1+1)
    ```

=== "LNAST direct"
    ```lnast
    store
      ref    ___t1
      const  2
    plus
      ref    ___t2
      const  1
      const  1
    tuple_add:
      ref     a
      store
        ref     b
        ref     __t1
      store
        ref     x
        ref     ___t2
    tuple_get
      ref     ___m1
      ref     a
      const   b
    declare
      ref     ___m1
      prim_type_none
      const   "mut"
    ```

The field payloads are plain `store` entries; a `mut` field is marked by a
`tuple_get` of the field followed by a `declare` with a `"mut"` qualifier. A
field with no such `declare` is immutable.

Tuple concatenation does not use `plus` but the `tuple_concat` operator.

=== "Tuple in Pyrope"
    ```pyrope
    mut a = (2, 1+1)
    const x = (...a, const c=3, 1)
    ```

=== "LNAST direct"
    ```lnast
    store
      ref    ___1
      const  2
    plus
      ref    ___2
      const  1
      const  1
    tuple_add:
      ref    ___33
      ref    ___1
      ref    ___2
    declare
      ref    a
      prim_type_none
      const  "mut"
      ref    ___33
    tuple_add
      ref    ___3
      const  c
      const  3
    tuple_concat
      ref    ___4
      ref    a
      ref    ___3
      const  1
    declare
      ref    x
      prim_type_none
      const  "const"
      ref    ___4
    ```

## Attributes

There are 2 LNAST nodes for attributes: `attr_set` and `attr_get`. They operate
at statement level and follow the same syntax as `store`/`tuple_get`, where the
last entry is the attribute name. Attributes never appear as sub-nodes of
`ref`; an attribute set or check is always its own statement.

Attribute checks lower through `attr_get` followed by a `cassert` (or
`attr_get` followed by a comparison and `cassert` for more complex checks).

Attribute set declarations like `a::[f=3,b]` lower to the assignment plus one
`attr_set` per attribute. The same pattern applies to attributes set on tuple
entries.

=== "Pyrope"
    ```pyrope
    a::[f=3,b] = 1
    x = (y::[z=7]=2, 4)
    ```

=== "LNAST"
    ```lnast
    store
      ref a
      const 1
    attr_set
      ref a
      const f
      const 3
    attr_set
      ref a
      const b
      const true

    tuple_add
      ref ___1
      store
        ref y
        const 2
      const 4
    attr_set
      ref ___1
      const y
      const z
      const 7
    store
      ref x
      ref ___1
    ```

Attribute reads (`var.[attr]`) appear anywhere a normal expression is
allowed and lower to `attr_get`. To turn a read into a check, wrap it in
`cassert`/`assert`; that lowers to `attr_get` followed by an `fcall` to
`cassert`. More complex attribute comparisons go through `attr_get`, a
comparison node, and then `cassert`.

=== "Pyrope"
    ```pyrope
    const z = q.[y]
    const y = a.[b] + 1
    ```

=== "LNAST"
    ```lnast
    attr_get
      ref ___1
      ref q
      const y
    declare
      ref z
      prim_type_none
      const "const"
      ref ___1

    attr_get
      ref ___2
      ref a
      const b
    plus
      ref ___3
      ref ___2
      const 1
    declare
      ref y
      prim_type_none
      const "const"
      ref ___3
    ```


### Sticky attributes


Attributes can be sticky or not. A sticky attribute "polutes" or keeps
the attribute to the left-hand-side expression. Non-sticky attributes
do not affect or propagate.


Attributes are not sticky by default, but some like `debug` are sticky.
This means that if any of the elements in any operation has a `debug`
attribute, the result also has a `debug` attribute. There is no way to
remove these attributes.

=== "Pyrope"
    ```pyrope
    const d::[debug] = 3

    mut a = d + 100

    cassert(a.[debug]) // debug is sticky
    ```

=== "LNAST"
    ```lnast
    declare
      ref d
      prim_type_none
      const "const"
      const 3
    attr_set
      ref d
      const debug
      const true

    plus
      ref ___tmp
      ref d
      const 100

    declare
      ref a
      prim_type_none
      const "mut"
      ref ___tmp

    attr_get
      ref ___get
      ref a
      const debug

    fcall
      ref ___unused
      ref cassert
      ref ___get
    ```

Once a variable gets assigned an attribute, the attribute stays with the
variable and any variables that got a direct copy. The only way to remove it is
with arithmetic operations and/or bit selection.


```pyrope
const foo::[attr1=2] = 3

mut foo2 = foo
cassert(foo2.[attr1] == 2)

const foo3 = foo#[..]
cassert(foo3.[attr1] == nil) // bit selection drops attributes

mut xx::[attr2=5] = 1                 // sets attr2 at declaration

const xx2 = xx
cassert(xx2.[attr2] == 5)
cassert(xx2.[attr2] != nil)

const xx3 = xx + 0
cassert(xx3.[attr2] == nil) // dropped after arithmetic
```


## Bit selection


Pyrope has several bit selection operations. The default maps `get_mask` and
`set_mask` LNAST nodes. One important thing is that both `get_mask` and
`set_mask` operate over a MASK. This means that it is a one-hot encoding if a
single bit is operated. The one-hot encoding can be created with a `range` or
with a `shl` operator.


The selector takes a single expression (bit index or range). To write
non-contiguous bits, emit one assignment per range — each lowers to its own
`set_mask`.

=== "Pyrope"
    ```pyrope
    foo#[1..=2] = xx
    yy = foo#[5] + xx#[1..<4]
    ```

=== "LNAST direct"
    ```lnast
    range
      ref ___r
      const 1
      const 2
      const 1

    set_mask
      ref foo
      ref foo
      ref ___r
      ref xx

    range
      ref ___c5
      const 5
      const 5
      const 1

    get_mask
      ref ___3
      ref foo
      ref ___c5

    range
      ref ___4
      const 1
      const 3
      const 1

    get_mask
      ref ___5
      ref xx
      ref ___4

    plus
      ref yy
      ref ___4
      ref ___5
    ```

=== "LNAST optimized"
    ```lnast
    range
      ref ___r
      const 1
      const 2
      const 1

    set_mask
      ref foo
      ref foo
      ref ___r
      ref xx

    get_mask
      ref ___3
      ref foo
      const 5

    range
      ref ___4
      const 1
      const 3
      const 1

    get_mask
      ref ___5
      ref xx
      ref ___4

    plus
      ref yy
      ref ___4
      ref ___5
    ```

It is possible to use a `foo#sext[range]` to perform a bit selection with sign
extension. The `sext` LNAST node is equivalent to the Lgraph `sext` that has 2
inputs. The variable and from what bit to perform sign-extension. This means
that the LNAST translation needs a `get_mask` and a `sext` node. The `sext`,
`+`, `|`, `^` bit selection modifiers can only be applied to right-hand-side
operations.


=== "Pyrope"
    ```pyrope
    const t1 = foo#sext[..=4]
    const t2 = foo#|[..=4]
    const t3 = foo#&[..=4]
    const t4 = foo#^[..=4]
    const t5 = foo#+[..=4]
    ```

=== "LNAST"
    ```lnast
    range
      ref ___r
      const 0
      const 4
      const 1

    get_mask
      ref ___t
      ref foo
      ref ___r

    sext
      ref ___t1
      ref ___t
      const 4
    declare
      ref t1
      prim_type_none
      const "const"
      ref ___t1

    red_or
      ref ___t2
      ref ___t
    declare
      ref t2
      prim_type_none
      const "const"
      ref ___t2

    red_and       // red_and(x) returns unsigned 0 or 1
      ref ___t3
      ref ___t
    declare
      ref t3
      prim_type_none
      const "const"
      ref ___t3

    red_xor
      ref ___t4
      ref ___t
    declare
      ref t4
      prim_type_none
      const "const"
      ref ___t4

    popcount
      ref ___t5
      ref ___t
    declare
      ref t5
      prim_type_none
      const "const"
      ref ___t5
    ```

## Direct LNAST/Lgraph call


A direct Lgraph call can be done with `__cell` where `cell` is the Lgraph cell
like `plus`, `LUT`, `memory`. In LNAST this is translated like a lambda call.


=== "Pyrope"
    ```pyrope
    const foo = 3
    const bar = 300
    const b = __plus(1,2,foo,bar)
    ```

=== "LNAST"
    ```lnast
    declare
      ref foo
      prim_type_none
      const "const"
      const 3
    declare
      ref bar
      prim_type_none
      const "const"
      const 300
    tuple_add
      ref ___0
      const 1
      const 2
      ref foo
      ref bar
    fcall
      ref b
      ref __plus
      ref ___0
    ```

A direct LNAST call can be done calling an LNAST method, where the first entry
is the root LNAST node, and rest follow a tree syntax with strings.

=== "Pyrope"
    ```pyrope
    LNAST("let", ("ref", "x"), ("const", "5"))
    ```

=== "LNAST"
    ```lnast
    let
      ref x
      const 5
    ```

## Basic operators

Basic operators are binary or unary operators in Pyrope that have a one-to-one
translation to LNAST nodes.

### Unary

* `!a` or `not a` translates to `log_not`
* `~a` translates to `bit_not`
* `-a` translates to `minus(0,a)`

### Binary integer

* `a + b` translates to `plus`
* `a - b` translates to `minus`
* `a * b` translates to `mult`
* `a / b` translates to `div`
* `a & b` translates to `bit_and`
* `a | b` translates to `bit_or`
* `a ^ b` translates to `bit_xor`
* `a >> b` translates to `sra`
* `a << b` translates to `shl`


There is a `mod` LNAST operator that performs module operations. It does not
have a direct Pyrope syntax, but it can be called directly `__mod(a,b)`.

### Binary boolean

* `a and b` translated to `log_and`
* `a or b` translates to `log_or`


## Complex operators

Complex operators are binary operators in Pyrope that require more than one
LNAST statement.

### Binary integer

Binary nand (`x=a ~& b`):
```lnast
bit_and
  ref ___0
  ref a
  ref b
bit_not
  ref x
  ref ___0
```

Binary nor (`x=a ~| b`):
```lnast
bit_or
  ref ___0
  ref a
  ref b
bit_not
  ref x
  ref ___0
```

Binary xor (`x=a ~^ b`):
```lnast
bit_xor
  ref ___0
  ref a
  ref b
bit_not
  ref x
  ref ___0
```

Logical shift right (`x = a#[..] >> b`):
```lnast
get_mask
  ref ___0
  ref a
sra
  ref x
  ref ___0
  ref b
```

### Binary logical


Logical implication (`x = a implies b`):
```lnast
log_not
  ref ___0
  ref a
log_or
  ref x
  ref ___0
  ref b
```

Logical nand (`x = not (a and b)`):
```lnast
log_and
  ref ___0
  ref a
  ref b
log_not
  ref x
  ref ___0
```

Logical nor (`x = not (a or b)`):
```lnast
log_or
  ref ___0
  ref a
  ref b
log_not
  ref x
  ref ___0
```

Logical not implication (`x = not (a implies b)`):
```lnast
log_not
  ref ___0
  ref b
log_and
  ref x
  ref a
  ref ___0
```

### Tuple/Set operators

The `in` operator does not have a Lgraph equivalent becuase it is type
dependent: tuple, range, or enumerate. The range and enumerate can get
translated to an AND gate over the bitcode translation, but the tuple check
requires a tuple check.

```pyrope
const tup=(1,2,3)
const ran=1..<5
const enu = enum(a,b=(x,y),c)

cassert(2 in tup)
cassert(3 in ran)
cassert(enu.b.x in enu.b)
```

The resul is a common `in` LNAST operation that gets different functionality
dependent on the input type.


=== "Pyrope"
    ```pyrope
    c = a in b
    d = not (a in b)
    ```

=== "LNAST"
    ```lnast
    in
      ref c
      ref a
      ref b
    log_not
      ref d
      ref c
    ```

The tuple concatenate operator is the `...` splice. `x = (...a, ...b)`
translates to:

```lnast
tuple_concat
  ref x
  ref a
  ref b
```

Tuple concat recursively merges matching tuple-valued fields. A duplicate final
field is accepted when one side is `nil` or constant propagation proves both
sides have the same value; otherwise it is an overlap and triggers a compile
error.

`x = (a, ...b)` translates to:
```lnast
tuple_concat
  ref x
  ref a
  ref b
in
  ref ___1
  ref a
  ref x
in
  ref ___2
  ref b
  ref x
log_and
  ref ___3
  ref ___1
  ref ___2
fcall
  ref ___0
  ref cassert
  ref ___3
```

### Tuple to operator

The `to` is an iterator but instead of a range, it creates a tuple.


`tmp = a to b by c` translates to:
```lnast
to
  ref tmp
  ref a
  ref b
  ref c
```

`tmp = 3 to b` translates to:
```lnast
to
  ref tmp
  const 3
  ref b
  const 1
```

### Range operator

Ranges can be open or closed. The closed ranges have the start/end/step
defined.

`x = a..<=b by 2` translates to:
```lnast
range
  ref x
  ref a
  ref b
  const 2
```

`x = a..<=b by 2` translates to:
```lnast
range
  ref x
  ref a
  ref b
  const 2
```

`x = a..<b` translates to:
```lnast
minus
  ref tmp
  ref b
  ref 1

range
  ref x
  ref a
  ref tmp
  const 1
```

### Type operators

To check if a field name or position exists in a tuple, `x = a has b` translates:
```lnast
has
  ref x
  ref a
  ref b
```

To check the tuple structure, Pyrope has `a does b`. It returns true if `a`
provides all the tuple structure required by `b`; in other words, `a` may have
extra fields, but it must contain the required fields from `b`. `x = a does b`
translates to:
```lnast
does
  ref x
  ref a
  ref b
```

To check equality of tuples `x = a equals b` same as `x = (a does b) and (b does a)`. Translates to:
```lnast
does
  ref ___0
  ref a
  ref b
does
  ref ___1
  ref b
  ref a
log_and
  ref x
  ref ___0
  ref ___1
```

The `a case b` does match operation. `a case b` first checks `a does b`, then
checks that every defined value in `b` has the same value in `a`. Undefined
values in `b` (`nil`, `0sb?`) act as wildcards and do not participate in the
value check. `x = a case b` translates to:
```lnast
does
  ref ___0
  ref a
  ref b
in
  ref ___1
  ref b
  ref a
log_and
  ref x
  ref ___0
  ref ___1
```

## if/unique if


Like many modern languages, `if` accepts not only a boolean expression but a
sequence of statements. Like C++17, before a condition, there can be a sequence
of statements that can include variable declarations. Pyrope variables initial
statement declarations are visiable in the `if` and `else` statements like
C++17 does.


A special constraint from Pyrope is that the initial statements and condition
check can not have side-effects. Hence, they can not have `procedure` calls,
only `function` calls.

=== "Pyrope"
    ```pyrope
    mut total=3
    if mut x=3; x<3 {
      total+=x
    }elif mut z=3; z<4 {
      total+=x+z
    }
    ```

=== "Pyrope Equivalent"
    ```pyrope
    mut total=3
    {
      mut x=3
      if x<3 {
        total+=x
      }else{
        mut z=3
        if z<4 {
          total+=x+z
        }
      }
    }
    ```

=== "C++17 equivalent"
    ```c++
    int total=3;
    if (int x=3; x<3) {
      total+=x;
    }else if (int z=3; z<4) {
      total+=x+z;
    }
    ```

Pyrope has `if` and `unique if`. The difference is that `unique if` guarantees
that only one of the branch conditions is taken. It is possible to have all the
conditions not taken. This allows synthesis optimizations because it implies
that the condition is a one-hot encoding.


=== "Pyrope"
    ```pyrope
    if mut x=a ; x<3 {
      t = 100+x               // z not in scope
    }elif mut z = x+c ; z>5 {
      t = 200+z+x             // z and x in scope
    }
    ```

=== "LNAST"
    ```lnast
    stmts
      declare
        ref x
        prim_type_none
        const "mut"
        ref a
      lt
        ref ___1
        ref x
        const 3
      if
        ref ___1
        stmts
          plus
            ref t
            const 100
            ref x
        stmts
          plus
            ref ___2
            ref x
            ref c
          declare
            ref z
            prim_type_none
            const "mut"
            ref ___2
          gt
            ref ___3
            ref z
            const 5
          if
            ref ___3
            stmts
              plus
                ref t
                const 200
                ref z
                ref x
    ```

The `unique if` is similar, but all the conditions include an `assume`
directive to be checked. This means that the conditions must be checked even if
the `else` is not reached. This is fine because neither the statements nor the
condition checks are allowed to have side-effects.


An important limitation of `unique if` is that only the first condition can
have initial statement. It is not allowed to have initialization statements in
the `elif` conditions.

=== "Pyrope"
    ```pyrope





    unique if a<3 {
      y = 10
    }elif a>40 {  // not allowed to do 'elif mut z=40; a>z'
      y = 20+x
    }
    ```

=== "Pyrope Equivalent"
    ```pyrope
    const tmp1 = a<3
    const tmp2 = a>40
    const tmp3 = 1<<(tmp1,tmp2)
    assume(tmp3#+[..]<=1) // at most one bit set

    if tmp1 {
      y = 10
    }elif tmp2 {
      y = 20+x
    }
    ```

=== "LNAST"
    ```lnast
    lt
      ref ___1
      ref z
      const 3
    gt
      ref ___2
      ref a
      const 40
    shl           // create one-hot encoding
      ref ___3
      const 1
      ref ___1
      ref ___2
    popcount
      ref ___4
      ref ___3
    le
      ref ___5
      ref ___4
      const 1
    fcall
      ref nil
      ref assume
      ref ___5
    uif
      ref ___1
      stmts
        store
          ref y
          const 10
      ref ___2
      stmts
        plus
          ref y
          const 20
          ref x
    ```

## match

The match statement behaves like a `unique if` but it also checks that at least
one of the paths is taken. This means that if the `else` exists in the match,
it behaves like a `unique if`. If the else does not exist, an `else { assert
false }` is created.


=== "Pyrope"
    ```pyrope
    mut z = 0
    match x {
     == 3 { z = 1 }
     in 4..<6 { z = 2 }
     else { }
    }

    match x {
     <  5 { z = 1 }
     else { z = 3 }
    }
    ```

=== "LNAST"
    ```lnast
    declare
      ref z
      prim_type_none
      const "mut"
      const 0

    eq
      ref ___0
      ref x
      const 3
    range
      ref ___2
      const 4
      const 5
    in
      ref ___1
      ref x
      ref ___2

    shl
      ref ___3
      const 1
      ref ___1
      ref ___2
    popcount
      ref ___4
      ref ___3
    le
      ref ___5
      ref ___4
      const 1
    fcall
      ref nil
      ref assume
      ref ___5

    uif
      ref ___1
      stmts
        store
          ref z
          const 1
      ref ___2
      stmts
        store
          ref z
          const 2
      stmts
        fcall
          ref ___6
          ref assert
          const false

    // 2nd match
    lt
      ref ___6
      ref x
      const 5
    shl
      ref ___7
      const 1
      ref ___6
    popcount
      ref ___8
      ref ___7
    le
      ref ___9
      ref ___8
      const 1
    fcall
      ref nil
      ref assume
      ref ___9
    uif
      ref ___6
      stmts
        store
          ref z
          const 1
      stmts
        store
          ref z
          const 3
    ```



## Scope

Like most languages Pyrope has variable scope, but it does not allow variable
shadowing. This section showcases some cases on how the scope is generated.


New variables can have a statement scope for `if`, `while`, and `match`
statements.

=== "Pyrope"
    ```pyrope
    if mut x=3; x<4 {
      cassert(x==3)
    }
    while mut z=1; x != 0 {
      x -= z
    }
    mut z=0
    match mut x=2 ; z+x {
      == 2 { cassert(true)  }
      != 7 { cassert(true)  }
      else { cassert(false) }
    }
    ```

=== "LNAST"
    ```lnast
    stmts
      declare
        ref x
        prim_type_none
        const "mut"
        const 3
      lt
        ref ___1
        ref x
        const 4
      if
        ref ___1
        stmts
          eq
            ref ___2
            ref x
            const 3
          fcall
            ref ___0
            ref cassert
            ref ___2

    stmts
      declare
        ref z
        prim_type_none
        const "mut"
        const 1
      while
        if
          ref x
          stmts
            break
        minus
          ref x
          ref x
          ref z

    declare
      ref z
      prim_type_none
      const "mut"
      const 0
    stmts
      declare
        ref x
        prim_type_none
        const "mut"
        const 2
      plus
        ref ___3
        ref z
        ref x
      eq
        ref ___t1
        ref ___3
        const 2
      ne
        ref ___t2
        ref ___3
        const 7
      shl           // create one-hot encoding
        ref ___x
        const 1
        ref ___t1
        ref ___t2
      popcount
        ref ___y
        ref ___x
      le
        ref ___z
        ref ___y
        const 1
      fcall
        ref nil
        ref assume
        ref ___z
      uif
        ref ___t1
        stmts
          fcall
            ref ___4
            ref cassert
            const true
        ref ___t2
        stmts
          fcall
            ref ___5
            ref cassert
            const true
        stmts
          fcall
            ref ___6
            ref cassert
            const false
    ```

## while/loop/for


Pyrope has `loop`, `while`, and `for` constructs to handle different types of loops.
In all the cases, the loops must be expanded at LNAST compile time. In LNAST, there
is only a `while` construct.

=== "Pyrope loop"
    ```pyrope
    loop {
      i += 1
      if i==3 { break }
    }
    ```

=== "LNAST"
    ```lnast
    while
      plus
        ref i
        ref i
        const 1
      eq
        ref ___1
        ref i
        const 3
      if
        ref ___1
        stmts
          break
    ```

The Pyrope `while` translates to a `while` node with a `break` statement.

=== "Pyrope while"
    ```pyrope
    while mut i=0 ; i!=3 {
      i += 1
    }
    ```

=== "LNAST"
    ```lnast
    stmts
      declare
        ref i
        prim_type_none
        const "mut"
        const 0
      while
        ne
          ref ___1
          ref i
          const 3
        log_not
          ref ___2
          ref ___1
        if
          ref ___2
          stmts
            break
    ```

The `for` construct is also a loop, but it can have element, index, and key in the iterator. Also, it can allow a `ref` to mutate the contents.

=== "Pyrope for"
    ```pyrope
    for (index,value,key) in tup {
      mycall(value,index,key)
    }
    ```
=== "Pyrope ref for"
    ```pyrope
    for value in ref tup {
      mycall(value)
      value = 0
    }
    ```
=== "LNAST for"
    ```lnast
    attr_get
      ref ___tup_size
      ref tup
      const size
    gt
      ref ___2
      ref ___tup_size
      const 0
    if
      ref ___2
      stmts
        declare
          ref value
          prim_type_none
          const "mut"
          ref _
        declare
          ref index
          prim_type_none
          const "mut"
          const 0
        declare
          ref key
          prim_type_none
          const "mut"
          const ""
        while
          attr_get
            ref key
            ref tup
            ref index
            const "key"
          tuple_get
            ref value
            ref tup
            ref index
          tuple_add
            ref ___6
            ref index
            ref key
            ref value
          fcall
            ref ___empty
            ref mycall
            ref ___6
          plus
            ref index
            ref index
            const 1
          eq
            ref ___3
            ref ___tup_size
            ref index
          if
            ref ___3
            stmts
              break
    ```
=== "LNAST ref for"
    ```lnast
    attr_get
      ref ___tup_size
      ref tup
      const size
    gt
      ref ___2
      ref ___tup_size
      const 0
    if
      ref ___2
      stmts
        declare
          ref value
          prim_type_none
          const "mut"
          ref _
        declare
          ref index
          prim_type_none
          const "mut"
          const 0
        declare
          ref key
          prim_type_none
          const "mut"
          const ""
        while
          attr_get
            ref key
            ref tup
            ref index
            const "key"
          tuple_get
            ref tup
            ref index
            ref value
          tuple_add
            ref ___6
            ref index
            ref key
            ref value
          fcall
            ref ___empty
            ref mycall
            ref ___6
          store
            ref tup
            ref index
            ref value
          plus
            ref index
            ref index
            const 1
          eq
            ref ___3
            ref ___tup_size
            ref index
          if
            ref ___3
            stmts
              break
    ```


The `for` comprehensions behave similarly, but the `cont`/`brk` statements have
the value that must be concatenated (`tuple_concat`) to the result. If the last
statement is an expression, the value is contatenated.

## puts/print/format

All the string variables must be known at compile time, but it is still OK to
pass strings as arguments to simulation functions that have no side-effects in
the running simulation like `puts` and `print`.

`format` uses C++ fmt::format syntax and returns a string, so it must be solved
at compile time. This means that the LNAST passes should have a `format`
implementation to allow copy propagation to proceed. When format is used, a
single  quote should be used to avoid string interpolation.


The LNAST translation for all these instructions is just a normal function
call. The `format` must be executed at compile time and propagate/copy as
needed. The `puts`/`print` should generate simulation calls but not synthesis
code.


```pyrope
const num = 1
const color = "blue"
const extension = "s"
const text = "I have {num} {color} potato{extension}"
```

String interpolation lowers to string conversions and concatenation. When all
embedded values are known at compile time, the result folds to one string.
There is no `format(...)` built-in.

## Lambda call

A lambda call arguments requires do not always require to be named like when a
variable used matches a calling argument. To support the matching while
processing the LNAST, the arguments tuple must be named for all the arguments
unless an argument is an expression.


=== "Pyrope"
    ```pyrope
    x = fcall(a,b=3,foo,1+2)
    ```
=== "LNAST"
    ```lnast
    plus
      ref ___t
      const 1
      const 2

    tuple_add
      ref ___args
      store
        ref a
        ref a
      store
        ref b
        const 3
      store
        ref foo
        ref foo
      ref ___t

    fcall
      ref x
      ref fcall
      ref ___args
    ```
