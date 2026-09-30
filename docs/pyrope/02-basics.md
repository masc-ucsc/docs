# Basic syntax

## Comments

A line comment begins with `//` and ends at the end of the line. A block
comment starts with `/*` and ends with `*/`. Block comments nest, so
`/* a /* b */ c */` is one comment; this makes it safe to comment out code that
already has block comments.

```pyrope
// comment
a = 3 // another comment
b = /* inline */ 4
/* outer
  c = 5 /* inner */
  still in the outer comment
*/
```

Nothing inside a comment affects parsing: an operator inside a comment does
not continue a statement, and quotes or braces inside it do not open a string
or an interpolation.

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
(`? + 1` is a syntax error; `0sb? + 1` is a valid operation with unknown
bits). There is no bare `?`
placeholder either: every declaration supplies its value (see
[Initialization](#initialization)).

Outside binary literals, `?` is reserved for a future validity check such as
`foo?` ("is foo valid?"). Both bare `?` and `foo?` are syntax errors for now.

There are two distinct "no value" concepts in Pyrope — unknown-bit integer
literals (`0sb?` / `0ub?`) and `nil`:

* **`0sb?` / `0ub?` (undefined bits)**: An integer value in which one or
  more bits have not been decided by the designer, but the resulting
  circuit must be correct whether each bit turns out to be 0 or 1. During
  simulation, each `?` bit is randomly resolved to 0 or 1 to verify
  correctness under both possibilities. For every operation involving
  unknowns, Dlop tries to resolve the result but may leave bits unknown even
  when a precise result could be proved. It never returns an incorrect
  definite result. For example, `0ub? | 1` may resolve to `1` or remain
  unknown; it cannot resolve to `0`. In synthesized hardware, the synthesis
  tool may choose concrete values for unspecified bits to produce a smaller
  or faster circuit. Unknowns do not imply that a condition is unreachable;
  use `assume` to express those constraints.

* **`nil` (invalid)**: An invalid value that must never be used in any
  expression. Any arithmetic or decision with `nil` triggers a simulation
  assertion error. The only allowed operation is copying or checking for
  validity (`x.[valid]` returns false for `nil`). The compiler must prove that all
  `nil` uses are eliminated at compile time, or a compile error is generated.
  `nil` never exists in synthesized hardware — it is a compile-time and
  simulation-time safety mechanism.

```pyrope
const masked = 0ub? | 1         // may resolve to 1 or remain unknown
cassert((0sb? + 1) == 0sb??)     // error: comparison is unknown, so cassert fails
cassert((nil | 1)==nil)          // error: nil is invalid, not unknown
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
sequences. A raw newline inside either kind of string is a syntax error (write
`\n`); inside a `{...}` interpolation hole a newline is ordinary whitespace.

```pyrope
const a = "hello \n newline"
const b = 'simpler here'
```

The escape sequences are exactly these (the Python/Rust common set):

* `\n`: newline
* `\t`: tab
* `\r`: carriage return
* `\\`: backslash
* `\"`: double quote
* `\'`: single quote
* `` \` ``: backtick quote
* `\0`: NUL character
* `\xNN`: hexadecimal 8 bit character (2 digits)
* `\u{N}`: Unicode character UTF-8 encoded, 1 to 6 hexadecimal digits
  inside the braces (`\u{41}`, `\u{2287}`, `\u{1F600}`)

Any other `\c` is an error. In particular `\uNNNN` without braces is an error
(write `\u{NNNN}`), and `\{` and `\}` are not escapes: a literal brace is
written doubled (`{{`, `}}`).


Pyrope allows string interpolation only when double quote is used (`"bla {expression:format_style} bla"`).
The format style is like C++23 std::format, and it needs an expression: `"{:b}"`
is a syntax error, and so is the empty hole `"{}"`. There are no positional
placeholders filled by extra arguments, not even in `puts`/`print`: write
`puts("a={a} b={b}")`, not `puts("a={} b={}", a, b)`. A hole holds exactly one
expression (`"{x y}"` is an error), and a format style after the `:` is not
empty and holds no brace and no backslash (`"{x:}"`, `"{x:{}}"`, and
`"{x:\x41}"` are errors). In a double quoted string a doubled brace is a
literal brace, as in Python or Rust format strings: `{{` is the text `{` and
`}}` is the text `}`, so `"{{num}}"` is the text `{num}` (no interpolation). A
lone `}` outside a hole is an error (write `}}`). A comment opener inside a
string (`"//"`, `"/*"`) is text, while inside a `{...}` hole the normal code
rules apply, comments included: a `{`, `}`, or `:` inside such a comment never
closes the hole or starts a format style.

```pyrope
const num       = 2
const color     = "blue"
const extension = "s"

