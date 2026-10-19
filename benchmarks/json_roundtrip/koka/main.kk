// json_roundtrip: parses a JSON array of records, aggregates and transforms it, and serializes it again.

import std/os/env
import std/os/file
import std/os/path
import std/num/int64
import std/num/float64

// A JSON value. Objects keep their keys in order. A number without a fraction or exponent is an
// arbitrary-precision int, any other number a float64 (the benchmark's data has only integers).
type json
  JNull
  JBool(b : bool)
  JInt(n : int)
  JFloat(x : float64)
  JStr(s : string)
  JArr(items : list<json>)
  JObj(fields : list<(string, json)>)

// ---------------------------------------------------------------------------------------------
// Parsing: recursive descent over a string slice. Each function returns its value and the rest.

fun is-ws(c : char) : bool
  c == ' ' || c == '\n' || c == '\r' || c == '\t'

fun skip-ws(s : sslice) : div sslice
  match s.next
    Just((c, rest)) | c.is-ws -> skip-ws(rest)
    _ -> s

// The next character after any whitespace, and the slice after it.
fun next-token(s : sslice) : <exn,div> (char, sslice)
  match skip-ws(s).next
    Just(t) -> t
    Nothing -> throw("json: unexpected end of input")

fun expect-word(s : sslice, word : list<char>) : <exn,div> sslice
  match word
    Nil -> s
    Cons(c, cs) -> match s.next
      Just((d, rest)) | d == c -> expect-word(rest, cs)
      _ -> throw("json: invalid literal")

fun parse-value(s : sslice) : <exn,div> (json, sslice)
  val start = skip-ws(s)
  val (c, rest) = match start.next
    Just(t) -> t
    Nothing -> throw("json: unexpected end of input")
  match c
    '{' -> parse-object(rest)
    '[' -> parse-array(rest)
    '"' ->
      val (str, after) = parse-string(rest)
      (JStr(str), after)
    't' -> (JBool(True), expect-word(rest, ['r', 'u', 'e']))
    'f' -> (JBool(False), expect-word(rest, ['a', 'l', 's', 'e']))
    'n' -> (JNull, expect-word(rest, ['u', 'l', 'l']))
    '-' -> parse-number(start, rest, True, 0, 0)
    _ ->
      if c.is-digit then parse-number(start, rest, False, c.int - '0'.int, 1)
      else throw("json: unexpected character " ++ c.string)

// A number from `start`, its sign read and `count` digits of its integer part read into `acc`, with
// `s` the slice after them. Without a fraction or exponent it is an int; otherwise its whole text is
// read as a float64.
fun parse-number(start : sslice, s : sslice, neg : bool, acc : int, count : int) : <exn,div> (json, sslice)
  match s.next
    Just((c, rest)) | c.is-digit -> parse-number(start, rest, neg, acc * 10 + (c.int - '0'.int), count + 1)
    Just((c, _)) | count > 0 && (c == '.' || c == 'e' || c == 'E') ->
      parse-float(start, s, (if neg then 1 else 0) + count)
    _ ->
      if count == 0 then throw("json: expected a digit")
      else (JInt(if neg then 0 - acc else acc), s)

// The fraction and exponent after an integer part of `int-len` characters, then the number's text
// from `start` as a float64.
fun parse-float(start : sslice, after : sslice, int-len : int) : <exn,div> (json, sslice)
  val frac = match after.next
    Just(('.', r)) -> digits-after(r, ".")
    _ -> 0
  val exp = match after.advance(frac).next
    Just((e, r)) | e == 'e' || e == 'E' -> match r.next
      Just((sgn, r1)) | sgn == '+' || sgn == '-' -> 1 + digits-after(r1, "e")
      _ -> digits-after(r, "e")
    _ -> 0
  val len = int-len + frac + exp
  match start.truncate.extend(len).string.parse-float64
    Just(x) -> (JFloat(x), start.advance(len))
    Nothing -> throw("json: invalid number")

fun count-digits(s : sslice, n : int) : div int
  match s.next
    Just((c, rest)) | c.is-digit -> count-digits(rest, n + 1)
    _ -> n

// The length of a fraction or exponent part: its marker plus at least one digit.
fun digits-after(s : sslice, part : string) : <exn,div> int
  val k = count-digits(s, 0)
  if k == 0 then throw("json: expected a digit after " ++ part) else 1 + k

