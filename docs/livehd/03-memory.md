# Memory and concurrency

LiveHD uses RAII for local resources and HHDS ownership handles for persistent
IR bodies. Lifetime management and permission to mutate are separate concerns:
a smart pointer keeps an object alive; it does not make concurrent mutation
safe.

## IR ownership

LGraphs belong to an `hhds::GraphLibrary`; LNAST trees belong to an
`hhds::Forest`. Their public lookup interfaces distinguish readers from
writers:

| Operation | Graph library | Forest |
| --- | --- | --- |
| Read a published body | `find_graph(name)` | `find_tree(name)` |
| Acquire an existing body for mutation | `find_graph_rw(name)` | `find_tree_rw(name)` |

Read handles are `std::shared_ptr<const ...>`. Writable handles use
`std::shared_ptr<...>` with HHDS-managed publication state. A writer acquisition
can fail while readers or another writer hold the body; callers must handle
an empty result. While a writer owns the slot, public read lookup does not
expose the in-progress body. Releasing the final writer handle publishes it;
explicit `commit()` can publish earlier, after mutation is complete.

Updating an existing body is in place: `find_graph_rw` / `find_tree_rw` do not
provide transactional rollback. A transformation that may fail and must leave
the input untouched should work on a private copy, as synthesis does.

The former `ref_rd_snapshot` / `ref_wr_snapshot` API is not the current HHDS
interface. Consult the owning library's
[graph](https://github.com/masc-ucsc/hhds/blob/main/hhds/graph.hpp) and
[tree](https://github.com/masc-ucsc/hhds/blob/main/hhds/tree.hpp) headers for
publication, creation and abort details.

## Parallel work

Independent graph or tree bodies can be processed in parallel. A body remains
single-threaded for mutation; library registry locking does not protect every
node, pin or attribute access. Do not hand the same writable body to multiple
workers or retain borrowed references past their owning body's lifetime.

Keep pass-local scratch data local to the task. Synchronize publication and
persistence at the flow boundary; saving a library is not a substitute for
waiting for its writers to finish.

## Local resources

Use automatic objects and RAII guards for scoped resources. Use
`std::unique_ptr` for exclusive dynamic ownership and `std::shared_ptr` where
shared lifetime is required by the API. Moving a unique pointer transfers
ownership; destroying it deletes its object. Shared ownership releases the
object when the last owning reference disappears.

Pass references or borrowed pointers when a function does not need ownership.
When it must retain an object, make that ownership explicit in its interface.
