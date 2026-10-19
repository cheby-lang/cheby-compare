// ping_pong: two async tasks pass a number back and forth n times over two rendezvous channels.

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

/** Task B: answers each number on `ping` with that number plus one on `pong`, n times. */
async function echo(
  n: number,
  ping: Channel<number>,
  pong: Channel<number>,
): Promise<void> {
  for (let i = 0; i < n; i++) {
    const x = await ping.receive();
    await pong.send(x + 1);
  }
}

/** Task A: sends 1..n on `ping` and adds up the answers from `pong`. */
async function play(
  n: number,
  ping: Channel<number>,
  pong: Channel<number>,
): Promise<number> {
  let sum = 0;
  for (let i = 1; i <= n; i++) {
    await ping.send(i);
    sum += await pong.receive();
  }
  return sum;
}

async function main(): Promise<void> {
  const n = Number.parseInt(process.argv[2] ?? "0", 10);
  const ping = new Channel<number>();
  const pong = new Channel<number>();
  const b = echo(n, ping, pong);
  const sum = await play(n, ping, pong);
  await b;
  console.log(n);
  console.log(sum);
}

await main();
