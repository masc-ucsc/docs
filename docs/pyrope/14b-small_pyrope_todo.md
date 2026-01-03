# Small Pyrope – TODO Features

This document lists features not included in Small Pyrope with small code examples that should parse once implemented.

## Core Language Features

### Lambda capture
```pyrope
mut a = 2
comb make_adder[a]() -> (f) {
  cassert a::[comptime] == true  // all captures are always comptime
  // Capture a, b from outer scope
  const b = 3
  f = comb[a, b] (x:int) -> (y:int) { a*x + b }
}
a= 1000     // Does not affect the capture value
const add2 = make_adder().f
assert add2(10) == 23
```

### Tuple scope and self
```pyrope
mut point = (x=10, y=20,
  // Method using tuple scope
  comb move(self, dx:int, dy:int) -> (out) {
    out = (x=self.x + dx, y=self.y + dy)
  }
  ,move2 = comb(self, dx:int, dy:int) -> (out:int) { // Also legal
    out = (x=self.x + dx, y=self.y + dy)
  }
)
const p2 = point.move(1, -2)
assert p2.x == 11 and p2.y == 18
// NOTE: `self` is explicit; earlier drafts suggested implicit `self`, which is invalid.
```

### Optional types ("?")
```pyrope
mut maybe_u8:u8 = ?         // default invalid
cassert maybe_u8::[valid] == false
maybe_u8 = 5
cassert maybe_u8::[valid] == true
if maybe_u8? {               // test valid (sugar for maybe_u8::[valid] == true)
  assert maybe_u8 == 5
}
mut pkt = (data:u16, valid:bool)
if pkt.data? { // sugar for pkt.data::[valid] == true
  puts "data=", pkt.data
}
// NOTE: `?` is default value (unknown/invalid). Invalid means `x::[valid] == false`.
```

### Type operators (does, equals, case, is)
```pyrope
type Eq = ( comb eq(self, other) -> bool )
type Point = (x:int, y:int)
impl Eq for Point ( comb eq(self, o:Point) -> bool { self.x == o.x and self.y == o.y } )

const p:Point = (x=1, y=2)
assert p does Eq
assert (Point does p)
assert (Point does (x:int, y:int))

// NOTE: No `trait` keyword; use `type` for interfaces and `impl` blocks for attachment.
type Eq = (comb eq(self, other) -> bool)
type Point = (x:int, y:int)
impl Eq for Point ( comb eq(self, o:Point) -> bool { self.x == o.x and self.y == o.y } )

const p:Point = (x=1, y=2)
const x:Point = (x=3, y=2)
cassert p does Point
cassert p does Eq
cassert p is Point           // nominal type matches declared type
cassert p !is Eq             // `is` is nominal; interfaces are not nominally equal
cassert p.eq(p)
cassert !p.eq(x)
match p {
  does (x:int, y:int) { puts "p matches fields (x,y)" }
}
```

Some case/does/equals assertion:
* `a does b` is the tuple structure of `a` a subset of `b`
* `a equals b` same as `(a does b) and (b does a)`
* `a case b` same as `cassert a does b` and for each `b` field with a defined value,
  the value matches `a` (`nil`, `0sb?` are undefined values)
* `a is b` is a nominal type check. Equivalent to `a::[typename] == b::[typename]`
cassert((a=1,b=2) has "a")

cassert (a=1,b=3) does (b=100,a=333,e=40,5)
cassert (a=1,3) does (a=100,300,b=333,e=40,5)
cassert (a=1,3) !does (b=100,300,a=333,e=40,5)

mut t1 = (a:int=1, b:string)
const t2 = (a:int=100, b:string)
cassert t1 equals t2
cassert t1 != t2
t1.a=100
cassert t1 == t2

### Advanced pattern matching
```pyrope
const v = (tag="sum", a=1, b=2)
const r = match v {
  case (tag="sum", a, b) { v.a + v.b }
  case (tag="val", x)     { v.x }
  else                     { 0 }
}
cassert r == 1+2
```

### Matching with local scope variables
```pyrope
if mut x=3; x<4 {
  cassert x==3
}
while mut z=1; x {
  x -= z
}
mut z=0
match mut x=2 ; z+x {
  case 2 { cassert true  }
  != 7   { cassert true  }
  else   { cassert false }
}
```

