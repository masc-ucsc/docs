
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
    y = 'one'
    mut a[x].age = 10
    mut a[y].age = 10
    ```

In the future, it may be allowed but some options may not be allowed. For
example, if the index bundle is not unordered, the result of the assignment may
not be easy to predict by the programmer. 

