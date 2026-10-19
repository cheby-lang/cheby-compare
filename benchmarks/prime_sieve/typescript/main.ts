// prime_sieve: the concurrent prime sieve, one async task per stage, linked by rendezvous channels.

/** A rendezvous channel on promises: a send waits until a receiver takes the value. */
class Channel<T> {
  private readonly receivers: Array<(value: T) => void> = [];
  private readonly senders: Array<{ value: T; resolve: () => void }> = [];

  send(value: T): Promise<void> {
    const receiver = this.receivers.shift();
    if (receiver !== undefined) {
      receiver(value);
      return Promise.resolve();
    }
    return new Promise((resolve) => this.senders.push({ value, resolve }));
  }

  receive(): Promise<T> {
    const sender = this.senders.shift();
    if (sender !== undefined) {
      sender.resolve();
      return Promise.resolve(sender.value);
    }
    return new Promise((resolve) => this.receivers.push(resolve));
  }
}

/** Sends 2, 3, 4 and so on, forever. */
async function generate(out: Channel<number>): Promise<void> {
  for (let i = 2; ; i++) {
    await out.send(i);
  }
}

/** Passes on the numbers from `input` that `prime` does not divide, forever. */
async function filter(
  input: Channel<number>,
  out: Channel<number>,
  prime: number,
): Promise<void> {
  for (;;) {
    const m = await input.receive();
    if (m % prime !== 0) {
      await out.send(m);
    }
  }
}

async function main(): Promise<void> {
  const n = Number.parseInt(process.argv[2] ?? "0", 10);
  let ch = new Channel<number>();
  void generate(ch);
  let last = 0;
  let sum = 0;
  for (let k = 0; k < n; k++) {
    const prime = await ch.receive();
    last = prime;
    sum += prime;
    const next = new Channel<number>();
    void filter(ch, next, prime);
    ch = next;
  }
  // Shut down (SPEC option 1): print and let the process end on its own. The stages stay blocked
  // on promises that never settle, which do not keep node alive.
  console.log(`primes: ${n}`);
  console.log(`last: ${last}`);
  console.log(`sum: ${sum}`);
}

await main();
