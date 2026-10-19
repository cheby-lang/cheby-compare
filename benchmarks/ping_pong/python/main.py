"""ping_pong: two asyncio tasks exchange n messages over two queues of size 1."""

import asyncio
import sys


async def echo(n: int, ping: asyncio.Queue, pong: asyncio.Queue) -> None:
    """Task B: answers each of the n values from ping with the value plus one on pong."""
    for _ in range(n):
        x = await ping.get()
        await pong.put(x + 1)


async def main(n: int) -> None:
    ping: asyncio.Queue = asyncio.Queue(maxsize=1)
    pong: asyncio.Queue = asyncio.Queue(maxsize=1)
    b = asyncio.create_task(echo(n, ping, pong))

    total = 0
    for i in range(1, n + 1):
        await ping.put(i)
        total += await pong.get()
    await b

    print(n)
    print(total)


if __name__ == "__main__":
    asyncio.run(main(int(sys.argv[1])))
