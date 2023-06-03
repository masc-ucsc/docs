
# LNAST

This document is to showcase some of the Pyrope to LNAST translation. This is
useful to have a more "formal" description of the language semantics.


## Variable names

LNAST does not rename variables to be SSA, it relies in a symbol table to track
past entries. Nevertheless, to reduce amount of tracking information when a
variable starts with underscores (`___foo` or `_._foo`), the variable can not
be updated, BUT it is still legal to update tuple fields inside `___foo` like
`___foo.bar = 3`. Program variables names that do not need SSA (`let`) can use
`_._foo` to reduce tracking. Special variable names like the ones needing an
underscore use double tick in the name `_foo here`. Those are special variables
names that do not allow to use compact tuple representation like `foo here.field`.

=== "Pyrope"
    ```
    let x = 3 + 1
    var z = 4
    `foo x` = x + z + 2
    ```

=== "LNAST direct"
    ```lnast
    plus
      ref ___1
      const 3
      const 1
    let
      ref  x
      ref  ___1
    var
      ref z
      const 4
    plus
      ref ___2
      ref x
      ref z
      const 2
    assign
      ref `foo x`
      ref ___2
    ```

=== "LNAST optimized"
    ```lnast
    plus
      ref ___1
      const 3
      const 1
    let
      ref  x
      ref  ___1
    var
      ref z
      const 4
    plus
      ref `foo x`
      ref x
      ref z
      const 2
    ```

The three LNAST nodes to set values in variables are `let`/`var`/`assign`. Each can have
types and/or attributes.

=== "Pyrope"
    ```
    let a:u2:[foo] = b:u1:[bar]

    x:u2:[foo] = y:u1:[bar]
    ```

=== "LNAST"
    ```lnast
    set
      ref a
        prim_type_uint
          const 2
        attr_ref_set
          const foo
          const true
      ref b
        prim_type_uint
          const 2
        attr_check
          const bar
          const true

    assign
      ref x
        prim_type_uint
          const 2
        attr_ref_set
          const foo
          const true
      ref y
        prim_type_uint
          const 2
        attr_check
          const bar
          const true
    ```

## Tuples

Tuples are "ordered" sequences that can be named. There are LNAST tuple
specific nodes (`tup_add`, `tup_set`, `tup_get`, `tup_concat`) but in many
cases the direct LNAST operations can handle tuples directly.

* `tup_add` creates a new tuple with entries
* `tup_set` adds/updates a field to an existing tuple.
* `tup_get` gets the contents of a tuple entry
* `tup_concat` concatenates two or more tuples

To indicate the tuple position, identifiers can have `:pos:name`. For example
`x.:3:foo = 2` is legal. It is the same as `x[3] = 2` or `x.foo=2` and check
that entry `3` has label `foo`. This allows to create more compact LNAST.
Direct access in operations like `plus` behave like a `tup_set` or `tup_get`.


=== "Tuple in Pyrope"
    ```
    x = 3
    a = (b=2, x=x+1, y=self.b+1)
    ```

=== "LNAST direct"
    ```lnast
    assign
      ref      x
      const    3
    assign
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
    tup_add
      ref      a
      var
        ref      b
        ref      __t1
      var
        ref      x
        ref      ___t2
      var
        ref      y
        ref      ___t4
    ```

=== "LNAST optimized"
    ```lnast
    assign
      ref      x
      const    3
    plus
      ref      ___t2
      ref      x
      const    1
    plus
      ref      ___t3
      ref      ___t1
      const    1
    tup_add
      ref      a
      var
        ref      b
        const   2
      var
        ref      x
        ref      ___t2
      var
        ref      y
        ref      ___t4
    ```

=== "LNAST Alternative"
    ```lnast
    assign
      ref      x
      const    3
    var
      ref      a.0b
      ref      2
    plus
      ref      ___t1
      ref      x
      const    1
    var
      ref      a.1x
      ref      ___t1
    plus
      ref      ___t2
      const    a.0b
      const    1
    var
      ref     a.2y
      ref     ___t2
    ```

