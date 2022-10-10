
# LNAST

This document is to showcase some of the Pyrope to LNAST translation. This is
useful to have a more "formal" description of the language semantics.


## Variable names

Temporal variables that do not need to SSA (single assignment) start with 3
underscores (`___foo`). Program variables names that do not need SSA (`let`) use
`_._foo`. Special variable names like the ones needing an underscore use double
ticky in the name `_foo here`.

=== "Pyrope"
    ```
    let x = 3 + 1
    var z = 4
    `foo x` = x + z + 2
    ```

=== "LNAST direct"
    ```
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
    ```
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
    ```
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
    ```
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
    ```
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
    ```
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
    ```
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
    ```
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
    ```
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
    ```
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
    ```
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

