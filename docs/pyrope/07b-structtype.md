# Structural Typing


Pyrope uses structural typing somewhat simular to other languages like
Typescript, but there are some difference simplifications like not references,
everything is passed by value, no union types.



## Type check


The `x does y` checks that `x` provides all the structure required by `y`, and
maybe more. In type system syntax, `x` is a subtype of `y`, or `y` is a
supertype of `x`. For tuples, this means every required field in `y` must be
available in `x`; extra fields in `x` are allowed.


Using the typical `Animal`, `Dog`, `Greyhound` set of tuples, `Dog does Animal`
and `Greyhound does Dog`, but `not (Animal does Dog)`.

Dealing with tuple assignments `y = x`, a compile error is generated unless the
type system satisfies `y does x` or an explicit type conversion is provided.
The basic behavior of `does` is explained in (Type
equivalance)[07-typesystem.md#Type_equivalence].

```
const Animal = (
  mut legs:int = nil,
  mut name = "unnamed",
  comb say_name() { puts name }
)

const Dog = Animal ++ (
  comb setter(ref self) { self.legs = 4 },
  comb bark() { puts "bark bark" }
)

comb bird_setter_default(ref self)           { self.legs = 2 }
comb bird_setter_animal(ref self, a:Animal)  { self.legs = 2; name = "bird animal" }

const Bird = Animal ++ (
  mut seeds_eaten:int = nil,
  const setter = [bird_setter_default, bird_setter_animal],
  comb eat_seeds(ref self, n) { self.seeds_eaten += n }
)

const Greyhound = Dog ++ ( // also extends Dog
  comb race() { puts "running fast" }
)
```

```
mut a:Animal = ?
mut b:Bird = ?
mut d:Dog = ?

d = a // error: 'a does d' is false
b = a // OK, explicit setter in Bird for Animal

a = d // OK, 'd does a' is true
a = b // OK, 'Bird does Animal' is true
```

When the `x` in `x = y` is an `integer` basic type, there is an additional
check to guarantee that no precision is lost. Integer widths such as `u16` and
`u32` are constraints on the same basic `int` type, so `u32 does u16` and
`u16 does u32` are both true as type-structure checks, but `x = y` may still
fail if the right-hand side can not be proven to fit in the left-hand side.
Otherwise, an explicit `wrap` or `drop` directive must be used.


### Arrays

The same rules of assignments exists for arrays. In Pyrope, arrays can be
mutable, but they can never be passed by reference. This means that the typical
issue of mutable containers can not exists.


```
mut a_vec:[?]Animal = ?
mut b_vec:[?]Bird = ?
mut d_vec:[?]Dog = ?

a_vec[0] = d:Dog    // OK
a_vec[1] = b:Bird   // OK

d_vec[0] = d:Dog        // OK  'd does d'
d_vec[0] = g:Greyhound  // OK  'g does d'
d_vec[0] = b:Bird       // error:
d_vec[0] = a:Animal     // error:

b_vec[0] = d:Dog        // OK, explicit conversion
b_vec[0] = g:Greyhound  // OK, explicit conversion
b_vec[0] = b:Bird       // OK, 'b does b'
b_vec[0] = a:Animal     // OK, explicit conversion

comb do_animal_vec(a_vec:[?]Animal) -> (r:[?]Animal) {
  r = a_vec
  r[0] = d:Dog  // OK `d does r[0]`
}

mut x = do_animal_vec(b_vec:[?]Bird) // OK
cassert x does _:[?]Animal  // not :[?]Bird
```

### Basic types

One of the complains about structural type system is that two types with
exactly the same tuple fields have the same type. In Pyrope, the field name
should match. Since every element is a type of one, read/writing a named tuple
of one does not need the field, and hence it allows to create different types:

```
const Age = (
  age:int = ?
)
const Weight = (
  weight:int = ?
)

cassert Age !does Weight

mut a:Age = 3
cassert a == a.age == a[0] == 3

mut w:Weight = 100

const err = a == w // error: not (a equals w) or overload
```


### Lambda


A way to classify a language is to look at the generics and lambda calls.
Languages can have type constraints or type classes. Type classes (Hakell,
Rust, Swift) specify the "consent" of argumetns or return types allowed for
lambda or generic. Type constrains (C++, typescript, Pyrope) constraints the
arguments or return types allowed. Pyrope follows a type constraint approach.

The following `f` method has no constraints on the input arguments. It can pass
anything, but constraints the return value to be an integer.

```
comb f(a,b) -> (r:int) { r = xx(a) + xx(b) }
```

The type can be inferred for arguments and return values. If the lambda
definition has no type constraints. A "different" implementation lambda exist
for each combination of inferred types. It behaves like if the the lambda were
inlined in the caller.


The constraints can be different per type, or use a more familiar generic syntax.
The `f1` example constraints `a` and `b` arguments to have a type that
satisfies `(a does Some_type_class) and (b does Some_type_class)`.

```
comb f1<T:Some_type_class>(a:T,b:T) -> (r:int) { r = xx(a) + xx(b) }
```


While performing assignments checks that the left-hand-side tuple fields are
fully populated (`x=y`) by checking that `y does x`. The same check happens for
the lambda calls, but the check is performed when a lambda is passed as
an argument.


For each lambda call (`ret_val = f(a1,a2)`), the type system check against the
defined lambda (`f = comb(ad1:ad1_t, ad2)->(rd1:rd1_t, rd2)`). In this case, the
check for the calling arguments (`(a1,a2) does (:ad1_t, :())`) should be
satisfied. Notice that some of the inputs (`ad2`) have no defined type, so those
unspecified arguments always satisfies by the type check.

The return tuple is also used in the type system (`ret_val does (:rd1_t,
:())`), the check is the same as in an assignment (`lhs does rhs`). In
overloading cases explained later, the return type could also be part of the
overloading check.



```
comb fa_t(a:Animal) { }
comb fd_t(d:Dog) { }

comb call_animal(a:Animal) {
   puts a.name // OK
}
comb call_dog(d:Dog) {    // OK
   d.bark()    // OK
}

comb f_a(fa:fa_t) {
  mut a:Animal = ?
  mut d:Dog = ?
  fa(a)  // OK
  fa(d)  // OK, `d does Animal` is true
}
f_a(call_animal) // OK
f_a(call_dog)    // error: `fa_t does call_dog` is false

comb f_d(fd:fd_t) {
  mut a:Animal = ?
  mut d:Dog = ?
  fd(a)  // error: `a does Dog` is false
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
comb m(a:int, ...x:(_:string, c:int, d), y:int) {
  assert a == 1
  assert x[0] == "here"
  assert x[1] == 2 == x.c
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

m("1","here",2,33,3)       // error: a:int
m("1","here",2,3)          // error: x has 3 fields
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
Animal` is true, but `comb(x:Dog)->()` type `does` type `:fun(x:Animal)->()` is false. The
reason is shown in the previous example. The `comb(fd:fd_t)` can be called
with `call_animal` because the fields accessed by `call_animal` are only a
subset of `Dog` and hence if called inside `f_d` it can handle the `Dog` type.
The opposite is not the case.


Given a lambda passed as argument (`comb(x:fun(c:c_t)->(d:d_t))->(y)`), the
check when passing the lambda as argument to `x` a function like
`comb(w:w_t)->(z:z_t)`. In this case, the `comb(:w_t)->(_:z_t) does
comb(:c_t)->(_:d_t)` is a contravariant test for inputs and covariant for
outputs. This makes it equivalent to `(_:c_t does _:w_t) and (_:z_t does _:d_t)`.


If the same type is used as input and output is an equivalence check (`((a does
b) and (b does a)) == (a equals b)`). In programming languages this is called
an invariance or bivariance.


Pyrope uses the typical check in modern languages where the function arguments
are contravariant and the return type is covariant. In Pyrope, the return type
is checked in the covariant and contravariant checks.



## Lambda overloading

Pyrope does not have global scope for defined lambdas. Instead, all the lambda
must reside in a local variable or must be "imported". Nevertheless, a local
variable can have multiple lambdas. It is similar to Odin's "explicit lambda
overloading". This section explains how the overloading selection works.


By overloading, this section refers to typical ad-hoc polymorphism where the same
lambda name can have different functionality for different types.


For Pyrope overloading, lambdas are typically added at the end `++=` of the tuple.
This means that it is NOT overwriting an existing functionality, but providing
a new call capability.

There is a priority of overloading in the tuple order. If the intention is to
intercept, the lambda must be added at the head of the tuple entry.

```
comb base_fun1() -> (r) { r = 1 }             // catch all
comb base_fun2() -> (r) { r = 2 }             // catch all
comb base_fun3() -> (r) { r = 3 }             // catch all
const base = (
  const fun1 = base_fun1,
  const fun2 = base_fun2,
  const fun3 = base_fun3
)

comb ext_fun1(a, b)    -> (r) { r = 4 }
comb ext_fun2_ab(a, b) -> (r) { r = 5 }
comb ext_fun2_noarg()  -> (r) { r = 6 }
comb ext_fun3_ab(a, b) -> (r) { r = 7 }
comb ext_fun3_noarg()  -> (r) { r = 8 }

const ext = base ++ (
  const fun1 = ext_fun1,                                        // overwrite
  const fun2 = [ext_fun2_ab, ext_fun2_noarg, base_fun2],        // append
  const fun3 = [ext_fun3_ab, ext_fun3_noarg, base_fun3]         // prepend
)

mut t:ext = nil

// t.fun1 only has ext.fun1
assert t.fun1(a=1,b=2) == 4
t.fun1()                 // error: no option without arguments

// t.fun2 has base.fun2 and then ext.fun2
assert t.fun2(1,2) == 5  // EXACT match of arguments has higher priority
assert t.fun2() == 2     // base.fun2 catches all ahead of ext.fun2

// t.fun3 has ext.fun3 and then base.fun3
assert t.fun3(1,2) == 7  // EXACT match of arguments has higher priority
assert t.fun3() == 8     // ext.fun3 catches all ahead of ext.fun3
```

A more traditional "overload" calling the is possible by calling the lambda directly:

```
comb x_fun1() -> (r) { r = base.fun1() + 100 }
const x = base ++ (
  const fun1 = x_fun1
)
```

To allow overloading the base `lambda` as `mut`. By concatenating lambdas to a
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

* If the list has more than one entry, and any of them is a `pipe`/`mod`,
  generate a compile error. Static dispatch resolves to exactly one
  `comb`/`pipe`/`mod` based on arg and return types.

Pyrope does not have a `where` clause on lambda declarations — dispatch is
purely static (by argument and return types). Any runtime dispatch is
expressed explicitly with an `if`/`elif` chain at the call site, picking
which named lambda to invoke. This keeps control flow visible locally; the
compiler does not hide the branch behind a declaration-time predicate.


```
comb fun_list_ab(a, b)         -> (r) { r = a + b }
comb fun_list_abc(a, b, c)     -> (r) { r = a + b + c }
comb fun_list_abcd(a, b, c, d) -> (r) { r = a + b + c + d }

const fun_list = [fun_list_ab, fun_list_abc, fun_list_abcd]

assert fun_list.[size] == 3    // 3 lambda entries in fun_list

assert fun_list(1,2) == 3
assert fun_list(1,2,4) == 7
assert fun_list(1,2,4,5) == 12
assert fun_list(1,2,4,5,6) == 18 // error: no function with 5 args


comb fun_list_ab100(a, b) -> (r) { r = 100 }
const fun_list2 = [fun_list_ab, fun_list_abc, fun_list_abcd, fun_list_ab100]
assert fun_list2(1, 2) == 3       // first match wins

comb fun_list_ab200(a, b) -> (r) { r = 200 }
const fun_list3 = [fun_list_ab200, fun_list_ab, fun_list_abc, fun_list_abcd]
cassert fun_list3(1, 2) == 200
```

For untyped named argument calls:

```
comb f1_ab(a, b) -> (r) { r = a + b + 100 }
comb f1_xy(x, y) -> (r) { r = x + y + 200 }
const f1 = [f1_ab, f1_xy]

cassert f1(a=1, b=2) == 103
cassert f1(x=1, y=2) == 203
cassert f1(1, 2) == 103  // first in list
```

For typed calls:

```
comb fo_is(a:int, b:string) -> (result:bool)   { result = true }
comb fo_ii_b(a:int, b:int)  -> (result:bool)   { result = false }
comb fo_ii_s(a:int, b:int)  -> (result:string) { result = "hello" }
const fo = [fo_is, fo_ii_b, fo_ii_s]

const a = fo(3, "hello")
cassert a == true

const b = fo(3, 300)        // first in list return bool
cassert b == false

const c:int = fo(3, 300)    // error: no lambda fulfills constrains
const c:string = fo(3, 300)
cassert c == "hello"
```

For runtime-conditional dispatch, write the condition chain directly at the
call site:

```
comb f1_a40(a, b)     -> (r) { r = b + 100 }
comb f1_x300(a, b)    -> (x) { x = b + 200 } // output x
comb f1_a20(a, b)     -> (a) { a = b + 300 } // input a
comb f1_x10(a, b)     -> (x) { x = b + 400 } // output x
comb f1_default(a, b) -> (r) { r = a + b + 1000 } // default

comb f1(a, b) -> (r) {
  if a > 40 {
    r = f1_a40(a, b)
  } elif (b + 200) > 300 {
    r = f1_x300(a, b)
  } elif a > 20 {
    r = f1_a20(a, b)
  } elif (b + 400) > 10 {
    r = f1_x10(a, b)
  } else {
    r = f1_default(a, b)
  }
}

test "check f1" {
  for a in -100..=100 {
    for b in -100..=100 {
      assert f1(a, b) != nil
    }
  }
}
```

### Parametric polymorphism

Add-hoc polymorphism overloads a function, and parametric polymorphism allows to
parametrize types based on arguments.

```
comb Param_type(a) -> (r) { r = (mut xx:a = nil) }

const x:Param_type(string) = (xx="hello")
const x:Param_type(int)    = (xx=130)
```

### Summary polymorphism


Subtype polymorphism: A subtype provides functionality/api for another super type.
```
const Animal = (
  comb speak(self) { }
)
const Cat = Animal ++ (
  comb speak(self) { puts "meaow" }
)
const Bird = Animal ++ (
  comb speak(self) { puts "pio pio" }
)
```

Parametric polymorphism: Same function works for many types
```
comb smallest(...a) -> (r) {
  r = a[0]
  for i in a[1..] {
    r = i when i < r
  }
}
```

Ad-hoc polymorphism: capacity to overload the same lambda name with different types.
```
comb speak_bird(a:Bird) { puts "pio pio" }
comb speak_cat(a:Cat)   { puts "meaow" }
const speak = [speak_bird, speak_cat]
```

Coercion polymorphism: Capacity to cast a type to another
```
const Type1 = (
  comb setter(ref self, a:int) { }
)
const a:Type1 = 33
```

## Tuple mixin

There is no object inheritance in Pyrope, but tuples allow to build mixin and
composition.

A mixin is when an object or class can add methods and the parent object can
access them. In several languages, there are different constructs to build them
(E.g: an include inside a class in Ruby). Since Pyrope tuples are not
immutable, new methods can be added like in mixin.

```
const Say_mixin = (
  comb say(s) { puts s }
)

const Say_hi_mixin = (
  comb say_hi() { self.say("hi {}", self.name) },
  comb say_bye() { self.say("bye {}", self.name) }
)

const User = (
  mut name:string = "",
  comb setter(ref self, n:string) { self.name = n }
)

const Mixing_all = Say_mixin ++ Say_hi_mixin ++ User

mut a:Mixing_all = "Julius Caesar"
a.say_hi()
```

Mixin is very expressive by allowing redefining methods. If two tuples have the
same field a tuple, the concatenated operator (`++`) will create an entry with
two or more sub-entries. This is likely an error with basic types but useful to
handle explicit method overload.


In a way, the concatenate just adds methods from two tuples to create a new
tuple. In programming languages with object-oriented programming (OOP), there
are many keywords (`virtual`, `final`, `override`, `static`...) to constrain
how methods can be updated/changed. In Pyrope, the `const` and `mut` keywords can
be added to any tuple field. The `const` makes the entry immutable when applied
to a method, it behaves like a `final` keyword in most languages.


There are also two ways to concatenate tuples in Pyrope. `t1 ++ t2` and
`(...t1, ...t2)`:

* `t1 ++ t2` concatenates each field in both tuples. A compile error is
  generated if `t1` field is a `const` with a defined value, and `t2` has also
  the same defined field.


* `(...t1, ...t2)` inserts in-place, triggers a compile error if the same
  public field appears in both tuples and it is defined in both. `private`
  fields are privatized and hence do not trigger overload failure.


```
const Int1 = (
  mut counter:int:[private] = 0,
  comb add(ref self, v) { self.counter += v },
  comb get(self) -> (result:int) { result = self.counter },
  comb api_pending(ref self, x:int) -> (o:string) { }
)

const Int2 = (
  mut counter:int:[private] = 0,
  comb accumulate(ref self, v) { self.counter += v; self.counter },
  comb api_pending(ref self, x:string) -> (o:string) { }
)

const Combined = (...Int1, ...Int2,
  comb api_pending(ref self, x:int) -> (o:string) {
    self.add(x)
    o = string(self.accumulate(self.get()))
  }
)
```

It is also important to notice that when one of the tuples as an entry, it can
have an undefined value (`nil` or `0sb?`).  If the entry value is undefined,
neither concatenate (`++`) or in-place insert (`...`) trigger a compile error.
This is quite useful for defining interfaces because the default value for a
function is `nil`.

```
const Interface = (
  comb add(ref self, x),          // undefined method
  comb sub(ref self, x) { self.add(-x) }
)

Interface.add(3)                // error: undefined method

const My_obj = (
  mut val1:u8 = 0,
  comb add(ref self, x) { self.val += x }
) ++ Interface                  // OK, but not recommended

const My_obj2 = (
  ...Interface,                 // recommended
  mut val1:u8 = 0,
  comb add(ref self, x) { self.val += x }
)
cassert My_obj equals My_obj2   // same behavioir no defined overlap fiels

const xx:My_obj = ?               // default initialization

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
comb exclude(o,...a) {
  const new_tup = ()
  for (key,idx,e) in zip(o.keys(),o.enumerate()) {
    // create single tupe and append to preserve key and position order
    const sing_tup = ()
    sing_tup[key] = e
    new_tup ++= sing_tup unless key in o
  }
  new_tup
}

const Shape = (
  mut name:string = "",
  comb area(self) -> (result:i32) { },           // undefined
  comb increase_size(ref self, x:i12) { },       // undefined

  comb setter(ref self, name) { self.name = name }, // implemented
  comb say_name(self) { puts "name:{}", name }
)

const Circle = (
  ...exclude(Shape, 'setter'),

  comb setter(ref self) { Circle.setter(this, "circle") },
  comb increase_size(ref self, x:i12) { self.rad *= x },
  mut rad:i32 = 0,
  comb area(self) -> (result:i32) {
     const pi = import("math").pi
     result = pi * self.rad * self.rad
  }
)
cassert Circle does Shape  // extra check that the exclude did not remove too many fields
```

## Row type

Pyrope has structural typing and allows inferring types. Preconditions that
used to be carried on a `where` clause are now plain `cassert` / `assert`
statements at the top of the body (compile-time where possible, runtime
otherwise). The caller is responsible for meeting them.

```
comb rotate(a) {
  cassert a has 'x' and a has 'y'
  assert a.y != 30
  mut r = a
  r.x = a.y
  r.y = a.x
  r
}
```

Callers decide which `rotate`-like lambda to call based on the tuple shape
using an `if`/`elif` chain or a match on tuple fields.
