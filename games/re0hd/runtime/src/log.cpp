#include "log.hpp"

#include <windows.h>

#include <cstdarg>
#include <cstdio>
#include <deque>
#include <mutex>

namespace remods {
namespace {

constexpr size_t kRingSize = 300;

std::mutex g_mutex;
FILE* g_file = nullptr;
std::deque<LogEntry> g_ring;

const char* level_name(LogLevel level) {
    switch (level) {
        case LogLevel::Warn: return "WARN ";
        case LogLevel::Error: return "FEHLER";
        default: return "INFO ";
    }
}

}  // namespace

void log_open(const std::string& path) {
    std::lock_guard lock{g_mutex};
    if (g_file == nullptr) {
        g_file = std::fopen(path.c_str(), "w");
    }
}

void log_line(LogLevel level, const std::string& text) {
    SYSTEMTIME t{};
    GetLocalTime(&t);
    char prefix[64];
    std::snprintf(prefix, sizeof(prefix), "%02u:%02u:%02u.%03u %s ", t.wHour, t.wMinute, t.wSecond, t.wMilliseconds,
                  level_name(level));

    std::lock_guard lock{g_mutex};
    if (g_file != nullptr) {
        std::fprintf(g_file, "%s%s\n", prefix, text.c_str());
        std::fflush(g_file);  // Bei einem Absturz soll nichts verloren gehen
    }
    OutputDebugStringA(("[REMods] " + text + "\n").c_str());
    g_ring.push_back({level, std::string{prefix} + text});
    if (g_ring.size() > kRingSize) {
        g_ring.pop_front();
    }
}

void log_fmt(LogLevel level, const char* fmt, ...) {
    char buffer[2048];
    va_list args;
    va_start(args, fmt);
    std::vsnprintf(buffer, sizeof(buffer), fmt, args);
    va_end(args);
    log_line(level, buffer);
}

std::vector<LogEntry> log_tail(size_t max) {
    std::lock_guard lock{g_mutex};
    const size_t start = g_ring.size() > max ? g_ring.size() - max : 0;
    return {g_ring.begin() + static_cast<std::ptrdiff_t>(start), g_ring.end()};
}

}  // namespace remods
