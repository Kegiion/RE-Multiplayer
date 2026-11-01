#include "coop/net/session.hpp"
#include "test_util.hpp"

#include <chrono>
#include <functional>
#include <thread>

using namespace coop::net;
using namespace std::chrono_literals;

namespace {

constexpr uint16_t kPort = 47811;

// Wartet, bis cond() true liefert (max. timeout). Sammelt dabei Events.
bool wait_for(const std::function<bool()>& cond, std::chrono::milliseconds timeout = 3000ms) {
    const auto deadline = std::chrono::steady_clock::now() + timeout;
    while (std::chrono::steady_clock::now() < deadline) {
        if (cond()) return true;
        std::this_thread::sleep_for(5ms);
    }
    return cond();
}

void test_connect_send_disconnect() {
    Session host, client;
    std::string err;
    CHECK(host.host(kPort, 1, &err));
    CHECK(host.mode() == Mode::Hosting);
    CHECK(client.connect("127.0.0.1", kPort, &err));

    std::vector<Event> host_events, client_events;
    auto drain = [&] {
        for (auto& e : host.poll()) host_events.push_back(std::move(e));
        for (auto& e : client.poll()) client_events.push_back(std::move(e));
    };

    CHECK(wait_for([&] { drain(); return client.mode() == Mode::Connected && !host_events.empty(); }));
    CHECK(host_events[0].type == EventType::Connected);
    CHECK(client_events.at(0).type == EventType::Connected);
    CHECK(host.peers().size() == 1);
    CHECK(client.peers().size() == 1);

    const uint32_t client_id_on_host = host_events[0].peer;
    const uint32_t host_id_on_client = client_events[0].peer;
    host_events.clear();
    client_events.clear();

    // reliable Client -> Host
    CHECK(client.send(host_id_on_client, std::string{"hallo host"}, true));
    // unreliable Host -> alle
    CHECK(host.send(kAllPeers, std::string{"hallo alle"}, false));
    // gezielt Host -> Client, binaere Daten mit Nullbyte
    const std::string binary{"a\0b", 3};
    CHECK(host.send(client_id_on_host, binary, true));

    CHECK(wait_for([&] { drain(); return !host_events.empty() && client_events.size() >= 2; }));
    CHECK(host_events[0].type == EventType::Message);
    CHECK(host_events[0].data == "hallo host");
    CHECK(host_events[0].reliable);
    CHECK(host_events[0].peer == client_id_on_host);

    bool got_unreliable = false, got_binary = false;
    for (const auto& e : client_events) {
        if (e.data == "hallo alle" && !e.reliable) got_unreliable = true;
        if (e.data == binary && e.reliable) got_binary = true;
    }
    CHECK(got_unreliable);
    CHECK(got_binary);

    const auto stats = host.stats();
    CHECK(stats.messages_sent == 2);
    CHECK(stats.messages_received == 1);

    // Sauberes Trennen: Host bekommt ein Disconnect-Event.
    host_events.clear();
    client.disconnect();
    CHECK(client.mode() == Mode::Idle);
    CHECK(wait_for([&] { drain(); return !host_events.empty(); }));
    CHECK(host_events[0].type == EventType::Disconnected);
    CHECK(host_events[0].peer == client_id_on_host);
    CHECK(host.peers().empty());

    // Senden ohne Verbindung schlaegt fehl.
    CHECK(!client.send(kAllPeers, std::string{"x"}, true));
}

void test_host_shutdown_notifies_client() {
    Session host, client;
    std::string err;
    CHECK(host.host(kPort + 1, 1, &err));
    CHECK(client.connect("localhost", kPort + 1, &err));
    CHECK(wait_for([&] { return client.mode() == Mode::Connected; }));
    host.poll();
    client.poll();

    host.disconnect();
    std::vector<Event> client_events;
    CHECK(wait_for([&] {
        for (auto& e : client.poll()) client_events.push_back(std::move(e));
        return !client_events.empty();
    }));
    CHECK(client_events[0].type == EventType::Disconnected);
    CHECK(wait_for([&] { return client.mode() == Mode::Idle; }));
    CHECK(!client.last_error().empty());
}

void test_port_in_use() {
    Session a, b;
    std::string err;
    CHECK(a.host(kPort + 2, 1, &err));
    CHECK(!b.host(kPort + 2, 1, &err));
    CHECK(!err.empty());
    CHECK(b.mode() == Mode::Idle);
}

void test_restart() {
    Session host, client;
    std::string err;
    for (int round = 0; round < 3; ++round) {
        CHECK(host.host(kPort + 3, 1, &err));
        CHECK(client.connect("127.0.0.1", kPort + 3, &err));
        CHECK(wait_for([&] { return client.mode() == Mode::Connected; }));
        client.disconnect();
        host.disconnect();
    }
}

}  // namespace

int main() {
    test_connect_send_disconnect();
    test_host_shutdown_notifies_client();
    test_port_in_use();
    test_restart();
    std::puts("netcore_test: alles ok");
    return 0;
}
