# Tuples

Tuples are a basic construct in Pyrope. Tuples are defined as an "ordered"
sequence fields that can be named.


```
b := (f1=3,f2=4) // b is named and ordered
c := (1,d=4)     // c is ordered and unnamed (some entries are not named)
```

To access fields in a tuple we use the dot `.` or `[]`
```
a := (
  ,r1 = (b=1,c=2)
  ,r2 = (3,4)
)
// tuple position is from left to right
assert a.r1 == (1,2) and a.r2 == (3,4)
assert a.0  == (1,2) and a[1] == (3,4)

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

The only main difference between `a.0` (dot) and `a[0]` (select) access is that
dot access guarantees to be compile time index, while the select can have
compile time or run-time index.

There is introspection to check for an existing field with the `has` and `!has` operators.

```
a := (foo = 3)
assert a has 'foo'
assert !(a has 'bar')
assert a !has 'bar' // "has no" is the opposite of "has"
assert a has 0
assert a !has 1
assert a !has 1
```

Tuple named fields can have a default type and or contents:

```
val := 4
x := (
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
a := (1,2)   // tuple of 2 entries, 1 and 2
b := (1)     // tuple of 1 entry, 1
c := 1       // tuple of 1 entry, 1
d := (,,1,,) // tuple of 1 entry, 1
assert a.0 == b.0 == c.0 == d.0
assert a!=b
assert b == c == d
```

A tuple with a single entry element is called a scalar. 

Tuples are used in many places:

* The arguments for a call function are a tuple. E.g: `fcall(1,2)`
* The return of a function call is always a tuple. E.g: `foo = fcall()`
* The index for a selector `[...]` is a tuple. As syntax sugar, the tuple parenthesis can be omitted. E.g: `foo@[0,2,3]`
* The complex type declaration are a tuple. E.g: `Xtype <- (f=1,b:string)`


## Tuple mutability

The tuple entries can be mutable/immutable and named/unnamed. Tuple entries
follow the variable mutability rules with the exception that `=` can be
used and it means to follow the top variable definition mutability.


```
c:=(x=1,b<-2, d:=3)
c.x   = 3  // OK, x inherited the mutable declaration
x.foo = 2  // compile error, tuple 'x' does not have field 'foo'
c.b   = 10 // compile error, 'c.b' is immutable
c.d   = 30 // OK, d was already mutable type

d<-(x=1, y<-2, z:=3)
d.x   = 2  // compile error: x inherits the 'immutable' declaration
d.foo = 3  // compile error, tuple 'd' does not have field foo'
d.z   = 4  // compile error, 'd' is immutable
```

Tuples are always ordered, but they can have unnamed entries. If needed a `_`
can be used for name or default value during the tuple declaration.

```
b := 100
a := (b:u8, b, b:u8 = _, c<-4)
a.b = 200
assert a == (100, 100, 200, 4)

f := (b=3, e<-5)
f.b = 4             // OK
f.e = 10            // compile error, `f.e` is immutable

x <- (1,2)
x[0] = 3            // compile error, 'x' is immutable
y := (1, _ <- 3)
y[0] = 100          // OK
y[1] = 101          // compile error, `y[1]` is immutable
```


While the tuple entries can be either mutable or immutable, the field
name/types are immutable. It is possible to construct new tuples with the `++`
(concatenate) and `...` (in-place operator):

```
a:=(a=1,b=2)
b<-(c=3)

ccat1 <- a ++ b
assert ccat1 == (a=1,b=2,c=3)
assert ccat1 == (1,2,3)

ccat2 := a                // mutable tuple
a = a ++ (b=20)
assert ccat2 == (a=1,b=(2,20),c=3)
assert ccat2 == (1,(2,20),3)

join1 := (...a,...b)
assert join1 == (a=1,b=2,c=3)
assert join1 == (1,2,3)

join2 := (...a,...(b=20)) // compile error, 'b' already exists
```


The `a ++ b` concatenates two tuples. If the same field exists in both tuples,
the resulting field will have a tuple with the entries of `a` and `b`.  The
concat tries to match by field name, if the field names do not match or have no
name a new entry is created. The algorithm starts with tuple `a` and starts
from tuple field 0 upwards.

```
assert(((1,a=2,c=3) ++ (a=20,33,c=30,4)) == (1,a=(2,20),c=(3,30),33,4))
```

The `...` also concatenates, but it is an "inline concatenate". The difference
is where the fields are concatenated and that it triggers a compile error if
the same entry already exists.



## Field access

Since everything is a tuple, any variable can do `variable.0.0.0.0` because it
literaly means, return the tuple first entry for four times. 


Another useful shortcut is when a tuple has a single field or entry, the tuple
contents can be accessed without requiring the individual position or field
entry name. This is quite useful for function return tuples with a single
entry.

```
x <- (first=(second=3))

assert x.first.second == 3
assert x.first        == 3
assert x              == 3
assert x.0.second     == 3
assert x.first.0      == 3
assert x.0            == 3
```


## Tuples vs Arrays

Tuples are ordered, as such, it is possible to use them as arrays. 

```
bund1 := (0,1,2,3,4) // ordered and can be used as an array

bund2 := (bund1,bund1,((10,20),30))
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
array := (0,1,2)       // size 3, not 4
tmp = array[3]            // compile error, out of bounds access
index := 2
if runtime {
  index = 4
}
// Index can be 2 or 4

res1 := array[index]   // compile error, out of bounds access 

res2 := 0sb?           // Possible code to be compatible with Verilog
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


### Concatenate fields

Each tuple field must be unique. Nevertheless, it is practical to have
fields that add more subfields. This is the case for overloading. To
append or concatenate in a given field the `++=` operator can be assigned.

```
x := (
  ,ff = 1
  ,ff = 2 // compile error
)

y := (
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
* For the inputs in a match statement.
* A single element lambda return value.

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

addb <- fun(a,b:u32)-> a:u32 { // same as: addb <- fun(a,b:u32)->(a:u32)  
  a = a + b
}
```

A named tuple parenthesis can be omitted on the left-hand side of an assignment. This is
to mutate or declare multiple variables at once. 

```
a:=0
b:=1

a,b = (2,3)
assert a==2 and b==3

c,d := 1        // compile error, 2 entry tuple in lhs
c,d := (1,2)
assert c == 1 and d == 2
```


## enums

Enums use the familiar tuple structure, but there is a significant difference.
The following case generates an enum compile error because the enum entries
shadow existing variable entries.


```
a <- "foo"
Err <- :enum(a,b)         // compile error, 'a' is a shadow variable
Good <- :enum(a=_,'b',c)  // OK
```

The reason is to avoid confusion between tuple and enum that use similar
tuple syntax. In the `err` example, it is unclear if the intention is to have
`err.foo` or `err.a`.

The shadow variable constrain does not happen if the enum has a non-default
value. Another solution is to move the enum declaration ahead of the shadowing
variables, or to declare the entry as a string literal.

```
a <- 10
b <- 20
c <- 30

v <- (a,b,c)
assert v == (10,20,30)

En <- :enum(a=1,b=2,c=300)
assert e.a == 1 and e.b == 2 and e.c == 300

x <- e.a
puts "x is {}", x  // prints: "x is e.a"
```


The enum default values are NOT like typical non-hardware languages. The enum
auto-created values use a one-hot encoding. The first entry has the first bit
set, the 2nd the 2nd bit set. If an entry has a value, the next entry uses
the next free bit.

```
V3 <- :enum(
   ,a
   ,b=5
   ,c
)
assert V3.a == 1
assert V3.b == 5
assert V3.c == 2
```

Enum can accept hierarchical tuples. Each enum level follows the same algorithm.
Each entry tries to find a new bit. In the case of the hierarchy, the lower
hierarchy level bits are kept.

```
Animal <- :enum(
  ,bird=(eagle, parrot)
  ,mammal=(rat, human)
)

assert Animal.bird.eagle != Animal.mammal
assert Animal.bird != Animal.mammal.human
assert Animal.bird == Animal.bird.parrot

assert Animal.bird         == 0b000001
assert Animal.bird.eagle   == 0b000011
assert Animal.bird.parrot  == 0b000101
assert Animal.mammal       == 0b001000
assert Animal.mammal.rat   == 0b011000
assert Animal.mammal.human == 0b101000
```

In general, if there is no value specified in an entry, the number of bits is
equivalent to the number of entries in the tuple.


It is possible to use a sequence that is more consistent with traditional
programming languages, but this only works with non-hierarchical enumerates
when a `:int` type is used.

```
V3:int <- :enum( // V3 has type :int
   ,a
   ,b=5
   ,c
)
assert V3.a == 0
assert V3.b == 5
assert V3.c == 6
```

The same syntax is used for enums to different objects. The hierarchy is not
allowed when an ordered numbering is requested.


Enumerates of the same type can perform bitwise binary operations
(and/or/xor/nand/xnor/xnor) and set operators (in/!in).

```
human_rat <- Animal.mammal.rat | Animal.mammal.human  // union op

assert Animal.mammal      in human_rat
assert Animal.mammal.rat  in human_rat
assert Animal.bird       !in human_rat
```

