# Type system

Type system assign types for each variable (type synthesis) and check that each
variable use/expression respects the allowed types (type check). Additionally, a
language can also use the type synthesis results to implement polymorphism.


Most HDLs do not have modern type systems, but they could benefit like in other
software domains. Unlike software, in the hardware, we do not need to have many integer
sizes because hardware can implement any size. This simplifies the type system
allowing unlimited precision integers but it needs a bitwidth inference mechanism.


Additionally, in hardware, it makes sense to have different implementations that
adjust for performance/constraints like size, area, FPGA/ASIC. Type systems
could help in these areas.


## Types vs `cassert`

To understand the type check, it is useful to see an equivalent `casser`
translation. The type system has two components: type synthesis and type check.
The type check can be understood as a `cassert`.


After type synthesis, each variable has an associated type. Pyrope checks that
for each each assignment, the left-hand side (LHS) has a compatible type with
the right-hand side (RHS) of the expression. Additional type checks happen when
variables have a type check explicitly set (`variable:type`) in the rhs expression.


Although the type system is not implemented with asserts, it is an equivalent
way to understand the type system "check" behavior.  Although it is possible to
declare just the `cassert` for type checks, the recommendation is to
use the explicit Pyrope type syntax because it is more readable and easier to
optimize.


=== "Snippet with declaration-site types"

    ```pyrope
    mut b = "hello"

    mut a:u32 = 0

    a += 1

    a = b                       // incorrect (b is string)


    mut dest:u32 = 0
    mut foo:u16 = 0
    mut v:u8   = 0

    dest = foo + v              // types come from the declarations
    ```

=== "Snippet with comptime assert"

    ```pyrope
    mut b = "hello"

    mut a:u32 = 0

    a += 1
    cassert(a does u32)
    a = b                       // incorrect
    cassert(b does u32) // fails

    mut dest:u32 = 0
    mut foo:u16 = 0
    mut v:u8   = 0
    cassert((dest does u32) and (foo does u16) and (v does u8))
    dest = foo + v
    ```


## Building types

Each variable can be a basic type. In addition, each variable can have a set of
constraints from the type system. Pyrope type system constructs to handle types:

* `mut` and `const` allows declaring types.