`tup_set` and `tup_get` can access through several levels in one command.
`tup_add` does not allow recursive entrances, it requires intermediate tuple
construction. `attr_get` and `attr_set` follow the same syntax as
`tup_get`/`tup_set`.

=== "Pyrope"
    ```
    x = tup[1].foo[xx]
    tup[4].foo[yy] = y

    z = (foo=(bar=1))
    ```

=== "LNAST"
    ```lnast
    tup_get
      ref x
      ref tup
      const 1
      const foo
      ref xx

    tup_set
      ref tup
      const 4
      const foo
      ref yy
      ref y

    tup_add
      ref ___1
      var
        ref bar
        const 1

    tup_add
      ref z
      var
        ref foo
        ref ___1
    ```


Tuples can have a `let` in declaration to indicate that the field is immutable.

=== "Tuple in Pyrope"
    ```
    var a = (b=2, let x=1+1)
    ```

=== "LNAST direct"
    ```lnast
    assign
      ref    ___t1
      const  2
    plus
      ref    ___t2
      const  1
      const  1
    tup_add:
      ref     a
      var
        ref     b
        ref     __t1
      let
        ref     x
        ref     ___t2
    ```

=== "LNAST Optimized"
    ```lnast
    var
      ref    a.:0:b
      const  2
    plus
      ref    ___2
      const  1
      const  1
    let
      ref    a.:1:x
      ref    ___2
    ```

Tuple concatenation does not use `plus` but the `tup_concat` operator.

=== "Tuple in Pyrope"
    ```
    var a = (2, 1+1)
    let x = a ++ (c=3) ++ 1
    ```

=== "LNAST direct"
    ```lnast
    assign
      ref    ___1
      const  2
    plus
      ref    ___2
      const  1
      const  1
    tup_add:
      ref    ___33
      ref    ___1
      ref    ___2
    var
      ref    a
      ref    ___33
    tup_add
      ref    ___3
      const  c
      const  3
    tup_concat
      ref    ___4
      ref    a
      ref    ___3
      const  1
    let
      ref    x
      ref    ___4
    ```

=== "LNAST optimized"
    ```lnast
    var
      ref    a.:0:
      const  2
    plus
      ref    ___2
      const  1
      const  1
    var
      ref    a.:1:
      ref    ___2
    tup_add
      ref    ___3
      const  c
      const  3
    tup_concat
      ref    ___4
      ref    a
      ref    ___3
      const  1
    let
      ref    x
      ref    ___4
    ```

## Attributes

There are 3 main operations with attributes: set, get, check, but 4 types of
LNAST nodes (`attr_get`/`attr_set` and `attr_ref_set`/`attr_ref_check`).
`attr_get`/`attr_set` operate at the root level and have the same syntax as
`tup_set`/`tup_get` but the last entry is an attribute name.
`attr_ref_set`/`attr_ref_check` are sub-nodes of `ref`, as such they operate
over the associated `ref` node destination.

`attr_ref_check` only works comparing equal to a `const` or `ref`. More complex
attribute comparisons needs `attr_get` and `casserts` to operate. 

Attribute set are in left-hand-side of assignments which can also be in tuple entries.

=== "Pyrope"
    ```
    a::[f=3,b] = 1
    x = (y::[z=7]=2, 4)
    ```

=== "LNAST direct"
    ```lnast
    assign
      ref a
        attr_ref_set
          const f
          const 3
        attr_ref_set
          const b
          const true
      const 1

    tup_add
      ref ___1
      var
        ref y
          attr_ref_set
            const z
            const 7
        const 2
      const 4

    assign
      ref x
      ref ___1
    ```

Attribute checks are always right-hand-side. The constraint in all the cases is
that an attribute name can be check against an expression but only 3 basic
comparisons are valid (`[attr==(expr)` or `[attr]` or `[!attr]`). The
expression can not use other attribute fields. If complex relationships must be
checked between attributes a `cassert` must be used.

=== "Pyrope"
    ```
    var x = (let z=x::[!y], 4::[foo])
    let y = a::[f==3,b] + 1
    ```

