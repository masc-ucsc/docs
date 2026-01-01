# Small Pyrope – TODO Features

This document lists features not included in Small Pyrope with small code examples that should parse once implemented.

## Core Language Features

### Lambda capture
```pyrope
var a = 2
comb make_adder[a]() -> (f) {
  cassert a::[comptime]  // all captures are always comptime
  // Capture a, b from outer scope
  let b = 3
  f = fun[a, b] (x:int) -> (y:int) { a*x + b }
}
a= 1000     // Does not affect the capture value
let add2 = make_adder().f
assert add2(10) == 23
```
```ebnf
// Conventions
comma_sep         ::= "," { "," }
list<T>           ::= [comma_sep] T { [comma_sep] T } [comma_sep]

// Function definition and captures
function_definition ::= '[' [capture_list] ']' [ '<' typed_identifier_list '>' ] [arg_list]
                        ["->" (arg_list | type_or_identifier)]
                        ["where" expression_list]
                        { ("requires" | "ensures") expression }
                        scope_statement
capture_list       ::= typed_identifier [ '=' expression_with_comprehension ]
                        { ',' typed_identifier [ '=' expression_with_comprehension ] }
```

### Tuple scope and self
```pyrope
var point = (x=10, y=20,
  // Method using tuple scope
  comb move(self, dx:int, dy:int) -> (out) {
    out = (x=self.x + dx, y=self.y + dy)
  }
  ,move2 = comb(self, dx:int, dy:int) -> (out:int) { // Also legal
    out = (x=self.x + dx, y=self.y + dy)
  }
)
let p2 = point.move(1, -2)
assert p2.x == 11 and p2.y == 18
// NOTE: `self` is explicit; earlier drafts suggested implicit `self`, which is invalid.
```
```ebnf
tuple_item       ::= function_inline scope_statement | ...
function_inline  ::= ("fun"|"comb"|"pipe"|"flow") identifier [ '<' typed_identifier_list '>' ] [arg_list] ["->" arg_list]
(* Conventional method: first parameter named 'self'; no special grammar. *)
```

### Optional types ("?")
```pyrope
var maybe_u8:u8 = _         // default invalid
cassert !maybe_u8::[valid]
maybe_u8 = 5
cassert maybe_u8::[valid]
if maybe_u8? {               // test valid
  assert maybe_u8 == 5
}
var pkt = (data:u16, valid:bool)
if pkt.data? { // sugar for pkt.data::[valid]
  puts "data=", pkt.data
}
// NOTE: `_` is default value (empty/zero/false). Invalid means `!x::[valid]`.
```
```ebnf
optional_expression ::= expression '?'
```

### Type operators (does, equals, case, is)
```pyrope
type Eq = ( comb eq(self, other) -> bool )
type Point = (x:int, y:int)
impl Eq for Point ( comb eq(self, o:Point) -> bool { self.x == o.x and self.y == o.y } )

let p:Point = (x=1, y=2)
assert p does Eq
assert (Point does p)
assert (Point does (x:int, y:int))

// NOTE: No `trait` keyword; use `type` for interfaces and `impl` blocks for attachment.
type Eq = (comb eq(self, other) -> bool)
type Point = (x:int, y:int)
impl Eq for Point ( comb eq(self, o:Point) -> bool { self.x == o.x and self.y == o.y } )

let p:Point = (x=1, y=2)
let x:Point = (x=3, y=2)
cassert p does Point
cassert p does Eq
cassert p is Point           // nominal type matches declared type
cassert p !is Eq             // `is` is nominal; interfaces are not nominally equal
cassert p.eq(p)
cassert !p.eq(x)
match p {
  does (x:int, y:int) { puts "p matches fields (x,y)" }
}
```ebnf
type_compare_op   ::= 'does' | '!does' | 'equals' | '!equals' | 'is' | '!is' | 'case' | '!case'
binary_expression ::= expression type_compare_op expression | ...
```
```

Some case/does/equals assertion:
* `a does b` is the tuple structure of `a` a subset of `b`
* `a equals b` same as `(a does b) and (b does a)`
* `a case b` same as `cassert a does b` and for each `b` field with a defined value,
  the value matches `a` (`nil`, `0sb?` are undefined values)
* `a is b` is a nominal type check. Equivalent to `a::[typename] == b::[typename]`

