// Gemeinsame Daten der RE0-Runtime (Pfade, Infos zur exe, Netzwerk-Session).
#pragma once

#include <cstdint>
#include <string>

namespace coop::net {
class Session;
}

namespace remods {

// Bei jeder Aenderung an der Runtime erhoehen (Lua-Skripte haben eigene Versionen).
constexpr const char* kRuntimeVersion = "0.2.1";

// Git-Commit des Builds (von CMake gesetzt), damit man im Spiel sieht, welcher Build laeuft.
#ifndef REMODS_BUILD_ID
#define REMODS_BUILD_ID "lokal"
#endif
constexpr const char* kBuildId = REMODS_BUILD_ID;
constexpr const char* kGameId = "re0hd";

struct Paths {
    // Kommentare mit "/" statt Backslash (Backslash am Zeilenende = Zeilenfortsetzung!)
    std::string game_dir;     // <Spiel>/                 mit Trennzeichen am Ende
    std::string remods_dir;   // <Spiel>/remods/
    std::string autorun_dir;  // <Spiel>/remods/autorun/  Lua-Skripte, werden automatisch geladen
    std::string lib_dir;      // <Spiel>/remods/lib/      Lua-Bibliotheken (require)
    std::string data_dir;     // <Spiel>/remods/data/     Konfiguration, Diagnose (json.*)
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

}  // namespace remods
