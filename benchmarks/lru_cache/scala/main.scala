// lru_cache: an LRU cache (mutable.LinkedHashMap) under a skewed Lehmer key stream.

import scala.collection.mutable

val LehmerM = 2147483647L
val LehmerA = 48271L
val Seed = 42L
val HotPercent = 80L
val Modulus = 1000000007L

@main def main(capacity: Int, ops: Long): Unit =
  val hot = capacity.toLong
  val cold = hot * 15
  val cache = mutable.LinkedHashMap.empty[Long, Long]
  var hits = 0L
  var misses = 0L
  var values = 0L
  var state = Seed

  var i = 0L
  while i < ops do
    state = state * LehmerA % LehmerM
    val draw = state / 100
    val key = if state % 100 < HotPercent then draw % hot else hot + draw % cold
    cache.remove(key) match
      case Some(value) => // a hit: re-inserting moves the key to the most recent end
        cache.update(key, value)
        hits += 1
        values = (values + value) % Modulus
      case None => // a miss
        if cache.size == capacity then cache.remove(cache.head._1)
        cache.update(key, key * 2 + 1)
        misses += 1
    i += 1

  var checksum = 0L
  var position = 1L
  for key <- cache.keysIterator do
    checksum = (checksum + position * key) % Modulus
    position += 1

  print(s"hits $hits\nmisses $misses\nvalues $values\nchecksum $checksum\n")
