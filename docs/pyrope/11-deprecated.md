
# Deprecated or Future


Pyrope has been in internal development for many years, those are some features
tried and deprecated or removed until a better solution is found.


## `step` options

The `step` command breaks the execution of the function in the statements before and after the step. In the next
cycle, the statements after the step are executed. The issue was that the step could be placed inside complicated
nests of 'if' and 'for' loops. This results in a difficult code to get right. 

The plan is to add something like this feature in the future, once a cleaner implementation is designed.


## Fluid Pipelines

The plan is to re-add the fluid pipelines syntax, but all the other features must be added first.


## Bundle index with bundles

Bundles do not allow an index with another bundle unless it is a trivial bundle
(one element). To illustrate the current constraints:

=== "Bundle index (not allowed)"

    ```old
    type Person = (name:string, age:u32)
    var a = (one:Person, two:Person)

    x = ('one', 'two')
    a[x].age = 10
    ```

=== "Current legal Pyrope"

    ```
    let Person = (name:string=_, age:u32=_)
    var a = (one:Person, two:Person)

    x = 'one'
    y = 'two'
    a[x].age = 10
    a[y].age = 10
    ```

In the future, it may be allowed but some options may not be allowed. For
example, if the index bundle is not unordered, the result of the assignment may
not be easy to predict by the programmer. 

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


```pyrope
let telescope_unit = fun(a:u32,b:u32,start:bool) -> (res:u32) {

  var result_done:reg = 0
  var result_flop:reg = 0

  if result_done {
    res = result_flop
  }

  var int_done:reg = _
  var int_flop:reg = _
  var int_b:reg = _

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

```pyrope
 let res1 =#[1,2] telescope_unit(a,b,start)

 if res1? {
   puts "{}-{}+1 is {}", a, b, res1.res  // incorrect reference to a
 }
```

To address the issue that the `telescope_unit` can have multiple cycles to
complete, a `yield` directive can behave like co-routines. Effectively,
remembering the live-ins and continue executing when the condition is
satisfied.

```pyrope
 let res1 =#[1,2] telescope_unit(a,b,start)

 yield res1? // wait for condition to happen
 assert res1?

 // code executed 1 or 2 cycles after telescope_unit is called
 puts "{}-{}+1 is {}", a, b, res1.res
```

An alternative implementation is using the `#>` keyword. The disadvantage is
that two operations could finish on the same cycle, and the circuits are not as
efficient.

```pyrope
// implicit start/end (starts when called)
let telescope_unit3 = fun(a:u32,b:u32) -> (:u32) {

  {
    let tmp = a+1
  } #> {
    if b == 0 {
      ret tmp
    }
    let tmp2 = tmp-b
  } #> {
    ret tmp2
  }
}
```

The code sample for explicitly managed step function usage:

```pyrope
 let res2 =#[1,2] telescope_unit3(a,b,start)

 if res2? { // code executed 1 or 2 cycles after telescope_unit is called
   puts "{}-{}+1 is {}", a, b, res2
 }
```

The code sample for implicitly managed step function usage:

```future
 async res3 =#[1,2] telescope_unit3(a,b) when start

 await res3 {
   // a and b could have the correct results due to the async/await
   puts "{}-{}+1 is {}", a, b, res3.res
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
enum Order2 = Order ++ Four       // error on overlap?
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


