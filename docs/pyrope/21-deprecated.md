
# Deprecated or Future


Pyrope has been in internal development for many years, those are some features
tried and deprecated or removed until a better solution is found.


## `step` options

The `step` command breaks the execution of the function in the statements before and after the step. In the next
cycle, the statements after the step are executed. The issue was that the step could be placed inside complicated
nests of 'if' and 'for' loops. This results in a difficult code to get right.

The plan is to add something like this feature in the future, once a cleaner implementation is designed.


## Fluid pipelines

The plan is to re-add the fluid pipelines syntax, but all the other features must be added first.


## async/await and coroutines

In non-hardware languages, there are several constructs to handle
asynchronicity.  Asynchronicity is not to leverage parallelism for speedup but
software constructs to handle long latency operations. The most popular
models/techniques are async/await, coroutines, and actors.

In a way, pipelining could be expressed with similar constructs. This has the
advantage of having a larger community (software) to understand/program
hardware more easily.


To illustrate the point, suppose a telescoping subtract-like unit that
provides a response of the operation in 1 or 2 cycles depending on the value of
the input.  If the `b` input is 0, the result is `a+1`. Otherwise, the result is
`a-b+1`. The first finishes in 1 cycle, the second in 2 cycles. This seemly
easy idea is not so easy to implement because it needs to handle 2 flops and
there could be a structural hazard on the flop if the previous cycle was scheduled
for 2 cycles and the current for 1 cycle.

This example explicitly manages the valid output signals.


```pyrope_old
let telescope_unit = fun(a:u32,b:u32,start:bool) -> (res:u32) {

  reg result_done = 0
  reg result_flop = 0

  if result_done {
    res = result_flop
  }

  reg int_done = false
  reg int_flop = 0
  reg int_b = 0

  if int_done {  // pending work (2 cycle op, can not telescope)
    result_flop = int_flop-int_b
    result_done = int_done
    int_flop = a+1
    int_b    = b
    int_done = start
  }else{          // no pending work from before (telescoping is allowed)
    if b == 0 {
      result_flop = a+1
      result_done = start
    }else{
      result_flop = int_flop-int_b
      int_flop = a+1
      int_b    = b
      int_done = start
    }
  }
}
```

In a simple telescoping use case, the `puts` command will be called 1 or 2 cycles
after the `telescope_unit` starts. For the designer, this is quite difficult to
handle. How many flops to add to remember the starting point for `a` and `b`.

```pyrope_old
 let res1 =@[1,2] telescope_unit(a,b,start)

 if res1? {
   puts "{}-{}+1 is {}", a, b, res1.res  // incorrect reference to a
 }
```

To address the issue that the `telescope_unit` can have multiple cycles to
complete, a `yield` directive can behave like co-routines. Effectively,
remembering the live-ins and continue executing when the condition is
satisfied.

```pyrope_old
 let res1 =@[1,2] telescope_unit(a,b,start)

 yield res1? // wait for condition to happen
 assert res1?

 // code executed 1 or 2 cycles after telescope_unit is called
 puts "{}-{}+1 is {}", a, b, res1.res
```

An alternative implementation is using the `#>identifier[lat=cycles]` keyword. The disadvantage is
that two operations could finish on the same cycle, and the circuits are not as
efficient.

```pyrope_old
// implicit start/end (starts when called)
let telescope_unit3 = fun(a:u32,b:u32) -> (res:u32) {

  {
    let tmp = a+1
  } #>one_pipe[lat=1] {
    if b == 0 {
      return tmp
    }
    let tmp2 = tmp-b
  } #> {
    return tmp2
  }
}
```

The code sample for explicitly managed step function usage:

```pyrope_old
 let res2 =@[1,2] telescope_unit3(a,b,start)

 if res2? { // code executed 1 or 2 cycles after telescope_unit is called
   puts "{}-{}+1 is {}", a, b, res2
 }
```

The code sample for implicitly managed step function usage:

```future
 if start {
   async res3 =@[1,2] telescope_unit3(a,b)

   await res3 {
     // a and b could have the correct results due to the async/await
     puts "{}-{}+1 is {}", a, b, res3.res
   }
 }
```

## Extensible enums


Once an enum is created, it can not be modified. There is no reason not to support
compile time addition/removal from an enum. Languages with union types could behave
like extending an enum, but not reducing it. Some potential API for Pyrope

Using the set operations:

```future
enum Order = (One, Two, Three)
enum Order2 = (...Order, Four)
enum Order3 = Order except Three  // new "remove" tuple op
```

Overloading the logical operations is another option, but breaks the rule of
lack of overloading in ops:

```future
enum Order2 = Order or (Four)
enum Order3 = Order and not (Three)
```

Using the trait syntax creates some confusion on the meaning, but an option is to have
custom keywords for enum:

