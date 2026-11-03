// Gemeinsame Daten der RE0-Runtime (Pfade, Infos zur exe, Netzwerk-Session).
#pragma once

#include <cstdint>
#include <string>

namespace coop::net {
class Session;
}

namespace remultiplayer {

// Bei jeder Aenderung an der Runtime erhoehen (Lua-Skripte haben eigene Versionen).
constexpr const char* kRuntimeVersion = "0.5.0";

// Git-Commit des Builds (von CMake gesetzt), damit man im Spiel sieht, welcher Build laeuft.
#ifndef REMULTIPLAYER_BUILD_ID
#define REMULTIPLAYER_BUILD_ID "lokal"
#endif
constexpr const char* kBuildId = REMULTIPLAYER_BUILD_ID;
constexpr const char* kGameId = "re0hd";

struct Paths {
    // Kommentare mit "/" statt Backslash (Backslash am Zeilenende = Zeilenfortsetzung!)
    std::string game_dir;     // <Spiel>/                 mit Trennzeichen am Ende
    std::string remultiplayer_dir;   // <Spiel>/remultiplayer/
    std::string autorun_dir;  // <Spiel>/remultiplayer/autorun/  Lua-Skripte, werden automatisch geladen
    std::string lib_dir;      // <Spiel>/remultiplayer/lib/      Lua-Bibliotheken (require)
    std::string data_dir;     // <Spiel>/remultiplayer/data/     Konfiguration, Diagnose (json.*)
};

struct ExeInfo {
    uintptr_t base = 0;
    uint32_t size = 0;       // SizeOfImage
    uint32_t timestamp = 0;  // PE-TimeDateStamp: aendert sich mit jedem Spiel-Update
};

const Paths& paths();
const ExeInfo& exe_info();

// Lebt bis zum Prozessende (wird absichtlich nie freigegeben).
coop::net::Session& session();

}  // namespace remultiplayer