const txt1 = "I have {num:d} {color} potato{extension}"
cassert(txt1 == "I have 2 blue potatos")

const txt3 = 'I have {num}'     // single quote does not do interpolation
cassert(txt3 == "I have {{num}}") // a doubled brace escapes the interpolation
cassert("{{{num}}}" == '{2}')     // literal braces around an interpolation
cassert("a // b" == 'a // b')     // a comment opener inside a string is text
cassert("{num /* } */ + 1}" == "3") // a comment inside a hole is a comment
cassert("\u{41}\x42" == 'AB')    // escapes: \u{...} and \xNN
const bad = "{:b}"                // error: format style without an expression
const bad2 = "{num:}"             // error: empty format style
const bad3 = "{num color}"        // error: a hole holds one expression
const bad4 = "num={}"             // error: empty hole, write "num={num}"
const bad5 = "a } b"              // error: lone `}`, write "a }} b"
const bad6 = "I have \{num\}"     // error: not escapes, write "I have {{num}}"
const bad7 = "\u2287"             // error: write "\u{2287}"
const bad8 = "{num:\x41}"         // error: backslash inside a format style

comptime const text4 = "I have {num+1} x"
cassert(text4 == "I have 3 x")
```

`String(value)` converts an integer to decimal text:

```pyrope
const value = 127
const text = String(value)
cassert(text == "127")
```

Strings are opaque; they do not implicitly convert to numeric values or bit
vectors.

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
belongs to a new statement. A line that starts with a binary operator (`+`,
`-`, `*`, `/`, `%`, `|`, `==`, `.`, ...), a `:` (type annotation or attribute),
or a `#` bit selector (`#[0..=3]`, `#|[..]`, ...) continues the previous
statement. A timing read `@[N]` is not an operator: it stays on the line of its
name (a line starting with `@` is an error, also inside an `if` condition).

```pyrope
mut (a,b,c,d) = (0,0,0,0)
a = 1
  + 3           // 1st stmt
(b,c) = (1,3)   // 2nd stmt
cassert(a == 4 and b == 1 and c == 3)

d = 1 +         // OK, but not formatted to style
    3

mut e
  :U8 = 0xF5    // same statement: `mut e:U8 = 0xF5`
const lo = e
  #[0..=3]      // same statement: `e#[0..=3]`
cassert(lo == 5)
const m = 17
  % 5           // same statement: `17 % 5`
cassert(m == 2)
```
Operators spelled as words work like the symbol ones. A line that starts with
`and`, `or`, `implies`, `in`, `has`, `does`, `equals`, or `case` continues the
previous statement. `case` always continues, even though it is also the
`match` arm keyword. The match is whole-word, so a line that starts with an
identifier like `order` or `index` is a new statement.

```pyrope
const r = false
        or true          // same statement

cassert(r)

const ok = (const x=1, const y=2)
         has "x"         // same statement

