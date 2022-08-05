# vs Other Languages

This section provides some snippet examples to understand the differences
between Pyrope and a different set of languages.


## Rust

Rust is not an HDL, as such it has to deal with many other issues like memory. This section is just
a syntax comparison.

## Lambda

In Rust, the `self` keyword when applied to lambda arguments can be `&self`,
`self`, `&mut self`. In Pyrope, there is only a `self` and `ref self`. The
equivalent of the `&mut self` is `ref self`. Pyrope does not have the
equivalent of `mut self` that allows to modify a copy of self.


```rust
pub struct AnObject {
  v:i32
}

imp AnObject {
  pub fn f1(&mut self) -> i32 {
    let res = self.v;
    self.v += 1;
    res
  }
  pub fn f2(self) -> i32 {
    self.v
  }
}
```

A Rust style Pyrope equivalent, but this is an overkill because the base type
does not have any method pending, so the `extends` does not have anything to
check.

```
pub type AnObject = (
  ,v:i32
)

pub type AnObject2 extends AnObject2 with (
  ,pub f1 = proc(ref self) -> (:i32) {
    let res = self.v
    self.v += 1
    ret res
  }
  ,pub f2 = fun(self) -> (:i32) {
    ret self.v
  }
)
```

A more Pyrope style equivalent:

```
pub type AnObject = (
  ,v:i32
  ,pub f1 = proc(ref self) -> (:i32) {
    let res = self.v
    self.v += 1
    ret res
  }
  ,pub f2 = fun(self) -> (:i32) {
    ret self.v
  }
)
```

Another Pyrope style equivalent alternative when the methods can be declared
outside the object declaration.

```
pub type AnObject = (
  ,v:i32
)

pub f1 = proc(ref self:AbObject) -> (:i32) {
  let res = self.v
  self.v += 1
  ret res
}
pub f2 = fun(self:AbObject) -> (:i32) {
  ret self.v
}
```