## String and I/O Features

### String interpolation
```pyrope
const name = "Pyrope"
const msg  = "Hello {name}!"
puts msg
```

### String methods
```pyrope
const s = "hello"
assert s.len() == 5
assert s.find("ll") == 2
assert s.substr(1,3) == "ell"
// NOTE: Names/returns similar to C++23 string_view; not grammar-relevant.
```

### File I/O
```pyrope
const cfg = read_file("config.txt")
puts cfg
// NOTE: File I/O comes from imported C++ methods; no special grammar.
```

## Advanced Types

### Variant types (sum types)

```pyrope
// NOTE: The following snippet is not valid Pyrope
type Option[T] = Some(T) | None  // compile error or invalid syntax
const a:Option(_:u8) = Some(3)
const b:Option[u8] = None          // compile error as None is not a valid type/variable either
match a { Some(v): v+1, None: 0 } // compile error, wrong match syntax
```
// NOTE: Correct Pyrope variant example follows:
```pyrope
type v_type = variant(str:String, num:int) // No default value in variant

const another_x:variant(IntKind:int, StrKind:string)=?

mut vv:v_type = (num=0x65)
cassert vv.num == 0x65
const xx = vv.str                         // compile error: active variant is `num`

type Vtype = variant(str:String, num:int, b:bool)

const x1a:Vtype = "hello"                 // implicit variant type
const x1b:Vtype = (str="hello")           // explicit variant type

mut x2:Vtype:[comptime=true] = "hello"    // comptime

cassert x1a.str == "hello" and x1a == "hello"
cassert x1b.str == "hello" and x1b == "hello"

const err1 = x1a.num                      // compile error: active variant is `str`
const err2 = x1b.b                        // compile error: active variant is `str`
const err3 = x2.num                       // compile error: comptime value is `str`
```

### Complex enumerations (ADTs)
```pyrope
// Define an ADT with associated values
enum Expr = (
    ,,, // extra commas are OK (no meaning)
    ,number:Int=?
    ,,, // extra commas are OK (no meaning)
    ,add:(_:Expr, _:Expr)=?
    ,,, // extra commas are OK (no meaning)
)

// Evaluate recursively
comb eval(e: Expr) -> int {
    match e {
      does Expr.number { e.number }
      does Expr.add    { eval(e.add[0]) + eval(e.add[1]) }
    }
}

const expr = Expr.add(Expr.number(2), Expr.number(3))
puts "result:{eval(expr)} should be 5"
```

```pyrope
enum ADT = (
  Person:(eats:string) = ?,
  Robot:(charges_with:string) = ?
)

const nourish = comb(x:ADT) {
  match x {
    does ADT.Person { puts "eating:{x.eats}" }
    does ADT.Robot { puts "charging:{x.charges_with}" }
  }
}

test "my main" {
  (_:Person="pizza", _:Robot="electricity").each(nourish)
}
```

### Hierarchical enums
```pyrope
enum Token = ( Id:string=?, Lit:variant(IntKind:int, StrKind:string)=? )
```

### Generic types
```pyrope
// ->() is an explicit void return
type Queue<T> = (push:comb(T)->(), pop:comb()->(T), empty:comb()->(bool))

// Same meaning, generic list is allowed before tuple declarations
const Queue = type<T>(push:comb(T)->(), pop:comb()->(T), empty:comb()->(bool))

// comb, type, flow, pipe can have an option <parameter_list>

const triadd1 = comb<T>(a:T, b:T, c:T) -> T { a + b + c }
const triadd2 = pipe<T>::[stages=3] (a:T, b:T, c:T) ->T { a + b + c }
const triadd3 = flow<T> (a:T, b:T, c:T) ->T { a@0 + b@0 + c@0 }
cassert triadd1(1,2,3) == 6
```

### Traits and mixins
```pyrope
// No trait keyword, but `type`
type Show ( comb show(self) -> String )
impl Show for int ( comb show(self) -> String { "_{self}_" } )
cassert 42.show() == "_42_"
```


