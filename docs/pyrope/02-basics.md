# Basic syntax

## Comments

Comments begin with `//`, there are no multi-line comments

```pyrope
// comment
a = 3 // another comment
```

## Constants

### Integers

Pyrope has unlimited precision signed integers. Any literal starting with a
digit is a likely integer constant.

```pyrope
cassert(0xF_a_0  == 4000) // Underscores have no meaning
cassert(0b1100   == 12) // error: use 0ub1100 or 0sb1100
cassert(0ub1100  == 12) // ub explicit unsigned binary
cassert(0sb1110  == -2) // sb signed binary
cassert(33       == 33) // 33 in decimal
cassert(0o111    == 73) // octal
cassert(0111     == 111) // decimal (some languages use octal here)
```

Since powers of two are very common, Pyrope decimal integers can use the `K`, `M`, `G`, and `T` modifiers.

```pyrope
cassert(1K == 1024)
cassert(1M == 1024*1024)
cassert(1G == 1024*1024*1024)
cassert(1T == 1024*1024*1024*1024)
```

Several hardware languages support unknown bits (`?`) or high-impedance (`z`). Pyrope
aims at being compatible with synthesizable Verilog, as such `?` is also supported in
the binary encoding.

```pyrope
0ub?            // 0 or 1 in decimal (unsigned, `0ub` explicit prefix)
0sb?            // 0 or -1 in decimal (signed)
0ub?0           // 0 or 2 in decimal
0ub10??1?01     // mixed known and unknown bits (unsigned)
0sb0?0          // 0 or 2 in decimal (signed)
```

The Verilog high impedance `z` is not supported. Tri-state behavior can be
expressed with `unique if`, which EDA tools can optimize to tri-state buffers
when appropriate.

