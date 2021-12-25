# Tuples

Tuples are a basic construct in Pyrope. Tuples are defined as an "ordered"
sequence fields or entries that can be named.


```
let b = (f1=3,f2=4) // b is named and ordered
let c = (1,d=4)     // c is ordered and unnamed (some entries are not named)
```

To access fields in a tuple we use the dot `.` or `[]`
```
let a = (
  ,r1 = (b=1,c=2)
  ,r2 = (3,4)
)
// different ways to access the same field
assert a.r1.c    == 2
assert a['r1'].c == 2
assert a.r1.1    == 2
assert a.r1[1]   == 2
assert a[0][1]   == 2
assert a[0]['c'] == 2
assert a['r1.c'] == 2
assert a['r1.1'] == 2
assert a['0.c']  == 2
assert a['0.1']  == 2
assert a.0.c     == 2
assert a.0.1     == 2
```

There is introspection to check for an existing field with the `has` and `has
no` operators.

```
let a = (foo = 3)
assert a has 'foo'
assert !(a has 'bar')
assert a has no 'bar' // "has no" is the opposite of "has"
assert a has 0
assert !(a has 1)
assert a has no 1
```

Tuple named fields can have a default type and or contents:

```
let val = 4
let x = (
  ,field1=1         // field1 with implicit type and 1 value
  ,field2:string    // field2 with explicit type and "" default value
  ,field3:int = 3   // field3 with explicit type and 3 value
  ,val              // unnamed field with value `val` (4)
)
```

## Everything is a Tuple

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

```
a = (1,2)   // tuple of 2 entries, 1 and 2
b = (1)     // tuple of 1 entry, 1
c = 1       // tuple of 1 entry, 1
d = (,,1,,) // tuple of 1 entry, 1
assert a.0 == b.0 == c.0 == d.0
assert a!=b
assert b == c == d
```

Tuple can have attributes associated with each entry. These attributes start with
a double underscore `__attr_sample`. A tuple with a single entry element is
called a scalar. A tuple with a single element and no attributes is called a
trivial scalar.


Tuples are used in many places:

* The arguments for a call function are a tuple. E.g: `fcall(1,2)`
* The return of a function call is always a tuple. E.g: `foo = fcall()`
* The index for a selector `[...]` is a tuple. As syntax sugar, the tuple parenthesis can be omitted. E.g: `foo@[0,2,3]`
* The complex type declaration are a tuple. E.g: `type x = (f=1,var b:string)`

The tuple entries can be mutable/immutable and named/unnamed. By default
variables are immutable, and by default tuple entries follow the top variable
definition. The entry can be changed with the `var` and `let` keywords. The
`type` declaration is an immutable variable type.

To declare a named entry the default is `lhs = var` which follows the default
tuple entry type. Again, the `var` and `let` keywords can be added to change
it.

```
b = 3
a = (b:u8, 4)
assert a == (3:u8, 4)

var f = (b=3, let e=5)
f.b = 4             // OK
f.e = 10            // compile error, `f.e` is immutable

let x = (1,2)
x[0] = 3            // compile error, 'x' is immutable
var y = (1, let 3)
y[0] = 100          // OK
y[1] = 101          // compile error, `y[1]` is immutable
```

## Tuples vs Arrays

Tuples are ordered, as such, it is possible to use them as arrays. 

```
var bund1 = (0,1,2,3,4) // ordered and can be used as an array

var bund2 = (bund1,bund1,((10,20),30))
assert bund2[0][1] == 1
assert bund2[1][1] == 1
assert bund2[2][0] == (10,20)
assert bund2[2][0][1] == 20
assert bund2[2][1] == 30
```

Pyrope tries to be compatible with synthesizable Verilog. In Verilog, when an
out of bounds, access is performed in a packed array (unpacked arrays are not
synthesizable), or an index has unknown bits (`?`), a runtime warning can be
generated and the result is an unknown (`0sb?`). Notice that this is a
pessimistic assumption because maybe all the entries have the same value when
the index has unknowns.


The Pyrope compile will trigger compile errors for out-of-bound access. It is not
possible to create an array index that may perform an out of bounds access.

```
var array = (0,1,2)       // size 3, not 4
tmp = array[3]            // compile error, out of bounds access
var index = 2
if runtime {
  index = 4
}
// Index can be 2 or 4

var res1 = array[index]   // compile error, out of bounds access 

var res2 = 0sb?           // Possible code to be compatible with Verilog
if index<3 {
  res = array[index]      // OK
}
```

Pyrope compiler will allow an index of an array/tuple with unknowns. If the
index has unknown bits (`0sb?` or `0b1?0`) but the compiler can not know, the
result will have unknowns (see [internals](10-internals.md) for more details).
Notice that the only way to have unknowns is that somewhere else a variable or
a memory was explicitly initialized with unknowns. The default initialization
in Pyrope is 0, not unknown like Verilog.


## Attributes/Fields

