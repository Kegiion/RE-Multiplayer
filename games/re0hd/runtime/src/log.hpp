// Log-Datei <Spiel>/remultiplayer/remultiplayer_re0.log plus Ringpuffer fuer das Menue.
// Thread-sicher.
#pragma once

#include <string>
#include <vector>

namespace remultiplayer {

enum class LogLevel { Info, Warn, Error };

void log_open(const std::string& path);
void log_line(LogLevel level, const std::string& text);
void log_fmt(LogLevel level, const char* fmt, ...);

struct LogEntry {
    LogLevel level;
    std::string text;
};

// Die letzten `max` Eintraege (aelteste zuerst).
std::vector<LogEntry> log_tail(size_t max);

}  // namespace remultiplayer

#define LOG_INFO(...) ::remultiplayer::log_fmt(::remultiplayer::LogLevel::Info, __VA_ARGS__)
#define LOG_WARN(...) ::remultiplayer::log_fmt(::remultiplayer::LogLevel::Warn, __VA_ARGS__)
#define LOG_ERROR(...) ::remultiplayer::log_fmt(::remultiplayer::LogLevel::Error, __VA_ARGS__)
