// spawn_many: spawn `n` short virtual threads in batches of 1000, join each batch and print the sum.
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;

public class Main {
    static final long BATCH = 1_000;
    static final int ROUNDS = 10;
    static final long MODULUS = 2_147_483_647L; // 2^31 - 1
    static final long MULTIPLIER = 48_271L; // the MINSTD generator

    /** The value of the task with this index: ROUNDS steps of MINSTD from index + 1. */
    static long work(long index) {
        long x = index + 1;
        for (int r = 0; r < ROUNDS; r++) {
            x = x * MULTIPLIER % MODULUS;
        }
        return x;
    }

    /** Submits one virtual thread per index in start..start+count-1, joins them all, returns the sum. */
    static long spawnAndJoin(long start, long count) throws Exception {
        try (var ex = Executors.newVirtualThreadPerTaskExecutor()) {
            List<Future<Long>> batch = new ArrayList<>((int) count);
            for (long index = start; index < start + count; index++) {
                long i = index;
                batch.add(ex.submit(() -> work(i)));
            }
            long sum = 0;
            for (Future<Long> f : batch) {
                sum += f.get();
            }
            return sum;
        }
    }

    public static void main(String[] args) throws Exception {
        long n = Long.parseLong(args[0]);
        long sum = 0;
        for (long start = 0; start < n; start += BATCH) {
            sum += spawnAndJoin(start, Math.min(BATCH, n - start));
        }
        System.out.println("tasks: " + n);
        System.out.println("sum: " + sum);
    }
}
