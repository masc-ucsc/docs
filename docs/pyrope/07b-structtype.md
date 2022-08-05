# Structural Typing


Pyrope uses structural typing somewhat simular to other languages like
Typescript, but there are some difference simplifications like not references,
everything is passed by value, no union types.


## Type Check


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
type Animal = (
  ,pub let legs:int
  ,var name= "unnamed"
  ,pub let say_name = fun() { puts name }
)

type Dog extends Animal with (
  ,pub var set = proc(ref self) { self.legs = 4 }
  ,bark = fun() { puts "bark bark" }
)

type Bird extends Animal with (
  ,seeds_eaten:int

  ,pub var set = proc(ref self)  { self.legs = 2 }
  ++ proc(ref self, a:Animal)    { self.legs = 2 ; name = "bird animal" }
  ,eat_seeds = proc(ref self, n) { self.seeds_eaten += n }
)

type Greyhound = Dog ++ ( // also extends Dog
  ,race = fun() { puts "running fast" }
)
```

```
var a:Animal
var b:Bird
var d:Dog

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
var a_vec:Animal[]
var b_vec:Bird[]
var d_vec:Dog[]

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

pub do_animal_vec = fun(a_vec:Animal[])->(r:Animal[]) {
  r = a_vec
  r[0] = d:Dog  // OK `d does r[0]`
}

var x = do_animal_vec(b_vec:Bird[]) // OK
assert x does :Animal[]  // not :Bird[]
```

### Basic types

One of the complains about structural type system is that two types with
exactly the same tuple fields have the same type. In Pyrope, the field name
should match. Since every element is a type of one, read/writing a named tuple
of one does not need the field, and hence it allows to create different types:

```
type Age = (
  ,pub var age:int
)
type Weight = (
  ,pub var weight:int
)

assert not (Age does Weight)

var a:Age
a = 3      // same as a.0 = 3
assert a == a.age == a.0 == 3

var w:Weight
w = 100    // same as w.0 = 100

let err = a == w // compile error, not (a equals w) or overload
```


### Lambda

While performing assignments checks that the left-hand-side tuple fields are
fully populated (`x=y`) by checking that `y does x`. The same check happens for
the lambda calls but not for lambda references.


Lambda calls (`f(a1,a2)->(r1,r2)`) to defined lambdas (`f = fun(ad1:ad1_t,
ad2)->(rd1:rd1_t, rd2)`) always checks the calling arguments `(a1,a2) does
(ad1:ad1_t, ad2)`. The return tuple is used in the type inference. In
overloading cases explained later, the return type could also be part of the
call check.


The type is inferred for arguments and return values. If the lambda definition
has no type (`ad2` and `rd2`). A "different" implementation lambda exist for
each combination of infered types or the lambda must be inlined in the caller.


```
type fa_t = fun(a:Animal)->()
type fd_t = fun(d:Dog)->()

let call_animal = fun(a:Animal)->() {
   puts a.name // OK
}
let call_dog = fun(d:Dog)->() {
   d.bark()    // OK
}

let f_a = fun(fa:fa_t) { 
  var a:Animal
  var d:Dog
  fa(a)  // OK
  fa(d)  // OK, `d does Animal` is true
}
f_a(call_animal) // OK
f_a(call_dog)    // compile error, `fa_t does call_dog` is false

let f_d = fun(fd:fd_t) { 
  var a:Animal
  var d:Dog
  fd(a)  // compile error, `a does Dog` is false
  fd(d)  // OK
}
f_d(call_animal) // OK, `fd_t does call_animal` is true
f_d(call_dog)    // OK
```


For fully named calls, when all the arguments have names, the argument position
is not considered in the `does` check. In a way, the call arguments for
`(a=1,b=2) does (b=2,a=1)`. This consistent with the tuple check semantics. The
difference happens when the lambda definition has a in-place operator (`...`).
Only one in-place operator are allowed per lambda definition `(a,b,...x,c)`,
the `does` operator uses name and position like in unnamed tuples even if all
the fields are named. First, it matches the position and names provided, and
then checks the rest to the in-place with the relative order left.


```
let m = fun(a:integer,...x:(:string,c:int,d), y:integer)->() { 
  assert a == 1
  assert x.0 == "here"
  assert x.1 == 2 == x.c
  assert y == 3
  if d does :integer { // inferred type
    assert d == 33
  }else{
    assert d == "x"
  }
}