cassert(ok)
```

This functionality allows parallelizing the parsing and elaboration in Pyrope.
More important, it makes the code more readable, by looking at the beginning of
the line, it is possible to know if it is a new statement or a continuation of
the last one. It also helps to standardize the code format by allowing only one
style.


### Identifiers

An unescaped identifier is a non-reserved name that starts with an underscore or an
alphabetic character, followed by letters (non-ASCII letters included), digits,
or underscores. `$` is not an identifier character, and neither is any other
non-ASCII symbol (emoji, a no-break or zero-width space, `—`). Since Pyrope is designed to
support any synthesizable Verilog automatic translation, any nonempty sequence of
characters between backticks (\`) can form a valid identifier, so a Verilog
name like `foo$bar` is written `` `foo$bar` ``. The identifier uses the same
escape sequence as strings.

```pyrope
const `foo is . strange!\nidentifier` = 4
const `for` = 3
cassert(`for`+1 == `foo is . strange!\nidentifier`)
```

Backticks are required whenever an ordinary name matches a reserved keyword
or type spelling, ignoring case, or contains characters outside the identifier
rules above. This is one rule for every name: declarations, destructuring,
parameters and outputs, generics, loop variables, tuple fields, methods,
enum members, named arguments, dotted selectors, and attributes. There are no
field-name or attribute-name exceptions. Name lookup itself remains
case-sensitive: `` `if` `` and `` `IF` `` are distinct names.

Keywords used as language syntax keep their normal spelling: `if` starts a
conditional and `comptime` is a declaration modifier. When the same text names
an attribute, field, or other entity, escape it: ``x.[`comptime`]``,
``x.`if` ``, ``f(`in`=x)``, and ``f<`type`=U8>(x)``.

```pyrope
const cfg = (const `type` = 1, const `if` = 2)
cassert(cfg.`type` == 1 and cfg.`if` == 2)
const `in` = 3
const `IF` = 4                  // case variants require backticks too
// const in = 3                // error: reserved word used as a name
// const If = 4                // error: reservation ignores case
for `for` in 0..<2 { cassert(`for` < 2) }
```

`` `foo` `` and `foo` are the same name only when `foo` is a non-reserved word
made of identifier characters. A reserved word keeps its meaning only
unescaped: a backticked reserved word is an ordinary name in every position,
so `` `else` `` is not `else`.

The formatter preserves backticks around reserved keywords and type spellings
using a case-insensitive match: `` `else` ``, `` `ELSE` ``, `` `u8` ``, and
`` `U8` `` all keep their backticks. This formatting rule does not change the
language's case-sensitive name lookup.

The built-in type words `U<N>`, `S<N>`, `Unsigned`, `Signed`, `Bool`, `String`,
`Clock`, and `Reset` ([type system](07-typesystem.md)) are reserved words too.
`U<N>` and `S<N>` stand for `U` or `S` followed by any digit string (`U0`,
`U1333`, `S99999999`). They cannot be declared or used as a variable, port,
parameter, lambda, or field name, not even after a `.` (`foo.U33` is an error);
a name with that spelling must be backticked, and `` `U4` `` is then a
variable, never the type (`` foo.`U33` `` is a field).

The old lowercase type spellings are banned words: `u`, `s`, or `i` followed by
digits (`u8`, `s4`, `i32`), `bool`, `boolean`, `unsigned`, `signed`, and
`string`. Using one anywhere (as a type, a cast, a variable, lambda, or field
name) is an error that names the new spelling (`u8` was renamed `U8`). So `s1`,
`i0`, and `u4` are not legal names; pick another name (`st1`, `in0`) or
backtick it (`` `s1` ``), since a backticked banned word is an ordinary name.

```pyrope
const `U4` = 3         // a variable named U4
mut x:U4 = `U4`        // the type U4 holding the variable U4
const U4 = 3           // error: U4 is a reserved type word, use `U4`
const s1 = 1           // error: s1 is a banned old spelling (now S1)
const st1 = 1          // OK
const `s1` = 1         // OK: a backticked banned word is an ordinary name
const cfg2 = (const `U8` = 1, const `bool` = true)
cassert(cfg2.`U8` == 1)
const `foo$bar` = 2    // `$` needs backticks
const foo$bar = 2      // error: `$` is not an identifier character
```

The backticks are Pyrope spelling only; they never reach the generated Verilog.
There the bare name is emitted, and Verilog's own `\name ` escape is added only
when Verilog itself needs it: `` `if` `` becomes `\if ` because `if` is a Verilog
keyword, while `` `in` `` — not reserved in Verilog — is emitted as plain `in`.

Identifiers are case-sensitive like Verilog. User-defined type and variable
names may use uppercase or lowercase letters; capitalization is not enforced
by the compiler. The style guide recommends starting type names with an
uppercase letter (`Pixel`, `GcdModel`) and variable names with a lowercase
letter (`pixel`, `count`).

The reserved type words and banned old spellings listed above still require
backticks when used as ordinary names. That restriction is independent of
the capitalization style recommendation.

`comptime` is not inferred from casing. To require compile-time evaluation,
prefix the declaration with `comptime` explicitly (e.g.,
`comptime const size = 16`). The ``.[`comptime`]`` query checks whether the current
value is known at compile time, regardless of the declaration's modifier.

The bare underscore (`_`) and names matching `_[digit][alnum]*` (e.g., `_0`,
`_1a`, `_23abc`) are reserved for future syntax (anonymous lambda
placeholders). Here a digit is a Unicode decimal digit, and alphanumeric
means a Unicode letter or decimal digit. These unescaped names are syntax
errors in every position (a binding, a destructuring slot, a parameter, a
value, or a field). The pattern matches the whole name: `_1_a` and `__0`
remain legal. Using the backtick form (`` `_` ``, `` `_0` ``, `` `_1a` ``)
bypasses the reservation if a Verilog import really needs that exact spelling.

```pyrope
const _ = 8            // error: `_` is reserved
(_, b) = f()           // error: `_` is reserved, also as a destructuring slot
const x = _ + 1        // error: `_` is reserved, also as a value
const _1a = 8          // error: `_[digit][alnum]*` is reserved
const `_` = 8          // OK: a backticked `_` is an ordinary name
const `_1a` = 8        // OK: a backticked reserved name
```

## Semicolons

Semicolons are not needed to separate statements. In Pyrope, a semicolon (`;`)
has the same meaning as a newline. Sometimes it is possible to add
semicolons to separate statements. Since newlines affect the meaning of the
program, a semicolon can do too.

```pyrope
const a = 1 ; const b = 2
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
puts(priority=2, msg=" world")

