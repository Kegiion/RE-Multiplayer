// dinput8.dll - Loader fuer REMods in RE0 HD (re0hd.exe, 32-Bit).
//
// re0hd.exe importiert dinput8.dll. Liegt diese Datei neben der exe, laedt
// Windows sie statt der System-DLL. Wir
//   1. reichen alle Aufrufe an die echte dinput8.dll aus dem Systemordner
//      weiter (das Spiel merkt nichts davon) und
//   2. laden in einem eigenen Thread remods\remods_re0.dll und rufen deren
//      Export `remods_init` auf.
//
// Der Loader bleibt absichtlich winzig: Die ganze Logik steckt in der Runtime.

#include <windows.h>

#include <cstdio>

namespace {

HMODULE g_real = nullptr;

using DirectInput8Create_t = HRESULT(WINAPI*)(HINSTANCE, DWORD, REFIID, LPVOID*, LPUNKNOWN);
using DllCanUnloadNow_t = HRESULT(WINAPI*)();
using DllGetClassObject_t = HRESULT(WINAPI*)(REFCLSID, REFIID, LPVOID*);
using DllRegisterServer_t = HRESULT(WINAPI*)();

// Echte dinput8.dll erst beim ersten Aufruf laden (nicht in DllMain:
// LoadLibrary unter Loader-Lock ist verboten).
FARPROC real(const char* name) {
    if (g_real == nullptr) {
        wchar_t path[MAX_PATH]{};
        GetSystemDirectoryW(path, MAX_PATH);  // 32-Bit-Prozess: wird nach SysWOW64 umgeleitet
        wcscat_s(path, L"\\dinput8.dll");
        g_real = LoadLibraryW(path);
        if (g_real == nullptr) {
            return nullptr;
        }
    }
    return GetProcAddress(g_real, name);
}

// Ordner der exe inkl. abschliessendem Backslash.
void game_dir(wchar_t* out, DWORD size) {
    GetModuleFileNameW(nullptr, out, size);
    wchar_t* slash = wcsrchr(out, L'\\');
    if (slash != nullptr) {
        slash[1] = L'\0';
    }
}

DWORD WINAPI load_runtime(LPVOID) {
    wchar_t path[MAX_PATH]{};
    game_dir(path, MAX_PATH);
    wcscat_s(path, L"remods\\remods_re0.dll");

    HMODULE mod = LoadLibraryExW(path, nullptr, LOAD_WITH_ALTERED_SEARCH_PATH);
    if (mod == nullptr) {
        wchar_t msg[MAX_PATH + 128]{};
        swprintf_s(msg, L"REMods: %s konnte nicht geladen werden (Fehler %lu).", path, GetLastError());
        OutputDebugStringW(msg);
        return 1;
    }
    using init_t = void (*)();
    auto init = reinterpret_cast<init_t>(GetProcAddress(mod, "remods_init"));
    if (init == nullptr) {
        OutputDebugStringW(L"REMods: remods_init fehlt in remods_re0.dll");
        return 1;
    }
    init();
    return 0;
}

}  // namespace

extern "C" {

HRESULT WINAPI Proxy_DirectInput8Create(HINSTANCE inst, DWORD version, REFIID iid, LPVOID* out, LPUNKNOWN outer) {
    auto fn = reinterpret_cast<DirectInput8Create_t>(real("DirectInput8Create"));
    return fn != nullptr ? fn(inst, version, iid, out, outer) : E_FAIL;
}

HRESULT WINAPI Proxy_DllCanUnloadNow() {
    auto fn = reinterpret_cast<DllCanUnloadNow_t>(real("DllCanUnloadNow"));
    return fn != nullptr ? fn() : S_FALSE;
}

HRESULT WINAPI Proxy_DllGetClassObject(REFCLSID clsid, REFIID iid, LPVOID* out) {
    auto fn = reinterpret_cast<DllGetClassObject_t>(real("DllGetClassObject"));
    return fn != nullptr ? fn(clsid, iid, out) : E_FAIL;
}

HRESULT WINAPI Proxy_DllRegisterServer() {
    auto fn = reinterpret_cast<DllRegisterServer_t>(real("DllRegisterServer"));
    return fn != nullptr ? fn() : E_FAIL;
}

HRESULT WINAPI Proxy_DllUnregisterServer() {
    auto fn = reinterpret_cast<DllRegisterServer_t>(real("DllUnregisterServer"));
    return fn != nullptr ? fn() : E_FAIL;
}

}  // extern "C"

// Exporte unter den Originalnamen. Bei 32-Bit-__stdcall sind die internen
// Namen dekoriert (_Name@Bytes der Parameter), deshalb explizit per Linker.
#if defined(_M_IX86)
#pragma comment(linker, "/EXPORT:DirectInput8Create=_Proxy_DirectInput8Create@20")
#pragma comment(linker, "/EXPORT:DllCanUnloadNow=_Proxy_DllCanUnloadNow@0,PRIVATE")
#pragma comment(linker, "/EXPORT:DllGetClassObject=_Proxy_DllGetClassObject@12,PRIVATE")
#pragma comment(linker, "/EXPORT:DllRegisterServer=_Proxy_DllRegisterServer@0,PRIVATE")
#pragma comment(linker, "/EXPORT:DllUnregisterServer=_Proxy_DllUnregisterServer@0,PRIVATE")
#else
#error "Der RE0-Loader muss als 32-Bit (Win32) gebaut werden."
#endif

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(inst);
        HANDLE thread = CreateThread(nullptr, 0, load_runtime, nullptr, 0, nullptr);
        if (thread != nullptr) {
            CloseHandle(thread);
        }
    }
    return TRUE;
}
