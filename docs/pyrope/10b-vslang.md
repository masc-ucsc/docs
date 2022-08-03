# vs Other Languages

This section provides some snippet examples to understand the differences
between Pyrope and a different set of languages.


## Rust

Rust is not an HDL, as such it has to deal with many other issues like memory. This section is just
a syntax comparison.

## Lambda

In Rust, the `self` keyword when applied to methods can be `&self`, `self`, `&mut self`. In Pyrope,
there is only a `self`, because values are not passed by reference but by value. The equivalent of the `&mut self` is
when Pyrope has the input and output tuple with `self`.


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

A Rust style Pyrope equivalent:

```
pub type AnObject = (
  ,v:i32
)

pub type AnObject2 extends AnObject2 with (
  ,pub f1 = proc(self) -> (self,:i32) {
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
  ,pub f1 = proc(self) -> (self,:i32) {
    let res = self.v
    self.v += 1
    ret res
  }
  ,pub f2 = fun(self) -> (:i32) {
    ret self.v
  }
)
```