=== "LNAST option 1"
    ```lnast
    assign
      ref ___tmp
      const 4

    tup_add
      ref ___4
      let
        ref z
        ref x
          attr_ref_check
            const y
            const false
      ref ___tmp
        attr_ref_check
          const foo
          const true
    var
      ref x
      ref ___4

    plus
      ref ___1
      ref a
        attr_ref_check
          const f
          const 3
        attr_ref_check
          const b
          const true
      const 1
    let
      ref y
      ref ___1
    ```

=== "LNAST option 2"
    ```lnast
    tup_add
      ref ___4
      let
        ref z
        ref x
          attr_ref_check
            const y
            const false
      const 4

    attr_get
      ref ___no_attr_const_check
      const 4
      const foo

    fcall
      ref ___0
      ref cassert
      ref ___no_attr_const_check

    var
      ref x
      ref ___4

    plus
      ref ___1
      ref a
        attr_ref_check
          const f
          const 3
        attr_ref_check
          const b
          const true
      const 1
    let
      ref y
      ref ___1

    ```


### Sticky attributes


Attributes can be sticky or not. A sticky attribute "polutes" or keeps
the attribute to the left-hand-side expression. Non-sticky attributes
do not affect or propagate.


Attributes are not sticky by default, but some like `.[debug]` is a sticky
attribute. This means that if any of the elements in any operation has a debug
attribute, the result also has a `.[debug]` attribute. There is no way to
remove these attributes.

=== "Pyrope"
    ```
    let d::[debug] = 3

    var a = d + 100

    cassert a.[debug]  // debug is sticky
    ```

=== "LNAST"
    ```lnast
    let
      ref d
        attr_ref_set
          const debug
          const true
      const 3

    plus
      ___tmp
      ref d
      const 100

    var
      ref a
      ref ___tmp

    attr_get
      ref ___get
      ref a
      const debug

    fcall
      ___unused
      ref cassert
      ref ___get
    ```

Once a variable gets assigned an attribute, the attribute stays with the
variable and any variables that got a direct copy. The only way to remove it is
with arithmetic operations and/or bit selection.


```
let foo::[attr1=2] = 3

var foo2 = foo
cassert foo2.[attr1] == 2

let foo3 = foo@[..]
cassert foo3 !has _::[attr1]

var xx = 4
xx::[attr2=5] = 1

let xx2 = xx
cassert xx2.[attr2] == 5
cassert xx2 has _::[attr2]

let xx3 = xx + 0
cassert xx3 !has _::[attr2]
```


## Bit selection


Pyrope has several bit selection operations. The default maps `get_mask` and
`set_mask` LNAST nodes. One important thing is that both `get_mask` and
`set_mask` operate over a MASK. This means that it is a one-hot encoding if a
single bit is operated. The one-hot encoding can be created with a `range` or
with a `shl` operator.


=== "Pyrope"
    ```
    foo@[1,2] = xx
    yy = foo@[5] + xx@[1..<4]
    ```

=== "LNAST direct"
    ```lnast
    shl
      ref ___c1
      const 1
      const 1

    shl
      ref ___c2
      const 1
      const 2

    tup_add
      ref ___t
      ref ___c1
      ref ___c2

    set_mask
      ref foo
      ref foo
      ref ___t
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

    add
      ref yy
      ref ___4
      ref ___5
    ```

=== "LNAST optimized"
    ```lnast
    shl
      ref ___t
      const 1
      const 1
      const 2

    set_mask
      ref foo
      ref foo
      ref ___t
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

    add
      ref yy
      ref ___4
      ref ___5
    ```

It is possible to use a `foo@sext[range]` to perform a bit selection with sign
extension. The `sext` LNAST node is equivalent to the Lgraph `sext` that has 2
inputs. The variable and from what bit to perform sign-extension. This means
that the LNAST translation needs a `get_mask` and a `sext` node. The `sext`,
`+`, `|`, `^` bit selection modifiers can only be applied to right-hand-side
operations.


