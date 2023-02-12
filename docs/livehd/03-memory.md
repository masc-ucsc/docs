# Memory and concurrency

This section explains the memory management or garbage collect principles used
and the relationship with concurrency models.

## Memory management models

Memory management in a multi-threaded environment main challenge arises from
deletes and additions that can trigger memory allocation/de-allocation. In
LiveHD, we address this problem the following way:

* Only one thread can allocate/deallocate memory in an object at a given time.
  To allow updates, a RW access is required. Otherwise, a RD access is enough.
  Both return a std::unique_ptr. The API guarantees that only one thread can do
  RW-access for a given object. Notice that the calling thread can have
  multiple RD access and WR access to the same object simulnateusly. The check
  is only against "other threads". There are 2 APIs: 

  * ref_rd_snapshot(): gets a RD access, and an assertion checks that
    there is no other thread has wr_snapshot during the lifetime of the
    returned std::unique_ptr

  * ref_wr_snapshot(): gets a RW access, and an assertion checks that
    there is no other thread has rd_snapshot during the lifetime of the
    returned std::unique_ptr.

!!! NOTE 

    Updating an atomic counter inside an object does not require a RW-access,
    but a rd_snapshot because it does not trigger memory
    allocation/deallocation. Adding/deleting elements requires a wr_snapshot.

* Creating an object requires a ref_wr_snapshot.

* The only way to pass references across threads is with std::unique_ptr or
  calling to the library which will create a std::unique_ptr. 

!!! NOTE

    If a std::unique_ptr created from a snapshot is passed to another thread,
    the creator thread is still the owner of the thread pointer. If this is not
    the intention, it may be safer for the new thread to call the library to
    access ownership.


This approach is somewhat similar to a hazzard pointer. The snapshot API
indicates intention to modify (which can delete), but instead of failing with a
nullptr return, we trigger a compile failure because it should never be the
case. Each lgraph/lnast can be updated in parallel, but only if they are
independent. The assertion is to check that there is no bug.

LiveHD uses 3 main techniques to perform memory management.

### RAII or std::unique_ptr

When an object is created and there is a single user, the code should use RAII
or std::unique_ptr. RAII means that when the object is out of scope, the memory
is recycled. std::unique_ptr will automatically call the destructor when the
reference use is zero.

* In LiveHD, RAII references should not be passed between threads.
* std::unique_ptr can be passed between threads.

### snapshot

For objects that can be shared across threads, the snapshot API must be used.

### std::shared_ptr

std::shared_ptr is one of the "heavy" cost options for garbage collection. In
LiveHD, we do not use the atomic std::shared_ptr. The std::shared_ptr are NOT
allowed to be passed between threads. It is a memory management for data only
within a thread or compiler pass.

To avoid reference counting overheads, when passed to methods, a `const
std::shared<XX> &` should be used nearly in all the cases.

