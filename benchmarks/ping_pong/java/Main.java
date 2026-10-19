// ping_pong: two virtual threads exchange `n` messages over two rendezvous channels.
import java.util.concurrent.FutureTask;
import java.util.concurrent.SynchronousQueue;

public class Main {
    /** Task B: answers each of the `n` values from `ping` with the value plus one on `pong`. */
    static void echo(long n, SynchronousQueue<Long> ping, SynchronousQueue<Long> pong)
            throws InterruptedException {
        for (long r = 0; r < n; r++) {
            long x = ping.take();
            pong.put(x + 1);
        }
    }

    /** Task A: sends 1..n on `ping` and adds up the answers from `pong`. */
    static long play(long n, SynchronousQueue<Long> ping, SynchronousQueue<Long> pong)
            throws InterruptedException {
        long sum = 0;
        for (long i = 1; i <= n; i++) {
            ping.put(i);
            sum += pong.take();
        }
        return sum;
    }

    public static void main(String[] args) throws Exception {
        long n = Long.parseLong(args[0]);
        var ping = new SynchronousQueue<Long>();
        var pong = new SynchronousQueue<Long>();

        // The JVM main thread is a platform thread, so A runs on a virtual thread like B.
        Thread b = Thread.ofVirtual().start(() -> {
            try {
                echo(n, ping, pong);
            } catch (InterruptedException e) {
                throw new RuntimeException(e);
            }
        });
        var play = new FutureTask<>(() -> play(n, ping, pong));
        Thread a = Thread.ofVirtual().start(play);
        a.join();
        long sum = play.get();
        b.join();

        System.out.println(n);
        System.out.println(sum);
    }
}
