# Pyrope Standard Library

This is a list of functionality that `import prp` should produce.

## Basic operations

All the LNAST node have an associated function matching name to simplify the
creation of operations: `plus`, `minus`, `mult`, `div`, `mod`, `ror`...

```pyrope
const prp = import("prp")
cassert(prp.plus(1,2,3) == 6)
```

Library code:
```pyrope
comb plus(...a:int) -> (r:int) {
  r = 0
  for e in a {
    r += e
  }
}
```

## Array/Tuple operators

### Size of length

Sample use:
```pyrope
const x = (1,2,23)

cassert(prp.len(x) == 3)
```

Library code:
```pyrope
comb len(x) -> (r) { r = x.[size] }
```

### map

Sample use:

```pyrope
const x = (1,2,3)
comb inc(a) -> (r) { r = a + 1 }

cassert(x.map(inc) == (2,3,4))
```

Library code:
```pyrope
comb map<T>(f, ...x:[]T) -> (r:[]) {
  r = nil
  for e in x {
    r ++= f(e)
  }
}
```

### filter

Sample use:

```pyrope
comb not_two(a) -> (r) { r = a != 2 }

cassert((1,2,3).filter(not_two) == (1,3))
```

Library code:

```pyrope
comb filter<T>(f, ...x:[]T) -> (r:[]) {
  r = nil
  for e in x {
    if not f(e) {
      r ++= e
    }
  }
}
```

### reduce

Sample use:

```pyrope
cassert (1,2,3).reduce(prp.plus) == 6
```

Library code:

```pyrope
comb reduce<T>(op, ...x:[]T) -> (res:T) {
  if x.[size] <= 1 {
    res = x
    return
  }

  res = x[0]
  for i in x[1..] {
    res = op(res, i)
  }
}
```

### TODO

 It would be nice to have the same methods (and names) as the c++20 `std::views`
 adaptors so that it is easier for developers to get familiar. E.g: filter,
 transform, drop, join, split, reverse, common, counted...

 https://en.cppreference.com/w/cpp/ranges
