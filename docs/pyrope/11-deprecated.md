
# Deprecated or Future


Pyrope has been in internal development for many Years, those are some features
tried and deprecated or removed until a better solution is found.


## `step` options

The `step` command breaks the execution of the function in the statements before and after the step. The next
cycle, the statements after the step are executed. The issue was that the step could be placed inside complicated
nests of 'if' and 'for' loops. This results in a difficult code to get right. 

The plan is to add something like this feature in the future, once a cleaner implementation is designed.


## Fluid Pipelines

The plan is to re-add the fluid pipelines syntax, but all the other features must be added first.


## Bundle index with bundles

Bundles do not allow an index with another bundle unless it is a trivial bundle
(one element). To illustrate the current constrains:

=== "Bundle index (not allowed)"

    ```
    type Person = (name:string, age:u32)
    var a = (one:Person, two:Person)

    x = ('one', 'two')
    mut a[x].age = 10
    ```

=== "Current legal Pyrope"

    ```
    type Person = (name:string, age:u32)
    var a = (one:Person, two:Person)

    x = 'one'
    y = 'two'
    mut a[x].age = 10
    mut a[y].age = 10
    ```

In the future, it may be allowed but some options may not be allowed. For
example, if the index bundle is not unordered, the result of the assignment may
not be easy to predict by the programmer. 

## async/await and coroutines

In non hardware languages, there are several constructs to handle
asynchronicity.  Asynchronicity is not to leverage parallelism for speedup but
software constructs to handle long latency operations. The most popular
models/technies are async/await, coroutines, and actors. 

In a way, pipelining could be expressed with similar constructs. This has the
advantage of having a larger community (software) to understand/program
hardware more easily.


To illustrate the point, suppose a telescoping substract-like unit that
provides a response of the operation in 1 or 2 cycles depending in the value of
the input.  If the `b` input is 0, the result is `a+1`. Otherwise the result is
`a-b+1`. The first finishes in 1 cycle, the second in 2 cycles. This seemly
easy idea is not so easy to implement because it needs to handle 2 flops and
there could be a structural hazard on the flop if the previous cycle scheduled
for 2 cycles and the current for 1 cycle.

This example explicitly manages the valid output signals.


```pyrope
telescope_unit = {|(a:u32,b:u32,start:bool) -> (res:u32,done:bool)|

  %.done = #result_done
  %.res  = #result_flop

  if #int_done {  // pending work (2 cycle op, can not telescope)
    #result_flop = #int_flop-$int_b
    #result_done = #int_done
    #int_flop = $a+1
    #int_b    = $b
    #int_done = $.start
  }else{          // no pending work from before (telescoping is allowed)
    if $b == 0 {
      #result_flop = $a+1
      #result_done = $.start
    }else{
      #result_flop = #int_flop-#int_b
      #int_flop = $a+1
      #int_b    = $b
      #int_done = $.start
    }
  }
}
```

A simple telescoping use case, the `puts` command will be called 1 or 2 cycles
after the `telescope_unit` starts. For the designer, this is quite difficult to
handle. How many flops to add to remember the starting point for `a` and `b`.

```pyrope
 res1 =#[1,2] telescope_unit($a,$b,$start)

 if res1.done {
   puts "{}-{}+1 is {}", $a, $b, res1.res  // incorrect reference to a
 }
```


To address the issue that the `telescope_unit` can have multiple cycles to
complete, a `yield` directive can behave like co-routines. Effectively,
remembering the live-ins and continue executing when the condition is
satisfied.

```pyrope
 res1 =#[1,2] telescope_unit($a,$b,$start)

 yield res1.done // wait for condition to happen

 if res1.done { // code executed 1 or 2 cycles after telescope_unit is called
   puts "{}-{}+1 is {}", $a, $b, res1.res
 }
```

While `yield` waits for a condition, the `step` directive waits for a number of cycles,
but the functionality is quite similar. The advantage is that if the telescope
unit uses step to pipeline, a simpler async (no need to track done signal) could be used.

```pyrope
// explicit start/end
telescope_unit2 = {|(a:u32,b:u32,start:bool) -> (res:u32,done:bool)|
  var y
  if $b == 0 or #pending {
    x = $a+1
    #pending = true
    step 1 {
      #pending = false
      y = x - $b
      s = $start
    }
  }else{
    y = $a+1-$b
    s = $start
  }
  step 1 {
    return (res=y, done=s)
  }
}

// implicit start/end (starts when called)
telescope_unit3 = {|(a:u32,b:u32) -> (res:u32)|
  var y
  if $b == 0 or #pending {
    x = $a+1
    #pending = true
    step 1
    #pending = false
    y = x - $b
  }else{
    y = $a+1-$b
  }
  step 1 
  return res=y
}
```

The code sample for explicitly managed step function usage:

```pyrope
 res2 =#[1,2] telescope_unit2($a,$b,$start)

 yield res2.done // wait for condition to happen

 if res2.done { // code executed 1 or 2 cycles after telescope_unit is called
   puts "{}-{}+1 is {}", $a, $b, res2.res
 }
```

The code sample for implicitly managed step function usage:

```pyrope
 async res3 =#[1,2] telescope_unit3($a,$b) when $start

 await res3 { // code executed 1 or 2 cycles after telescope_unit is called
   puts "{}-{}+1 is {}", $a, $b, res3.res
 }
```