Like in many HDLs, Pyrope supports unknown bits for Verilog compatibility,
but only as digits inside a binary integer literal — never as a standalone
value. `0ub?`, `0sb?`, `0ub101?`, and `0ub??10` are valid integer
values; bare `?` is **not** an integer and cannot be used in arithmetic
(`? + 1` is a type error, `0sb? + 1` is `0sb??`). Bare `?` is a separate
concept — a declaration placeholder meaning "use the type's default" (see
[Initialization](#initialization)).

There are two distinct "no value" concepts in Pyrope — unknown-bit integer
literals (`0sb?` / `0ub?`) and `nil`:

* **`0sb?` / `0ub?` (undefined bits)**: An integer value in which one or
  more bits have not been decided by the designer, but the resulting
  circuit must be correct whether each bit turns out to be 0 or 1. During
  simulation, each `?` bit is randomly resolved to 0 or 1 to verify
  correctness under both possibilities. Arithmetic follows Verilog
  x-propagation semantics: `0sb? + 1` is `0sb??`, `0sb? | 1` is `1`. In
  synthesized hardware, `?` bits give the synthesis tool freedom to
  choose whichever value produces a smaller or faster circuit.

* **`nil` (invalid)**: An invalid value that must never be used in any
  expression. Any arithmetic or decision with `nil` triggers a simulation
  assertion error. The only allowed operation is copying or checking for
  validity (`x.[valid]` returns false for `nil`). The compiler must prove that all
  `nil` uses are eliminated at compile time, or a compile error is generated.
  `nil` never exists in synthesized hardware — it is a compile-time and
  simulation-time safety mechanism.

```pyrope
cassert (0sb? | 1) == 1    // OK: unknown OR 1 = 1
cassert (0sb? + 1) == 0sb?? // unknown propagation
nil | 1      // error: nil is invalid, not unknown
```

Notice that `nil` is a state in the integer basic type, it is not a new type by
itself, it does not represent an invalid pointer, but rather an invalid
integer.

The advice is not to use unknown-bit literals (`0sb?`, `0ub?`, …)
outside of `match` pattern matching. It is less error prone to use the
concrete default value (zero or empty string), but sometimes it is easier to
use `nil` when converting Verilog code to Pyrope.


### Strings

Pyrope accepts single line strings with a single quote (`'`) or double quote
(`"`).  Single quote does not have escape character, double quote supports escape
sequences.

```pyrope
a = "hello \n newline"
b = 'simpler here'
```

* `\n`: newline
* `\\`: backslash
* `\"`: double quote
* `` ` ``: backtick quote
* `\xNN`: hexadecimal 8 bit character (2 digits)
* `\uNNNN`: hexadecimal 16-bit Unicode character UTF-8 encoded (4 digits)


Pyrope allows string interpolation only when double quote is used (`"bla {expression:format_style} bla"`).
The format style is like C++23 std::format.

```pyrope
const num       = 2
const color     = "blue"
const extension = "s"

const txt1 = "I have {num:d} {color} potato{extension}"
const txt2 = string("I have {:d} {} potato{}", num, color, extension)
cassert(txt1 == txt2 == "I have 2 blue potatos")

const txt3 = 'I have {num}'     // single quote does not do interpolation
cassert(txt3 == "I have \{num\}") // \{ escapes the interpolation

comptime const text4 = "I have {num+1} x"
cassert(text4 == "I have 3 x")
```

Integers and strings can be converted back and forth:

```pyrope
mut a:string = "127"
mut b:int = a        // same as mut b = int(a)
mut c:string = b     // same as mut c = string(b)
cassert(a == c)
cassert(b == 0x7F)
assert(a == b) // error: 'a' and 'b' have different types
```


## Newlines and spaces

Spaces do not have meaning but new lines do. Several programming languages like
Python use indentation level (spaces) to know the parsing meaning of
expressions. In Pyrope, spaces do not have meaning, and newlines combined with
the first token after newline is enough to decide the end of statement.


By looking at the first character after a new line and the last one the
previous line, it is possible to know if the rest of the line belongs to the
previous statement or it is a new statement.


If the line starts with an alphanumeric (`[a-z0-9]` that excludes operators
like `or`, `and`) value or an open parenthesis (`(`), the rest of the line
belongs to a new statement.

```pyrope
mut (a,b,c,d) = nil
a = 1
  + 3           // 1st stmt
(b,c) = (1,3)   // 2nd stmt
cassert(a == 4 and b == 1 and c == 3)

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

```pyrope
`foo is . strange!\nidentifier` = 4
`for` = 3
cassert(`for`+1 == `foo is . strange!\nidentifier`)
```

Using the backtick, Pyrope can use any string as an identifier, even reserved
keywords. Identifiers are case sensitive like Verilog, but the compiler issues
errors for non \` escaped identifiers that do not follow these conditions in
order:

* Identifiers with a single character followed by a number can be upper or lower case.
* `comptime` is not inferred from casing. To make a binding compile-time,
  prefix the declaration with `comptime` explicitly (e.g.,
  `comptime const SIZE = 16`). An all-uppercase name without `comptime`
  is just a runtime constant — the compiler does not treat casing as a
  comptime signal.
* Types should either: (1) start the first character uppercase and everything
  else lower case; (2) be all lower case and finish with `_t`.
* All the other identifiers that start with an alpha character `[a-z]` are
  always lower case.

The bare underscore (`_`) and any name of the form `_<digits>` (e.g., `_0`,
`_1`, `_2`, ...) are reserved and may not be used as binding names. They
are reserved for future syntax (anonymous lambda placeholders). Using the
backtick form (`` `_` ``, `` `_0` ``) bypasses the reservation if a Verilog
import really needs that exact spelling.

## Semicolons

Semicolons are not needed to separate statements. In Pyrope, a semicolon (`;`)
has the same meaning as a newline. Sometimes it is possible to add
semicolons to separate statements. Since newlines affect the meaning of the
program, a semicolon can do too.

```pyrope
a = 1 ; b = 2
```

## Printing and debugging

Printing messages is useful for debugging. `puts` prints a message and the string
is formatted using the c++23 std::format. There is an implicit newline printed.
The same without a newline can be achieved with print.

```pyrope
const a = 1
const msg = "Hello a is {a}"
puts(msg)
cassert(msg == "Hello a is 1")
```

Pyrope does string interpolation, and it has attributes to access line of code
and file name. Since tracing or debugging variables is quite common, the `dbg`
statement behaves like `puts` and also prints the line of code and file name
for easier tracing.


```pyrope
a = 1

puts("{}:{} a:{} tracing a", a.[file], a.[loc], a)
puts("{a.[file]}:{a.[loc]} a:{a} tracing a")          // Same
```

The previous statements print "foo:3 a:1 tracing a" in the 3 cases. The line of
code corresponds to the latest update of variable, not the `dbg` statement.


Since many modules can print at the same cycle, it is possible to put a
relative priority between `puts` calls (`priority`). If no relative priority is
provided, a default 0 priority is provided. Messages are kept to the end of the
cycle, and then printed in alphabetical order for a given priority. This is
done to be deterministic. Higher priority (higher value) are printed after
lower priority. Messages generated by assertions also get serialized like `puts`
statements but have the highest priority.


To avoid breaking down different `puts` inside the same method. All the `puts`
in a given cycle are shown together.


This example will print "hello world" even though there are 2 puts/prints in
different files.

```pyrope
// src/file1.prp
puts(priority=2, " world")

// src/file2.prp
print(priority=1, "hello")
```

The available puts/print arguments:
* `priority`: relative order to print in a given cycle.
* `file`: file to send the message. E.g: `stdout`, `stderr`, `my_large.log`,...


A related command to `puts` is `format` — it behaves like `print` but
returns a string.

`puts/print` are a bit special. In most languages, IO operations like `puts` are
considered to have side-effects. In Pyrope, the `puts` can not modify the
behavior of the synthesized code and it is considered a non-side-effect lambda
call. This allows to have `puts` calls in `functions`.


## Lambda or Routines


Pyrope only supports anonymous lambdas, but the lambdas can have attributes that restrict
the lambda functionality to combinational only (`comb`), pipeline stages
that have all the outputs with the same delay (`pipe`), or modules that can
do anything — including orchestrating pipelined calls with explicit timing
(`mod`). [Lambda section](06-functions.md) has more details on the allowed
syntax.


```pyrope
comb f(a, b) -> (r) { r = a + b }
cassert(f(2, 3) == 5)
```

Pyrope naming for consistency:

* `comb` is pure combinational logic (zero cycles). Can use `ref` to modify tuples (equivalent to implicit output).

* `pipe[N]` is a fixed N-cycle pipeline (Moore machine — outputs always registered)

* `pipe[A..=B]` is a flexible A-to-B cycle pipeline; the caller picks a concrete latency via `stage[N]`

* Bare `pipe` leaves the latency fully flexible; the caller picks it via `stage[N]` at the call site

* `mod` has no constraints on registers or outputs (can be Mealy or Moore), operates cycle by cycle, and is also the kind used to orchestrate pipelined calls — `stage[N]` and `@[N]` are the timing constructs available inside `mod`.

* `stage` is a reserved declaration modifier used inside `mod` blocks. `async`/`await` are reserved for future use.

* `comb`, `pipe`, or `mod` that uses a `self` parameter is also called a method


## Evaluation order

Statements are evaluated one after another in program order. The main source of
conflicts come from expressions.


The expression evaluation order is important if the elements in the expression
can have side effects. Pyrope constrains the expressions so that no matter the
evaluation order, the synthesis result is the same.


Languages like C++11 do not have a defined order of evaluation for
all types of expressions. Calling `call1() + call2()` is not defined. Either
`call1()` first or `call2()` first.


In many languages, the evaluation order is defined for logical expressions.
This is typically called short-circuit evaluation. Pyrope `and`/`or` always
short-circuit like most modern languages: in `a and b`, `b` is not evaluated
if `a` is false; in `a or b`, `b` is not evaluated if `a` is true. Since
Pyrope expressions have no side effects, short-circuit produces the same
hardware as evaluating both sides — the compiler is free to optimize either
way.

The programmer can also set evaluation order with control expressions
(`if/else`, `match`, `for`). An expression can have many `comb` calls because
those have no side-effects, and hence the evaluation order is not important.


A `pipe` can update state internally and has one or more cycle delays. As
such, `pipe` statements can do many calls to `comb` lambdas, but not to
other `pipe` lambdas. `pipe` lambdas can only be called inside `mod`
lambdas, where their outputs are consumed via `stage[N]` with an explicit
latency.



Expressions also can have code blocks (`{  }`) as long as there are no
side-effects. In a way, expression code blocks can be seen as a type of
`comb` lambda that is called immediately after definition.


```pyrope
mut a = {mut d=3 ; d+1} + 100 // OK
cassert(a == (3+1+100))
cassert(a == {3+1+100}) // same, expression evaluated as 104 and returned
```


For most expressions, Pyrope is more restrictive than other languages because
it wants to be a fully defined deterministic independent of implementation. To
handle logging/messaging in `comb` calls, Pyrope treats `puts` as a special
instruction. Pyrope runtime delays the `puts` output until the end of the cycle.
See the Printing section above for more details.


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
statements. Since `and`/`or` short-circuit, they provide a defined left-to-right
evaluation order for logical expressions.


=== "Incorrect code with side-effects"
    ```pyrope
    mut r3 = mcall1() +   mcall2()  // error:
    // error: only if mcall1/mcall2 can have side effects
    ```

=== "Fix with separate statements"
    ```pyrope
    mut r1 = fcall1()
    r1  = fcall2() unless r1

    mut r2 = fcall1()
    r2  = fcall2() when r2

    mut r3 = fcall1()
    r3 += fcall2()
    ```

=== "Fix with short-circuit"
    ```pyrope
    mut r1 = fcall1() or fcall2()


    mut r2 = fcall1() and fcall2()


    mut r3 = fcall1()
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
* `__hotmux` for a one-hot encoded multiplexer
* `__memory` for a memory gate
* `__flop` for a flop gate
* `__latch` for a latch gate


Each of the basic gates operate always over signed integers like Pyrope, but
their semantics vary. A more detailed explanation is available at [LiveHD cell
type section](/livehd/05-lgraph/#cell-type).


Pyrope does not have a "mod" operator. The semantics for "mod" with signed
integers are different in languages like Python and C. It is a complex operator
to provide hardware support.

## Initialization


Each variable declaration (`mut` or `const`) must have an assigned value. The
type default value is `?` (unknown/uninitialized).

```pyrope
a  = 3        // error: no previous const or mut

mut b = 3
b  = 5        // OK
b += 1        // OK
cassert(b == 6)

const (a:u32,b2) = (1,"string_inferred")
cassert(a == 1 and b2 == "string_inferred")

const d = "hello"  // OK
d = "bar"        // error: 'd' is immutable
mut d = "bar"    // error: 'd' already declared

mut e:u32 = 33
cassert(e == 33)

mut Foo = 33     // error: 'const Foo = 33'
Foo  = 33        // error: `Foo` already declared as immutable
```

When the variable is a tuple or a range style, the default initialization is
`nil`. `0sb?` can not be applied to ranges or tuples value because it is
restricted for integers. `nil` should be used in those cases.

```pyrope
mut tup = nil

assert(cond.[comptime]) // Tuples are compile time, it would fail otherwise
if cond == true {
  tup = (a=1,b=2)
}else{
  tup = (a=1,b:u4=3,c=3)
}

cassert(tup.a == 1)
cassert(cond implies tup.b==2)
cassert(!cond implies tup.b==3)
```

Variables with first character upper case are `comptime`. This means that the contents
must be known/fixed at compilation time.

```pyrope
assert(something.[comptime])
comptime const A_xxx = something      // comptime
assert(A_xxx.[comptime]) // also comptime
```
