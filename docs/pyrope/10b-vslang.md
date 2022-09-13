# vs Other Languages

This section provides some snippet examples to understand the differences
between Pyrope and a different set of languages.

## Generic non-HDL

Pyrope is an HDL that tries to look like a non-HDL with modern/concise syntax.
Some of the Pyrope semantics are simpler than most non-HDL because of several
features like unlimited precision, lack of pointers and issues to manage memory
do not exist in ASICs/FPGAs. These are explained in [simpler HDL
constructs](00-hwdesign.md/#simpler-hdl-constructs) section.


There are some features in Pyrope that are non-existing in non-HDLs.
ASICs/FPGAs design leverage some features like reset, pipelining, connecting
modules that require syntax/semantics not needed in languages like Rust, C,
Java. This section lists the main hardware specific syntax.


### reset vs cycle


Nearly all the programming languages have a "main" that starts execution. From
the entry point, a precise control flow is followed until an "exit" is found.
If there is no exit, the control flow eventually returns to the end of main and
an implicit exit exist when "main" finishes. There is no concept of cycle or
reset.


Pyrope tries to imitate non-HDLs and it has the same entry point "top" and also follows
a precise control flow from that entry point. This is what a non-hardware designer
will expect, but there is no exit/abort. The control flow will continue until
it returns to the end of the "top" or entry point. 


The key difference is that the "top" or entry point is called every cycle. From
a hardware point of view, the whole program executes in a single clock cycle.
All the program state is lost unless preserved in register variables.


Those registers variables have an "initialization" step that in hardware
corresponds to a reset phase. Each register declaration assignment has reset
code only executed during reset.


### Defer

Some programming languages like Zig or Odin have a defer statement. In
non-HDLs, a defer means that the statements inside the defer are executed when
the "scope" finishes. Usually, the defer statements are executed before the
function return.


Pyrope defers the statements not to the end of the scope but to the end of the
clock cycle. Even more important, it can defer the reads or the writes. These
are constructs not existing in software but needed in hardware because it is
necessary to connect blocks. Following the control flow from the top only allows
to connect forward. Some contructs like connecting a ring require a "backward edge".
The `defer_read` and `defer_write` allow such type of constructs.


From a non-HDL point of view, the semantics are quite weird. A `defer_read x =
a` means that `x` sees "future" or end of cycle contents of `a` and it can be
used now. But if you think about hardware it is something happening on the same
cycle, and the design may need the value to compute. Obviously, something like
`defer_read a = a + 1` can lead to what it is known as a combination loop in
hardware. Pyrope should have combination loop detectors and notify as compiler
error because they are not allowed in most designs. 


### Pipelining


Pyrope should be easier to program than non-HDLs with the exception of dealing
with cycles. While memory management tends to be the main complexity in
non-HDLs, pipelining or dealing with interaction across cycles is the main
complexity in HDLs.


Pyrope has several constructs to help that do not apply to non-HDL,
[pipelining](06c-pipelining.md) has most of the pipelining specific syntax.


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

A Rust style Pyrope equivalent:

```
let AnObject = (
  ,v:i32 = _
)

let f1 = proc(ref self:AnObject) -> :i32 { // unnamed output tuple
  let res = self.v
  self.v += 1
  ret res
}
let f2 = fun(self:AnObject) -> :i32 {
  ret self.v
}
```

A more Pyrope style equivalent:

```
let AnObject = (
  ,v:i32 = _
  ,f1 = proc(ref self) -> (res:i32) {
    res = self.v
    self.v += 1
  }
  ,f2 = fun(self) -> :i32 { self.v }
)
```