A tuple can have named fields like `counter`, but when the field starts with 2
underscores, it is an attribute to be passed to the compiler flow. The attributes
do not use tuple order entries.

Attributes for basic types, usually simple variables or tuple entries:

* `__max`: sets the maximum value allowed
* `__min`: sets the minimum value allowed
* `__ubits`: Maximum number of bits to represent the unsigned value. The number must be positive or zero
* `__sbits`: Maximum number of bits, and the number can be negative

Some attributes apply for basic types and/or any type of tuple:

* `__size`: number of tuple sub-entries
* `__id`: get the field name


Some syntax sugar on the language creates wrappers around the attributes, but
they can be accessed directly. When types are used, a more traditional syntax
wrapper for max/min/ubits/sbits is created.


The programmer could create custom attributes but then a LiveHD compiler pass
to deal with the new attribute is needed to handle based on their specific
semantic. To understand the potential Pyrope syntax, this is a hypothetical
`__poison` attribute that marks tuple.

```
let bad (a=3,b=4)
bad.b.__poison = true

let b = bad.b

assert  b.__poison and b==4
```

### Concatenate fields

Each tuple field must be unique. Nevertheless, it is practical to have
fields that add more subfields. This is the case for overloading. To
append or concatenate in a given field the `++=` operator can be assigned.

```
var x = (
  ,ff = 1
  ,ff = 2 // compile error
)

var y = (
  ,ff = 1
  ,ff ++= 2
  ,zz ++= 3
)
assert y == (ff=(1,2),zz=3)
```




## Optional tuple parenthesis

Parenthesis marks the beginning and the end of a tuple. Those parentheses can
be avoided for an unnamed tuple in some cases:

* When doing a simple function call after an assignment or at the beginning of a line.
* When used inside a selector `[...]`.
* When used after an `in` operator followed by a `{` like in a `for` and `match` statements.
* For the inputs in a match statement

```
fcall 1,2         // same as: fcall(1,2)
x = fcall 1,2     // same as: x = fcall(1,2)
b = xx[1,2]       // same as: xx[(1,2)]

for a in 1,2,3 {  // same as: for a in (1,2,3) {
  x = a
}
y = match z {    
  in 1,2 { 4 }    // same as: in (1,2) { 4 }
  else { 5 }
}
y2 = match 1,z {  // same as: y2 = match (1,z) {
}
```

A named tuple parenthesis can be omitted on the left-hand side of an assignment. This is
to mutate or declare multiple variables at once. 

```
var a=0
var b=1

a,b = (2,3)
assert a==2 and b==3

var c,d = 1        // compile error, 2 entry tuple in lhs
var c,d = (1,2)
assert c == 1 and d == 2
```


## enums

Enums use the familiar tuple structure, but there is a significant difference.
The following case generates an enum compile error because the enum entries
shadow existing variable entries.


```
let a = "foo"
enum err = (a,b) // compile error, 'a' is a shadow variable
```

The reason is to avoid confusion between tuple and enum that use similar
tuple syntax. In the `err` example, it is unclear if the intention is to have
`err.foo` or `err.a`.

The shadow variable constrain does not happen if the enum has a non-default
value. Another solution is to move the enum declaration ahead of the shadowing
variables.

```
let a = 10
let b = 20
let c = 30

let v = (a,b,c)
assert v == (10,20,30)

enum e = (a=1,b=2,c=300)
assert e.a == 1 and e.b == 2 and e.c == 300

let x = e.a
puts "x is {}", x  // prints: "x is e.a"
```


The enum default values are NOT like typical non-hardware languages. The enum
auto-created values use a one-hot encoding. The first entry has the first bit
set, the 2nd the 2nd bit set. If an entry has a value, the next entry uses
the next free bit.

```
enum v3 = (
   ,a
   ,b=5  // alias with 'a'
   ,c
)
assert v3.a == 1
assert v3.b == 5
assert v3.c == 2
```

Enum can accept hierarchical tuples. Each enum level follows the same algorithm.
Each entry tries to find a new bit. In the case of the hierarchy, the lower
hierarchy level bits are kept.

```
enum animal = (
  ,bird=(eagle, parrot)
  ,mammal=(rat, human)
)

assert animal.bird.eagle != animal.mammal
assert animal.bird != animal.mammal.human
assert animal.bird == animal.bird.parrot

assert animal.bird         == 0b000001
assert animal.bird.eagle   == 0b000011
assert animal.bird.parrot  == 0b000101
assert animal.mammal       == 0b001000
assert animal.mammal.rat   == 0b011000
assert animal.mammal.human == 0b101000
```

In general, if there is no value specified in an entry, the number of bits is
equivalent to the number of entries in the tuple.


It is possible to use a sequence that is more consistent with hardware languages.

```
enum v3:int = (
   ,a
   ,b=5  // alias with 'a'
   ,c
)
assert v3.a == 0
assert v3.b == 5
assert v3.c == 6
```

The same syntax is used for enums to different objects. The hierarchy is not
allowed when an ordered numbering is requested.


