"""spawn_many: spawn n short asyncio tasks in batches of BATCH, gather each batch, print the sum."""

import asyncio
import sys

BATCH = 1_000
ROUNDS = 10
MODULUS = 2_147_483_647
MULTIPLIER = 48_271


async def work(index: int) -> int:
    """The value of the task with this index: ROUNDS MINSTD steps from index + 1."""
    x = index + 1
    for _ in range(ROUNDS):
        x = x * MULTIPLIER % MODULUS
    return x


async def spawn_and_join(start: int, count: int) -> int:
    """Spawns one task per index in start..start + count, gathers them and returns their sum."""
    tasks = [asyncio.create_task(work(index)) for index in range(start, start + count)]
    return sum(await asyncio.gather(*tasks))


async def main() -> None:
    n = int(sys.argv[1])
    total = 0
    for start in range(0, n, BATCH):
        total += await spawn_and_join(start, min(BATCH, n - start))
    print(f"tasks: {n}")
    print(f"sum: {total}")


asyncio.run(main())