```
cassert((a=1,b=2) has "a")

cassert (a=1,b=3) does (b=100,a=333,e=40,5)
cassert (a=1,3) does (a=100,300,b=333,e=40,5)
cassert (a=1,3) !does (b=100,300,a=333,e=40,5)

var t1 = (a:int=1, b:string)
let t2 = (a:int=100, b:string)
cassert t1 equals t2
cassert t1 != t2
t1.a=100
cassert t1 == t2
```

### Advanced pattern matching
```pyrope
let v = (tag="sum", a=1, b=2)
let r = match v {
  case (tag="sum", a, b) { v.a + v.b }
  case (tag="val", x)     { v.x }
  else                     { 0 }
}
cassert r == 1+2
```
```ebnf
match_expression ::= 'match' stmt_list '{' [match_list] '}'
match_list       ::= (match_cond scope_statement)+
match_cond       ::= ( [match_operator] expression_list ) | 'else'
```

### Matching with local scope variables
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

## String and I/O Features

### String interpolation
```pyrope
let name = "Pyrope"
let msg  = "Hello {name}!"
puts msg
```
```ebnf
complex_string_literal ::= '"' { ( escape | text | '{' [expression] '}' ) } '"'
```

### String methods
```pyrope
let s = "hello"
assert s.len() == 5
assert s.find("ll") == 2
assert s.substr(1,3) == "ell"
// NOTE: Names/returns similar to C++23 string_view; not grammar-relevant.
```

### File I/O
```pyrope
let cfg = read_file("config.txt")
puts cfg
// NOTE: File I/O comes from imported C++ methods; no special grammar.
```

## Advanced Types

### Variant types (sum types)

```pyrope
// NOTE: The following snippet is not valid Pyrope
type Option[T] = Some(T) | None  // compile error or invalid syntax
let a:Option(_:u8) = Some(3)
let b:Option[u8] = None          // compile error as None is not a valid type/variable either
match a { Some(v): v+1, None: 0 } // compile error, wrong match syntax
```
// NOTE: Correct Pyrope variant example follows:
```
type v_type = variant(str:String, num:int) // No default value in variant

let another_x:variant(IntKind:int, StrKind:string)=_

var vv:v_type = (num=0x65)
cassert vv.num == 0x65
let xx = vv.str                         // compile error: active variant is `num`

let Vtype = variant(str:String, num:int, b:bool)

let x1a:Vtype = "hello"                 // implicit variant type
let x1b:Vtype = (str="hello")           // explicit variant type

var x2:Vtype:[comptime] = "hello"       // comptime

cassert x1a.str == "hello" and x1a == "hello"
cassert x1b.str == "hello" and x1b == "hello"

let err1 = x1a.num                      // compile error: active variant is `str`
let err2 = x1b.b                        // compile error: active variant is `str`
let err3 = x2.num                       // compile error: comptime value is `str`
```
```ebnf
(* Proposed *)
enum_block            ::= 'enum' identifier '{' { ',' identifier ':' ( type | arg_list ) '=' '_' } [ ',' ] '}'
variant_type          ::= 'variant' arg_list
enum_assignment_stmt  ::= ('enum' | 'variant') identifier '=' tuple ';'
```

### Complex enumerations (ADTs)
```pyrope
// Define an ADT with associated values
enum Expr (
    ,,, // extra commas are OK (no meaning)
    ,number:Int=_
    ,,, // extra commas are OK (no meaning)
    ,add:(_:Expr, _:Expr)=_
    ,,, // extra commas are OK (no meaning)
)

// Evaluate recursively
comb eval(e: Expr) -> int {
    match e {
      does Expr.number { e.number }
      does Expr.add    { eval(e.add[0]) + eval(e.add[1]) }
    }
}

let expr = Expr.add(Expr.number(2), Expr.number(3))
puts "result:{eval(expr)} should be 5"
```
```ebnf
(* Proposed; see enum_block above *)
```

```
let ADT = enum(
  Person:(eats:string) = _,
  Robot:(charges_with:string) = _
)

let nourish = fun(x:ADT) {
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
enum Token ( Id:string=_, Lit:variant(IntKind:int, StrKind:string)=_ )
```
```ebnf
(* Proposed; uses enum_block with nested variant types *)
```