=== "Pyrope"
    ```
    let t1 = foo@sext[..=4]
    let t2 = foo@|[..=4]
    let t3 = foo@&[..=4]
    let t4 = foo@^[..=4]
    let t5 = foo@+[..=4]
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
    let
      ref t1
      ref ___t1

    reduce_or
      ref ___t2
      ref ___t
    let
      ref t2
      ref ___t2

    reduce_and       // reduce_and(x) == (sext(x) == -1)
      ref ___t3
      ref ___t
    let
      ref t3
      ref ___t3

    reduce_xor
      ref ___t4
      ref ___t
    let
      ref t4
      ref ___t4

    popcount
      ref ___t5
      ref ___t
    let
      ref t5
      ref ___t5
    ```

## Direct LNAST/Lgraph call


A direct Lgraph call can be done with `__cell` where `cell` is the Lgraph cell
like `plus`, `LUT`, `memory`. In LNAST this is translated like a lambda call.


=== "Pyrope"
    ```
    let foo = 3
    let bar = 300
    let b = __plus(1,2,foo,bar)
    ```

=== "LNAST"
    ```lnast
    let
      ref foo
      const 3
    let
      ref bar
      const 300
    tup_add
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
    ```
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

* `!a` or `not a` translates to `lnot`
* `~a` translates to `not`
* `-a` translates to `minus(0,a)`

### Binary integer

* `a + b` translates to `plus`
* `a - b` translates to `minus`
* `a * b` translates to `mult`
* `a / b` translates to `div`
* `a & b` translates to `and`
* `a | b` translates to `or`
* `a ^ b` translates to `xor`
* `a >> b` translates to `sra`
* `a << b` translates to `shl`


There is a `mod` LNAST operator that performs module operations. It does not
have a direct Pyrope syntax, but it can be called directly `__mod(a,b)`.

### Binary boolean

* `a and b` translated to `land`
* `a or b` translates to `lor`


## Complex operators

Complex operators are binary operators in Pyrope that require more than one
LNAST statement.

### Binary integer

Binary nand (`x=a ~& b`):
```lnast
and
  ref ___0
  ref a
  ref b
not
  ref x
  ref ___0
```

Binary nor (`x=a ~| b`):
```lnast
or
  ref ___0
  ref a
  ref b
not
  ref x
  ref ___0
```

Binary xor (`x=a ~^ b`):
```lnast
xor
  ref ___0
  ref a
  ref b
not
  ref x
  ref ___0
```

Logical shift right (`x = a@[..] >> b`):
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
not
  ref ___0
  ref a
lor
  ref x
  ref ___0
  ref b
```

Logical nand (`x = a !and b`):
```lnast
land
  ref ___0
  ref a
  ref b
not
  ref x
  ref ___0
```

Logical nor (`x = a !or b`):
```lnast
lor
  ref ___0
  ref a
  ref b
not
  ref x
  ref ___0
```

Logical not implication (`x = a !implies b`):
```lnast
not
  ref ___0
  ref b
land
  ref x
  ref a
  ref ___0
```


Short-circuit boolean (`and_then`/`or_else`)

The short-circuit boolean prevent expressions from being evaluated. This only
matters if there is a procedure call, but at LNAST it is not possible to know
due to getter overload. As a result, the sequence of statments is translated to
a sequence of nested if statements.

=== "Pyrope"
    ```
    a = b and_then c and_then (d or e)
    ```
=== "LNAST"
  ```lnast
  land
    ref ___0
    ref b
    ref c
  assign
    ref a
    ref ___0
  if
    ref ___0
    stmts
      lor ___1
        ref d
        ref e
      assign
        ref a
        ref ___1
  ```

=== "Pyrope"
    ```
    a = b or_else c or_else (d and e)
    ```
=== "LNAST"
  ```lnast
  lor
    ref ___0
    ref b
    ref c
  assign
    ref a
    ref ___0
  if
    ref ___0
    stmts
    stmts  // else only
      land
        ref ___1
        ref d
        ref e
      assign
        ref a
        ref ___1
  ```

### Tuple/Set operators

The `in` operator does not have a Lgraph equivalent becuase it is type
dependent: tuple, range, or enumerate. The range and enumerate can get
translated to an AND gate over the bitcode translation, but the tuple check
requires a tuple check.

```
let tup=(1,2,3)
let ran=1..<5
let enu = enum(a,b=(x,y),c)

