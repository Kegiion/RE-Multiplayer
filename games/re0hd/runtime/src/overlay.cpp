#include "overlay.hpp"

#include <windows.h>

#include <d3d9.h>

#include <imgui.h>
#include <imgui_impl_dx9.h>
#include <imgui_impl_win32.h>

#include <algorithm>
#include <cstdio>
#include <mutex>
#include <string>
#include <vector>

#include "log.hpp"
#include "lua_host.hpp"
#include "runtime.hpp"

extern IMGUI_IMPL_API LRESULT ImGui_ImplWin32_WndProcHandler(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam);

namespace remods::overlay {
namespace {

constexpr ULONGLONG kBannerMs = 20000;  // Startmeldung 20 Sekunden zeigen

IDirect3DDevice9* g_device = nullptr;
HWND g_hwnd = nullptr;
WNDPROC g_orig_wndproc = nullptr;
bool g_context = false;
bool g_dx9_ready = false;
bool g_menu_open = false;
float g_scale = 1.0f;
ULONGLONG g_start_tick = 0;
std::string g_ini_path;

// Fenster-Nachrichten kommen evtl. in einem anderen Thread an als Present.
// ImGui ist nicht thread-sicher, deshalb sammeln wir sie und geben sie im
// Render-Thread an ImGui weiter.
struct Message {
    HWND hwnd;
    UINT msg;
    WPARAM wparam;
    LPARAM lparam;
};
std::mutex g_msg_mutex;
std::vector<Message> g_messages;

bool is_input_message(UINT msg) {
    return (msg >= WM_MOUSEFIRST && msg <= WM_MOUSELAST) || msg == WM_KEYDOWN || msg == WM_KEYUP ||
           msg == WM_SYSKEYDOWN || msg == WM_SYSKEYUP || msg == WM_CHAR;
}

bool is_forwarded_message(UINT msg) {
    return is_input_message(msg) || msg == WM_SETFOCUS || msg == WM_KILLFOCUS || msg == WM_MOUSELEAVE;
}

LRESULT CALLBACK wndproc(HWND hwnd, UINT msg, WPARAM wparam, LPARAM lparam) {
    if (is_forwarded_message(msg)) {
        std::lock_guard lock{g_msg_mutex};
        if (g_messages.size() < 4096) {
            g_messages.push_back({hwnd, msg, wparam, lparam});
        }
    }
    // Solange das Menue offen ist, bekommt das Spiel keine Maus/Tastatur
    // ueber Fenster-Nachrichten (Alt-Tasten bleiben erlaubt).
    if (g_menu_open && is_input_message(msg) && msg != WM_SYSKEYDOWN && msg != WM_SYSKEYUP) {
        return 0;
    }
    return CallWindowProcW(g_orig_wndproc, hwnd, msg, wparam, lparam);
}

void replay_messages() {
    std::vector<Message> pending;
    {
        std::lock_guard lock{g_msg_mutex};
        pending.swap(g_messages);
    }
    for (const auto& m : pending) {
        ImGui_ImplWin32_WndProcHandler(m.hwnd, m.msg, m.wparam, m.lparam);
    }
}

HWND find_window(IDirect3DDevice9* device) {
    D3DDEVICE_CREATION_PARAMETERS cp{};
    if (SUCCEEDED(device->GetCreationParameters(&cp)) && cp.hFocusWindow != nullptr) {
        return cp.hFocusWindow;
    }
    IDirect3DSwapChain9* chain = nullptr;
    HWND result = nullptr;
    if (SUCCEEDED(device->GetSwapChain(0, &chain)) && chain != nullptr) {
        D3DPRESENT_PARAMETERS pp{};
        if (SUCCEEDED(chain->GetPresentParameters(&pp))) {
            result = pp.hDeviceWindow;
        }
        chain->Release();
    }
    return result;
}

UINT backbuffer_height(IDirect3DDevice9* device) {
    IDirect3DSurface9* surface = nullptr;
    UINT height = 720;
    if (SUCCEEDED(device->GetBackBuffer(0, 0, D3DBACKBUFFER_TYPE_MONO, &surface)) && surface != nullptr) {
        D3DSURFACE_DESC desc{};
        if (SUCCEEDED(surface->GetDesc(&desc))) {
            height = desc.Height;
        }
        surface->Release();
    }
    return height;
}

void init(IDirect3DDevice9* device) {
    if (!g_context) {
        IMGUI_CHECKVERSION();
        ImGui::CreateContext();
        ImGuiIO& io = ImGui::GetIO();
        g_ini_path = paths().remods_dir + "imgui.ini";
        io.IniFilename = g_ini_path.c_str();
        io.ConfigFlags |= ImGuiConfigFlags_NoMouseCursorChange;  // Mauszeiger zeichnet ImGui selbst
        io.ConfigErrorRecoveryEnableAssert = false;

        // Groesse an die Aufloesung anpassen: 720p = 1.0, 1080p = 1.5, 1440p = 2.0
        const UINT height = backbuffer_height(device);
        g_scale = std::clamp(static_cast<float>(height) / 720.0f, 1.0f, 3.0f);
        ImGui::StyleColorsDark();
        ImGuiStyle& style = ImGui::GetStyle();
        style.ScaleAllSizes(g_scale);
        style.FontScaleMain = g_scale;

        g_hwnd = find_window(device);
        ImGui_ImplWin32_Init(g_hwnd);
        if (g_hwnd != nullptr) {
            g_orig_wndproc = reinterpret_cast<WNDPROC>(
                SetWindowLongPtrW(g_hwnd, GWLP_WNDPROC, reinterpret_cast<LONG_PTR>(&wndproc)));
        }
        LOG_INFO("Overlay: Fenster %p, Fenster-Thread %lu, Render-Thread %lu, Backbuffer-Hoehe %u, Skalierung %.2f",
                 static_cast<void*>(g_hwnd), g_hwnd != nullptr ? GetWindowThreadProcessId(g_hwnd, nullptr) : 0UL,
                 GetCurrentThreadId(), height, g_scale);
        if (g_orig_wndproc == nullptr) {
            LOG_WARN("Overlay: Fenster-Nachrichten konnten nicht abgefangen werden - Maus/Tastatur im Menue evtl. tot");
        }
        g_start_tick = GetTickCount64();
        g_context = true;
    }

    if (g_device != device) {
        if (g_dx9_ready) {
            ImGui_ImplDX9_Shutdown();
            LOG_INFO("Overlay: neues D3D9-Device %p", static_cast<void*>(device));
        }
        ImGui_ImplDX9_Init(device);
        g_device = device;
        g_dx9_ready = true;
    }
}

bool key_pressed(int vk) {
    static bool down[256]{};
    const bool now = (GetAsyncKeyState(vk) & 0x8000) != 0;
    const bool pressed = now && !down[vk];
    down[vk] = now;
    return pressed;
}

void handle_toggle_key() {
    // Beide Tasten immer abfragen, damit der "gedrueckt"-Zustand stimmt
    const bool insert = key_pressed(VK_INSERT);
    const bool f8 = key_pressed(VK_F8);
    if ((insert || f8) && GetForegroundWindow() == g_hwnd) {
        g_menu_open = !g_menu_open;
    }
}

void draw_banner() {
    const auto errors = lua_host::errors();
    const bool show_start = GetTickCount64() - g_start_tick < kBannerMs;
    if (g_menu_open || (!show_start && errors.empty())) {
        return;
    }
    ImGui::SetNextWindowPos(ImVec2(10.0f * g_scale, 10.0f * g_scale));
    ImGui::SetNextWindowBgAlpha(0.6f);
    const ImGuiWindowFlags flags = ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_AlwaysAutoResize |
                                   ImGuiWindowFlags_NoSavedSettings | ImGuiWindowFlags_NoFocusOnAppearing |
                                   ImGuiWindowFlags_NoNav | ImGuiWindowFlags_NoInputs;
    if (ImGui::Begin("##remods_banner", nullptr, flags)) {
        if (show_start) {
            ImGui::Text("REMods RE0 %s geladen - Einfg oder F8 oeffnet das Menue", kRuntimeVersion);
        }
        if (!errors.empty()) {
            ImGui::TextColored(ImVec4(1.0f, 0.35f, 0.35f, 1.0f), "%d Lua-Fehler - Details im Menue",
                               static_cast<int>(errors.size()));
        }
    }
    ImGui::End();
}

void draw_menu() {
    ImGui::SetNextWindowSize(ImVec2(640.0f * g_scale, 560.0f * g_scale), ImGuiCond_FirstUseEver);
    if (ImGui::Begin("REMods - Resident Evil 0 HD", &g_menu_open)) {
        const auto& exe = exe_info();
        ImGui::Text("Runtime %s   re0hd.exe: Basis 0x%08X, Zeitstempel 0x%08X", kRuntimeVersion,
                    static_cast<unsigned>(exe.base), exe.timestamp);
        ImGui::Text("Skripte geladen: %d", lua_host::script_count());
        ImGui::SameLine();
        if (ImGui::Button("Skripte neu laden")) {
            lua_host::request_reload();
        }

        const auto errors = lua_host::errors();
        if (!errors.empty()) {
            char header[64];
            std::snprintf(header, sizeof(header), "Skript-Fehler (%d)###errors", static_cast<int>(errors.size()));
            if (ImGui::CollapsingHeader(header, ImGuiTreeNodeFlags_DefaultOpen)) {
                ImGui::PushStyleColor(ImGuiCol_Text, ImVec4(1.0f, 0.4f, 0.4f, 1.0f));
                for (const auto& e : errors) {
                    ImGui::TextWrapped("%s", e.c_str());
                }
                ImGui::PopStyleColor();
            }
        }
        ImGui::Separator();

        lua_host::draw_ui();

        ImGui::Separator();
        if (ImGui::CollapsingHeader("Runtime-Log")) {
            ImGui::BeginChild("##log", ImVec2(0.0f, 220.0f * g_scale), ImGuiChildFlags_Borders);
            for (const auto& entry : log_tail(200)) {
                ImVec4 color(0.85f, 0.85f, 0.85f, 1.0f);
                if (entry.level == LogLevel::Warn) {
                    color = ImVec4(1.0f, 0.8f, 0.3f, 1.0f);
                } else if (entry.level == LogLevel::Error) {
                    color = ImVec4(1.0f, 0.4f, 0.4f, 1.0f);
                }
                ImGui::TextColored(color, "%s", entry.text.c_str());
            }
            ImGui::EndChild();
        }
    }
    ImGui::End();
}

}  // namespace

void on_present(IDirect3DDevice9* device) {
    static bool busy = false;  // Schutz gegen Rekursion (z. B. durch andere Overlays)
    if (busy) {
        return;
    }
    busy = true;

    init(device);
    replay_messages();
    handle_toggle_key();

    // Bei verlorenem Device (Alt+Tab im Vollbild) nicht zeichnen, aber Lua
    // weiterlaufen lassen, damit die Netzwerk-Session aktuell bleibt.
    if (device->TestCooperativeLevel() != D3D_OK) {
        lua_host::run_frame(false);
        busy = false;
        return;
    }

    ImGui::GetIO().MouseDrawCursor = g_menu_open;
    ImGui_ImplDX9_NewFrame();
    ImGui_ImplWin32_NewFrame();
    ImGui::NewFrame();

    lua_host::run_frame(true);
    draw_banner();
    if (g_menu_open) {
        draw_menu();
    }

    ImGui::Render();
    if (SUCCEEDED(device->BeginScene())) {
        ImGui_ImplDX9_RenderDrawData(ImGui::GetDrawData());
        device->EndScene();
    }
    busy = false;
}

void on_before_reset() {
    if (g_dx9_ready) {
        ImGui_ImplDX9_InvalidateDeviceObjects();
    }
}

void on_after_reset(bool ok) {
    if (ok && g_dx9_ready) {
        ImGui_ImplDX9_CreateDeviceObjects();
    }
}

}  // namespace remods::overlay
