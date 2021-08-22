# Bundles

Bundles are a basic construct in Pyrope. They provide a mix of tuples and structs. Tuples are usually defined as "ordered"
sequence of elements, while structs or records are named but un-ordered data structures.

Bundles can be "ordered and named", "ordered", or just "named". A bundle can not be unnamed and unordered.

```
a.field1 = 1
a.field2 = 2    // a is named unordered
b = (f1=3,f2=4) // b is named and ordered
c = (1,d=4)     // c is ordered and unnamed (some entries are not named)
```

To access fields in a bundle we use the dot `.` or `[]`
```
a = (
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
a.foo = 3
assert a has 'foo'
assert !(a has 'bar')
assert !(a has 0)     // unordered

v = (33,44,55)
assert v has 2
assert !(v has 3)
```

## Everything is a bundle

In Pyrope all the variables are bundles, just a bundle of size 1. As such, it is possible
to have this code:

```
a = 3              // bundle of 1 element which is 3
b = a.0.0          // get first element which is 3 (a bundle too)
assert b == a == 3
c = (3)            // bundle of 1 element which is 3
assert a == c
```

## Attributes/Fields


A bundle can have named fields like `counter`, but when the field starts with 2
underscores, it is an attribute to be passed to the compiler flow. 

Attributes for individual bundle entries:

* `__max`: sets the maximum value allowed
* `__min`: sets the minimum value allowed
* `__ubits`: Number of bits and set as unsigned
* `__sbits`: Number of bits and set as signed

Attributes for multiple bundle entries:

* `__size`: number of bundle sub-entries
* `__init`: default initialization value (zero by default)
* `__rnd`: generate a random bundle
* `__do`: code block passed
* `__else`: else code block passed


Some syntax sugar on the language creates wrappers around the attributes, but
they can be accessed directly. When types are used, a more traditional syntax
wrapper for max/min/ubits/sbits is created.


The programmer could create custom attributes but then a LiveHD compiler pass
to deal with the new attribute is needed to handle based on their specific
semantic. To understand the potential Pyrope syntax, this is a hypothetical
`__poison` attribute that marks bundles.

```
bad.a        = 3
bad.b        = 4
bad.__poison = true

b = bad.b
c = 3

assert  b.__poison
assert !c.__poison
```

