#include "coop/net/session.hpp"

#include <enet/enet.h>

#include <chrono>
#include <cstdlib>
#include <unordered_map>
#include <utility>

namespace coop::net {

namespace {

constexpr uint8_t kChannelReliable = 0;
constexpr uint8_t kChannelUnreliable = 1;
constexpr size_t kChannelCount = 2;

// Wie lange wir beim Beenden auf ein sauberes "Tschuess" der Gegenseite warten.
constexpr uint32_t kDisconnectGraceMs = 300;

bool ensure_enet_initialized(std::string* error) {
    static std::once_flag once;
    static bool ok = false;
    std::call_once(once, [] {
        ok = enet_initialize() == 0;
        if (ok) {
            std::atexit(enet_deinitialize);
        }
    });
    if (!ok && error != nullptr) {
        *error = "enet_initialize fehlgeschlagen";
    }
    return ok;
}

uint32_t peer_id(const ENetPeer* peer) {
    return static_cast<uint32_t>(reinterpret_cast<uintptr_t>(peer->data));
}

std::string format_address(const ENetAddress& address) {
    char ip[64]{};
    if (enet_address_get_host_ip(&address, ip, sizeof(ip)) != 0) {
        return "?";
    }
    return std::string{ip} + ":" + std::to_string(address.port);
}

}  // namespace

const char* to_string(Mode mode) {
    switch (mode) {
    case Mode::Idle: return "idle";
    case Mode::Hosting: return "hosting";
    case Mode::Connecting: return "connecting";
    case Mode::Connected: return "connected";
    }
    return "unknown";
}

struct Session::Impl {
    ENetHost* host{nullptr};
    bool is_host{false};
    uint32_t next_peer_id{1};
    std::unordered_map<uint32_t, ENetPeer*> peers;
};

Session::Session() : m_impl(std::make_unique<Impl>()) {}

Session::~Session() {
    disconnect();
}

bool Session::host(uint16_t port, size_t max_peers, std::string* error) {
    return start(true, {}, port, max_peers, error);
}

bool Session::connect(const std::string& address, uint16_t port, std::string* error) {
    return start(false, address, port, 1, error);
}

bool Session::start(bool as_host, const std::string& address, uint16_t port, size_t max_peers, std::string* error) {
    disconnect();

    if (!ensure_enet_initialized(error)) {
        return false;
    }

    ENetAddress addr{};
    ENetHost* host = nullptr;

    if (as_host) {
        addr.host = ENET_HOST_ANY;
        addr.port = port;
        host = enet_host_create(&addr, max_peers, kChannelCount, 0, 0);
        if (host == nullptr) {
            const auto msg = "Host konnte nicht gestartet werden (Port " + std::to_string(port) + " belegt?)";
            set_error(msg);
            if (error != nullptr) *error = msg;
            return false;
        }
    } else {
        if (enet_address_set_host(&addr, address.c_str()) != 0) {
            const auto msg = "Adresse '" + address + "' konnte nicht aufgeloest werden";
            set_error(msg);
            if (error != nullptr) *error = msg;
            return false;
        }
        addr.port = port;
        host = enet_host_create(nullptr, 1, kChannelCount, 0, 0);
        if (host == nullptr) {
            const auto msg = std::string{"Client-Socket konnte nicht erstellt werden"};
            set_error(msg);
            if (error != nullptr) *error = msg;
            return false;
        }
        if (enet_host_connect(host, &addr, kChannelCount, 0) == nullptr) {
            enet_host_destroy(host);
            const auto msg = std::string{"Verbindungsaufbau konnte nicht gestartet werden"};
            set_error(msg);
            if (error != nullptr) *error = msg;
            return false;
        }
    }

    m_impl->host = host;
    m_impl->is_host = as_host;
    m_impl->peers.clear();

    {
        std::lock_guard lock{m_mutex};
        m_outbox.clear();
        m_inbox.clear();
        m_peers.clear();
        m_stats = {};
        m_last_error.clear();
    }

    m_stop = false;
    m_mode = as_host ? Mode::Hosting : Mode::Connecting;
    m_thread = std::thread{[this] { thread_main(); }};
    return true;
}

void Session::disconnect() {
    m_stop = true;
    if (m_thread.joinable()) {
        m_thread.join();
    }
    m_mode = Mode::Idle;

    std::lock_guard lock{m_mutex};
    m_outbox.clear();
    m_peers.clear();
}

bool Session::send(uint32_t peer, const void* data, size_t size, bool reliable) {
    if (size > kMaxMessageSize) {
        return false;
    }
    const auto mode = m_mode.load();
    if (mode != Mode::Hosting && mode != Mode::Connected) {
        return false;
    }

    std::lock_guard lock{m_mutex};
    m_outbox.push_back(Outgoing{peer, reliable, std::string{static_cast<const char*>(data), size}});
    return true;
}

std::vector<Event> Session::poll() {
    std::lock_guard lock{m_mutex};
    std::vector<Event> out;
    out.swap(m_inbox);
    return out;
}

std::vector<PeerInfo> Session::peers() const {
    std::lock_guard lock{m_mutex};
    return m_peers;
}

Stats Session::stats() const {
    std::lock_guard lock{m_mutex};
    return m_stats;
}

std::string Session::last_error() const {
    std::lock_guard lock{m_mutex};
    return m_last_error;
}

void Session::push_event(Event ev) {
    std::lock_guard lock{m_mutex};
    if (ev.type == EventType::Message) {
        ++m_stats.messages_received;
        m_stats.bytes_received += ev.data.size();
    }
    m_inbox.push_back(std::move(ev));
}

void Session::set_error(std::string err) {
    std::lock_guard lock{m_mutex};
    m_last_error = std::move(err);
}

void Session::thread_main() {
    auto& impl = *m_impl;
    auto last_peer_refresh = std::chrono::steady_clock::now();

    const auto refresh_peers = [&] {
        std::vector<PeerInfo> infos;
        infos.reserve(impl.peers.size());
        for (const auto& [id, peer] : impl.peers) {
            infos.push_back(PeerInfo{id, format_address(peer->address), peer->roundTripTime});
        }
        std::lock_guard lock{m_mutex};
        m_peers = std::move(infos);
    };

    const auto send_one = [&](ENetPeer* peer, const Outgoing& msg) {
        const enet_uint32 flags = msg.reliable ? static_cast<enet_uint32>(ENET_PACKET_FLAG_RELIABLE) : 0u;
        ENetPacket* packet = enet_packet_create(msg.data.data(), msg.data.size(), flags);
        if (packet == nullptr) {
            return;
        }
        // Bei Erfolg gehoert das Paket ENet; bei Fehler muessen wir es freigeben.
        if (enet_peer_send(peer, msg.reliable ? kChannelReliable : kChannelUnreliable, packet) != 0) {
            enet_packet_destroy(packet);
            return;
        }
        std::lock_guard lock{m_mutex};
        ++m_stats.messages_sent;
        m_stats.bytes_sent += msg.data.size();
    };

    bool client_lost = false;

    while (!m_stop && !client_lost) {
        // 1. Ausgehende Nachrichten verschicken.
        std::deque<Outgoing> outgoing;
        {
            std::lock_guard lock{m_mutex};
            outgoing.swap(m_outbox);
        }
        for (const auto& msg : outgoing) {
            if (msg.peer == kAllPeers) {
                for (const auto& [id, peer] : impl.peers) {
                    send_one(peer, msg);
                }
            } else if (auto it = impl.peers.find(msg.peer); it != impl.peers.end()) {
                send_one(it->second, msg);
            }
        }

        // 2. Eingehende Ereignisse verarbeiten (wartet max. 5 ms).
        ENetEvent ev{};
        int result = enet_host_service(impl.host, &ev, 5);
        while (result > 0) {
            switch (ev.type) {
            case ENET_EVENT_TYPE_CONNECT: {
                const uint32_t id = impl.next_peer_id++;
                ev.peer->data = reinterpret_cast<void*>(static_cast<uintptr_t>(id));
                impl.peers[id] = ev.peer;
                if (!impl.is_host) {
                    m_mode = Mode::Connected;
                }
                refresh_peers();
                push_event(Event{EventType::Connected, id, true, {}});
                break;
            }
            case ENET_EVENT_TYPE_RECEIVE: {
                const uint32_t id = peer_id(ev.peer);
                Event out{EventType::Message, id, (ev.packet->flags & ENET_PACKET_FLAG_RELIABLE) != 0, {}};
                out.data.assign(reinterpret_cast<const char*>(ev.packet->data), ev.packet->dataLength);
                enet_packet_destroy(ev.packet);
                if (id != 0) {
                    push_event(std::move(out));
                }
                break;
            }
            case ENET_EVENT_TYPE_DISCONNECT: {
                const uint32_t id = peer_id(ev.peer);
                ev.peer->data = nullptr;
                if (id != 0) {
                    impl.peers.erase(id);
                    refresh_peers();
                }
                push_event(Event{EventType::Disconnected, id, true, {}});
                if (!impl.is_host) {
                    set_error(id != 0 ? "Verbindung zum Host verloren"
                                      : "Verbindung fehlgeschlagen (Host nicht erreichbar?)");
                    client_lost = true;
                }
                break;
            }
            case ENET_EVENT_TYPE_NONE:
                break;
            }
            if (client_lost) {
                break;
            }
            result = enet_host_check_events(impl.host, &ev);
        }

        if (result < 0) {
            set_error("Netzwerkfehler (enet_host_service)");
        }

        // 3. Ping-Werte regelmaessig aktualisieren.
        const auto now = std::chrono::steady_clock::now();
        if (now - last_peer_refresh > std::chrono::milliseconds{500}) {
            refresh_peers();
            last_peer_refresh = now;
        }
    }

    // Sauber abmelden, damit die Gegenseite nicht erst in einen Timeout laeuft.
    if (!impl.peers.empty()) {
        for (const auto& [id, peer] : impl.peers) {
            enet_peer_disconnect(peer, 0);
        }
        const auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds{kDisconnectGraceMs};
        ENetEvent ev{};
        while (!impl.peers.empty() && std::chrono::steady_clock::now() < deadline) {
            if (enet_host_service(impl.host, &ev, 10) <= 0) {
                continue;
            }
            if (ev.type == ENET_EVENT_TYPE_RECEIVE) {
                enet_packet_destroy(ev.packet);
            } else if (ev.type == ENET_EVENT_TYPE_DISCONNECT) {
                impl.peers.erase(peer_id(ev.peer));
            }
        }
        for (const auto& [id, peer] : impl.peers) {
            enet_peer_reset(peer);
        }
    }

    impl.peers.clear();
    enet_host_destroy(impl.host);
    impl.host = nullptr;

    {
        std::lock_guard lock{m_mutex};
        m_peers.clear();
    }
    m_mode = Mode::Idle;
}

}  // namespace coop::net