// src/file2.prp
print(priority=1, msg="hello")
```

The available puts/print arguments:
* `msg`: the message string.
* `priority`: relative order to print in a given cycle.
* `file`: file to send the message. E.g: `stdout`, `stderr`, `my_large.log`,...

Arguments follow the normal [argument naming](06-functions.md#argument-naming)
rules. `msg` and `file` are both strings, so once `priority` or `file` is
passed the message is named too: `puts(priority=2, " world")` is an error.


Use string interpolation to build a string without printing it.

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
cassert(f(a=2, b=3) == 5)
```

Pyrope naming for consistency:

* `comb` is pure combinational logic (zero cycles). Can use `ref` to modify tuples (equivalent to implicit output).

* `pipe[N]` is a fixed N-cycle pipeline with `N > 0` (every output lands exactly N cycles after its inputs; no combinational input-to-output path). A zero-cycle block is `comb`, not `pipe[0]`.

* `pipe[A..=B]` is a flexible A-to-B cycle pipeline, with positive cycle counts; the caller picks a concrete latency via `stage[N]`

* Bare `pipe` leaves the latency fully flexible; the caller picks a positive latency via `stage[N]` at the call site

* `mod` has no constraints on registers or output structure (can be Mealy or Moore), operates cycle by cycle, and is also the kind used to orchestrate pipelined calls — `stage[N]` and `@[N]` are the timing constructs available inside `mod`. Unlike `pipe`, each `mod` output declares its own landing cycle `@[N]` (`N` from `0` to `n`) at the interface (`mod f(a:U8) -> (x:U8@[2], y:U8@[0])`); a cycle-0 output is a combinational feedthrough, legal in `mod` but forbidden in `pipe`. To generate an LGraph module (for Verilog or simulation), the concrete `comb`/`pipe`/`mod` interface must be fully typed and have a fixed port list. This can be written directly in the declaration, or deferred until a call binds untyped parameters, generics, and varargs to concrete declared actuals. A `comb` with an untyped input or generics is a template: it is always inlined and never generates its own LGraph. A fully typed `comb` (even one with a defaulted input) is a normal unit with its own LGraph.

