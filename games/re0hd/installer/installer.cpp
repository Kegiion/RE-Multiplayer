// RE:Multiplayer RE0 Installer - eine exe, die die RE0-Koop-Mod installiert,
// aktualisiert oder entfernt.
//
// Alle Dateien der Mod stecken als Ressourcen (RCDATA) in der exe. Die
// Ressource 1 ist ein Verzeichnis "id|relativer/pfad" pro Zeile (von CMake
// erzeugt, siehe games/re0hd/CMakeLists.txt).
//
// Ablauf:
//   1. RE0-Ordner finden (Steam-Registry + libraryfolders.vdf, sonst Ordnerauswahl)
//   2. Fragen: installieren/aktualisieren oder deinstallieren
//   3. Dateien schreiben. Fehlen Schreibrechte, startet sich der Installer als Administrator neu.
//
// Befehlszeile (fuer den Neustart als Administrator und zum Testen):
//   RE-Multiplayer-RE0-Installer.exe [--path <Spielordner>] [--install | --uninstall] [--quiet]

#include <windows.h>

#include <shellapi.h>
#include <shlobj.h>

#include <cstdio>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

#pragma comment(linker, "\"/manifestdependency:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'\"")

namespace {

constexpr const wchar_t* kTitle = L"RE:Multiplayer – Resident Evil 0 HD Koop";
constexpr uint32_t kSupportedTimestamp = 0x6799D40F;  // re0hd.exe, Steam-Build 17178773
constexpr const char* kAppId = "339340";

#ifndef REMULTIPLAYER_MOD_VERSION
#define REMULTIPLAYER_MOD_VERSION "?"
#endif
#ifndef REMULTIPLAYER_RUNTIME_VERSION
#define REMULTIPLAYER_RUNTIME_VERSION "?"
#endif
#ifndef REMULTIPLAYER_BUILD_ID
#define REMULTIPLAYER_BUILD_ID "lokal"
#endif

bool g_quiet = false;

std::wstring widen(const std::string& s) {
    if (s.empty()) {
        return {};
    }
    const int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), nullptr, 0);
    std::wstring w(static_cast<size_t>(n), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, s.data(), static_cast<int>(s.size()), w.data(), n);
    return w;
}

int message(const std::wstring& text, UINT flags) {
    if (g_quiet) {
        return (flags & MB_YESNOCANCEL) == MB_YESNOCANCEL || (flags & MB_YESNO) == MB_YESNO ? IDYES : IDOK;
    }
    return MessageBoxW(nullptr, text.c_str(), kTitle, flags);
}

