- **Cheby is last, 127× slower than Rust.** Its estimated run is 49.1 s, against 387 ms for Rust.
  The next slowest row, Gleam at 12.4 s, is 3.96× faster. Cheby is 11.8× slower than Erlang
  (4.17 s), 14.3× slower than OCaml (3.44 s) and 6.27× slower than Koka (7.83 s), whose program
  carries its own hand-written parser. That is about 2.7 MB of input per second over the whole
  round trip (a 14.7 MB file read 9 times, in the tables' 2^20-byte MB). Peak RSS is 352 MB,
  against 159 MB for Rust.
- **`std::json` is written in Cheby, with no native fast path.** The module builds on the
  `std::string`, `std::int` and `std::float` kernels (D-274, `std/json.cheby`). `std::string`
  and `std::map`, by contrast, do their work in Rust kernels called through `@external`. This is
  the current state of the standard library, not a limit of the language.
- **The parser steps through a list of code points.** `tree::parse` (`std/json/tree.cheby`) turns
  the whole text into a `List<Int>` first. It then reads one code point at a time with
  `[point, ..rest]` patterns, each one a runtime call for the head and another for the O(1) slice
  view of the rest (D-053). It also rebuilds an `Input` record at every step, to track the line
  and column for error positions (D-324). Each string is built by pushing code points into a list
  and converting the list back. In a profile at a reduced size, `cheby_rt_list_get` was the top
  function, and the syntax pass took most of the run. Decoding and writing took the rest.
- **The decoders and the writer add more allocation.** `decode::list` formats an index into the
  error path (`ints::show(index)`) for every element, even when decoding succeeds. Each
  `decode::field` pushes its name onto the path and scans the members from the end. Each
  record's `use` chain builds fresh decoder closures. On output, `json::to_string` keeps an
  explicit stack of steps so that deep documents cannot overflow the stack (D-094, D-326). Its
  `quote` turns every string into a code-point list and back, although no string here needs an
  escape.
- **The comparison is not like for like.** Koka's program writes its own parser, as the SPEC
  says. Python's and Ruby's parsers are written in C. Rust, C++, Java, Scala, Clojure, OCaml and
  Gleam use the libraries named in the table. Cheby's estimate makes no difference here: the
  size-0 run takes 18 ms against a 49.1 s whole run. Runs over 5 s get 3 timed runs instead of 10.
- **Two library effects stand out in the other rows.** Ruby's C-extension `json` (1.52 s) beats
  C++ with nlohmann/json (1.90 s). Gleam parses with the same OTP `json` module as Erlang, but
  decodes into typed records through `gleam/dynamic/decode`, and takes 2.97× Erlang's time.
