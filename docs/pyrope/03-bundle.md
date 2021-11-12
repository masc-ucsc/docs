# Tuples

Tuples are a basic construct in Pyrope. Tuples are defined as "ordered"
sequence of elements where the entries may be named.


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
assert a[':0:r1'].1    == 2 // indicate position with :num:
assert a[':0:r1.1']    == 2
assert a[':0:r1.:1:c'] == 2
```

Ordered and named fields also can use `:position:key` to indicate the position
and key. If either mismatches a compilation error is triggered.


There is introspection to check for an existing field with the `has` operator.

```
let a = (foo = 3)
assert a has 'foo'
assert !(a has 'bar')
assert a has 0
assert !(a has 1)
```

## Everything is a Tuple

In Pyrope all the variables are tuples, just a tuple of size 1. As such, it is possible
to have this code:

```
let a = 3              // tuple of 1 element which is 3
let b = a.0.0          // get first element which is 3 (a tuple too)
assert b == a == 3
let c = (3)            // tuple of 1 element which is 3
assert a == c
```

## Tuples vs Arrays

Tuples are ordered, as such it is possible to use them as arrays. The index may
not be known at compile time. If an out-of-bounds access is performed, either a
compile or simulation error is triggered.

```
var bund1 = (0,1,2,3,4) // ordered and can be used as an array

var bund2 = (bund1,bund1,((10,20),30))
assert bund2[0][1] == 1
assert bund2[1][1] == 1
assert bund2[2][0] == (10,20)
assert bund2[2][0][1] == 20
assert bund2[2][1] == 30
```


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
* `__id`: get field name


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

