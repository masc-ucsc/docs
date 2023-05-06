# Basic syntax

## Comments

Comments begin with `//`, there are no multi-line comments

```
// comment
a = 3 // another comment
```

## Constants

### Integers

Pyrope has unlimited precision signed integers. Any literal starting with a
digit is a likely integer constant.

```
0xF_a_0 // 4000 in hexa. Underscores have no meaning
0b1100  // 12 in binary
0sb1110 // -2 in binary (sb signed binary)
33      // 33 in decimal
0o111   // 73 in octal
0111    // 111 in decimal (some languages use octal here)
```

Since powers of two are very common, Pyrope decimal integers can use the `K`, `M`, `G`, and `T` modifiers.

```
assert 1K == 1024
assert 1M == 1024*1024
assert 1G == 1024*1024*1024
assert 1T == 1024*1024*1024*1024
```

Several hardware languages support unknown bits (`?`) or high-impedance (`z`). Pyrope
aims at being compatible with synthesizable Verilog, as such `?` is also supported in
the binary encoding.

```
0b?             // 0 or 1 in decimal
0sb?            // 0 or -1 in decimal
0b?0            // 0 or 2 in decimal
0sb0?0          // 0 or 2 in decimal
```

The Verilog high impedance `z` is not supported. A `bus` construct must be used instead.

Like in many HDLs, Pyrope has unknowns `?`. The x-propagation is a source of
complexity in most hardware models. Pyrope has `x` or `?` to be compatible with
Verilog existing designs. This means that inside the Pyrope compiler, the
constant operations with unknowns are compatible with Verilog semantics. When
the simulation is performed, the expectation is to randomly generate a 0 or 1
for each unknown (`?`) bit.


The advice is not to use `x` besides `match` statement pattern matching. It is
much better to use the default value (zero or empty string), but sometimes it
is easier to use `nil` when converting Verilog code to Pyrope code. The `nil`
means that the numeric value is invalid. If any operation is performed with
`nil`, the result is an assertion failure. The only thing allowed to do with
nil is to copy it. While the `nil` behaves like an invalid value, the `0sb?`
behaves like an unknown value that still can be used in arithmetic operations.
E.g: `0sb? | 1` is `1` but `nil | 1` is an assertion error.


Notice that `nil` is a state in the integer basic type, it is not a new type by
itself, it does not represent an invalid pointer, but rather an invalid integer. Also
important is that the compiler will guarantee that all the `nil` are eliminated
at compile time or a compile error is generated.


### Strings

Pyrope accepts single line strings with a single quote (`'`) or double quote
(`"`).  Single quote does not have escape character, double quote supports escape
sequences.

```
a = "hello \n newline"
b = 'simpler here'
```

* `\n`: newline
* `\\`: backslash
* `\"`: double quote
* `` ` ``: backtick quote
* `\xNN`: hexadecimal 8 bit character (2 digits)
* `\uNNNN`: hexadecimal 16-bit Unicode character UTF-8 encoded (4 digits)


Pyrope allows string interpolation but only for variables, not expressions. The style
is like C++ fmt::format which allows an identifier. When the identifier is provided
the string is processed acordingly.

```
let num       = 2
let color     = "blue"
let extension = "s"

