# Structural Typing


Pyrope uses structural typing somewhat simular to other languages like
Typescript, but there are some difference simplifications like not references,
everything is passed by value, no union types.



## Type check


The `x does y` checks that `x` does the same as `y` and maybe more. It type
system syntax means that `x` is a subtype of `y`, or that `y` is a supertype
`x`.


Using the typical `Animal`, `Dog`, `Greyhound` set of tuples, `Dog does Animal`
and `Greyhound does Dog`, but `not (Animal does Dog)`.

Dealing with tuple assignments `y = x`, a compile error is generated unless the
type system satisfies `y does x` or an explicit type conversion is provided.
The basic behavior of `does` is explained in (Type
equivalance)[07-typesystem.md#Type_equivalence].

```
let Animal = (
  ,legs:int = _
  ,name= "unnamed"
  ,say_name = fun() { puts name }
)

let Dog = Animal ++ (
  ,setter = proc(ref self) { self.legs = 4 }
  ,bark = fun() { puts "bark bark" }
)

let Bird = Animal ++ (
  ,seeds_eaten:int = _

  ,setter = proc(ref self)  { self.legs = 2 }
      ++ proc(ref self, a:Animal)    { self.legs = 2 ; name = "bird animal" }
  ,eat_seeds = proc(ref self, n) { self.seeds_eaten += n }
)

let Greyhound = Dog ++ ( // also extends Dog
  ,race = fun() { puts "running fast" }
)
```

```
var a:Animal = _
var b:Bird = _
var d:Dog = _

d = a // compile error, 'a does d' is false
b = a // OK, explicit setter in Bird for Animal

a = d // OK, 'd does a' is true
a = b // OK, 'Bird does Animal' is true
```

When the `x` in `x = y` is an `integer` basic type, there is an additional
check to guarantee that no precision is lost. Otherwise, an explicit `wrap` or
`drop` directive must be used.


### Arrays

The same rules of assignments exists for arrays. In Pyrope, arrays can be
mutable, but they can never be passed by reference. This means that the typical
issue of mutable containers can not exists. 


```
var a_vec:[]Animal = _
var b_vec:[]Bird = _
var d_vec:[]Dog = _

a_vec[0] = d:Dog    // OK
a_vec[1] = b:Bird   // OK

d_vec[0] = d:Dog        // OK  'd does d'
d_vec[0] = g:Greyhound  // OK  'g does d'
d_vec[0] = b:Bird       // Compile error
d_vec[0] = a:Animal     // Compile error

b_vec[0] = d:Dog        // OK, explicit conversion
b_vec[0] = g:Greyhound  // OK, explicit conversion
b_vec[0] = b:Bird       // OK, 'b does b'
b_vec[0] = a:Animal     // OK, explicit conversion

let do_animal_vec = fun(a_vec:[]Animal)->(r:[]Animal) {
  r = a_vec
  r[0] = d:Dog  // OK `d does r[0]`
}

var x = do_animal_vec(b_vec:[]Bird) // OK
assert x does _:[]Animal  // not :[]Bird
```

### Basic types

One of the complains about structural type system is that two types with
exactly the same tuple fields have the same type. In Pyrope, the field name
should match. Since every element is a type of one, read/writing a named tuple
of one does not need the field, and hence it allows to create different types:

```
let Age = (
  ,age:int = _
)
let Weight = (
  ,weight:int = _
)

assert Age !does Weight

var a:Age = 3
assert a == a.age == a.0 == 3

var w:Weight = 100

let err = a == w // compile error, not (a equals w) or overload
```


### Lambda


A way to classify a language is to look at the generics and lambda calls.
Languages can have type constraints or type classes. Type classes (Hakell,
Rust, Swift) specify the "consent" of argumetns or return types allowed for
lambda or generic. Type constrains (C++, typescript) constraints the arguments
or return types allowed. Pyrope follows a type constraint approach.

The following `f` method has no constraints on the input arguments. It can pass
anything, but constraints the return value to be an integer.

```
let f = fun(a,b) -> (r:int) { r = xx(a) + xx(b) }
```

The type can be inferred for arguments and return values. If the lambda
definition has no type constraints. A "different" implementation lambda exist
for each combination of inferred types. It behaves like if the the lambda were
inlined in the caller.


The constraints can be different per type, or use a more familiar generic syntax.
The `f1` example constraints `a` and `b` arguments to have a type that
satisfies `(a does Some_type_class) and (b does Some_type_class)`.

```
let f1 = fun<T:Some_type_class>(a:T,b:T) -> (r:int) { r = xx(a) + xx(b) }
```


While performing assignments checks that the left-hand-side tuple fields are
fully populated (`x=y`) by checking that `y does x`. The same check happens for
the lambda calls, but a slightly check is performed when a lambda is passed as
an argument.


For each lambda call (`ret_val = f(a1,a2)`), the type system check against the
defined lambda (`f = fun(ad1:ad1_t, ad2)->(rd1:rd1_t, rd2)`). In this case, the
check for the calling arguments (`(a1,a2) does (:ad1_t, :())`) should be
satisfied. Notice that some of the inputs (`ad2`) have no defined type, so those
unspecified arguments always satisfies by the type check. 

The return tuple is also used in the type system (`ret_val does (:rd1_t,
:())`), the check is the same as in an assignment (`lhs does rhs`). In
overloading cases explained later, the return type could also be part of the
overloading check.



```
let fa_t:fun(a:Animal)->() = _
let fd_t:fun(d:Dog)->() = _

let call_animal = fun(a:Animal)->() {
   puts a.name // OK
}
let call_dog:fd_t = fun(d:Dog)->() {    // OK to add type in lhs
   d.bark()    // OK
}

let f_a = fun(fa:fa_t) { 
  var a:Animal = _
  var d:Dog = _
  fa(a)  // OK
  fa(d)  // OK, `d does Animal` is true
}
f_a(call_animal) // OK
f_a(call_dog)    // compile error, `fa_t does call_dog` is false

let f_d = fun(fd:fd_t) { 
  var a:Animal = _
  var d:Dog = _
  fd(a)  // compile error, `a does Dog` is false
  fd(d)  // OK
}
f_d(call_animal) // OK, `fd_t does call_animal` is true
f_d(call_dog)    // OK
```


In tuple comparisons, `does` and `==`, the tuple field position is not used
when both tuples are fully named. If tuple field is unnamed, both existing
names and positions should match in the comparison.  For fully named tuples,
when all the fields have names,  `(a=1,b=2) does (b=2,a=1)` is true. 


The same rule also applies to lambda calls. If all the arguments are named, the
relative call argument position is independent. If an argument is an expression
or unnamed, the position is important.


A special case is the in-place operator (`...`) during lambda definition.  Even
for fully named tuples, the position is used.  One one in-place operator is
allowed per lambda definition `(a,b,...x,c)`, the `does` operator uses name and
position like in unnamed tuples even if all the fields are named. First, it
matches the position and names provided, and then checks the rest to the
in-place with the relative order left.


```
let m = fun(a:int,...x:(_:string,c:int,d), y:int)->() { 
  assert a == 1
  assert x.0 == "here"
  assert x.1 == 2 == x.c
  assert y == 3
  if d does int { // inferred type
    assert d == 33
  }else{
    assert d == "x"
  }
}

m(1,"here",2,"x",3)         // OK
m(a=1,"here",2,"x",3)       // OK
m(a=1,"here",c=2,"x",3)     // OK
m(a=1,"here",c=2,33,y=3)    // OK

m("1","here",2,33,3)       // compile error, a:int
m("1","here",2,3)          // compile error, x has 3 fields
```


For all the checks that are not function reference or in-place, the `x does y`
check could be summarized as `x` is a superset of `y`. `x` has all the
functionality of `y` and maybe more. In a more formal compiler nomenclature `x does
y` applied to tuples is called a covariant relationship. It is covariant
because adding the same extra fields to both `x` and `y` keeps the semantics
(`((foo=3,...x) does (foo=3,...y)) == x does y`). This allows to extend the
tuple semantics and the relationship is preserved.


When `x` and `y` are in a lambda passed as reference to another lambda (lambda
reference), the relationship is not covariant but contravariant. `Dog does
Animal` is true, but `:fun(x:Dog)->() does _:fun(x:Animal)->()` is false. The
reason is shown in the previous example. The `fun(fd:fd_t)` can be called
with `call_animal` because the fields accessed by `call_animal` are only a
subset of `Dog` and hence if called inside `f_d` it can handle the `Dog` type.
The opposite is not the case.


`:fun(x1)->(x2) does _:fun(y1)->y2` check is equivalent to `(y1 does x1) and (x2
does y2)`.




Given a lambda passed as argument (`:fun(x:fun(c:c_t)->(d:d_t))->(y)`), the
check when passing the lambda as argument to `x` a function like
`fun(w:w_t)->(z:z_t)`. In this case, the `:fun(:w_t)->(_:z_t) does
fun(:c_t)->(_:d_t)` is a contravariant test for inputs and covariant for
outputs. This makes it equivalent to `(_:c_t does _:w_t) and (_:z_t does _:d_t)`.


If the same type is used as input and output is an equivalence check (`((a does
b) and (b does a)) == (a equals b)`). In programming languages this is called
an invariance or bivariance.


Pyrope uses the typical check in modern languages where the function arguments
are contravariant and the return type is covariant. In Pyrope, the return type
is checked in the covariant and contravariant checks.



## Lambda Overloading

Pyrope does not have global scope for defined lambdas. Instead, all the lambda
must reside in a local variable or must be "imported". Nevertheless, a local
variable can have multiple lambdas. It is similar to Odin's "explicit procedure
overloading". This section explains how is the overloading selection in this
case.

When overloading, lambdas are typically added at the end `++=` of the tuple.
This means that it is NOT overwriting an existing functionality, but providing
a new call capability.

If the intention is to intercept, the lambda must be added at the head of the
tuple entry.

```
let base = (
  ,fun1 = fun() { 1 }         // catch all
  ,fun2 = fun() { 2 }         // catch all
  ,fun3 = fun() { 3 }         // catch all
)
let ext = base ++ (
  ,fun1 =   fun (a,b){ 4 }  // overwrite allowed with extends
  ,fun2 ++= fun (a,b){ 5 }  // append
  ,fun2 ++= fun ()   { 6 }  // append
  ,fun3 =   fun(a,b) { 7 } ++ base.fun3 // prepend
  ,fun3 =   fun()    { 8 } ++ base.fun3 // prepend
)

var t:ext = _

// t.fun1 only has ext.fun1
assert t.fun1(a=1,b=2) == 4
t.fun1()                 // compile error, no option without arguments

// t.fun2 has base.fun2 and then ext.fun2
assert t.fun2(1,2) == 5  // EXACT match of arguments has higher priority
assert t.fun2() == 2     // base.fun2 catches all ahead of ext.fun2

// t.fun3 has ext.fun3 and then base.fun3
assert t.fun3(1,2) == 7  // EXACT match of arguments has higher priority
assert t.fun3() == 8     // ext.fun3 catches all ahead of ext.fun3
```

A more traditional "overload" calling the is possible by calling the lambda directly:

```
let x = base ++ (
  ,fun1 = fun() { ret base.fun1() + 100 }
)
```

To allow overloading the base `lambda` as `var`. By concatenating lambdas to a
variable, we effectively create an unnamed tuple with multiple entries. Since
all the variables are tuples of size one too, the following rules apply to any
lambda call:


* Given a lambda call `f(a:a_t)->(_:r_t)` with defined call and return types.
  Iterate and pick all the lambda definitions `f(x)->(y)` that satisfy `x does
  a_t and y does r_t` using the previously explained lambda checks.

* If the `r_t` is unknown at call time, use only the call arguments `x does
  a_t`. Check that all the matching lambdas have the same defined return type.
  Otherwise a compile error is generated indicating that the type can not be
  infered.

* If the list is empty, generate a compile error (no possible lambda to call).

* Once a list of ordered modules is found, evaluate the `where COND`. `COND`
  can include inputs, self, and outputs. If a `COND` is comptime true (no
  `COND` is the same as `true`), stop selecting additional modules. If `COND`
  is comptime `false` remove from the list and continue. All the selected
  modules will be executed, but the output will be selected based on priority
  order based on the `COND` result at runtime.

* If the list has more than one entry, and any of them is a `proc`, generate a
  compile error. Dynamic dispatch only works with functions `fun`.

If the `where COND` is not compile time there must be a `where true` condition
to catch the default behavior. 

The previous rules imply that Pyrope has some type of dynamic dispatch. The
types for the inputs and outputs must be known at compile time (static
dispatch) but the `where` condition may be known at run-time as long as the
lambda is immutable (`fun`).


The `where` condition is not considered part of the type system, but a syntax
sugar to allow several function implementations depending on some condition.
The alternative and equivalent syntax is to add all the `if/else` chain at
every call but this result in not so maintanable code.


```
var fun_list = fun(a,b){ ret a+b}
fun_list ++= fun(a,b,c){ ret a+b+c }
fun_list ++= fun(a,b,c,d){ ret a+b+c+d }

assert fun_list.[size] == 3    // 3 lambda entries in fun_list

assert fun_list(1,2) == 3
assert fun_list(1,2,4) == 7
assert fun_list(1,2,4,5) == 12
assert fun_list(1,2,4,5,6) == 18 // compile error, no function with 5 args


fun_list ++= fun(a,b){ ret 100}
assert fun_list(1,2) == 3

fun_list = fun(a,b){ ret 200} ++ fun_list
assert fun_list(1,2) == 200
```

For untyped named argument calls:

```
var f1 = fun(a,b){ ret a+b+100 }
  f1 ++= fun(x,y){ ret x+y+200 }

assert f1(a=1,b=2) == 103
assert f1(x=1,y=2) == 203
assert f1(  1,  2) == 103  // first in list
```

For typed calls:

```
var fo = fun(a:int,b:string)->(_:bool)  { ret true    }
  fo ++= fun(a:int,b:int   )->(_:bool)  { ret false   }
  fo ++= fun(a:int,b:int   )->(_:string){ ret "hello" }

let a = fo(3,hello)
assert a == true

let b = fo(3,300)        // first in list return bool
assert b == false

let c:int = fo(3,300)    // compile error, no lambda fulfills constrains
let c:string = fo(3,300)
assert c == "hello"
```

For conditional argument calls:

```
var f1 = fun(a,b)      where a >  40 { ret b+100    }
      ++ fun(a,b)->(x) where x > 300 { ret b+200    } // output x
      ++ fun(a,b)->(a) where a >  20 { ret b+300    } // input a
      ++ fun(a,b)->(x) where x >  10 { ret b+400    } // output x
      ++ fun(a,b)                    { ret a+b+1000 } // default

var fun_manual = fun(a,b){  // equivalent but not as maintenable
  if a>40 {
    ret b+100
  }
  let x = b + 200
  if x>300 {
    ret (x=x)
  }
  if a>20 {
    ret b+300
  }
  let tmp = a + b
  if tmp >10 {
    ret (a=tmp)
  }
  ret a+b+1000
}

test "check equiv" {
  for a in -100..=100 {
    for b in -100..=100 {
      assert f1(a,b) == fun_manual(a,b)
    }
  }
}
```

## Traits and mixin

There is no object inheritance in Pyrope, but tuples allow to build mixin and
composition.

A mixin is when an object or class can add methods and the parent object can
access them. In several languages, there are different constructs to build them
(E.g: an include inside a class in Ruby). Since Pyrope tuples are not
immutable, new methods can be added like in mixin.

```
let Say_mixin = (
  ,say = fun(s) { puts s }
)

let Say_hi_mixin = (
  ,say_hi  = fun() {self.say("hi {}", self.name) }
  ,say_bye = fun() {self.say("bye {}", self.name) }
)

let User = (
  ,name:string = _
  ,setter = proc(ref self, n:string) { self.name = n }
)

let Mixing_all = Say_mixin ++ Say_hi_mixin ++ User

var a:Mixing_all="Julius Caesar"
a.say_hi()
```

Mixin is very expressive by allowing redefining methods. If two tuples have the
same field a tuple, the concatenated operator (`++`) will create an entry with
two or more sub-entries. This is likely an error with basic types but useful to
handle explicit method overload.


In a way, the concatenate just adds methods from two tuples to create a new
tuple. In programming languages with object-oriented programming (OOP), there
are many keywords (`virtual`, `final`, `override`, `static`...) to constrain
how methods can be updated/changed. In Pyrope, the `let` and `var` keywords can
be added to any tuple field. The `let` makes the entry immutable when applied
to a method, it behaves like a `final` keyword in most languages.


There are also two ways to concatenate tuples in Pyrope. `t1 ++ t2` and
`(...t1, ...t2)`:

* `t1 ++ t2` concatenates each field in both tuples. A compile error is
  generated if `t1` field is a `let` with a defined value, and `t2` has also
  the same defined field.


* `(...t1, ...t2)` inserts in-place, triggers a compile error if the same
  public field appears in both tuples and it is defined in both. `private`
  fields are privatized and hence do not trigger overload failure.


```
let Int1 = (
  ,private var counter:int = 0
  ,add = proc(ref self, v) { self.counter += v }
  ,get = fun(self) -> (_:int) { self.counter }
  ,api_pending: proc(ref self, x:int) -> (o:string) = _
)

let Int2 = (
  ,private var counter:int = 0
  ,accumulate = proc(ref self, v) { self.counter += v ; ret self.counter }
  ,api_pending:proc(ref self, x:string) -> (o:string) = _
)

let Combined = (...Int1, ...Int2
  ,api_pending = proc(ref self, x:int) -> (o:string) {
    self.add(x)
    ret string(self.accumulate(self.get()))
  }
)
```

It is also important to notice that when one of the tuples as an entry, it can
have an undefined value (`nil` or `0sb?`).  If the entry value is undefined,
neither concatenate (`++`) or in-place insert (`...`) trigger a compile error.
This is quite useful for defining interfaces because the default value for a
function is `nil`.

```
let Interface = (
  ,let add:fun(ref self, x) = _ // nil or undefined method
  ,let sub = fun(ref self,x ) { self.add(-x) }
)

Interface.add(3)                // compile error, undefined method

let My_obj = (
  ,val1:u8 = 0
  ,let add = fun(ref self, x) { self.val += x }
) ++ Interface                  // OK, but not recommended

let My_obj2 = (
  ,...Interface                 // recommended
  ,val1:u8 = 0
  ,let add = fun(ref self, x) { self.val += x }
)
cassert My_obj equals My_obj2   // same behavioir no defined overlap fiels

let xx:My_obj = _               // default initialization

cassert xx.val1 == 0
xx.add(3)
cassert xx.val1 == 3
xx.sub(2)
cassert xx.val1 == 1
```

Pyrope does not directly check that all the undefined methods are implemented,
but this will trigger a compile error whenever the undefined method is used.
This is different from most static type languages, but a bit closer to
dynamically typed languages. The difference is that the check is at compile
time, but an error happens ONLY if the method is used anywhere in the
instantiated project.


To build tuples that implement the functionality of other tuples, the recommended
technique is to use the in-place operator. It checks that there is no defined overlap
between both tuples.


An issue with in-place operator is when more than one tuple has the `setter`
method. If the tuples are concatenated with `...` and error is triggered, if
the tuples are concatenated with `++` it does not check if methods overlap.
Neither is the expected solution for a mixin. 


The solution is to remove fields from the in-place concatenation and to
explicitly create the new methods with some support method.


```
let exclude = fun(o,...a) {
  let new_tup = ()
  for e,idx,key in o {
    // create single tupe and append to preserve key and position order
    let sing_tup = ()
    sing_tup[key] = e
    new_tup ++= sing_tup unless key in o
  }
  ret new_tup
}

let Shape = (
  ,name:string = _
  ,area:fun (self )->(_:i32)  = _            // undefined 
  ,increase_size:proc(ref self, x:i12) = _  // undefined 

  ,setter=proc(ref self, name ) { self.name = name } // implemented, use =
  ,say_name=fun(self) { puts "name:{}", name }
)

let Circle = (
  ,...exclude(Shape,'setter')
  
  ,setter        = proc(ref self) { Circle.setter(this, "circle") }
  ,increase_size = proc(ref self, x:i12) { self.rad *= x }
  ,rad:i32       = _
  ,area = fun(self) -> (_:i32) {
     let pi = import("math").pi
     ret pi * self.rad * self.rad
  }
):Shape  // extra check that the exclude did not remove too many fields
```

## Row type

Pyrope has structural typing, but also allows to infer the types. The `where`
statement can be used to implement some functionality that resembles the row
type inference. The `where` clause is followed by a list of comma separated
conditions that must evaluate true for the function to be valid.

```
let rotate = fun(a) where a has 'x', a has 'y' and_then a.y!=30 {
  var r = a
  r.x = a.y
  r.y = a.x
  ret r
}
```

The previous rotate function is difficult to implement with a traditional
structural typing.



