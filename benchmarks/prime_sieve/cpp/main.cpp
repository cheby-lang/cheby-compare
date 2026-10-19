// prime_sieve: the concurrent prime sieve, one OS thread per stage, connected by rendezvous
// channels.

#include <condition_variable>
#include <cstdint>
#include <iostream>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <thread>

// A rendezvous channel: one mutex, two condition variables and an optional value slot. `send`
// waits while the slot is full, fills it, signals, and then waits until a receiver has taken its
// value. `receive` waits while the slot is empty, takes the value and signals. Both signal after
// unlocking, so the woken thread does not block at once on the mutex the signaller still holds.
template <typename T>
class Channel {
public:
    void send(T value) {
        std::unique_lock lock(mutex_);
        senders_.wait(lock, [this] { return !slot_.has_value(); });
        slot_ = value;
        std::uint64_t ticket = ++sent_;
        lock.unlock();
        receivers_.notify_one();
        lock.lock();
        senders_.wait(lock, [this, ticket] { return taken_ >= ticket; });
    }

    T receive() {
        std::unique_lock lock(mutex_);
        receivers_.wait(lock, [this] { return slot_.has_value(); });
        T value = *slot_;
        slot_.reset();
        ++taken_;
        lock.unlock();
        senders_.notify_all();  // a sender may wait for the empty slot or for its ticket
        return value;
    }

private:
    std::mutex mutex_;
    std::condition_variable senders_;
    std::condition_variable receivers_;
    std::optional<T> slot_;
    std::uint64_t sent_ = 0;   // values put in the slot so far
    std::uint64_t taken_ = 0;  // values taken out of it so far
};

using IntChannel = std::shared_ptr<Channel<std::int64_t>>;

// Sends 2, 3, 4 and so on, forever.
void generate(IntChannel out) {
    for (std::int64_t i = 2;; ++i) {
        out->send(i);
    }
}

// Passes on the numbers from `in` that `prime` does not divide, forever.
void filter(IntChannel in, IntChannel out, std::int64_t prime) {
    for (;;) {
        std::int64_t m = in->receive();
        if (m % prime != 0) {
            out->send(m);
        }
    }
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cerr << "usage: main <n>\n";
        return 1;
    }
    std::int64_t n = std::stoll(argv[1]);

    // The threads are detached and never joined: returning from `main` ends the process with
    // them still blocked (SPEC, "Shut down", option 1). Each thread holds shared_ptrs to its
    // channels, so no channel is freed while a thread can still use it.
    auto ch = std::make_shared<Channel<std::int64_t>>();
    std::thread(generate, ch).detach();

    std::int64_t last = 0;
    std::int64_t sum = 0;
    for (std::int64_t k = 0; k < n; ++k) {
        std::int64_t prime = ch->receive();
        last = prime;
        sum += prime;
        auto next = std::make_shared<Channel<std::int64_t>>();
        std::thread(filter, ch, next, prime).detach();
        ch = next;
    }

    std::cout << "primes: " << n << '\n' << "last: " << last << '\n' << "sum: " << sum << '\n';
}