// A string body after its opening quote. Without escapes it is one copy of the slice.
fun parse-string(start : sslice) : <exn,div> (string, sslice)
  fun scan(s : sslice, n : int) : <exn,div> (string, sslice)
    match s.next
      Just((c, rest)) ->
        if c == '"' then (start.truncate.extend(n).string, rest)
        elif c == '\\' then parse-escaped(start, Nil)
        else scan(rest, n + 1)
      Nothing -> throw("json: unterminated string")
  scan(start, 0)

// The slow path for a string with escapes, collecting its characters in reverse.
fun parse-escaped(s : sslice, acc : list<char>) : <exn,div> (string, sslice)
  match s.next
    Just(('"', rest)) -> (acc.reverse.string, rest)
    Just(('\\', rest)) -> match rest.next
      Just((e, after)) -> match e
        'n' -> parse-escaped(after, Cons('\n', acc))
        't' -> parse-escaped(after, Cons('\t', acc))
        'r' -> parse-escaped(after, Cons('\r', acc))
        'b' -> parse-escaped(after, Cons('\x08', acc))
        'f' -> parse-escaped(after, Cons('\x0C', acc))
        'u' ->
          val (code, after4) = parse-hex4(after, 0, 4)
          parse-escaped(after4, Cons(code.char, acc))
        _ -> parse-escaped(after, Cons(e, acc))   // '"', '\\' and '/'
      Nothing -> throw("json: unterminated string")
    Just((c, rest)) -> parse-escaped(rest, Cons(c, acc))
    Nothing -> throw("json: unterminated string")

fun parse-hex4(s : sslice, acc : int, left : int) : <exn,div> (int, sslice)
  if left == 0 then (acc, s) else
    match s.next
      Just((c, rest)) ->
        val d = if c.is-digit then c.int - '0'.int
                elif c >= 'a' && c <= 'f' then c.int - 'a'.int + 10
                elif c >= 'A' && c <= 'F' then c.int - 'A'.int + 10
                else throw("json: invalid \\u escape")
        parse-hex4(rest, acc * 16 + d, left - 1)
      Nothing -> throw("json: invalid \\u escape")

fun parse-array(s : sslice) : <exn,div> (json, sslice)
  val (c, rest) = next-token(s)
  if c == ']' then (JArr(Nil), rest) else parse-items(s, Nil)

fun parse-items(s : sslice, acc : list<json>) : <exn,div> (json, sslice)
  val (v, rest) = parse-value(s)
  match next-token(rest)
    (',', after) -> parse-items(after, Cons(v, acc))
    (']', after) -> (JArr(Cons(v, acc).reverse), after)
    _ -> throw("json: expected ',' or ']'")

fun parse-object(s : sslice) : <exn,div> (json, sslice)
  val (c, rest) = next-token(s)
  if c == '}' then (JObj(Nil), rest) else parse-fields(s, Nil)

fun parse-fields(s : sslice, acc : list<(string, json)>) : <exn,div> (json, sslice)
  val key-rest = match next-token(s)
    ('"', r) -> r
    _ -> throw("json: expected a key")
  val (key, after-key) = parse-string(key-rest)
  val after-colon = match next-token(after-key)
    (':', r) -> r
    _ -> throw("json: expected ':'")
  val (v, rest) = parse-value(after-colon)
  match next-token(rest)
    (',', after) -> parse-fields(after, Cons((key, v), acc))
    ('}', after) -> (JObj(Cons((key, v), acc).reverse), after)
    _ -> throw("json: expected ',' or '}'")

pub fun parse(text : string) : <exn,div> json
  val (v, rest) = parse-value(text.slice)
  if skip-ws(rest).is-empty then v else throw("json: trailing characters")

// ---------------------------------------------------------------------------------------------
// Serializing: compact JSON as a list of pieces in reverse, joined once.

fun needs-escape(c : char) : bool
  c == '"' || c == '\\' || c < ' '

fun escape-char(c : char) : string
  match c
    '"' -> "\\\""
    '\\' -> "\\\\"
    '\n' -> "\\n"
    '\r' -> "\\r"
    '\t' -> "\\t"
    _ -> if c < ' ' then "\\u" ++ c.int.show-hex(4, use-capitals = False, pre = "") else c.string

