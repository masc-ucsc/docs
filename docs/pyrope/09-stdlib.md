# Pyrope std lib

Like most languages, a standard library provides some common functionality around.

* The built-in `std` namespace is part of the language (it is not the
  `import("prp")` library below). Every file sees it without an `import`:
  `std.clog2(x)` (Verilog `$clog2` semantics, comptime only), plus
  `std.readmemh(file)` / `std.readmemb(file)` for memory startup images. See
  [Built-in `std` namespace](13-stdlib.md#built-in-std-namespace).
* The `import("prp")` standard library provides methods for the basic types
  (`Unsigned`, `Signed`, `String`, `Bool`) and utility code like fifos. The
  utils must be imported but the basic types are imported by default. It is not
  implemented yet (TBD, see [Standard Library](13-stdlib.md) and
  [Implementation status](15-tbd.md)).

