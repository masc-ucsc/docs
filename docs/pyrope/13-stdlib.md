# Pyrope Standard Library

This is a list of functionality that `import prp` should produce.

## Basic operations

All the LNAST node have an associated function matching name to simplify the
creation of operations: `plus`, `minus`, `mult`, `div`, `mod`, `ror`... 

```
let prp = import("prp")
cassert prp.plus(1,2,3) == 6
```

Library code:
```
let plus = fun(...a:int)->(_:int) {
  var r = 0
  for e in a {
    r += e
  }
  ret r
}
```

## Array/Tuple operators

### Size of length

Sample use:
```
let x = (1,2,23)

cassert p.len(x) == 3
```

Library code:
```
let len = fun(x) { ret x.[size] }
```

### map

Sample use:

```
let x = (1,2,3)

cassert x.map(fun(i){ i+1 }) == (2,3,4)
```

Library code:
```
let map = fun<T>(f:fun(a:T),...x:[]T) {
  ret for e in x { f(e) }
}
```

### filter

Sample use:

```
cassert (1,2,3).filter(fun(i){ i!=2 }) == (1,3)
```

Library code:

```
let map = fun<T>(f:fun(a:T),...x:[]T) {
  ret for e in x { if f(e) { cont x } }
}
```

### reduce

Sample use:

```
cassrt (1,2,3).reduce(prp.plus) == 6
```

Library code:

```
let reduce = fun(op:fun<T>(a:T,b:T)->(_:T), ...x) {
  ret x when x.[size] <= 1

  var res = x[0]
  for i in x[1..] {
    res = op(res, i)
  }
  ret res
}
```