cassert 2 in tup
cassert 3 in ran
cassert enu.b.x in enu.b
```

The resul is a common `in` LNAST operation that gets different functionality
dependent on the input type.


=== "Pyrope"
    ```
    c = a in b
    d = a !in b
    ```

=== "LNAST"
    ```lnast
    in
      ref c
      ref a
      ref b
    not
      ref d
      ref c
    ```

There are two tuple concatenate operator  `a ++ b` and `(a,...b)`. `x=a++b` translates to:

```lnast
tup_concat
  ref x
  ref a
  ref b
```

The inplace concatenate is equivalent but it has a check (`cassert`) to detect overlap. After the concatenation,
the fields in `a` and `b` should be found in the result `x` or there was an overlap.

`x=(a,..b)` translates to:
```lnast
tup_concat
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
land
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
sub
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

To check the tuple structure, Pyrope has `a does b`. It returns true if the
tuple of `a` a subset of `b`. `x = a does b` translates to:
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
land
  ref x
  ref ___0
  ref ___1
```

The `a case b` does match operation. `a case b` same as `cassert b does a` and
for each `b` field with a defined value, the value matches `a` (`nil`, `0sb?`
are undefined values). `x = a case b` translates to:
```lnast
does
  ref ___0
  ref b
  ref a
fcall
  ref ___1
  ref cassert
  ref ___0
in
  ref x
  ref b
  ref a
```

To perform a nominal type check, the attributes can be accessed directly. `x = a is b` translates to:
```lnast
attr_get
  ref ___0
  ref a
  const typename
attr_get
  ref ___1
  ref b
  const typename
eq
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
    ```
    var total=3
    if var x=3; x<3 {
      total+=x
    }elif var z=3; z<4 {
      total+=x+z
    }
    ```

=== "Pyrope Equivalent"
    ```
    var total=3
    {
      var x=3
      if x<3 {
        total+=x
      }else{
        var z=3
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
    ```
    if var x=a ; x<3 {
      t = 100+x               // z not in scope
    }elif var z = x+c ; z>5 {
      t = 200+z+x             // z and x in scope
    }
    ```

=== "LNAST"
    ```lnast
    stmts
      var
        ref x
        ref a
      lt
        ref ___1
        ref x
        const 3
      if
        ref ___1
        stmts
          add
            ref t
            const 100
            ref x
        stmts
          add
            ref ___2
            ref x
            ref c
          var
            ref z
            ref ___2
          gt
            ref ___3
            ref z
            const 5
          if
            ref ___3
            stmts
              add
                ref t
                const 200
                ref z
                ref x
    ```

The `unique if` is similar, but all the conditions include and `optimize`
directive to be checked. This means that the conditions must be checked even if
the `else` is not reached. This is fine because neither the statements nor the
condition checks are allowed to have side-effects.


An important limitation of `unique if` is that only the first condition can
have initial statement. It is not allowed to have initialization statements in
the `elif` conditions.

=== "Pyrope"
    ```





    unique if a<3 {
      y = 10
    }elif a>40 {  // not allowed to do 'elif var z=40; a>z'
      y = 20+x
    }
    ```

=== "Pyrope Equivalent"
    ```
    let tmp1 = a<3
    let tmp2 = a>40
    let tmp3 = 1<<(tmp1,tmp2)
    optimize tmp3@+[..]<=1        // at most one bit set

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
      ref optimize
      ref ___5
    if
      ref ___1
      stmts
        assign
          ref y
          const 10
      ref ___2
      stmts
        add
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
    ```
    var z = 0
    match x {
     == 3 { z = 1 }
     in 4..<6 { z = 2 }
    }

    match x {
     <  5 { z = 1 }
     else { z = 3 }
    }
    ```

=== "LNAST"
    ```lnast
    var
      ref z
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
      ref optimize
      ref ___5

    if
      ref ___1
      stmts
        assign
          ref z
          const 1
      ref ___2
      stmts
        assign
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
      ref optimize
      ref ___9
    if
      ref ___6
      stmts
        assign
          ref z
          const 1
      stmts
        assign
          ref z
          const 3
    ```



