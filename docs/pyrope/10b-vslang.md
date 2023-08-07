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
clock cycle. The defer delays the "write" until the end of the clock cycle, the
defer does not defer the reads, just the write or update. To read the value
from the end of the cycle an attribute `variable.[defer]` must be used.


These are constructs not existing in software but needed in hardware because it
is necessary to connect blocks. Following the control flow from the top only
allows to connect forward. Some contructs like connecting a ring require a
"backward edge". The attribute `[defer]` allow such type of constructs.

```
var a = 1
var b = 2

cassert a==1 and b==2
b::[defer] = a
cassert a==1 and b==2

cassert b.[defer] == 1
```

### Pipelining


Pyrope should be easier to program than non-HDLs with the exception of dealing
with cycles. While memory management tends to be the main complexity in
non-HDLs, pipelining or dealing with interaction across cycles is the main
complexity in HDLs.


Pyrope has several constructs to help that do not apply to non-HDL,
[pipelining](06c-pipelining.md) has most of the pipelining specific syntax.

## C++

Pyrope and C++ are quite different in syntax, but some nice C++23 syntax has
similarities for Pyrope.

```c++
auto max_gap_count(std::vector<int> nums) {
    std::ranges::sort(nums, std::greater{});
    auto const diffs = nums
        | std::views::adjacent_transform<2>(std::minus{});
    return std::ranges::count(diffs, std::ranges::max(diffs));
}
```

```
let max_gap_count = fun(nums) {
  let max  = import("std").max
  let sort = import("std").sort
  let adjacent_transform = fun(a,num,f) {
    var res:[] = _
    for i in 0..<a.length step num {
      res ++= f(a[i..+num])
    }
    return res
  }
  let count = fun(a,b) {
    var r = 0
    for i in a {
      r += 1 when i == b
    }
    return r
  }

  return numbers
     |> sort(fun(a,b) { a<b })
     |> adjacent_transform(num=2, fun(a,b) { a-b } )
     |> fun(a) { count(a, a.max) }
}
```

## Swift

There are many diffirences with Swift, but this section just highlights a couple because it helps
to understand the Pyrope semantics.


### Protocol vs Pyrope constrains

Swift protocols resemble type classes. As such require consent for implementing
a functionality. Pyrope resembles C++ concepts that constraint functionality.

```swift
func add<T>(a:T, b:T) -> T { a + b }  // compile error
func add<T:Numeric>(a:T, b:T) -> T { a + b }
```

```
let add = fun(a,b) { a + b }            // OK, no constrains
let add = fun<T:int>(a:T,b:T) { a + b } // constrain both to have same type
```

When a protocol defines an interface, in Swift:

```swift
protocol Shape {
  func name()      -> String
  func area()      -> Float
  func perimeter() -> Float
}

class Rectangle : Shape {  }
class Circle    : Shape {  }

func print_share_info<T:Shape>(_ s:T) {

}
```

In Pyrope:
```
let Shape = (
  ,name:fun(self)->(_:string)    = _
  ,area:fun(self)->(_:Float)     = _  // NOTE: Pyrope does not have float type
  ,perimeter:fun(self)->(_:Float)= _
)

let Rectangle:(...Shape,...OtherAPI) = (...some_code_here)
let Circle:Shape = (...some_code_here)

let print_share_info = fun(s:Shape) { }
```


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
  return res
}
let f2 = fun(self:AnObject) -> :i32 {
  return self.v
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

## Typescript

Pyrope has a type system quite similar to Typescript, but there are significant
differences. The main is that Pyrope does not allow union types.


There are also difference in some semantics. For example, Typescript `"foo" in
bar` is equivalent to the `bar has "foo"` in Pyrope. Both check if entry `foo`
exists in the tuple `bar` (`bar.foo`). There is no Typescript equivalent to the
Pyrope `"foo" in bar` which checks if `bar` is a tuple with an entry equal to
string `"foo"`.


## Matlab

Matlab has a convenient multi-dimensional array or array initialization. It
does not require comma. E.g: `a = [a b 100 c]` is valid Matlab.


Pyrope requires commas to distinguish from multi-line statements, hence `a = [a,b,100,c]`
To initialize a multi-dimensional array, it follows other languages syntax, but
in Pyrope both `()` and `[]` are allowed and have the same meaning.

```
let x = [[1,2],[3,4]]
assert x == ((1,2),[3,4])
assert x[0,1] == 2 == x[0][1]
assert x[1,0] == 3 == x[1][0]
```

