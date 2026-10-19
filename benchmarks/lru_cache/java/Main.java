// lru_cache: a capacity-bounded LRU cache under a skewed pseudo-random key stream.
//
// The cache is a LinkedHashMap in access order: get moves a key to the most-recent end, and
// removeEldestEntry evicts the least recent key when an insert takes the size past capacity.

import java.util.LinkedHashMap;
import java.util.Map;

public class Main {
    private static final long MODULUS = 1_000_000_007L;
    private static final long LEHMER_M = 2_147_483_647L;
    private static final long LEHMER_A = 48_271L;
    private static final long SEED = 42L;
    private static final long HOT_PERCENT = 80L;
    private static final long KEY_SPACE_FACTOR = 16L;

    static final class Lru<K, V> extends LinkedHashMap<K, V> {
        private final int capacity;

        Lru(int capacity) {
            super(capacity, 0.75f, true);
            this.capacity = capacity;
        }

        @Override
        protected boolean removeEldestEntry(Map.Entry<K, V> eldest) {
            return size() > capacity;
        }
    }

    public static void main(String[] args) {
        int capacity = Integer.parseInt(args[0]);
        long ops = Long.parseLong(args[1]);
        long hot = capacity;
        long cold = capacity * (KEY_SPACE_FACTOR - 1);

        Lru<Long, Long> cache = new Lru<>(capacity);
        long hits = 0;
        long misses = 0;
        long values = 0;
        long state = SEED;
        for (long i = 0; i < ops; i++) {
            state = state * LEHMER_A % LEHMER_M;
            long draw = state / 100;
            long key = state % 100 < HOT_PERCENT ? draw % hot : hot + draw % cold;
            Long value = cache.get(key);
            if (value != null) {
                hits++;
                values = (values + value) % MODULUS;
            } else {
                cache.put(key, key * 2 + 1);
                misses++;
            }
        }

        long checksum = 0;
        long position = 1;
        for (long key : cache.keySet()) {
            checksum = (checksum + position * key) % MODULUS;
            position++;
        }

        System.out.print("hits " + hits + "\nmisses " + misses + "\nvalues " + values
                + "\nchecksum " + checksum + "\n");
    }
}