bool file_exists(const std::wstring& path) {
    const DWORD a = GetFileAttributesW(path.c_str());
    return a != INVALID_FILE_ATTRIBUTES && (a & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

bool read_file(const std::wstring& path, std::string& out) {
    std::ifstream f(path, std::ios::binary);
    if (!f) {
        return false;
    }
    std::ostringstream ss;
    ss << f.rdbuf();
    out = ss.str();
    return true;
}

std::wstring dir_of(std::wstring path) {
    for (auto& c : path) {
        if (c == L'/') {
            c = L'\\';
        }
    }
    while (!path.empty() && path.back() == L'\\') {
        path.pop_back();
    }
    return path;
}

// ---- RE0 finden ------------------------------------------------------------

std::wstring registry_string(HKEY root, const wchar_t* key, const wchar_t* value) {
    wchar_t buf[MAX_PATH * 2]{};
    DWORD size = sizeof(buf);
    if (RegGetValueW(root, key, value, RRF_RT_REG_SZ, nullptr, buf, &size) == ERROR_SUCCESS) {
        return buf;
    }
    return {};
}

// Alle "path"-Eintraege aus steamapps/libraryfolders.vdf
std::vector<std::wstring> steam_libraries(const std::wstring& steam) {
    std::vector<std::wstring> libs{steam};
    std::string vdf;
    if (!read_file(steam + L"\\steamapps\\libraryfolders.vdf", vdf)) {
        return libs;
    }
    size_t pos = 0;
    while ((pos = vdf.find("\"path\"", pos)) != std::string::npos) {
        const size_t q1 = vdf.find('"', pos + 6);
        const size_t q2 = q1 == std::string::npos ? q1 : vdf.find('"', q1 + 1);
        if (q2 == std::string::npos) {
            break;
        }
        std::string p = vdf.substr(q1 + 1, q2 - q1 - 1);
        // In der vdf sind Backslashes verdoppelt
        std::string clean;
        for (size_t i = 0; i < p.size(); ++i) {
            if (p[i] == '\\' && i + 1 < p.size() && p[i + 1] == '\\') {
                ++i;
            }
            clean += p[i];
        }
        libs.push_back(dir_of(widen(clean)));
        pos = q2;
    }
    return libs;
}

std::wstring find_game_dir() {
    std::wstring steam = registry_string(HKEY_CURRENT_USER, L"Software\\Valve\\Steam", L"SteamPath");
    if (steam.empty()) {
        steam = registry_string(HKEY_LOCAL_MACHINE, L"SOFTWARE\\WOW6432Node\\Valve\\Steam", L"InstallPath");
    }
    if (steam.empty()) {
        return {};
    }
    for (const auto& lib : steam_libraries(dir_of(steam))) {
        std::string acf;
        if (!read_file(lib + L"\\steamapps\\appmanifest_" + widen(kAppId) + L".acf", acf)) {
            continue;
        }
        const size_t k = acf.find("\"installdir\"");
        if (k == std::string::npos) {
            continue;
        }
        const size_t q1 = acf.find('"', k + 12);
        const size_t q2 = q1 == std::string::npos ? q1 : acf.find('"', q1 + 1);
        if (q2 == std::string::npos) {
            continue;
        }
        const std::wstring dir = lib + L"\\steamapps\\common\\" + widen(acf.substr(q1 + 1, q2 - q1 - 1));
        if (file_exists(dir + L"\\re0hd.exe")) {
            return dir;
        }
    }
    return {};
}

std::wstring pick_folder() {
    BROWSEINFOW bi{};
    bi.lpszTitle = L"Bitte den Ordner von Resident Evil 0 wählen (dort liegt re0hd.exe):";
    bi.ulFlags = BIF_RETURNONLYFSDIRS | BIF_NEWDIALOGSTYLE;
    PIDLIST_ABSOLUTE pidl = SHBrowseForFolderW(&bi);
    if (pidl == nullptr) {
        return {};
    }
    wchar_t path[MAX_PATH]{};
    SHGetPathFromIDListW(pidl, path);
    CoTaskMemFree(pidl);
    return path;
}

uint32_t exe_timestamp(const std::wstring& exe) {
    std::ifstream f(exe, std::ios::binary);
    IMAGE_DOS_HEADER dos{};
    if (!f.read(reinterpret_cast<char*>(&dos), sizeof(dos)) || dos.e_magic != IMAGE_DOS_SIGNATURE) {
        return 0;
    }
    f.seekg(dos.e_lfanew + 4 + 4);  // Signatur + Machine/NumberOfSections
    uint32_t ts = 0;
    f.read(reinterpret_cast<char*>(&ts), sizeof(ts));
    return ts;
}

// ---- Nutzlast --------------------------------------------------------------

struct PayloadFile {
    int id;
    std::wstring path;  // relativ, mit Backslashes
};

bool resource_bytes(int id, const void*& data, DWORD& size) {
    HRSRC res = FindResourceW(nullptr, MAKEINTRESOURCEW(id), MAKEINTRESOURCEW(10));  // RT_RCDATA
    if (res == nullptr) {
        return false;
    }
    HGLOBAL handle = LoadResource(nullptr, res);
    data = handle != nullptr ? LockResource(handle) : nullptr;
    size = SizeofResource(nullptr, res);
    return data != nullptr;
}

std::vector<PayloadFile> payload_index() {
    std::vector<PayloadFile> files;
    const void* data = nullptr;
    DWORD size = 0;
    if (!resource_bytes(1, data, size)) {
        return files;
    }
    std::istringstream in(std::string(static_cast<const char*>(data), size));
    std::string line;
    while (std::getline(in, line)) {
        const size_t bar = line.find('|');
        if (bar == std::string::npos) {
            continue;
        }
        while (!line.empty() && (line.back() == '\r' || line.back() == '\n')) {
            line.pop_back();
        }
        files.push_back({std::stoi(line.substr(0, bar)), dir_of(widen(line.substr(bar + 1)))});
    }
    return files;
}

// Unsere dinput8.dll enthaelt den Pfad zur Runtime als UTF-16-Text
bool is_our_loader(const std::wstring& path) {
    std::string bytes;
    if (!read_file(path, bytes)) {
        return false;
    }
    const std::wstring marker = L"remultiplayer\\remultiplayer_re0.dll";
    const std::string needle(reinterpret_cast<const char*>(marker.data()), marker.size() * sizeof(wchar_t));
    return bytes.find(needle) != std::string::npos;
}

DWORD write_file(const std::wstring& path, const void* data, DWORD size) {
    const std::wstring dir = path.substr(0, path.find_last_of(L'\\'));
    SHCreateDirectoryExW(nullptr, dir.c_str(), nullptr);
    HANDLE h = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h == INVALID_HANDLE_VALUE) {
        return GetLastError();
    }
    DWORD written = 0;
    const BOOL ok = WriteFile(h, data, size, &written, nullptr);
    const DWORD err = ok && written == size ? ERROR_SUCCESS : GetLastError();
    CloseHandle(h);
    return err;
}

std::wstring error_text(DWORD err) {
    if (err == ERROR_SHARING_VIOLATION || err == ERROR_LOCK_VIOLATION) {
        return L"Die Datei wird gerade benutzt. Läuft Resident Evil 0 noch? Bitte das Spiel beenden und erneut versuchen.";
    }
    wchar_t* buf = nullptr;
    FormatMessageW(FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, nullptr,
                   err, 0, reinterpret_cast<wchar_t*>(&buf), 0, nullptr);
    std::wstring text = buf != nullptr ? buf : L"Unbekannter Fehler";
    LocalFree(buf);
    return text + L" (Code " + std::to_wstring(err) + L")";
}

// ---- Aktionen ----------------------------------------------------------------

enum class Result { Ok, Failed, NeedsAdmin };

Result install(const std::wstring& game) {
    const auto files = payload_index();
    if (files.empty()) {
        message(L"Der Installer ist beschädigt (keine Dateien enthalten).", MB_ICONERROR);
        return Result::Failed;
    }

    // Fremde dinput8.dll (andere Mod) sichern, nicht ueberschreiben
    const std::wstring loader = game + L"\\dinput8.dll";
    if (file_exists(loader) && !is_our_loader(loader)) {
        const std::wstring backup = game + L"\\dinput8.dll.vor-remultiplayer";
        if (!CopyFileW(loader.c_str(), backup.c_str(), FALSE)) {
            const DWORD err = GetLastError();
            if (err == ERROR_ACCESS_DENIED) {
                return Result::NeedsAdmin;
            }
            message(L"Die vorhandene dinput8.dll konnte nicht gesichert werden:\n" + error_text(err), MB_ICONERROR);
            return Result::Failed;
        }
    }

    for (const auto& f : files) {
        const void* data = nullptr;
        DWORD size = 0;
        if (!resource_bytes(f.id, data, size)) {
            message(L"Der Installer ist beschädigt: " + f.path, MB_ICONERROR);
            return Result::Failed;
        }
        const DWORD err = write_file(game + L"\\" + f.path, data, size);
        if (err == ERROR_ACCESS_DENIED) {
            return Result::NeedsAdmin;
        }
        if (err != ERROR_SUCCESS) {
            message(L"Fehler beim Schreiben von\n" + f.path + L":\n\n" + error_text(err), MB_ICONERROR);
            return Result::Failed;
        }
    }
    return Result::Ok;
}

void delete_tree(const std::wstring& dir, const std::wstring& keep_name) {
    WIN32_FIND_DATAW fd{};
    HANDLE h = FindFirstFileW((dir + L"\\*").c_str(), &fd);
    if (h == INVALID_HANDLE_VALUE) {
        return;
    }
    do {
        const std::wstring name = fd.cFileName;
        if (name == L"." || name == L".." || name == keep_name) {
            continue;
        }
        const std::wstring full = dir + L"\\" + name;
        if ((fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
            delete_tree(full, L"");
            RemoveDirectoryW(full.c_str());
        } else {
            DeleteFileW(full.c_str());
        }
    } while (FindNextFileW(h, &fd));
    FindClose(h);
}

Result uninstall(const std::wstring& game) {
    const std::wstring loader = game + L"\\dinput8.dll";
    const std::wstring backup = game + L"\\dinput8.dll.vor-remultiplayer";
    if (file_exists(loader) && is_our_loader(loader)) {
        if (!DeleteFileW(loader.c_str())) {
            const DWORD err = GetLastError();
            if (err == ERROR_ACCESS_DENIED) {
                return Result::NeedsAdmin;
            }
            message(L"dinput8.dll konnte nicht gelöscht werden:\n" + error_text(err), MB_ICONERROR);
            return Result::Failed;
        }
    }
    if (file_exists(backup)) {
        MoveFileW(backup.c_str(), loader.c_str());  // vorherige Mod wiederherstellen
    }
    // remultiplayer-Ordner leeren, Einstellungen (data) behalten
    delete_tree(game + L"\\remultiplayer", L"data");
    RemoveDirectoryW((game + L"\\remultiplayer").c_str());  // klappt nur, wenn data leer war
    return Result::Ok;
}

bool is_elevated() {
    HANDLE token = nullptr;
    TOKEN_ELEVATION elevation{};
    DWORD size = 0;
    bool result = false;
    if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) {
        if (GetTokenInformation(token, TokenElevation, &elevation, sizeof(elevation), &size)) {
            result = elevation.TokenIsElevated != 0;
        }
        CloseHandle(token);
    }
    return result;
}

bool relaunch_as_admin(const std::wstring& game, bool do_install) {
    wchar_t self[MAX_PATH]{};
    GetModuleFileNameW(nullptr, self, MAX_PATH);
    const std::wstring args = L"--path \"" + game + L"\" " + (do_install ? L"--install" : L"--uninstall");
    SHELLEXECUTEINFOW sei{};
    sei.cbSize = sizeof(sei);
    sei.lpVerb = L"runas";
    sei.lpFile = self;
    sei.lpParameters = args.c_str();
    sei.nShow = SW_SHOWNORMAL;
    return ShellExecuteExW(&sei) != FALSE;
}

}  // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
    int argc = 0;
    wchar_t** argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    std::wstring game;
    int action = 0;  // 0 = fragen, 1 = installieren, 2 = deinstallieren
    for (int i = 1; i < argc; ++i) {
        const std::wstring a = argv[i];
        if (a == L"--path" && i + 1 < argc) {
            game = dir_of(argv[++i]);
        } else if (a == L"--install") {
            action = 1;
        } else if (a == L"--uninstall") {
            action = 2;
        } else if (a == L"--quiet") {
            g_quiet = true;
        }
    }
    LocalFree(argv);
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

    const std::wstring version = L"Mod " + widen(REMULTIPLAYER_MOD_VERSION) + L", Runtime " + widen(REMULTIPLAYER_RUNTIME_VERSION) +
                                 L" (Build " + widen(REMULTIPLAYER_BUILD_ID) + L")";

    if (game.empty()) {
        game = find_game_dir();
    }
    if (game.empty() || !file_exists(game + L"\\re0hd.exe")) {
        if (!g_quiet) {
            message(L"Resident Evil 0 HD wurde nicht automatisch gefunden.\nBitte im nächsten Fenster den Spielordner wählen.",
                    MB_ICONINFORMATION);
            game = dir_of(pick_folder());
        }
        if (game.empty() || !file_exists(game + L"\\re0hd.exe")) {
            message(L"In diesem Ordner liegt keine re0hd.exe. Abbruch.", MB_ICONERROR);
            return 1;
        }
    }

    const bool installed = file_exists(game + L"\\remultiplayer\\remultiplayer_re0.dll");
    if (action == 0) {
        std::wstring text = L"RE:Multiplayer Koop für Resident Evil 0 HD\n" + version + L"\n\nSpielordner:\n" + game + L"\n\n";
        if (installed) {
            text += L"Die Mod ist bereits installiert.\n\n"
                    L"Ja = aktualisieren\nNein = deinstallieren\nAbbrechen = nichts tun";
            const int r = message(text, MB_YESNOCANCEL | MB_ICONQUESTION);
            action = r == IDYES ? 1 : r == IDNO ? 2 : 0;
        } else {
            text += L"Jetzt installieren?";
            action = message(text, MB_YESNO | MB_ICONQUESTION) == IDYES ? 1 : 0;
        }
        if (action == 0) {
            return 0;
        }
    }

    if (action == 1) {
        const uint32_t ts = exe_timestamp(game + L"\\re0hd.exe");
        if (ts != kSupportedTimestamp) {
            wchar_t buf[64];
            std::swprintf(buf, 64, L"0x%08X", ts);
            if (message(std::wstring{L"Deine re0hd.exe hat eine andere Version (Zeitstempel "} + buf +
                            L") als die, für die die Mod gebaut ist.\nDas Menü funktioniert, der Koop bleibt aber aus.\n\n"
                            L"Trotzdem installieren?",
                        MB_YESNO | MB_ICONWARNING) != IDYES) {
                return 0;
            }
        }
    }

    const Result r = action == 1 ? install(game) : uninstall(game);
    if (r == Result::NeedsAdmin) {
        if (is_elevated()) {
            message(L"Keine Schreibrechte im Spielordner, auch nicht als Administrator.", MB_ICONERROR);
            return 1;
        }
        if (!relaunch_as_admin(game, action == 1)) {
            message(L"Für den Spielordner werden Administratorrechte benötigt.", MB_ICONERROR);
            return 1;
        }
        return 0;  // Die Kopie mit Administratorrechten macht weiter
    }
    if (r == Result::Failed) {
        return 1;
    }

    if (action == 1) {
        message(L"Fertig! Die Mod ist installiert.\n\nIm Spiel öffnet Einfg oder F8 das Menü. Unter \"RE0 Koop\" "
                L"kannst du hosten oder beitreten.\n\n" + version,
                MB_ICONINFORMATION);
    } else {
        message(L"Die Mod wurde entfernt. Deine Einstellungen liegen weiter unter remultiplayer\\data.", MB_ICONINFORMATION);
    }
    return 0;
}
