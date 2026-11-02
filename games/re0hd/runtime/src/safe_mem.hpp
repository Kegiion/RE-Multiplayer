// Absturzsicheres Lesen/Schreiben von Spielspeicher.
//
// Andere Threads des Spiels koennen jederzeit Speicher freigeben. Eine
// Pruefung mit VirtualQuery vorher reicht deshalb nicht: Wir fangen
// Zugriffsfehler per SEH ab (MSVC __try/__except).
#pragma once

#include <cstddef>
#include <cstdint>

namespace remultiplayer {

// Kopiert n Bytes von src nach dst. false bei ungueltigem Speicher.
bool safe_read(void* dst, uintptr_t src, size_t n);

// Kopiert n Bytes nach dst (Spielspeicher). false bei ungueltigem oder
// schreibgeschuetztem Speicher.
bool safe_write(uintptr_t dst, const void* src, size_t n);

template <typename T>
bool safe_get(uintptr_t addr, T& out) {
    return safe_read(&out, addr, sizeof(T));
}

}  // namespace remultiplayer
