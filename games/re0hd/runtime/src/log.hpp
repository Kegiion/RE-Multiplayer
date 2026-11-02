// Log-Datei <Spiel>/remods/remods_re0.log plus Ringpuffer fuer das Menue.
// Thread-sicher.
#pragma once

#include <string>
#include <vector>

namespace remods {

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

}  // namespace remods

#define LOG_INFO(...) ::remods::log_fmt(::remods::LogLevel::Info, __VA_ARGS__)
#define LOG_WARN(...) ::remods::log_fmt(::remods::LogLevel::Warn, __VA_ARGS__)
#define LOG_ERROR(...) ::remods::log_fmt(::remods::LogLevel::Error, __VA_ARGS__)
