// Netzwerk-Kern fuer alle RE:Multiplayer-Mods.
//
// Ein Session-Objekt ist entweder Host (wartet auf Verbindungen) oder Client
// (verbindet sich zu einem Host). Die eigentliche Netzwerkarbeit laeuft in
// einem eigenen Thread, damit Verbindungen auch waehrend Ladebildschirmen
// (wenn das Spiel keine Frames liefert) nicht abreissen.
//
// Alle oeffentlichen Methoden sind thread-sicher.
#pragma once

#include <atomic>
#include <cstdint>
#include <deque>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace coop::net {

// Peer-ID 0 bedeutet "an alle verbundenen Peers".
constexpr uint32_t kAllPeers = 0;

enum class Mode {
    Idle,        // keine Verbindung
    Hosting,     // wir sind Host (mit oder ohne verbundene Clients)
    Connecting,  // Client, Verbindungsaufbau laeuft
    Connected,   // Client, mit Host verbunden
};

enum class EventType {
    Connected,     // ein Peer hat sich verbunden
    Disconnected,  // ein Peer ist weg (oder Verbindungsaufbau fehlgeschlagen)
    Message,       // Nachricht empfangen
};

struct Event {
    EventType type{};
    uint32_t peer{};
    bool reliable{};
    std::string data;
};

struct PeerInfo {
    uint32_t id{};
    std::string address;  // "ip:port"
    uint32_t rtt_ms{};
};

struct Stats {
    uint64_t messages_sent{};
    uint64_t messages_received{};
    uint64_t bytes_sent{};
    uint64_t bytes_received{};
};

const char* to_string(Mode mode);

class Session {
public:
    Session();
    ~Session();

    Session(const Session&) = delete;
    Session& operator=(const Session&) = delete;

    // Startet einen Host auf dem angegebenen UDP-Port.
    bool host(uint16_t port, size_t max_peers, std::string* error);

    // Verbindet sich als Client zu address:port. Das Ergebnis kommt spaeter
    // als Connected- bzw. Disconnected-Event.
    bool connect(const std::string& address, uint16_t port, std::string* error);

    // Beendet Host bzw. Verbindung. Blockiert kurz, bis der Thread fertig ist.
    void disconnect();

    // Stellt eine Nachricht in die Warteschlange. reliable = garantierte,
    // geordnete Zustellung (Events wie "Tuer geoeffnet"); unreliable = nur die
    // neueste zaehlt (Positionen).
    bool send(uint32_t peer, const void* data, size_t size, bool reliable);
    bool send(uint32_t peer, const std::string& data, bool reliable) {
        return send(peer, data.data(), data.size(), reliable);
    }

    // Holt alle seit dem letzten Aufruf eingegangenen Events ab.
    std::vector<Event> poll();

    Mode mode() const { return m_mode.load(); }
    std::vector<PeerInfo> peers() const;
    Stats stats() const;
    std::string last_error() const;

    // Groesste erlaubte Nachricht in Bytes.
    static constexpr size_t kMaxMessageSize = 64 * 1024;

private:
    struct Outgoing {
        uint32_t peer;
        bool reliable;
        std::string data;
    };

    struct Impl;

    bool start(bool as_host, const std::string& address, uint16_t port, size_t max_peers, std::string* error);
    void thread_main();
    void push_event(Event ev);
    void set_error(std::string err);

    std::unique_ptr<Impl> m_impl;
    std::thread m_thread;
    std::atomic<bool> m_stop{false};
    std::atomic<Mode> m_mode{Mode::Idle};

    mutable std::mutex m_mutex;  // schuetzt alles darunter
    std::deque<Outgoing> m_outbox;
    std::vector<Event> m_inbox;
    std::vector<PeerInfo> m_peers;
    Stats m_stats;
    std::string m_last_error;
};

}  // namespace coop::net
