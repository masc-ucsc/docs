
# Defeatured


Pyrope has been in internal development for many Years, those are some features
tried and deprecated or removed until a better solution is found.


## `step` options

The `step` command breaks the execution of the function in the statements before and after the step. The next
cycle, the statements after the step are executed. The issue was that the step could be placed inside complicated
nests of 'if' and 'for' loops. This results in a difficult code to get right. 

The plan is to add something like this feature in the future, once a cleaner implementation is designed.


## Fluid Pipelines

The plan is to re-add the fluid pipelines syntax, but all the other features must be added first.


