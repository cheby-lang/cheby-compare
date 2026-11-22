- **Cheby runs in 3.76 s as an executable and 3.87 s under `cheby run`, about 10× Rust.** The rows
  are 17th and 18th of 21. Rust takes 387 ms. Cheby is ahead of Erlang (4.17 s), Koka (7.83 s),
  whose program carries its own hand-written parser, and Gleam (12.4 s). It is just behind Odin
  (3.71 s), OCaml (3.44 s, Cheby 1.09×), Elixir (3.36 s) and Swift (3.27 s). That is about 35 MB of
  input per second over the whole round trip (a 14.7 MB file read 9 times, in the tables' 2^20-byte
  MB). Peak RSS is 208 MB, against 159 MB for Rust. The October JIT was last, at 49.1 s and 127×
  Rust.
- **`std::json` is written in Cheby, over a few byte kernels.** The module builds on the
  `std::string`, `std::bytes`, `std::int` and `std::float` kernels (D-274, `std/json.cheby`). The
  parser (`std/json/tree.cheby`) scans the UTF-8 bytes of the text by offset. It tracks no line or
  column, and counts them only when the text is not JSON. It cuts strings and numbers out of the
  text by byte range. The writer appends to one string and quotes each string with one kernel call.
  In October the parser turned the whole text into a list of code points first and rebuilt a
  position record at every step, and that was most of the 49.1 s.
- **The time now goes to allocation and to compiled Cheby code, in equal parts.** A profile of the
  executable puts 35% of the samples in the runtime's allocation and counting code, 33% in compiled
  code, 13% in the text and bytes kernels and 11% in list code. The run makes 123 million
  allocations, 13.7 million per pass over the file. Each byte the parser reads is a call through
  `bytes::get`'s wrapper into a kernel (D-455), which takes 6% of the samples.
- **The decoders add work of their own.** Each `decode::field` scans the object's members from the
  end and compares names (D-223): that scan and its string comparisons take 6% of the samples. Each
  record's `use` chain builds fresh decoder closures. `decode::list` no longer formats an index for
  every element: it formats one only when an element fails.
- **The comparison is not like for like.** Koka's program writes its own parser, as the SPEC says.
  Python's and Ruby's parsers are written in C. Rust, C++, Java, Scala, Clojure, OCaml and Gleam use
  the libraries named in the table.
- **Two library effects stand out in the other rows.** Ruby's C-extension `json` (1.52 s) beats C++
  with nlohmann/json (1.90 s). Gleam parses with the same OTP `json` module as Erlang, but decodes
  into typed records through `gleam/dynamic/decode`, and takes 2.97× Erlang's time.
