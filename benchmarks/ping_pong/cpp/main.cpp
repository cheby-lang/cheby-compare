// ping_pong: two OS threads exchange `n` messages over two one-slot channels.

#include <condition_variable>
#include <cstdint>
#include <iostream>
#include <mutex>
#include <optional>
#include <string>
#include <thread>

// A one-slot blocking channel: one mutex, two condition variables and an optional value.
template <typename T>
class Channel {
public:
    void send(T value) {
        std::unique_lock lock(mutex_);
        not_full_.wait(lock, [this] { return !slot_.has_value(); });
        slot_ = value;
        not_empty_.notify_one();
    }

    T receive() {
        std::unique_lock lock(mutex_);
        not_empty_.wait(lock, [this] { return slot_.has_value(); });
        T value = *slot_;
        slot_.reset();
        not_full_.notify_one();
        return value;
    }

private:
    std::mutex mutex_;
    std::condition_variable not_full_;
    std::condition_variable not_empty_;
    std::optional<T> slot_;
};

// Task B: answers each of the `n` values from `ping` with the value plus one on `pong`.
void echo(std::int64_t n, Channel<std::int64_t>& ping, Channel<std::int64_t>& pong) {
    for (std::int64_t k = 0; k < n; ++k) {
        std::int64_t x = ping.receive();
        pong.send(x + 1);
    }
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "usage: main <n>\n";
        return 1;
    }
    std::int64_t n = std::stoll(argv[1]);

    Channel<std::int64_t> ping;
    Channel<std::int64_t> pong;
    std::thread b(echo, n, std::ref(ping), std::ref(pong));

    std::int64_t sum = 0;
    for (std::int64_t i = 1; i <= n; ++i) {
        ping.send(i);
        sum += pong.receive();
    }
    b.join();

    std::cout << n << '\n' << sum << '\n';
}