fun write-string(s : string, acc : list<string>) : list<string>
  val body = if s.foreach-while(fn(c) if c.needs-escape then Just(()) else Nothing).is-just
    then s.list.map(escape-char).join
    else s
  Cons("\"", Cons(body, Cons("\"", acc)))

// The shortest text that reads back as x, kept a float: 1.0 is "1.0", not "1".
fun show-float(x : float64) : string
  val t = x.show
  if t.list.all(fn(c) c.is-digit || c == '-') then t ++ ".0" else t

fun write-value(v : json, acc : list<string>) : div list<string>
  match v
    JNull -> Cons("null", acc)
    JBool(b) -> Cons(if b then "true" else "false", acc)
    JInt(n) -> Cons(n.show, acc)
    JFloat(x) -> Cons(show-float(x), acc)
    JStr(s) -> write-string(s, acc)
    JArr(items) -> match items
      Nil -> Cons("[]", acc)
      Cons(x, xs) ->
        val first = write-value(x, Cons("[", acc))
        Cons("]", xs.foldl(first, fn(a, item) write-value(item, Cons(",", a))))
    JObj(fields) -> match fields
      Nil -> Cons("{}", acc)
      Cons(f, fs) ->
        val first = write-field(f, Cons("{", acc))
        Cons("}", fs.foldl(first, fn(a, field) write-field(field, Cons(",", a))))

fun write-field(field : (string, json), acc : list<string>) : div list<string>
  val (key, v) = field
  write-value(v, Cons(":", write-string(key, acc)))

pub fun serialize(v : json) : div string
  write-value(v, Nil).reverse-join

// ---------------------------------------------------------------------------------------------
// Access to the parsed records.

fun get(v : json, key : string) : exn json
  match v
    JObj(fields) -> match fields.lookup(fn(k) k == key)
      Just(x) -> x
      Nothing -> throw("missing key " ++ key)
    _ -> throw("not an object")

fun as-int(v : json) : exn int
  match v
    JInt(n) -> n
    _ -> throw("not an integer")

fun as-bool(v : json) : exn bool
  match v
    JBool(b) -> b
    _ -> throw("not a boolean")

fun as-list(v : json) : exn list<json>
  match v
    JArr(items) -> items
    _ -> throw("not an array")

val fnv-offset = 2166136261.int64
val fnv-prime = 16777619.int64

fun fnv1a(out : string) : int64
  var h := fnv-offset
  out.bytes.foreach fn(b)
    h := ((h.xor(b.int64)) * fnv-prime).and(0xFFFF_FFFF.int64)
  h

pub fun main()
  val args = get-args()
  val name = args.head.default("")
  val reps = args.drop(1).head.default("0").parse-int.default(0)
  val text = read-text-file(path(name))
  var records-n := 0
  var active-n := 0
  var score-sum := 0
  var tags-n := 0
  var history-n := 0
  var amount-sum := 0
  var output-bytes := 0
  var h := fnv-offset
  for(0, reps - 1) fn(rep)
    val records = parse(text).as-list
    val kept = records.filter-map fn(r)
      val tags = r.get("tags")
      val history = r.get("history")
      val tag-count = tags.as-list.length
      val entries = history.as-list
      val total = entries.foldl(0, fn(acc, e) acc + e.get("amount").as-int)
      val score = r.get("score").as-int
      records-n := records-n + 1
      score-sum := score-sum + score
      tags-n := tags-n + tag-count
      history-n := history-n + entries.length
      amount-sum := amount-sum + total
      if r.get("active").as-bool then
        active-n := active-n + 1
        Just(JObj([
          ("id", r.get("id")),
          ("name", r.get("name")),
          ("score", JInt(score + 100 * tag-count)),
          ("tags", tags),
          ("address", r.get("address")),
          ("history", history),
          ("total", JInt(total)),
        ]))
      else Nothing
    val out = serialize(JArr(kept))
    // string/bytes is the string's own UTF-8 buffer (no copy), so this is its byte length.
    output-bytes := output-bytes + out.bytes.length
    if rep == reps - 1 then h := fnv1a(out)
  println("records " ++ records-n.show)
  println("active " ++ active-n.show)
  println("score_sum " ++ score-sum.show)
  println("tags " ++ tags-n.show)
  println("history " ++ history-n.show)
  println("amount_sum " ++ amount-sum.show)
  println("output_bytes " ++ output-bytes.show)
  println("output_fnv1a " ++ h.show)