* `a does b`: Checks 'a' is a superset or equal to 'b'. In the future, the
  Unicode character "\u02287" could be used as an alternative to `does` (`a`
&#8839 `b`).

* `a:b` binds variable `a` to type `b`. It is **only** allowed at
  declaration sites (`mut`/`reg`/`const`/`comb`/`pipe`/`mod`, lambda
  parameters and return types, and tuple field declarations). To check
  that an existing value has type `b`, use `a does b`. To
  convert a value to type `b`, call the type as a constructor: `b(a)`.

* `a equals b`: Checks that `a does b` and `b does a`. Effectively checking
  that they have the same type. Notice that this is not like checking for
  logical equivalence, just type equivalence.

```pyrope
const t1 = (const a:signed=1, const b:string = "")
const t2 = (const a:signed=100, const b:string = "")
mut v1 = (const a=33, const b="hello")

comb f1() -> (a:signed, b:string) {
  a = 33
  b = "hello"
}

cassert(t1 equals t2)
cassert(t1 equals v1)
cassert(f1() equals t1)
cassert(not (f1 equals t1))
cassert(t1 equals t2)
```


`equals` and `does` check for types. Sometimes, the type can have a function
call and you do not want to call it. The solution in this case is to use the
`:type` to avoid the function call.


Since the `puts` command understands types, it can be used on any variable, and
it is able to print/dump the results.

```pyrope
const At:signed(min=33) = nil    // number bigger than 32
const Bt = (
  mut c:string = nil,
  mut d = 100,
  comb init(ref self, ...args) { self.c = args }
)

mut a:At = 40
mut a2 = At(40)
cassert(a == a2)

mut b:Bt = "hello"
mut b2 = Bt("hello")
cassert(b == b2)

puts("a:{} or {}", a, at) // a:40 or 33
puts("b:{}", b)           // b:(c="hello",d=100)
```

### Type equivalence


The `does` operator is the base to compare types. It follows structural typing rules.
These are the detailed rules for the `a does b` operator depending on the `a` and `b` fields:


* false when `a` and `b` are different basic types (`boolean`, `comb`,
  `integer`, `mod`, `range`, `string`, `enums`).

* true when `a` and `b` have the same basic type of either `boolean` or `string`.

* true when `a` and `b` are `enum` and `a` has all the possible enumerates
  fields in `b` with the same value.

* `a.max>=b.max and a.min<=b.min` when `a` and `b` are integers. The `max/min`
  are previously constrained values in left-hand-side statements, or inferred
  from right-hand-side if no lhs type is specified.

* `(a#[..] & b#[..]) == b#[..]` when `a` and `b` are `range`. This means that the `a`
  range has at least all the values in `b` range.

* There are two cases for tuples. If all the tuple entries are named, `a does
  b` is true if for all the root fields in `b` the `a.field does b.field`. When
  either `a` or `b` have unnamed fields, for each field in `b` the name but
  also position should match. The conclusion is that if any field has no name,
  all the fields should match by position and/or name if available.

* `a does b` is false if the explicit array size of `a` is smaller than the
  explicit array size of `b`. If the size check is true, the array entry type
  is checked. `:[]x does :[]y` is false when `:x does :y` is false.

* The lambdas have a more complicated set of rules explained later.

```pyrope
const a:signed(max=33, min=0) = nil
const b:signed(max=20, min=5) = nil
cassert(a does b)
cassert(not (b does a))

cassert(    (const a:string=nil, const b:signed=nil) does (const a="hello", const b=33))
cassert(not (const b:string=nil, const a:signed=nil) does (const a="hello", const b=33))

type T_complex = comb(x, xxx2) -> (y, z)
type T_simple  = comb(x)       -> (y, z)
cassert(T_complex does T_simple)
cassert(not (T_simple does T_complex))
```

For named tuples, this code shows some of the corner cases:

```pyrope
const t1 = (const a:string = "", const b:signed = nil)
const t2 = (const b:signed = nil, const a:string = "")

mut a:t1 = ("hello", 3)     // OK
mut a1:t1 = (3, "hello")     // error: positions do not match
mut b:t1 = (a="hello", 3)   // OK
mut b1:t1 = (3, a="hello")   // error: positions do not match
mut c:t1 = (a="hello", b=3) // OK
mut c1:t1 = (b=3, a="hello") // OK

mut d:t2 = c                 // OK, both fully named
cassert(d[0] == c[1] and c[0] == d[1])
cassert(d.a == c.a and d.b == c.b)
```

Ignoring the value is what makes `equals` different from `==`. As a result
different functionality functions could be `equals`.

```pyrope
comb a() -> (r) { r = 1 }
comb b() -> (r) { r = 2 }
type ab_type = comb() -> (r)
cassert(a equals ab_type)

cassert(a() != b()) // 1 != 2
cassert(a() equals b()) // 1 equals 2
```

## Type check with values

Many programming languages have a `match` with structural checking. Pyrope
`does` allows to do so, but it is also quite common to filter/match for a given
value in the tuple. This is not possible with `does` because it ignores all the
field values. Pyrope has a `case` that extends the `does` comparison and also
checks that for the matching fields, the value is the same.


The previous explanation of `a does b` and `a case b` ignored types. When types
are present, both need to match type.

```pyrope
cassert((const a:u32=0, const b:bool=false) does (const a:u32=0, const c:string="hello", const b=false))
cassert((const a:u32=0, const c:string="hello", const b=false) case (a = 0, b:bool=nil)) // b is nil

cassert(not ((const a:u32=0, const c:string="hello", const b=false) case (a:u32 = 1, b:bool=nil)))
cassert(not ((const a:u32=0, const c:string="hello", const b=false) case (a:bool=nil, b:bool=nil)))
cassert(not ((const a:u32=0, const c:string="hello", const b=false) case (a = 0, b = true)))
```

## Enums with types

Enumerates (enums) create a number for each entry in a set of identifiers.
Pyrope also allows associating a tuple or type for each entry. Another
difference from a tuple is that the enumerate values must be known at compile
time.


```pyrope
const Rgb = (
  mut c:u24,
  comb init(ref self, c) { self.c = c }
)

const Color = enum(
  Yellow:Rgb = 0xffff00,
  Red:Rgb = 0xff0000,
  Green = Rgb(0x00ff00), // alternative
  GBlue = Rgb(0x0000ff)
)

mut y:Color = Color.Red
if y == Color.Red {
  puts("c1:{} c2:{}\n", y, y.c)  // prints: c1:Color.Red c2:0xff0000
}
```

## Bitwidth

Integers can be constrained based on the maximum and minimum value (not by
the number of bits).

Pyrope automatically infers the maximum and minimum values for each numeric
variable. If a variable width can not be inferred, the compiler generates a
compilation error. A compilation error is generated if the destination
variable has an assigned size smaller than the operand results.

The programmer can specify the maximum number of bits, or the maximum value range.
The programmer can not specify the exact number of bits because the compiler has
the option to optimize the design.


In fact, internally Pyrope only tracks the `max` and `min` value. When a
width-constrained type such as `u14` or `s4` is used, it is converted to a
`max/min` range. Pyrope code can read bitwidth attributes for each integer
variable, but these attributes are read-only; constrain them through the
declared type, not through an attribute write.

* `max`: the declared maximum value
* `min`: the declared minimum value
* `bits`: the number of bits needed to represent the declared `max`/`min`
  range (sugar over `max`/`min` — see [Attributes](04b-attributes.md)).
  There are no `ubits`/`sbits` attributes: use `bits`, and check the sign
  with `signed` (true when `min < 0`).
* `bw_max`/`bw_min`: the *actual* range computed by the bitwidth pass —
  readable only inside debug statements (`cassert`/`assert`)


Internally, Pyrope has 2 sets of `max/min`. The constrained and the current.
The constrained is set during type declaration. The current is computed based
on the possible max/min value given the current path/values. The current should
never exceed the constrained or a compile error is generated (use `wrap`/`sat`
on the assignment to fix it). Similarly, the
current should be bound to a given size or a compile error is generated.


The constraint does not need to be specified. In this case, the hardware will
use whatever current value is found. This allows to write code that adjust to
the needed number of integer bits.

When `max`/`min`/`bits` are read, they return the declared constraint. The
current range is readable as `bw_max`/`bw_min`, but **only inside debug
statements**: each elaboration may compute a different (legal) current range,
so non-debug code must not make decisions based on it.

```pyrope
mut val:u8 = 0   // designer constrains val to be between 0 and 255
cassert(val.[max] == 255 and val.[min] == 0 and val.[bits] == 8)

val = 3          // declared attributes unchanged: max=255, min=0
cassert(val.[bw_max] == 3) // current range: debug-only read

val = 300        // error: '300' overflows the maximum allowed value of 'val'

wrap val = 0x1F0 // Drop bits from 0x1F0 to fit in constrained type
cassert(val == 240 == 0xF0)

val = u8(0x1F0)  // error: 0x1F0 needs 9 bits — a sized cast can widen but
                 // never drops bits; use `wrap`/`sat` to drop bits
val = u8(200)    // OK: 200 fits u8, reinterprets through unchanged
cassert(val == 200)
```

A sign cast `signed(x)`/`unsigned(x)`/`sN(x)`/`uN(x)` *reinterprets* `x`'s bits
under the target signedness. The unsized `signed(x)`/`unsigned(x)` keep the bit
width unchanged (so `x` must be fully sized and `signed(unsigned(x)) == x`); the
sized `sN(x)`/`uN(x)` may widen but never drop bits — a target with fewer bits
than `x` is a compile error (use a `wrap`/`sat` prefix to drop bits on purpose),
e.g. `u30(s22(x))` is fine but `s22(u30(x))` is a compile error. Casting a
`boolean` interprets its single bit under the target's signedness —
`signed(true) == -1` / `s8(true) == -1` (1-bit signed), but
`unsigned(true) == 1` / `u8(true) == 1` (unsigned magnitude bit). The reverse,
`boolean(x)`/`bool(x)` on an integer, is `x != 0` (so `boolean(33)` is true); an
undefined (`?`) or `nil` operand is a compile error.

Branching on `bw_max`/`bw_min` outside a debug statement is a compile error
because the result would not converge — the next elaboration can compute a
different range and silently change the circuit:

```pyrope
if x.[bw_max] != 30 { // compiler error 'bw_max' is debug-only
  x = 30
} else {
  x = 40
}
```

Pyrope leverages LiveHD bitwidth pass to compute the maximum and minimum value
of each variable. For each operation, the maximum and minimum are computed. For
control-flow divergences, the worst possible path is considered.

```pyrope
mut a = 3                  // a: current(max=3,min=3) constrain()
mut c:signed(min=0,max=10) = nil // c: current(max=0,min=0) constrain(max=10,min=0)
if b {
  c = a + 1                // c: current(max=4,min=4) constrain(max=10,min=0)
} else {
  c = a                    // c: current(max=3,min=3) constrain(max=10,min=0)
}
                           // c: current(max=4,min=3) constrain(max=10,min=0)

mut e:s4 = nil             // e: current(max=0,min=0) constrain(max=7,min=-8)
e = 2                      // e: current(max=2,min=2) constrain(max=7,min=-8)
mut d = c                  // d: current(max=4,min=3) constrain()
if d == 4 {
  d = e + 1                // d: current(max=3,min=3) constrain()
}
mut g:u3 = d               // g: current(max=4,min=3) constrain(max=7,min=0)
mut h = c#[0..=1]          // h: current(max=3,min=0) constrain()
```


Bitwidth uses narrowing to converge (see
[internals](10-internals.md/#type-synthesis)). The GCD example does not specify
the input/output size, but narrowing allows it to work without typecasts.  To
understand, the comments show the max/min bitwidth computations.

```pyrope
if cmd.[valid] {
  (x, y) = cmd  // x.max=cmd.a.max; x.min = 0 (unsigned) ; ....
} elif x > y {
                // narrowing: x.min = y.min + 1 = 1
                // narrowing: y.max = x.min - 1
  x = x - y     // x.max = x.max - x.min = x.max - 1
                // x.min = x.min - y.max = 1
} else {        // x <= y
                // narrowing: x.max = y.min
                // narrowing: y.min = x.min
  y = y - x     // y.max = y.max - x.min = y.max
                // y.min = y.min - x.max = 0
}
                // merging: x.max = x.max ; x.min = 0
                // merging: y.max = y.max ; y.min = 0
                // converged because x and y is same or smaller at beginning
```

The bitwidth pass may not converge to find a valid size even with narrowing.
In this case, the programmer must insert a typecast or operation to constrain
the bitwidth by typecasting. For example, this could work:

```pyrope
reg x = 0
reg y = 0
if cmd.[valid] {
  (x, y) = cmd
} elif x > y {
  x = x - y
} else {
  y = y - x
}
wrap x:cmd.a = x  // use cmd.a type for x, and drop bits as needed
y = cmd.b(y)        // typecast y to cmd.b type (this can add a mux)
```


Pyrope uses signed integers for all the operations and transformations, but
when the code is optimized it does not need to waste bits when the most
significant bit is known to be always zero (positive numbers like u4). The
verilog code generation or the synthesis netlist uses the bitwidth pass to
remove the extra unnecessary bit when it is guaranteed to be zero. This
effectively "packs" the encoding.


## Tagged unions (enum `enum`)


A tagged union — the equivalent of a `enum` type — is spelled with `enum`
in Pyrope and carries a payload per case. The bits used are shared across
cases (only one case is active at a time), so the storage is the size of the
largest case plus the tag.


Unlike a C-style `union`, the tag is tracked from the assignment, and an
error is generated if the wrong case is accessed. Bit-level reinterpretation
across cases requires explicit bitwise operations.


The main advantage of a tagged enum is to save space, so the typical use is
in combination with registers or memories, where alternative types share a
single storage location.


```pyrope
const e_type = enum(str:String = "hello", num=22)
const v_type = enum(str:String, num:signed) // No default value when used as a tagged union

mut vv:v_type = (num=0x65)
cassert(vv.num == 0x65)
const xx = vv.str                         // error: active case is `num`
```


The variable allows to explicitly or implicitly access the active case.
Cases may not be solved at compile time, and the error will be a simulation
error. A `comptime` directive can force a compile time-only check.

```pyrope
const Vtype = enum(str:String, num:signed, b:bool)

const x1a:Vtype = "hello"                 // implicit case
const x1b:Vtype = (str="hello")           // explicit case

comptime const x2:Vtype = "hello"                  // comptime

cassert(x1a.str == "hello" and x1a == "hello")
cassert(x1b.str == "hello" and x1b == "hello")

const err1 = x1a.num                      // error: active case is `str`
const err2 = x1b.b                        // error: active case is `str`
const err3 = x2.num                       // error: comptime value is `str`
```

As a reference, `enums` allow to compare for field but not update enum entries.

```pyrope
mut ee = e_type
ee.str = "new_string"       // error: enum is immutable

match ee {
 == e_type.str { }
 == e_type.num { }
 else { }
}
```


## Typecasting


To convert between tuples, an explicit `init` is needed unless the tuple fields
names, order, and types match.

```pyrope
const at = (const c:string = nil, const d:u32 = nil)
const bt = (const c:string = nil, const d:u100 = nil)

const ct = (
  const d:u32 = nil,
  const c:string = nil
)
// different order
const dt = (
  mut d:u32 = nil,
  mut c:string = nil,
  comb init(ref self, x:at) { self.d = x.d; self.c = x.c }
)

mut b:bt = (c="hello", d=10000)
mut a:at = nil

a = b          // OK c is string, and 10000 fits in u32

mut c:ct = a   // OK even different order because all names match

mut d:dt = a   // OK, calls init to typecast at construction
```

* To string: The `format` allows to convert any type/tuple to a string.
* To integer: `variable#[..]` for string, range, and bool, union otherwise.
* `union` allows to convert across types by specifying the size explicitly.

## Introspection

Introspection is possible for tuples.

```pyrope
const a = (const b=1, const c:u32=2)
mut b = a
b.c = 100

cassert(a equals b)
cassert(a.size == 2)
cassert(a['b'] == 1)
cassert(a['c'] equals u32)

cassert(a has 'c')
cassert(!(a has 'foo'))

cassert(a.[id] == 'a')
cassert(a['b'].[id] == 'b' and a.b.[id] == 'b')
cassert(a['c'].[id] == 'c' and a.c.[id] == 'c')

cassert(a.[size] == 0)  // 0 unnamed entries
cassert(a.[fields] == ('b','c'))
```

Function definitions allocate a tuple, which allows to introspect the
function but not to change the functionality. Functions have two fields:
`inputs` and `outputs`.

```pyrope
comb fu(a, b=2) -> (c) { c = a + b }
cassert(fu.[inp] equals ('a', 'b'))
cassert(fu.[out] equals ('c'))
```

This means that when ignoring named vs unnamed calls, overloading behaves like
this:

```pyrope
const x:u32 = fn(a1, a2)

comb model_poly_call(fn, ...args) -> (out) {
  for f in fn {
     if not (f.[inp] does args) { continue }
     if not (f.[out] does out) { continue }
     out = f(args)
     return
  }
}
const x:u32 = model_poly_call(fn, a1, a2)
```

Any runtime precondition is expressed by the caller (e.g., with an
`if`/`elif` chain that picks which named lambda to invoke); there is no
`where` clause on declarations.

There are several uses for introspection, but for example, it is possible to build a
function that returns a randomly mutated tuple.

```pyrope
comb randomize::[debug](ref self) {
  const rnd = import("prp/rnd")
  for i in ref self {
    if i equals signed {
      i = rnd.between(i.[max], i.[min])
    } elif i equals bool {
      i = rnd.boolean()
    }
  }
  self
}

const x = (const a=1, const b=true, const c="hello")
const y = x.randomize()

assert(x.a == 1 and x.b == true and x.c == "hello")
cover(y.a != 1)
cover(y.b != true)
assert(y.c == "hello") // string is not supposed to mutate in randomize()
```


## Global scope

There are no global variables or functions in Pyrope. Variable scope is
restricted by code block `{ ... }` and/or the file. Each Pyrope file is a
function, but they are only visible to the same directory/project Pyrope files.


There are two separate mechanisms for accessing declarations outside a Pyrope
file. The `import` statement copies `pub` top-scope lambdas, types, and
constants from other files. Registers are never imported; `pub reg` is a
compile error. To reference an instantiated register outside the local scope,
use `regref`, which resolves through the instantiation hierarchy instead of
through the file import namespace. Debug statements can still observe registers
read-only (see
[Visibility](04-variables.md#visibility-private-by-default-pub-to-export)).


### import


`import` keyword allows to access functions not defined in the current file.
Any call to a function or tuple outside requires a prior `import` statement.


```pyrope
// file: src/my_fun.prp
pub comb fun1(a, b) -> (r) { r = a + b }
pub comb fun2(a) -> (r) {
  comb inside() -> (r) { r = 3 }
  r = a
}
comb another(a) -> (r) { r = a }   // no pub: private to this file

pub const mytup = (
  comb call3(self) -> () { puts("call called") }
)
```

```pyrope
// file: src/user.prp
a = import("my_fun")    // all the pub entries of the file
a.fun1(a=1, b=2)        // OK
a.another(a=1, 2)       // error: 'another' is not pub, not imported
a.fun2.inside()         // error: `inside` is not in top scope variable

const fun1 = import("my_fun.fun1")  // a single pub entry
lec(fun1, a.fun1)

x = import("my_fun.mytup")

x.call3()               // prints call called
```

The import string is either a file (`import("file")`, which brings all the
`pub` entries) or a single pub entry (`import("file.pub_name")`). Directory
hierarchy uses slashes: `import("proj/dir/file.pub_name")`. There are no glob
patterns.

An `lg:` prefix imports an already-compiled **lgraph** instead of a source
unit — e.g. a Verilog module compiled earlier, or a previously built Pyrope
lambda:

```pyrope
const add_sub = import("lg:add_sub")  // the compiled module, not its source
```

The `import` points to a file [setup code](06b-instantiation.md#setup-code)
list of `pub` lambdas, types, and constants. The setup code corresponds to the
"top" scope in the imported file. Registers are intentionally excluded from
imports; use `regref` for register instances. The import statement can only be
executed during the setup phase. The import allows for cyclic dependencies between files as long as
there is no true cyclic dependency between variables. This means that "false"
cyclic dependencies are allowed but not true ones.

`import` always uses the declared `pub` name. The `lg` attribute
([explicit lgraph name](04b-attributes.md#lg-explicit-lgraph-name))
renames only the generated lgraph, never the import key:
`pub comb my_log::[lg="foo_mod"](...)` is still imported as
`import("my_fun.my_log")`.

There is no wildcard namespace import and no version pinning syntax; aliasing
is plain assignment:

```pyrope
import math::*       // error: wildcard import not allowed
import std@1.2 as s  // error: version pinning not supported

const math = import("some/hierarchy/math")  // alias by assignment
```

To select among library versions, point the import path at the desired
version. Different parts of a project may import different versions of the
same library this way.


The import behaves like cut and pasting the imported code. It is not a
reference to the file, but rather a cut and paste of functionality. This means
that when importing a constant or lambda, it creates a copy. If two files import
the same declaration, they are not referencing the same declaration, but each
has a separate copy.


The import is delayed until the imported declaration is used in the local file.
There is no order guarantee between imported files, just that the code needed
to compute the used imported declarations is executed before.


The import statement is a filename or path without the file extension.
Directories named `code`, `src`, and `lib` are skipped. No need to add them in
the path. `import` stops the search on the first hit. If no match happens, a
compile error is generated.


`import` allows specialized libraries per subproject.  For example, xx/yy/zz can
use a different library version than xx/bb/cc if the library is provided by yy,
or use a default one from the xx directory.

```pyrope
const a = import("prj1/file1")
const b = import("file1")       // import xxx_fun from file1 in the local project
const c = import("file2")       // import the functions from local file2
const d = import("prj2/file3")  // import the functions from project prj2 and file3
```

Many languages have a "using" or "import" or "include" command that includes
all the imported functions/constants to the current scope. Pyrope does not allow
that, but it is possible to use a mixin to add the imported functionality to a
tuple.

```pyrope
const b = import("prp/Number")
mut a = import("fancy/Number_mixin")

const Number = (...b, ...a) // patch the default Number class

mut x:Number = 3
```

### Register reference


While import "copies" file-scope declarations, `regref` or Register reference
allows code to reference (not copy) an existing register in the call hierarchy.


The syntax of `regref` is similar to `import` but the semantics are very
different. While `import` looks through Pyrope files, `regref` looks through
the instantiation hierarchy for matching register names or paths. `regref`
only gets a reference to a register; it can not import functions, constants,
types, or ordinary variables.

`regref` is independent of `pub`
([Visibility](04-variables.md#visibility-private-by-default-pub-to-export)):

* In **debug statements** (`assert`, `test`, `puts`, monitors), `regref`
  can read any register.
* In **synthesizable code**, `regref` can attach to an instantiated register
  outside the local scope. The attached reference behaves exactly like a
  local `reg`: bare reads return the `q` value, assignments drive the `din`
  input, and stage inference classifies it like any state register (see
  [Pipelining](06c-pipelining.md)). Because every access crosses the flop
  boundary, a `regref` connection is sequential by construction — it can
  never create a combinational path between distant modules.

```pyrope
mod do_increase() -> () {
  reg counter:u32 = 0     // no pub needed: puts below is a debug statement

  wrap counter = counter + 1
}

mod do_debug() -> () {
  const cntr = regref("do_increase/counter")

  puts("The counter value is {}", cntr)
}
```


Verilog has a more flexible semantics with the Hierarchical Reference. It also
allows to go through the module hierarchy and read/write the contents of any
variable. Pyrope only allows you to reference registers by unique name. Verilog
hierarchical reference is not popular for 2 main reasons: (1) It is considered
"not nice" to bypass the module interface and touch an internal variable; (2)
some tools do not support it as synthesizable; (3) the evaluation order is not
clear because the execution order of the modules is not defined.


Allowing only a single lambda to update registers avoids the evaluation order
problem. From a low level point of view, the updates go to the register `din`
pin, and the references read the register `q` pin. The register references
follow the model of single writer multiple reader.  This means that only a
single lambda can update the register, but many lambdas can read the register.
This allows to be independent on the `lambda` evaluation order.


The register reference uses instantiated registers. This means that if a lambda
having a register is called in multiple places, only one can write, and the
others are reading the update. It is useful to have configuration registers. In
this case, multiple instances of the same register can have different values.
As an illustrative example, a UART can have a register and the controller can
set a different value for each uart base register.

```pyrope
// file remote.prp

mod xxx(some:u32, code:u32) -> () {
  reg uart_addr:u32 = nil
  assert(0x400 > uart_addr >= 0x300)
}

// file local.prp
mod setup_xx() -> () {
  mut xx = regref("uart_addr") // match xxx.uart_addr if xxx is in hierarchy
  mut index = 0
  for val in ref xx {          // ref does not allow enumerate
    val = 0x300 + index * 0x10 // sets uart_addr to 0x300, 0x310, 0x320...
    index += 1
  }
}
```


Maybe the best way to understand the `regref` is to see the differences with
the `import`:

* Instantiation vs File hierarchy
  + `regref` finds matches across instantiated registers.
  + `import` traverses the file/directory hierarchy to find one match.
* Success vs Failure
  + `regref` keeps going to find all the matches, and it is possible to have a zero matches
  + `import` stops at the first match, and a compile error is generated if there is no match or multiple matches.


### Mocking library

One possible use of the register reference is to create a "mocking" library. A
mocking library instantiates a large design but forces some subblocks to
produce some results for testing. The challenge is that it needs undriven
registers. During testing, the `peek`/`poke` is more flexible and it can
overwrite an existing value. The peek/poke use the same reference as `import`
or register reference.

```pyrope
const bpred = ( // complex predictor
  comb taken(self) -> (r:bool) { r = self.some_table[som_var] >= 0 }
)

test "mocking taken branches" {
  poke("bpred_file/taken", true)

  mut l = core.fetch.predict(0xFFF)
}
```

## Operator overloading

There is no operator overload in Pyrope. `+` always adds Numbers, `...` always
splices/concatenates a tuple or a String, `and` is always for boolean types,...


## Init method (constructor)

Pyrope tuples can use the same syntax as a lambda call or a direct assignment.
Both forms follow the same ambiguity rules as lambda calls; see
[Argument naming](06-functions.md#argument-naming). In practice, name fields
when positional binding would be unclear.

```pyrope
const Typ1 = (
  const a:string = "none",
  const b:u32 = 0
)

const w = Typ1(a="foo", b=33)       // OK
const x:Typ1 = (a="foo", b=33)      // OK, same as before

const v:Typ1 = Typ1(a="foo", b=33)  // OK, but redundant Typ1
const y:Typ1 = ("foo", 33)          // OK, because no conflict by type

mut z:Typ1 = nil                    // OK, default field values
cassert(z.a == "none" and z.b == 0)
z = ("foo", 33)

cassert(v == w == x == y == z)
```

Pyrope allows an `init` method to intercept construction. The same `init`
method is called in all the previous construction forms: a typed declaration
(`mut x:T = value`), a `nil` declaration (`mut x:T = nil`), and an explicit
call (`T(value)`). `init` is an implicit construction hook and must be
declared as `comb`. If an operation needs register state, pipeline latency, or
other cycle-level side effects, make it an explicit `mod` or `pipe` method
instead.

`init` runs only at construction. Once the variable exists, assignments and
field writes are plain structural writes — no hook is invoked, and reads
always return the structural value.


```pyrope
const Typ2 = (
  mut a:string = "none",
  mut b:u32 = 0,
  comb init(ref self, a, b) { self.a = a; self.b = b }
)

mut x:Typ2 = (a="x", b=0)     // init(ref x, "x", 0)
mut y:Typ2 = ("hello", 44)    // init(ref y, "hello", 44)
mut z = Typ2("hello", 44)     // same init, explicit call form
cassert(y == z)

x.a = "hello"                 // plain field write, init is NOT called
x.b = 44
cassert(x == y)
```

Tuples can be multi-dimensional, and each dimension is indexed with its own
`[...]` (e.g. `m[i][j]`, not `m[i,j]`).

```pyrope
comb matrix8x8_set_xy(ref self, x:signed(min=0,max=7), y:signed(min=0, max=7), v:u16) {
  self.data[x][y] = v
}
comb matrix8x8_set_row(ref self, x:signed(min=0, max=7), v:u16) {
  for ent in ref self.data[x] {
    ent = v
  }
}

const Matrix8x8 = (
  mut data:[8][8]u16 = 0,
  comb init(ref self) {       // default construction
    for ent in ref self.data {
      ent = 0
    }
  },
  const set_xy  = matrix8x8_set_xy,
  const set_row = matrix8x8_set_row
)

mut m:Matrix8x8 = nil          // init runs
cassert(m.data[0][3] == 0)

m.set_xy(x=1, y=2, v=100)      // explicit method call
cassert(m.data[1][2] == 100)
m.set_row(x=1, v=3)
cassert(m.data[1][2] == 3)
m.data[4][5] = 33              // plain structural indexed write
cassert(m.data[4][5] == 33)
```

There is no read hook: indexing or reading a tuple field always returns the
structural value (`m.data[1]` is the row slice, `m.data[1][2]` the element).
After construction, indexed writes are also structural; custom write behavior
is an explicit method like `set_xy` above.

The `init` method can be [overloaded](06-functions.md#Overloading) to select
between construction forms.

```pyrope
comb my_2_elem_init_xv(ref self, x:unsigned(min=0,max=1), v:string) { self.data[x] = v }
comb my_2_elem_init_copy(ref self, v:My_2_elem)          { self.data = v.data }
comb my_2_elem_init_default(ref self)                    { self.data = ("", "") }

const My_2_elem = (
  mut data:[2]string = ("", ""),
  const init = [my_2_elem_init_xv, my_2_elem_init_copy, my_2_elem_init_default]
)

mut v:My_2_elem = nil          // init_default
mut x:My_2_elem = (1, "hello") // init_xv: data[1] = "hello"
mut w:My_2_elem = x            // init_copy

v.data[0] = "world"            // plain structural write

cassert(v.data == ("world", ""))
cassert(w.data[1] == "hello")

const z = w                    // plain structural copy, no hook involved
cassert(z equals w)
```


A nested tuple field can have its own `init`; computed views of hidden fields
are explicit `comb` methods.


```pyrope
const some_obj = (
  mut a1:string,
  mut a2 = (
    mut _val:u32 = nil,                        // hidden field
    comb init(ref self, x) { self._val = x + 1 },
    comb val(self) -> (r) { r = self._val + 100 }
  ),
  comb init(ref self, a, b) {                  // constructor
    self.a1 = a
    self.a2._val = b
  }
)

mut x:some_obj = ("hello", 3)

assert(x.a1 == "hello")
assert(x.a2.val() == 103)  // explicit method call; reads are never intercepted
```


Since there is no read hook, typecast-style views are also explicit methods,
dispatched by name at the call site:

```pyrope
comb my_obj_to_string(self) -> (r:string) { r = string(self.val) }
comb my_obj_to_bool(self)   -> (r:bool)   { r = self.val != 0 }
const my_obj = (
  ,mut val:u32 = 0
  ,const to_string = my_obj_to_string
  ,const to_bool   = my_obj_to_bool
)

mut s:my_obj = nil
s.val = 100
const r1:string = s.to_string()
const r2:bool   = s.to_bool()
```

### Attribute access in init

The `init` method can also access attributes:

```pyrope
mut obj1::[attr1] = (
  ,mut data:signed = nil
  ,comb init(ref self, v) {
    if v.[attr2] {
      self.data.[attr3] = 33
    }
    cassert(self.[attr1])
  }
)
```

### Default init value

All variable declarations need an explicit assigned value. For complex tuple
types, constructing with no arguments (`nil` or `T()`) triggers the no-arg
`init` overload below.


```pyrope
const fint:signed  = 0
cassert(fint == 0)

mut fbool:bool = false
cassert(!fbool)

comb tup_init_default(ref self) { // no-argument overload
  cassert(self.v == "")
  self.v = "empty33"
}
comb tup_init_v(ref self, v) {
  self.v = v
}
const Tup = (
  ,mut v:string = ""    // default to empty
  ,const init = [tup_init_default, tup_init_v]
)

mut x:Tup = nil
cassert(x.v == "empty33")

mut x2:Tup = "Padua"
cassert(x2.v == "Padua")

mut y = Tup()
cassert(y.v == "empty33")

mut y2 = Tup("ucsc")
cassert(y2.v == "ucsc")
```

### Array/Tuple access

Array indexing reads and writes the underlying field directly. Custom indexed
access is an explicit method; hidden fields (leading underscore) keep the
representation private.

```pyrope
const Point = (
  ,mut _x:signed = 0    // leading underscore: private to the tuple
  ,mut _y:signed = 0

  ,comb init(ref self, x:signed, y:signed) {
    self._x = x
    self._y = y
  }

  ,comb get(self, idx:string) -> (r:signed) {
    r = match idx {
     == 'x' { self._x }
     == 'y' { self._y }
     else   { 0        }
    }
  }
)

const p:Point = (1,2)

cassert(p.get('x') == 1 and p.get('y') == 2)
cassert(p._x == 1) // error: _x is private outside the tuple
```

## Compare method


The comparator operations (`==`, `!=`, `<=`,...) need to be overloaded for most
objects. Pyrope has the `lt` and `eq` methods to build all the other
comparators. When non-provided the `lt` (Less Than) is a compile error, and the
`eq` (Equal) compares that all the tuple fields are equal.


```pyrope
const t=(
  ,mut v:signed = 0
  ,comb init(ref self, a:signed) { self.v = a }
  ,comb lt(self,other)->(r:bool){ r = self.v  < other.v }
  ,comb eq(self,other)->(r:bool){ r = self.v == other.v }
)

mut m1:t = 4
mut m2:t = 10
assert(m1 < m2 and !(m1==m2))
assert(m1 <= m2 and m1 != m2 and m2 > m1 and m2 >= m1)
```


The default tuple comparator (`a == b`) compares values, not types like `a does
b`, but a compile error is created unless `a equals b` returns true. This means
that a comparison by tuple position suffices even for named tuples.

```pyrope
const t1=(
  ,long_name:string = "foo"
  ,b=33
)
const t2=(
  ,b=33
  ,long_name:string = "foo"
)
const t3=(
  ,33
  ,long_name:string = "foo"
)

cassert(t1==t2)
cassert(not (t1 equals t3))
const x = t1==t3           // error: t1 !equals t3
```

The comparator `a == b` when `a` or `b` are tuples is equivalent to:
```pyrope
cassert((a==b) == ((a in b) and (b in a)))
cassert(a equals b)
```

With the `eq` overload, it is possible to compare named and unnamed tuples.

```pyrope
const t1 = (
  ,mut long_name:string = "foo"
  ,mut b = 33
)

comb t2_eq_t1(self, o:t1) -> (r:bool) {
  r = self.xx_a == o.b and self.xx_y == o.long_name
}
comb t2_eq_t2(self, o:t2) -> (r:bool) {
  r = self.xx_a == o.xx_a and self.xx_y == o.xx_y
}
const t2 = (
  ,mut xx_a = 33
  ,mut yy_b = "foo"
  ,const eq = [t2_eq_t1, t2_eq_t2]
)

cassert(t1==t2 and t2==t1)
```

Since `a == b` can compare two different objects, it is not clear if `a.eq` or `b.eq` method
is called. Pyrope has the following rule:

* If only one of the two has a defined method, that method is called.
* If both have defined methods, they should have the same set of `eq` methods or a compile error is created.


It is also possible to provide a custom `ge` (Greater Than). The `ge` is redundant
with the `lt` and `eq` (`(a >= b) == (a==b or b<a)`) but it allows to have more
efficient implemetations:

For integer operations, the Pyrope should result to the following equivalent Lgraph:

* `a == b` is `__eq(a,b)`
* `a != b` is `__not(__eq(a,b))`
* `a  < b` is `__lt(a,b)`
* `a  < b` is `__lt(b,a)`
* `a <= b` is `__lt(a,b) | __eq(a,b)` (without `ge`) or `__ge(b,a)`
* `a >= b` is `__lt(b,a) | __eq(a,b)` (without `ge`) or `__ge(a,b)`


## Non-Pyrope (C++) calls

Calling C++ or external code is still fully synthesizable if the code is
available at compile time. An example could be calling a C++ API to read a json
file during the setup phase to decide configuration parameters.


```pyrope
const cfg = __read_json()

const ext = if cfg.foo.bar == 3 {
   foo
}else{
   bar
}
```


Non-Pyrope calls use the same Pyrope lambda definition.


If no type is provided, a C++ call assumes a `pipe(...inp)->(...out)` type is
can pass many inputs/outputs and has permission to mutate values. Any call to a
method with two underscores `__` is either a basic gate or a C++ function.

```pyrope
type T_my_cpp = comb(a, b) -> (e)
const __my_typed_cpp:T_my_cpp = nil
```

Type defining non-Pyrope code is good to catch errors and also because declaring
`comb` allows to handle several cases of circular dependencies not possible with `mod` [import section](10-internals.md)