## Scope

Like most languages Pyrope has variable scope, but it does not allow variable
shadowing. This section showcases some cases on how the scope is generated.


New variables can have a statement scope for `if`, `while`, and `match`
statements.

=== "Pyrope"
    ```
    if var x=3; x<4 {
      cassert x==3
    }
    while var z=1; x {
      x -= z
    }
    var z=0
    match var x=2 ; z+x {
      == 2 { cassert true  }
      != 7 { cassert true  }
      else { cassert false }
    }
    ```

=== "LNAST"
    ```lnast
    stmts
      var
        ref x
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
      var
        ref z
        const 1
      loop
        if
          ref x
          stmts
            break
        sub
          ref x
          ref x
          ref z

    var
      ref z
      const 0
    stmts
      var
        ref x
        const 2
      add
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
        ref optimize
        ref ___z
      if
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
is only `loop` construct.

=== "Pyrope loop"
    ```
    loop {
      i += 1
      break when i==3
    }
    ```

=== "LNAST"
    ```lnast
    loop
      add
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

The `while` translates to a `loop` with a `break` statement.

=== "Pyrope while"
    ```
    while var i=0 ; i!=3 {
      i += 1
    }
    ```

=== "LNAST"
    ```lnast
    stmts
      var
        ref i
        const 0
      loop
        neq
          ref ___1
          ref i
          const 3
        not
          ref ___2
          ref ___1
        if
          ref ___2
          stmts
            break
    ```

The `for` construct is also a loop, but it can have element, index, and key in the iterator. Also, it can allow a `ref` to mutate the contents.

=== "Pyrope for"
    ```
    for (index,key,value) in enumerate(key(tup)) {
      mycall(value,index,key)
    }
    ```
=== "Pyrope ref for"
    ```
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
        var
          ref value
          ref _
        var
          ref index
          const 0
        var
          ref key
          const ""
        loop
          attr_get
            ref key
            ref tup
            ref index
            const "key"
          tup_get
            ref value
            ref tup
            ref index
          tup_add
            ref ___6
            ref index
            ref key
            ref value
          fcall
            ref ___empty
            ref mycall
            ref ___6
          add
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
        var
          ref value
          ref _
        var
          ref index
          const 0
        var
          ref key
          const ""
        loop
          attr_get
            ref key
            ref tup
            ref index
            const "key"
          tup_get
            ref tup
            ref index
            ref value
          tup_add
            ref ___6
            ref index
            ref key
            ref value
          fcall
            ref ___empty
            ref mycall
            ref ___6
          tup_set
            ref tup
            ref index
            ref value
          add
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
the value that must be concatenated (`tup_concat`) to the result. If the last
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


=== "Pyrope"
    ```
    let num = 1
    let color = "blue"
    let extension = "s"

    let txt1 = "I have {num} {color} potato{extension}"  // interpolation
    let txt2 = format('I have {:d} {} potato{}', num, color, extension)
    ```
=== "LNAST"
    ```lnast
    let
      ref num
      const 1
    let
      ref color
      const blue
    let
      ref extension
      const s

    tup_add
      ref ___tmp
      const "I have {} {} potato{}"
      ref num
      ref color
      ref extension

    fcall
      ref txt1
      ref format
      ref ___tmp

    tup_add
      ref ___tmp2
      const 'I have {:d} {} potato{}'
      ref num
      ref color
      ref extension

    fcall
      ref txt2
      ref format
      ref ___tmp2
    ```

## Lambda call

A lambda call arguments requires do not always require to be named like when a
variable used matches a calling argument. To support the matching while
processing the LNAST, the arguments tuple must be named for all the arguments
unless an argument is an expression.


=== "Pyrope"
    ```
    x = fcall(a,b=3,foo,1+2)
    ```
=== "LNAST"
    ```lnast
    add
      ref ___t
      const 1
      const 2

    tup_add
      ref ___args
      let
        ref a
        ref a
      let
        ref b
        const 3
      let
        ref foo
        ref foo
      ref ___t

    fcall
      ref x
      ref fcall
      ref ___args
    ```