### Row types (extensible records)
```pyrope
// NOTE: Use `...r` binding; prior `..r` was incorrect.
const r:(z:int) = 100
const p:(x:int, y:int, ...r) = (x=1, y=2, z=3)
const q_wrong:(x:int, ...r) = p     // compile error: `r` binds only (z:int); `p` has extra fields
const q:(x:int, ...r) = (x=1,z=10)  // OK
```

## Verification and Testing

### Advanced assertions
```pyrope
comb div(a:int, b:int) -> (q:int) {
  requires b != 0
  ensures  a == q*b + (a % b)  // Note: % is compile-time only
  q = a / b
}

const a = some_call(z)
optimize a < 1000  // a should never be over 1000, optimize accordingly
```

### Coverage directives and testing
```pyrope
cover (state == IDLE and start)
unique if x {
  y = 1
} elif z {
  y = 2
} else {
  y = 3
}
// NOTE: `unique if` asserts at most one branch condition holds at a time.
```

### Debug attributes
```pyrope
out = core(some_inputs)

x = peek(core.xx.some_wire)
poke(core.yy.some_register, 1)
// NOTE: `peek`/`poke` are library functions; no grammar change required.
```

## Advanced Hardware Features

### RTL instantiation
```pyrope
// Instantiate external RTL with port mapping
const (out_t) =  mymod(clock=clk, reset=rst, a=in_a)
// NOTE: Same form as comb/pipe/flow calls; import handles RTL binding.
```

### Advanced pipelining (elastic)
```pyrope
pipe stagetocreate::[elastic=true,stages=2..<8] (in:int) -> (out:int) {
  out = in + 1
}
pipe stage2::[stages=2..<8] (in:int) -> (out:int) {
  out = in + 1
}
// NOTE: `elastic` enables validity checks like `in?`; otherwise same syntax.
// Example usage:
const v = if in? { stage(in) } else { 0 }
```

### Bus structures and high-impedance
```pyrope
mut bus:u1 = 'z'              // compile error: no 'z' literal in Pyrope
bus = a when enable else 'z'  // compile error: no 'z' literal in Pyrope
// NOTE: Use bus resolution as a function-style primitive:
(a,b) = bus(a,b)
```

### Memory compilers
```pyrope
reg ram:[1024]u32:[macro="sram_32kx32", latency=1] = 0
```

## Control Flow Extensions

### Runtime loops

Loop attributes are passed and the compiler is responsible to decide if this loop can be partitioned and how.
```pyrope
mut i = 0
while::[some_attribute=true] 1<10 {
  i += 1
}
while::[elastic=true] mut z=1; x {
  x -= z
}
for::[
  ,loop_coalesce=2    // optional: help the compiler
  ,ivdep=true         // assert no loop-carried deps on chosen arrays
  ,unroll=2           // replicate body (if legal)
  ,ii=1
] mut total=0; j in 0..<n {
  total += j
  puts total
}
```

## Module System

### Advanced import features
```pyrope
import math::*        // compile error: wildcard import not allowed
import io as I
// NOTE: No wildcard-imports; use assignment or explicit aliasing.
// Some legal equivalent options:

const math = import("some/hierarchy/math")
import some.hierarchy.math as math

const myio = import("some/io/lib")
import "some/io/lib" as myio2
```

### Register references and no namespaces
```pyrope
namespace top { reg counter = 0 } // compile error, no namespace
regref r = top::counter      // compile error: no namespace access like this
const r = regref(top.counter) // library function call
// NOTE: Treat regref as a library call; no grammar impact.
```

### Library versioning
```pyrope
import std@1.2 as s  // compile error: version pinning not supported
// NOTE: Use import hierarchy/path to select versions if needed.
```

## Advanced Language Features

