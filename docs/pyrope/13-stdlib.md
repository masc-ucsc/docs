# Pyrope Standard Library

This is a list of functionality that `import prp` should produce.

## Basic operations

All the LNAST node have an associated function matching name to simplify the
creation of operations: `plus`, `minus`, `mult`, `div`, `mod`, `ror`...

```
const prp = import("prp")
cassert prp.plus(1,2,3) == 6
```

Library code:
```
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
```
const x = (1,2,23)

cassert prp.len(x) == 3
```

Library code:
```
comb len(x) -> (r) { r = x.[size] }
```

### map

Sample use:

```
const x = (1,2,3)

cassert x.map(_ + 1) == (2,3,4)
```

Library code:
```
comb map<T>(f:comb(a:T)->(_), ...x:[]T) -> (r) {
  r = f(e) for e in x
}
```

### filter

Sample use:

```
cassert (1,2,3).filter(_ != 2) == (1,3)
```

Library code:

```
comb filter<T>(f:comb(a:T)->(_:Bool), ...x:[]T) -> (r) {
  r = e for e in x if not f(e)
}
```

### reduce

Sample use:

```
cassert (1,2,3).reduce(prp.plus) == 6
```

Library code:

```
comb reduce<T>(op:comb(a:T,b:T)->(_:T), ...x:[]T) -> (res:T) {
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