### Generic types
```pyrope
// ->() is an explicit void return
type Queue<T> = (push:comb(T)->(), pop:comb()->(T), empty:comb()->(bool))

// Same meaning, generic list is allowed before tuple declarations
let  Queue = type<T>(push:comb(T)->(), pop:comb()->(T), empty:comb()->(bool))

// comb, type, flow, pipe can have an option <parameter_list>

let triadd1 = comb<T>(a:T, b:T, c:T) -> T { a + b + c }
let triadd2 = pipe<T>::[stages=3] (a:T, b:T, c:T) ->T { a + b + c }
let triadd3 = flow<T> (a:T, b:T, c:T) ->T { a@0 + b@0 + c@0 }
cassert triadd1(1,2,3) == 6
```
```ebnf
(* Proposed *)
type_definition   ::= 'type' [ '<' typed_identifier_list '>' ] identifier '=' tuple
function_type     ::= ("fun"|"comb"|"pipe"|"flow") [ '<' typed_identifier_list '>' ] [arg_list] ["->" arg_list]
```

### Traits and mixins
```pyrope
// No trait keyword, but `type`
type Show ( comb show(self) -> String )
impl Show for int ( comb show(self) -> String { "_{self}_" } )
cassert 42.show() == "_42_"
```
```ebnf
(* Proposed *)
interface_type   ::= 'type' identifier '(' { function_type [identifier] [arg_list] ["->" arg_list] } ')'
impl_block       ::= 'impl' identifier 'for' identifier '(' { function_definition } ')'
```


### Row types (extensible records)
```pyrope
// NOTE: Use `...r` binding; prior `..r` was incorrect.
let r:(z:int) = 100
let p:(x:int, y:int, ...r) = (x=1, y=2, z=3)
let q_wrong:(x:int, ...r) = p     // compile error: `r` binds only (z:int); `p` has extra fields
let q:(x:int, ...r) = (x=1,z=10)  // OK
```
```ebnf
(* Proposed (type-level spreads) *)
row_type       ::= '(' field_type_list [ ',' '...' identifier ] ')'
field_type     ::= identifier ':' type
```

## Verification and Testing

### Advanced assertions
```pyrope
comb div(a:int, b:int) -> (q:int) {
  requires b != 0
  ensures  a == q*b + (a % b)
  q = a / b
}

let a = some_call(z)
optimize a < 1000  // a should never be over 1000, optimize accordingly
```
```ebnf
func_def_verification ::= ('requires' | 'ensures') expression
(* Proposed *) optimize_statement ::= 'optimize' expression ';'
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
```ebnf
(* Proposed *) cover_statement ::= 'cover' '(' expression ')' ';'
if_expression    ::= ['unique'] 'if' stmt_list scope_statement ('elif' scope_statement)* ['else' scope_statement]
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
let (out_t) =  mymod(clock=clk, reset=rst, a=in_a)
// NOTE: Same form as comb/pipe/flow calls; import handles RTL binding.
```
```ebnf
function_call        ::= complex_identifier tuple
simple_function_call ::= complex_identifier expression_list
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
let v = if in? { stage(in) } else { 0 }
```
```ebnf
(* Proposed *)
function_type ::= ("fun"|"comb"|"pipe"|"flow") [ '[' identifier { ',' identifier } ']' ] [ '<' typed_identifier_list '>' ] [arg_list] ["->" arg_list]
```

### Bus structures and high-impedance
```pyrope
var bus:u1 = 'z'              // compile error: no 'z' literal in Pyrope
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
var i = 0
while::[some_attribute=true] 1<10 {
  i += 1
}
while::[elastic=true] var z=1; x {
  x -= z
}
for::[
  ,loop_coalesce=2    // optional: help the compiler
  ,ivdep=true         // assert no loop-carried deps on chosen arrays
  ,unroll=2           // replicate body (if legal)
  ,ii=1
] var total=0; j in 0..<n {
  total += j
  puts total
}
```
```ebnf
while_statement  ::= 'while' stmt_list scope_statement
for_statement    ::= 'for' ( '(' typed_identifier ((',' typed_identifier)*) ')' | typed_identifier )
                      'in' (ref_identifier | expression_list) scope_statement
loop_statement   ::= 'loop' scope_statement
```

## Module System

### Advanced import features
```pyrope
import math::*        // compile error: wildcard import not allowed
import io as I
// NOTE: No wildcard-imports; use assignment or explicit aliasing.
// Some legal equivalent options:

let math = import("some/hierarchy/math")
import some.hierarchy.math as math

let myio = import("some/io/lib")
import "some/io/lib" as myio2
```
```ebnf
(* Proposed *) import_alias ::= 'import' identifier 'as' identifier
(* Current parsing treats 'import(...)' as a normal function call. *)
```

### Register references and no namespaces
```pyrope
namespace top { reg counter = 0 } // compile error, no namespace
regref r = top::counter      // compile error: no namespace access like this
let r = regref(top.counter) // library function call
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