### Function overloading
```pyrope
comb add1(a:u8, b:u8) -> int { a + b }
comb add2(a:i8, b:i8) -> int { a + b }

const add = add1 ++ add2 // (add1, ...add2) should work too

const x = add(1u8, 2u8)
const y = add(-1i8, 2i8)
```
A more complex example:
```pyrope
const base = (
  fun1 = comb() { 1 },         // catch all
  fun2 = comb() { 2 },         // catch all
)
const ext = base ++ (
  fun1 = comb(a, b) { 4 },   // overwrite allowed with extends (++), not in-place (...)
  fun2 = comb(a, b) { 5 } ++ comb() { 6 },  // append
  fun3 = comb(a, b) { 7 } ++ comb() { 8 }   // base has no fun3
)

mut t:ext = ?

// t.fun1 only has ext.fun1
assert t.fun1(a=1,b=2) == 4
t.fun1()                 // compile error: no overload without arguments

// t.fun2 has base.fun2 and then ext.fun2
assert t.fun2(1,2) == 5  // EXACT match of arguments has higher priority
assert t.fun2() == 2     // base.fun2 catches all ahead of ext.fun2

// t.fun3 has ext.fun3 (no base.fun3)
assert t.fun3(1,2) == 7  // EXACT match of arguments has higher priority
assert t.fun3() == 8     // ext.fun3 catches all ahead of ext.fun3

```

Pyrope function declaration matches swift with the exception than Pyrope captures only compile time variables
with `[var1,var2,...]` list after the generic and before the parenthesis.

```pyrope
comb x1(a:int,b)->int { 3 }
comb x2(a:int,b)->(x) { 3 }
comb x3(a:int,b=5)->(x:int) { 3 }
comb x4(a:int,b:int3)->(x:int) { 3 }

const x5 = comb(a:int,b)->int { 3 }
const x6 = comb(a:int=10,b)->(x) { 3 }
const x7 = comb(a:int,b)->(x:int) { 3 }
const x8 = comb(a:int,b:int3)->(x:int) { 3 }
```


The tuple concat/in-place example with checks:
```pyrope
mut a=(a=1,b=2)
const b=(c=3)

const ccat1 = a ++ b
assert ccat1 == (a=1,b=2,c=3)
assert ccat1 == (1,2,3)

mut ccat2 = a ++ (b=20) ++ b
assert ccat2 == (a=1,b=(2,20),c=3)
assert ccat2 == (1,(2,20),3)

mut join1 = (...a,...b)
assert join1 == (a=1,b=2,c=3)
assert join1 == (1,2,3)

mut join2 = (...a,...(b=20)) // compile error, 'b' already exists
```

### Getter/setter methods
```pyrope
type RegBox = (reg v:int,
  comb get(self) -> (_:int) { self.v },
  pipe set(self, x:int) { self.v = x }  // pipe as it accesses a register
)

const rb:RegBox = (v=0)
rb.set(3)
assert rb.get() == 3
// NOTE: Methods inside tuple types are allowed. Also valid:

const RegBox = (reg v:int,
  get = comb(self) -> int { self.v },
  set = pipe(self, x:int) -> () { self.v = x }  // pipe as it accesses a register
)

```

### Operator overloading
```pyrope
type Vec2 = (x:int, y:int)
type addition<T> = comb(a:T, b:T) -> T
impl addition for Vec2 (
  comb add(a:Vec2, b:Vec2) -> Vec2 { (x=a.x+b.x, y=a.y+b.y) }
)
const v = (x=1,y=2).add(x=3,y=4)
// NOTE: Overloading via interface type + `impl`; example adjusted.
```

### Introspection
```pyrope
assert type_of(1) == int            // compile error: use attributes, not `type_of`
const flds = fields_of((x=1, y=2))    // compile error: use `has`/pattern-matching
// NOTE: Prefer attributes and operators (`has`/`does`/`equals`). Examples:
cassert 1::[typename] == int::[typename]
cassert ((x=1,y=2) has "x")

```

### Union/bit reinterpretation
```pyrope
const x:u32 = 0xDEADBEEF
const b:(u8,u8,u8,u8) = reinterpret x   // compile error: no `reinterpret` operator
// NOTE: Use explicit slicing/packing for reinterprets.
const b:(u8,u8,u8,u8) = (x[0..=7], x[8..=15], x[16..=23], x[24..=31])
```

## Synthesis and Optimization

### Placement, timing, power attributes
```pyrope
reg r:[left_of=other, max_delay=2, low_power=true, donttouch=true] = 0
```

## Standard Library

### Data structures
```pyrope
const std = import('std')
const q = std.queue.make[int](depth=16)
q.push(1)
assert !q.empty()
const v = q.pop()
```

### Math and utilities
```pyrope
const std = import('std')
assert std.math.gcd(12, 18) == 6
const s = std.str.join(("a","b"), ",")
```