let txt = "I have {num:d} {color} potato{extension}"
cassert txt == "I have 2 blue potatos"
```


Integers and strings can be converted back and forth:

```
var a:string = "127"
var b:int    = a     // same as var b = int(a)
var c:string = b     // same as var c = string(b)
assert a == c
assert b == 0x7F
assert a == b        // compile error, 'a' and 'b' have different types
```


## Newlines and spaces

Spaces do not have meaning but new lines do. Several programming languages like
Python use indentation level (spaces) to know the parsing meaning of
expressions. In Pyrope, spaces do not have meaning, and newlines combined with
the first token after newline is enough to decide the end of statement.


By looking at the first character after a new line, it is possible to know if
the rest of the line belongs to the previous statement or it is a new
statement.

If the line starts with an alphanumeric (`[a-z0-9]` that excludes operators
like `or`, `and`) value or an open parenthesis (`(`), the rest of the line
belongs to a new statement.

```
var (a,b,c,d) = _
a = 1
  + 3           // 1st stmt
(b,c) = (1,3)   // 2nd stmt
cassert a == 4 and b == 1 and c == 3

d = 1 +         // OK, but not formatted to style
    3
```

This functionality allows parallelizing the parsing and elaboration in Pyrope.
More important, it makes the code more readable, by looking at the beginning of
the line, it is possible to know if it is a new statement or a continuation of
the last one. It also helps to standardize the code format by allowing only one
style.


### Identifiers

An identifier is any non-reserved keyword that starts with an underscore or an
alphabetic character. Since Pyrope is designer to support any synthesizable
Verilog automatic translation, any sequence of characters between backticks
(\`) can form a valid identifier. The identifier uses the same escape sequence
as strings. 

```
`foo is . strange!\nidentifier` = 4
`for` = 3
cassert `for`+1 == `foo is . strange!\nidentifier`
```

Using the backtick, Pyrope can use any string as an identifier, even reserved
keywords. Identifiers are case sensitive like Verilog, but the compiler issues
errors for non \` escaped identifiers that do not follow these conditions in
order:

* Identifiers with a single character followed by a number can be upper or lower case.
* An all upper case variable must be a compile time constant `comptime`.
* Types should either: (1) start the first character uppercase and everything
  else lower case; (2) be all lower case and finish with `_t`.
* All the other identifiers that start with an alpha character `[a-z]` are
  always lower case.

## Semicolons

Semicolons are not needed to separate statements. In Pyrope, a semicolon (`;`)
has the same meaning as a newline. Sometimes it is possible to add
semicolons to separate statements. Since newlines affect the meaning of the
program, a semicolon can do too.

```
a = 1 ; b = 2
```

## Printing

Printing messages is useful for debugging. `puts` prints a message and the string
is formatted using the c++20 fmt format. There is an implicit newline printed.
The same without a newline can be achieved with print.

```
a = 1
puts "Hello a is {}", a
```

Since many modules can print at the same cycle, it is possible to put a
relative priority between puts (`priority`). If no relative priority is
provided, a default 0 priority is provided. Messages are kept to the end of the
cycle, and then printed in alphabetical order for a given priority. This is
done to be deterministic. Higher priority (higher value) are printed after
lower priority. Messages generated by assertions also get serialized like puts
statements but have the highest priority.


To avoid breaking down different `puts` inside the same method. All the `puts`
in a given cycle are shown together.


This example will print "hello world" even though there are 2 puts/prints in
different files.

```
// src/file1.prp
puts(priority=2, " world")

// src/file2.prp
print(priority=1, "hello")
```

The available puts/print arguments:
* `priority`: relative order to print in a given cycle.
* `file`: file to send the message. E.g: `stdout`, `stderr`, `my_large.log`,...


A related command to the puts is the `format` it behaves like `print` but
returns a string.

`puts/print` are a bit special. In most languages, IO operations like `puts` are
considered to have side-effects. In Pyrope, the `puts` can not modify the
behavior of the synthesized code and it is considered a non-side-effect lambda
call. This allows to have `puts` calls in `functions`.


## Functions and procedures

Pyrope only supports anonymous lambdas. A lambda can be assigned to a variable,
and it can be called as most programmers expect. [Lambda
section](06-functions.md) has more details on the allowed syntax.


```
var f = fun(a,b) { a + b }
```

Pyrope naming for consistency:

* `lambda` is any sequence of statements grouped in a code block that can be
  assigned to a variable and called to execute later.

* `function` is a lambda with only combination statements without non-Pyrope
  calls.

* `procedure` is a lambda that can have combination like function but also
  non-combinational (register/memories). Procedures are a superset of functions.

* `method` is a lambda (`function` or `procedure`) that updates another
  variable.  The first argument is an explicit `self`.

* `module` is a lambda that has a physical instance. Lambdas are either inlined
  or modules.


lambda are not only restricted to Pyrope code. It is possible to interface with
non-Pyrope (C++) code, but the calls should respect the same
`procedure`/`function` definition. A C++ `function` can not update the C++
internal state or generate output because the simulation/compiler is allowed to
call it multiple times. This is not the case for C++ `procedure`.

## Evaluation order


Statements are evaluated one after another in program order. The main source of
conflicts come from expressions.


The expression evaluation order is important if the elements in the expression
can have side effects. Pyrope constrains the expressions so that no matter the
evaluation order, the synthesis result is the same. 


As a reference, languages like C++11 do not have a defined order of evaluation for
all types of expressions. Calling `call1() + call2()` is not defined. Either
`call1()` first or `call2()` first.


In many languages, the evaluation order is defined for logical expressions.
This is typically called the short-circuit evaluation. Some languages like
Pascal, Rust, Kotlin have different `and/or` to express conditional evaluation.
In Pascal, there is an `and/or` and `and_then/or_else` (conditional). In Rust
`&/|` and `&&/||` (conditional). In Kotlin `&&/||` and `and/or` (conditional).
Pyrope uses has the `and/or` without short-circuit, and the `and_then/or_else`
with explicit short-circuit.



The programmer can explicitly set an evaluation order by using short-circuit
expressions like `and_then`, `or_else`, or control expressions (`if/else`,
`match`, `for`). An expression can have many `function` calls because those
have no side-effects, and hence the evaluation order is not important.


A `procedure` is an lambda that can update state internally. It can be through
a C++ API call, or some synthesizable state. As such, only one `procedure` call
can exist per expression.


```
var a = fcall() + 1               // OK
var x = pcall() + a               // OK, proc combined with variable read
var b = fcall(a) + 10 + pcall(a)  // OK
var d = t.pcall() + pcall2(b)     // compile error, multiple procedure calls
var y = t.pcall() + t.pcall()     // compile error, multiple procedure calls
```


Expressions also can have a code blocks (`{  }`) as long as there are no
side-effects. In a way, expression code blocks can be seen as a type of
`functions` that are called immedialy after definition.


```
var a = {var d=3 ; last d+1} + 100 // OK
assert a == (3+1+100)
assert a == {3+1+100}  // same, expression evaluated as 104 and returned
```


For most expressions, Pyrope is more restrictive than other languages because
it wants to be a fully defined deterministic independent of implementation. To
handle logging/messaging in `function` calls, Pyrope treats `puts` as a special
instruction. Pyrope runtime delays the puts output until the end of the cycle.
Section (Printing)[02-basics.md#printing] has more details.


To illustrate the evaluation order, it is useful to see a Verilog example. The
following Verilog sequence evaluates differently in VCS and Icarus Verilog.
Pyrope treats `puts` and assertion messages in a special way. The reason why
some methods may be called is dependent on the optimization (in this case,
`testing(1)` got optimized away by vcs).


```verilog
module test();

function testing(input [0:3] a);
  begin
    $display("test called with %d",a);
    testing=1;
  end
endfunction

initial begin
  if (0 && testing(1)) begin
    $display("test1");
  end

  if (1 && testing(2)) begin
    $display("test2");
  end

  if (0 || testing(3)) begin
    $display("test3");
  end

  if (1 || testing(4)) begin
    $display("test4");
  end
end
```

=== "Icarus output"
    ```bash
    test called with  1
    test called with  2
    test2
    test called with  3
    test3
    test called with  4
    test4
    ```

=== "VCS output"
    ```bash
    test called with  2
    test2
    test called with  3
    test3
    test called with  4
    test4
    ```

=== "C++/short-circuit output"
    ```bash
    test called with 2
    test2
    test called with 3
    test3
    test4
    ```

If an order is needed and a function call can have `debug` side-effects or
synthesis side-effects, the statement must be broken down into several
statements, or the `and_then` and `or_else` operations must be used.


=== "Incorrect code with side-effects"
    ```
    var r1 = pcall1() or  pcall2()  // compile error, non-deterministic


    var r2 = pcall1() and pcall2()  // compile error, non-deterministic


    var r3 = pcall1() +   pcall2()  // compile error
    // compile error only if pcall1/pcall2 can have side effects
    ```

=== "Alternative 1"
    ```
    var r1 = fcall1()
    r1  = fcall2() unless r1

    var r2 = fcall1()
    r2  = fcall2() when r2

    var r3 = fcall1()
    r3 += fcall2()
    ```

=== "Alternative 2"
    ```
    var r1 = fcall1() or_else fcall2()


    var r2 = fcall1() and_then fcall2()


    var r3 = fcall1()
    r3 += fcall2()
    ```

## Basic gates

Pyrope allows a low level or structural direct basic gate instantiation. There
are some basic gates to which to which the compiler translates Pyrope code to. These
basic gates are also directly accesible:


* `__sum` for addition and substraction gate.
* `__mult` for multiplication gate.
* `__div` for divisions gate.
* `__and` for bitwise and gate
* `__or` for bitwise or gate
* `__xor` for bitwise xor gate
* `__ror` for bitwise reduce-or gate
* `__not` for bitwise not gate
* `__get_mask` for extrating bits using a mask gate
* `__set_mask` for replacing bits using a mask gate
* `__sext` for sign-extension gate
* `__lt` for less-than comparison gate
* `__ge` for greater-equal comparison gate
* `__eq` for equal comparison gate
* `__shl` for shift left logical gate
* `__sra` for shift right arithmetic gate
* `__lut` for Look-Up-Table gate
* `__mux` for a priority multiplexer
* `__hotmux` for a one-hot excoded multiplexer
* `__memory` for a memory gate
* `__flop` for a flop gate
* `__latch` for a latch gate


Each of the basic gates operate always over signed integers like Pyrope, but
their semantics vary. A more detailed explanation is available at [LiveHD cell
type section](/livehd/05-lgraph/#cell-type).


## Initialization


Each variable declaration (`var` or `let`) must have an assigned value. The
type default value is `_` (`0` integer, `""` string, `false` boolean, `nil`
otherwise)

```
a  = 3        // compile error, no previous let or var

var b = 3
b  = 5        // OK
b += 1        // OK

let cu3 = if runtime { 3 }else{ 5 }

let d = "hello"  // OK
d = "bar"        // compile error, 'd' is immutable
var d = "bar"    // compile error, 'd' already declared

var e = _        // OK, no type or default value, just scope declaration
e:u32 = 33       // OK

var Foo = 33     // compiler error, 'let Foo = 33'
Foo  = 33        // compiler error, `Foo` already declared as immutable
```

When the variable is a tuple or a range style, the default initialization is
`nil`. `0sb?` can not be applied to ranges or tuples value because it is
restricted for integers. `nil` should be used in those cases.

```
var tup = nil

if cond::[comptime] {
  tup = (a=1,b=2)
}else{
  tup = (a=1,b:u4=3,c=3)
}

cassert tup.a == 1
cassert cond implies tup.b==2
cassert !cond implies tup.b==3
```

Variables with first character upper case are `comptime`. This means that the contents
must be known/fix at compilation time.

```
var A_xxx = something             // comptime
var A_yyy::[comptime] = something // also comptime, redundant but legal
```