```future
enum Order2 = Order with (Four)
enum Order3 = Order except Three
```

Once we support adding/removing to enums, operations like this would make sense:

```future
match x:Order {
  in Order2      { puts "1 or 2" }
  == Order.Three { puts "3"      }
}
```

## repipe

!!! NOTE
     The `repipe` statement was deprecated because the `pipestage` could
     achieve similar results more cleanly in most of the cases that it was
     tried. Also, `repipe` would have required a custom lgraph pass to balance
     pipeline stages.

The `repipe` statement tries to balance the number of pipeline stages by
inserting registers. If it can not guarantee the same pipeline depth, a compile
error is generated. If there is any feedback loop, likely, the
pipeline can not be rebalanced with `repipe`.


The syntax for `repipe` is `repipe res = (list of variables)`. The result is a
tuple with as many fields as the list of input variables but with enough flops
so that the pipeline is balanced from the list of variables and the function
inputs.


## concat

!!! NOTE
     `concat` was removed because `X#[..]` (the full bit vector of `X`) already
     packs an ordered value, and it packs it in the direction that the rest of
     the language uses. Two spellings for one operation, disagreeing about
     which end is bit 0, is a bug generator.

`concat(a, b, c)` was the positional bit-packing form, what SystemVerilog
spells `{a, b, c}`, Chisel `Cat(a, b, c)`, and Spade `concat(a, b, c)`. It was
**MSB-first**: the first argument occupied the high bits, and a tuple lane
expanded with field 0 most significant.

```pyrope_old
const a:u4 = 0ub1010
const b:u8 = 1

const c:u12 = concat(a, b)   // `a` in bits 11..=8, `b` in bits 7..=0
```

The problem is that it was a false friend. It reads exactly like `{a, b}`, so
it invites a transliteration from SystemVerilog rather than a reading, and it
was the only bit spelling in Pyrope that ran high-to-low. Everywhere else the
language counts up from the bottom: `#[0]` is the low bit, a bit range is
written low-to-high (`x#[3..=6]`, never `6..=3`), and the string encoding
assigns the lower bits to the first characters. Carrying two orders for the
same operation on the same data shape is the kind of detail that survives code
review and then shows up in a waveform.

`X#[..]` covers what `concat` did, in the language's own direction: entry 0 of
an ordered value sits at bit 0, and each later entry stacks above it. The
migration is mechanical — reverse the argument order and pack a tuple:

```pyrope
const a:u4 = 0ub1010
const b:u8 = 1

const c:u12 = (b, a)#[..]    // was `concat(a, b)`: `a` still on top, `b` at bit 0
```

An argument that was itself a tuple or an array becomes a `...` splice, because
`#[..]` packs a flat entry list. This is the case where reversing the argument
list is **not** enough, because the reversal reaches inside the spliced entry
too: `concat` gave field 0 the top of the lane's window, and `#[..]` gives
entry 0 the bottom of it.

```pyrope
const stages:[3]u8 = (1, 2, 3)
const inp:u8 = 4

// `concat(stages, inp)` was {stages[0], stages[1], stages[2], inp}. The
// faithful translation lists the entries reversed, each bound to a typed name
// first: an entry states its window with a DECLARED type, and an element read
// carries none of its own.
const s0:u8 = stages[0]
const s1:u8 = stages[1]
const s2:u8 = stages[2]
const same:u32 = (inp, s2, s1, s0)#[..]
cassert(same == 0x01020304)

// A `...` splice is NOT that layout -- it is {stages[2], stages[1], stages[0], inp}:
const natural:u32 = (inp, ...stages)#[..]
cassert(natural == 0x03020104)
```

Reach for the splice anyway in most cases. Code that packed an array with
`concat` was usually reversing it at the same time — writing entry 0 into the
high window of a word whose other end it indexes from zero — and `(inp,
...stages)#[..]` is the layout it wanted. The faithful translation above is for
the case where the old order was load-bearing, such as a port whose bit
assignment is fixed by something outside the source.


## Liam constructs

In most HDLs loops have to be compile time unrolled, in an earlier version of
Pyrope[^liam] allowed for extra keywords to create an actor model and create
state machines where each loop iteration will be executed in a cycle.


```
while some_condition {

  step   // next cycle starts here
}
```

Fluid constructs:

* `variable?` check if `variable` valid bit is set
* `variable!` check if `variable` has a fluid backpressure
* `keep` do not consume variable on use
* `step` stop the cycle here, continue next cycle after the yield statement


[^liam]: Liam: An Actor Based Programming Model for HDLs, Haven Skinner, Rafael
T. Possignolo, and Jose Renau. 15th ACM-IEEE International Conference on Formal
Methods and Models for System Design (MEMOCODE), October 2017.