* `stage` is a reserved declaration modifier used inside `mod` blocks.

* `comb`, `pipe`, or `mod` that declares `self` as its FIRST parameter is also called a method; methods may be called via UFCS (`obj.method(...)`) or directly (`method(obj, ...)`)


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

Short-circuit is still observable at compile time. Since the skipped operand is
never evaluated, an [illegal operation](05-assert.md#illegal-operations) inside
it is not reported, which makes `and`/`or` the way to guard a compile-time
computation:

```pyrope
const N = 0
// `64 % N` is skipped, so the modulo by zero is never evaluated
cassert(N == 0 or (N > 0 and (64 % N == 0)))
```

The untaken arm of an `if` behaves the same way, and there it is the only way to
guard a computation whose operands are not booleans.

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
cassert(a == {3+1+100}) // same, expression block evaluates to 104
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
    if not r1 {
      r1 = fcall2()
    }

    mut r2 = fcall1()
    if r2 {
      r2 = fcall2()
    }

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
* `__gt` for greater-than comparison gate
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
type section](/livehd/05-lgraph/#cell-type). A basic gate is an ordinary call:
its arguments are named with the LGraph pin names (``__sum(`as`=(a, b))``,
`__mux(s=cond, p1=b, p2=a)`), see [instantiation](06b-instantiation.md).


Pyrope has a modulo operator `a % b`, but only the cases that lower cheaply to
shift/mask are accepted as hardware; a general modulo is not. The semantics are
*truncated* (the remainder's sign follows the dividend, like Verilog `%`),
because the signed semantics for "mod" differ across languages like Python and
C, and a full divider is expensive. The lowered cases are:

* `b` a compile-time power of two, with a non-negative `a` → `a & (b-1)`.
* `b` provably larger than `a` (`a`'s value range fits in `[0, |b|)`) → `a`
  (no remainder is possible).
* `b == 3` (compile time), with a non-negative `a` → a base-4 digit-sum
  reduction (since `4 ≡ 1 (mod 3)`).

Any other `% b` (a runtime divisor, a possibly-negative dividend, or a divisor
that is none of the above) is a compile error. A fully compile-time `a % b`
still folds to a constant.

## Initialization


Each variable declaration (`mut` or `const`) must have an assigned value. There
is no implicit default: write a concrete value (`0`, `false`, `""`), `nil` for
no value yet, or `0sb?` for unknown bits (see
[Variable initialization](04-variables.md#variable-initialization)).

```pyrope
a  = 3        // error: no previous const or mut

mut b = 3
b  = 5        // OK
b += 1        // OK
cassert(b == 6)

const (a,b2) = (1,"string_inferred")
cassert(a == 1 and b2 == "string_inferred")
const (a3:U32,b3) = (1,"x")   // error: destructuring slots never carry a type

const d = "hello"  // OK
d = "bar"        // error: 'd' is immutable
mut d = "bar"    // error: 'd' already declared

mut e:U32 = 33
cassert(e == 33)

const Foo = 33   // immutable because of `const`; casing carries no meaning
Foo  = 34        // error: `Foo` already declared as immutable
```

When the variable is a tuple or a range style, `0sb?` can not be applied
because it is restricted for integers. `nil` should be used in those cases.

```pyrope
mut tup = nil

assert(cond.[`comptime`]) // Tuples are compile time, it would fail otherwise
if cond == true {
  tup = (const a=1, const b=2)
}else{
  tup = (const a=1, const b:U4=3, const c=3)
}

cassert(tup.a == 1)
cassert(cond implies tup.b==2)
cassert(!cond implies tup.b==3)
```

Casing does not affect `comptime`. The declaration modifier requires
compile-time evaluation; ``.[`comptime`]`` checks whether the current value is
known at compile time, even when the declaration has no `comptime` modifier.

```pyrope
assert(something.[`comptime`])
comptime const A_xxx = something      // comptime
assert(A_xxx.[`comptime`]) // also comptime
```