m(1,"here",2,"x",3)         // OK
m(a=1,"here",2,"x",3)       // OK
m(a=1,"here",c=2,"x",3)     // OK
m(a=1,"here",c=2,33,y=3)    // OK

m("1","here",2,33,3)       // compile error, a:integer
m("1","here",2,3)          // compile error, x has 3 fields
```


For all the checks that are not function reference or in-place, the `x does y`
check could be summarized as `x` is a superset of `y`. `x` has all the
functionality of `y` and more. In a more formal compiler nomenclature `x does
y` applied to tuples is called a covariant relationship. It is covariant
because adding the same extra fields to both `x` and `y` keeps the semantics
(`((foo=3,...x) does (foo=3,...y)) == x does y`). This allows to extend the
tuple semantics and the relationship is preserved.


When `x` and `y` are composed in a function reference, the relationship is not
covariant but contravariant. `Dog does Animal` is true, but
`:fun(x:Dog)->() does :fun(x:Animal)->()` is false. The reason is shown in the
previous example. The a `fun(fd:fd_t)` can be called with `call_animal` because
the fields accessed by `call_animal` are only a subset of `Dog` and hence if
called inside `f_d` it can handle the `Dog` type. The opposite is not the case.


`:fun(x1)->(x2) does :fun(y1)->y2` check is equivalent to `(y1 does x1) and (x2
does y2)`.


In progamming languages, this is usually called that the function arguments are
contravariant and the return type is covariant. In Pyrope, the return type
could be used to infer unless overloading is used.



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
type base = (
  ,pub var fun1 = fun() { 1 }         // catch all
  ,pub var fun2 = fun() { 2 }         // catch all
  ,pub var fun3 = fun() { 3 }         // catch all
)
type ext extends base with (
  ,pub var fun1 =   fun (a,b){ 4 }  // overwrite allowed with extends
  ,pub var fun2 ++= fun (a,b){ 5 }  // append
  ,pub var fun2 ++= fun ()   { 6 }  // append
  ,pub var fun3 =   fun(a,b) { 7 } ++ base.fun3 // prepend
  ,pub var fun3 =   fun()    { 8 } ++ base.fun3 // prepend
)

var t:ext

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
type x extends base with (
  ,pub var fun1 = fun() { ret base.fun1() + 100 }
)
```

To allow overloading the base `lambda` as `var`. By concatenating lambdas to a
variable, we effectively create an unnamed tuple with multiple entries. Since
all the variables are tuples of size one too, the following rules apply to any
lambda call:


* Given a lambda call `f(a:a_t)->(:r_t)` with defined call and return types.
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

assert fun_list.size()

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
var fo = fun(a:int,b:string)->(:bool)  { ret true    }
fo ++=   fun(a:int,b:int   )->(:bool)  { ret false   }
fo ++=   fun(a:int,b:int   )->(:string){ ret "hello" }

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
  f1 ++= fun(a,b)->(x) where x > 300 { ret b+200    } // output x
  f1 ++= fun(a,b)->(a) where a >  20 { ret b+300    } // input a
  f1 ++= fun(a,b)->(x) where x >  10 { ret b+400    } // output x
  f1 ++= fun(a,b)                    { ret a+b+1000 } // default

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

## Row type

Pyrope has structural typing, but also allows to infer the types. The where
statement can be used to implement some functionality that resembles the row
type inference.

```
let rotate = fun(a) where a has 'x' and a has 'y' {
  var r = a
  r.x = a.y
  r.y = a.x
  ret r
}
```

The previous rotate function is difficult to implement with a traditional
structural typing `fun(a:(let x, let y))` will restrict the type to have just
`x` and `y` fields.


