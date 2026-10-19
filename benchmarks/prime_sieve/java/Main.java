// prime_sieve: the concurrent prime sieve, one virtual thread per stage, connected by rendezvous
// channels. Prints n, the n-th prime and the sum of the first n primes.
import java.util.concurrent.SynchronousQueue;

public class Main {
    /** Sends 2, 3, 4 and so on to out, forever. */
    static void generate(SynchronousQueue<Long> out) {
        try {
            for (long i = 2; ; i++) {
                out.put(i);
            }
        } catch (InterruptedException e) {
            // Never interrupted: the stage stays blocked until the JVM exits.
        }
    }

    /** Passes on the numbers from in that prime does not divide, forever. */
    static void filter(SynchronousQueue<Long> in, SynchronousQueue<Long> out, long prime) {
        try {
            while (true) {
                long m = in.take();
                if (m % prime != 0) {
                    out.put(m);
                }
            }
        } catch (InterruptedException e) {
            // Never interrupted: the stage stays blocked until the JVM exits.
        }
    }

    public static void main(String[] args) throws Exception {
        int n = Integer.parseInt(args[0]);

        var ch = new SynchronousQueue<Long>();
        var first = ch;
        Thread.ofVirtual().start(() -> generate(first));
        long last = 0;
        long sum = 0;
        for (int k = 0; k < n; k++) {
            long prime = ch.take();
            last = prime;
            sum += prime;
            var in = ch;
            var next = new SynchronousQueue<Long>();
            Thread.ofVirtual().start(() -> filter(in, next, prime));
            ch = next;
        }

        // Virtual threads are daemon threads: returning from main ends the JVM with every stage
        // still blocked (SPEC, "Shut down", option 1).
        System.out.println("primes: " + n);
        System.out.println("last: " + last);
        System.out.println("sum: " + sum);
    }
}
