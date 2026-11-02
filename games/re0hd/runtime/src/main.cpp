// remods_re0.dll - Runtime fuer REMods in Resident Evil 0 HD (re0hd.exe, 32-Bit).
//
// Wird vom Loader (dinput8.dll) geladen, der danach `remods_init` aufruft.
// Ablauf:
//   1. Pfade bestimmen, Log-Datei <Spiel>/remods/remods_re0.log oeffnen
//   2. Infos zur exe loggen (Zeitstempel = Spielversion, wichtig fuer Adressen)
//   3. Netzwerk-Session anlegen (lebt bis Prozessende, ueberlebt "Skripte neu laden")
//   4. D3D9 hooken -> ab dem ersten Frame laufen Overlay und Lua-Skripte

#include <windows.h>

#include "coop/net/session.hpp"
#include "d3d9_hook.hpp"
#include "input_hook.hpp"
#include "log.hpp"
#include "overlay.hpp"
#include "runtime.hpp"

namespace remods {
namespace {

Paths g_paths;
ExeInfo g_exe;
coop::net::Session* g_session = nullptr;  // absichtlich nie freigegeben (kein Thread-Join beim Beenden)

void init_paths() {
    char buffer[MAX_PATH]{};
    GetModuleFileNameA(nullptr, buffer, MAX_PATH);
    std::string dir = buffer;
    dir.erase(dir.find_last_of("\\/") + 1);

    g_paths.game_dir = dir;
    g_paths.remods_dir = dir + "remods\\";
    g_paths.autorun_dir = g_paths.remods_dir + "autorun\\";
    g_paths.lib_dir = g_paths.remods_dir + "lib\\";
    g_paths.data_dir = g_paths.remods_dir + "data\\";
    CreateDirectoryA(g_paths.remods_dir.c_str(), nullptr);
    CreateDirectoryA(g_paths.data_dir.c_str(), nullptr);
}

void init_exe_info() {
    const auto base = reinterpret_cast<uintptr_t>(GetModuleHandleW(nullptr));
    const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
    const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS*>(base + static_cast<uintptr_t>(dos->e_lfanew));
    g_exe.base = base;
    g_exe.size = nt->OptionalHeader.SizeOfImage;
    g_exe.timestamp = nt->FileHeader.TimeDateStamp;
}

}  // namespace

const Paths& paths() {
    return g_paths;
}

const ExeInfo& exe_info() {
    return g_exe;
}

coop::net::Session& session() {
    return *g_session;
}

}  // namespace remods

extern "C" __declspec(dllexport) void remods_init() {
    using namespace remods;
    static bool started = false;
    if (started) {
        return;
    }
    started = true;

    init_paths();
    log_open(paths().remods_dir + "remods_re0.log");
    init_exe_info();
    LOG_INFO("REMods RE0 Runtime %s (Build %s) gestartet", kRuntimeVersion, kBuildId);
    LOG_INFO("Spielordner: %s", paths().game_dir.c_str());
    LOG_INFO("re0hd.exe: Basis 0x%08X, Groesse 0x%X, Zeitstempel 0x%08X", static_cast<unsigned>(exe_info().base),
             exe_info().size, exe_info().timestamp);

    g_session = new coop::net::Session{};

    d3d9::Callbacks callbacks;
    callbacks.on_present = overlay::on_present;
    callbacks.on_before_reset = overlay::on_before_reset;
    callbacks.on_after_reset = overlay::on_after_reset;
    if (d3d9::install(callbacks)) {
        LOG_INFO("D3D9-Hooks installiert - warte auf den ersten Frame");
    } else {
        LOG_ERROR("D3D9-Hooks fehlgeschlagen - kein Overlay");
    }
    if (!input::install()) {
        LOG_WARN("DirectInput-Hooks fehlgeschlagen - Spiel bekommt Eingaben auch bei offenem Menue");
    }
}
