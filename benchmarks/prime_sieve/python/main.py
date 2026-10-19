"""prime_sieve: the concurrent prime sieve, one asyncio task per stage, connected by queues of size 1."""

import asyncio
import sys


async def generate(output: asyncio.Queue) -> None:
    """Sends 2, 3, 4 and so on, until the task is cancelled."""
    n = 2
    while True:
        await output.put(n)
        n += 1


async def filter_multiples(inp: asyncio.Queue, output: asyncio.Queue, prime: int) -> None:
    """Passes on the numbers from inp that prime does not divide, until the task is cancelled."""
    while True:
        n = await inp.get()
        if n % prime != 0:
            await output.put(n)


async def main(n: int) -> None:
    numbers: asyncio.Queue = asyncio.Queue(maxsize=1)
    tasks = [asyncio.create_task(generate(numbers))]

    last = 0
    total = 0
    for _ in range(n):
        prime = await numbers.get()
        last = prime
        total += prime
        out: asyncio.Queue = asyncio.Queue(maxsize=1)
        tasks.append(asyncio.create_task(filter_multiples(numbers, out, prime)))
        numbers = out

    # The pipeline is shut down by cancelling every task at once and waiting for them (SPEC
    # "Shut down", option 2).
    for task in tasks:
        task.cancel()
    await asyncio.gather(*tasks, return_exceptions=True)

    print(f"primes: {n}")
    print(f"last: {last}")
    print(f"sum: {total}")


if __name__ == "__main__":
    asyncio.run(main(int(sys.argv[1])))
