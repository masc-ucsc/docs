
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
    assign  :
        ref     : x
        const   : 3
    assign  :
        ref     : ___t1
        const   : 2
    plus    :
        ref     : ___t2
        ref     : x
        const   : 1
    plus    :
        ref     : ___t3
        ref     : ___t1
        const   : 1
    tup_add:
        ref     : a
        assign  :
            ref     : b
            ref     : __t1
        assign  :
            ref     : x
            ref     : ___t2
        assign  :
            ref     : y
            ref     : ___t4
    ```

=== "LNAST Optimized"
    ```lnast
    assign  :
        ref     : x
        const   : 3
    assign    :
        ref     : a.:0:b
        ref     : 2
    plus    :
        ref     : a.:1:x
        ref     : x
        const   : 1
    plus    :
        ref     : a.:2:y
        const   : a.:0:b
        const   : 1
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
      assign
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

There are 3 main operations with attributes: set, get, check. Each has a
corresponding LNAST node (`attr_set`, `attr_get`, `attr_check`). Later compiler
passes decide what operation to perform in the attr depending on the attribute
type.

Attribute set are in left-hand-side of assignments which can also be in tuple entries.

=== "Pyrope"
    ```
    a::[f=3,b] = 1
    x = (x::[y=7]=2, 4)
    ```

=== "LNAST direct"
    ```lnast
    assign
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

    tup_add
      ref ___1
      assign
        ref x
        const 2
      const 4

    attr_set
      ref ___1
      const x
      const y
      const 7

    assign
      ref x
      ref ___1
    ```

=== "LNAST optimized"
    ```lnast
    assign
      ref a
      const 1
    attr_set
      ref a
      const f
      const 3
    attr_set
      ref a
      const b      // attribute field can not join first ref
      const true

    tup_add
      ref x
      assign
        ref x
        const 2
      const 4

    attr_set
      ref x.x
      const y
      const 7
    ```

Attribute get are always right-hand-side

=== "Pyrope"
    ```
    let x = a::[f==3,b] + 1
    var x = (let z=x::[y], 4::[foo])
    ```

=== "LNAST"
    ```lnast
    plus
      ref ___1
      ref a
      const 1

    attr_get
      ref ___2
      ref a
      const f

    equal
      ref ___3
      ref ___2
      const 3

    attr_check
      ref a
      ref ___3
    attr_check
      ref b
      const b

    tup_add
      ref ___4
      let
        ref z
        ref x
      const 4

    attr_check
      ref x
      const y

    attr_check
      const 4
      const foo
    ```

### Sticky Attributes


Once a variable gets assigned an attribute, the attribute stays with the
variable and any variables that got a direct copy. The only way to remove it is
with arithmetic operations and/or bit selection.


```
let foo::[attr1=2] = 3

var foo2 = foo
cassert foo2.::[attr1] == 2

let foo3 = foo@[]
cassert foo3 !has ::[attr1]

var xx = 4
xx::[attr2=5] = 1

let xx2 = xx
cassert xx2.::[attr2] == 5
cassert xx2 has ::[attr2]

let xx3 = xx + 0
cassert xx3 !has ::[attr2]
```

## Bit Selection


Pyrope has several bit selection operations. The default maps `get_mask` and `set_mask` LNAST nodes:


=== "Pyrope"
    ```
    foo@[1,2] = xx
    yy = foo@[5] + xx@[1..<4]
    ```

=== "LNAST"
    ```lnast
    tup_add
      ref ___t
      const 1
      const 2

    set_mask
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
    ```
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
    ```
    let
      ref x
      const 5
    ```

## Basic Operators

Basic operators are binary or unary operators in Pyrope that have a one-to-one
translation to LNAST nodes.

### Unary

* `!a` or `not a` translates to `lnot`
* `~a` translates to `not`
* `-a` translates to `minus(0,a)`

### Binary Integer

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

### Binary Boolean

* `a and b` translated to `land`
* `a or b` translates to `lor`


## Complex Operators

Complex operators are binary operators in Pyrope that require more than one
LNAST statement.

### Binary Integer

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

Logical shift right (`x = a@[] >> b`):
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

* `a in b` is element `a` in tuple `b`
* `a !in b` true when element `a` is not in tuple `b`

*TODO*

### Type operators

* `a does b` is the tuple structure of `a` a subset of `b`
* `a equals b` same as `(a does b) and (b does a)`
* `a case b` same as `cassert a does b` and for each `b` field with a defined value,
  the value matches `a` (`nil`, `0sb?` are undefined values)
* `a is b` is a nominal type check. Equivalent to `a::[typename] == b::[typename]`

*TODO*

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
    unique_if
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
          ref ___3
          ref assert
          const false

    lt
      ref ___4
      ref x
      const 5
    unique_if
      ref ___4
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
      x -= 1
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
        ref x
        const 1
      while
        ref x
        stmts
          sub
            ref x
            ref x
            const 1

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
      unique_if
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