let add = add1 ++ add2 // (add1, ...add2) should work too

let x = add(1u8, 2u8)
let y = add(-1i8, 2i8)
```
A more complex example:
```
let base = (
  fun1 = fun() { 1 },         // catch all
  fun2 = fun() { 2 },         // catch all
)
let ext = base ++ (
  fun1 = fun(a, b) { 4 },   // overwrite allowed with extends (++), not in-place (...)
  fun2 = fun(a, b) { 5 } ++ fun() { 6 },  // append
  fun3 = fun(a, b) { 7 } ++ fun() { 8 }   // base has no fun3
)

var t:ext = _

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

```
comb x1(a:int,b)->int { 3 }
comb x2(a:int,b)->(x) { 3 }
comb x3(a:int,b=5)->(x:int) { 3 }
comb x4(a:int,b:int3)->(x:int) { 3 }

let x5 = comb(a:int,b)->int { 3 }
let x6 = comb(a:int=10,b)->(x) { 3 }
let x7 = comb(a:int,b)->(x:int) { 3 }
let x8 = comb(a:int,b:int3)->(x:int) { 3 }
```


The tuple concat/in-place example with checks:
```
var a=(a=1,b=2)
let b=(c=3)

let ccat1 = a ++ b
assert ccat1 == (a=1,b=2,c=3)
assert ccat1 == (1,2,3)

var ccat2 = a ++ (b=20) ++ b
assert ccat2 == (a=1,b=(2,20),c=3)
assert ccat2 == (1,(2,20),3)

var join1 = (...a,...b)
assert join1 == (a=1,b=2,c=3)
assert join1 == (1,2,3)

var join2 = (...a,...(b=20)) // compile error, 'b' already exists
```
```ebnf
overload_set ::= function_definition { '++' function_definition }
(* Semantics: dispatch by best-argument match; no extra grammar beyond '++'. *)
```

### Getter/setter methods
```pyrope
type RegBox = (reg v:int,
  comb get(self) -> (_:int) { self.v },
  pipe set(self, x:int) { self.v = x }  // pipe as it accesses a register
)

let rb:RegBox = (v=0)
rb.set(3)
assert rb.get() == 3
// NOTE: Methods inside tuple types are allowed. Also valid:

let RegBox = (reg v:int,
  get = comb(self) -> int { self.v },
  set = pipe(self, x:int) -> () { self.v = x }  // pipe as it accesses a register
)

```
```ebnf
tuple_item     ::= function_inline scope_statement | identifier '=' function_inline scope_statement | ...
```

### Operator overloading
```pyrope
type Vec2 = (x:int, y:int)
type addition<T> = comb(a:T, b:T) -> T
impl addition for Vec2 (
  comb add(a:Vec2, b:Vec2) -> Vec2 { (x=a.x+b.x, y=a.y+b.y) }
)
let v = (x=1,y=2).add(x=3,y=4)
// NOTE: Overloading via interface type + `impl`; example adjusted.
```

### Introspection
```pyrope
assert type_of(1) == int            // compile error: use attributes, not `type_of`
let flds = fields_of((x=1, y=2))    // compile error: use `has`/pattern-matching
// NOTE: Prefer attributes and operators (`has`/`does`/`equals`). Examples:
cassert 1::[typename] == int::[typename]
cassert ((x=1,y=2) has "x")

```
```ebnf
attribute_access ::= expression '::' attributes
binary_expression ::= expression 'has' expression | ...
```

### Union/bit reinterpretation
```pyrope
let x:u32 = 0xDEADBEEF
let b:(u8,u8,u8,u8) = reinterpret x   // compile error: no `reinterpret` operator
// NOTE: Use explicit slicing/packing for reinterprets.
let b:(u8,u8,u8,u8) = (x[0..=7], x[8..=15], x[16..=23], x[24..=31])
```
```ebnf
(* No new grammar; uses slicing and tuple construction. *)
```

## Synthesis and Optimization

### Placement, timing, power attributes
```pyrope
reg r::[left_of=other, max_delay=2, low_power=true, donttouch] = 0
```

## Standard Library

### Data structures
```pyrope
let std = import('std')
let q = std.queue.make[int](depth=16)
q.push(1)
assert !q.empty()
let v = q.pop()
```

### Math and utilities
```pyrope
let std = import('std')
assert std.math.gcd(12, 18) == 6
let s = std.str.join(("a","b"), ",")
```
