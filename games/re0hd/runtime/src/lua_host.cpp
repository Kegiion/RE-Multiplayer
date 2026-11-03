#include "lua_host.hpp"

// winsock2 muss vor windows.h und iphlpapi.h stehen (sonst fehlen IP_ADAPTER_ADDRESSES & Co.)
#include <winsock2.h>
#include <ws2tcpip.h>

#include <windows.h>

#include <iphlpapi.h>

#include <lua.hpp>

#include <imgui.h>
#include <imgui_internal.h>  // ErrorRecovery*: faengt fehlende tree_pop/end_window von Skripten ab

#include <algorithm>
#include <cstdint>
#include <cstring>
#include <set>
#include <string>
#include <type_traits>
#include <vector>

#include "coop/net/lua_bindings.hpp"
#include "input_hook.hpp"
#include "log.hpp"
#include "mt_explorer.hpp"
#include "overlay.hpp"
#include "runtime.hpp"
#include "safe_mem.hpp"

// Hinweis: Lua-Fehler springen per longjmp aus den C-Funktionen heraus.
// In den Bindings deshalb erst alle luaL_check*-Aufrufe, und keine
// C++-Objekte mit Destruktor, solange ein Lua-Fehler auftreten kann.

namespace remultiplayer::lua_host {
namespace {

lua_State* g_L = nullptr;
bool g_reload_requested = true;  // erster Frame laedt die Skripte
bool g_imgui_active = false;     // nur dann duerfen imgui.*-Funktionen zeichnen
int g_ref_on_frame = LUA_NOREF;
int g_ref_on_draw_ui = LUA_NOREF;
int g_script_count = 0;

constexpr size_t kMaxErrors = 30;
std::vector<std::string> g_errors;
std::set<std::string> g_error_set;

void report_error(const std::string& text) {
    if (g_error_set.count(text) != 0) {
        return;  // jeder Fehler nur einmal (on_frame wiederholt ihn sonst jeden Frame)
    }
    g_error_set.insert(text);
    g_errors.push_back(text);
    if (g_errors.size() > kMaxErrors) {
        g_errors.erase(g_errors.begin());
    }
    log_line(LogLevel::Error, "Lua: " + text);
}

int msg_handler(lua_State* L) {
    const char* msg = lua_tostring(L, 1);
    if (msg == nullptr) {
        msg = luaL_tolstring(L, 1, nullptr);
    }
    luaL_traceback(L, L, msg, 1);
    return 1;
}

// Ruft die Funktion (mit nargs Argumenten darueber) geschuetzt auf.
bool protected_call(lua_State* L, int nargs, const char* where) {
    const int base = lua_gettop(L) - nargs;
    lua_pushcfunction(L, msg_handler);
    lua_insert(L, base);
    const int status = lua_pcall(L, nargs, 0, base);
    lua_remove(L, base);
    if (status != LUA_OK) {
        const char* msg = lua_tostring(L, -1);
        report_error(std::string{where} + ": " + (msg != nullptr ? msg : "(unbekannter Fehler)"));
        lua_pop(L, 1);
        return false;
    }
    return true;
}

void call_all(int ref, const char* where, bool in_window) {
    if (g_L == nullptr || ref == LUA_NOREF) {
        return;
    }
    lua_State* L = g_L;
    lua_rawgeti(L, LUA_REGISTRYINDEX, ref);
    const lua_Integer n = luaL_len(L, -1);
    for (lua_Integer i = 1; i <= n; ++i) {
        lua_rawgeti(L, -1, i);
        if (g_imgui_active) {
            ImGuiErrorRecoveryState state;
            ImGui::ErrorRecoveryStoreState(&state);
            protected_call(L, 0, where);
            if (in_window) {
                ImGui::ErrorRecoveryTryToRecoverWindowState(&state);
            } else {
                ImGui::ErrorRecoveryTryToRecoverState(&state);
            }
        } else {
            protected_call(L, 0, where);
        }
    }
    lua_pop(L, 1);
}

// ---- re -----------------------------------------------------------------

void append_callback(lua_State* L, int ref) {
    luaL_checktype(L, 1, LUA_TFUNCTION);
    lua_rawgeti(L, LUA_REGISTRYINDEX, ref);
    lua_pushvalue(L, 1);
    lua_rawseti(L, -2, luaL_len(L, -2) + 1);
    lua_pop(L, 1);
}

int l_re_on_frame(lua_State* L) {
    append_callback(L, g_ref_on_frame);
    return 0;
}

int l_re_on_draw_ui(lua_State* L) {
    append_callback(L, g_ref_on_draw_ui);
    return 0;
}

// ---- log ----------------------------------------------------------------

int log_with(lua_State* L, LogLevel level) {
    // Alle Argumente wie print() zusammenfuegen
    const int n = lua_gettop(L);
    luaL_Buffer b;
    luaL_buffinit(L, &b);
    for (int i = 1; i <= n; ++i) {
        if (i > 1) {
            luaL_addchar(&b, ' ');
        }
        luaL_tolstring(L, i, nullptr);
        luaL_addvalue(&b);
    }
    luaL_pushresult(&b);
    log_line(level, lua_tostring(L, -1));
    return 0;
}

int l_log_info(lua_State* L) { return log_with(L, LogLevel::Info); }
int l_log_warn(lua_State* L) { return log_with(L, LogLevel::Warn); }
int l_log_error(lua_State* L) { return log_with(L, LogLevel::Error); }

// ---- imgui ----------------------------------------------------------------
// Signaturen wie in REFramework. Ausserhalb eines ImGui-Frames passiert nichts.

const char* tostr(lua_State* L, int idx) {
    return luaL_tolstring(L, idx, nullptr);  // legt den String zusaetzlich auf den Stack
}

int l_imgui_text(lua_State* L) {
    const char* text = tostr(L, 1);
    if (g_imgui_active) {
        ImGui::TextUnformatted(text);
    }
    return 0;
}

// Farbe wie REFramework: 0xAABBGGRR (entspricht ImU32 von ImGui)
int l_imgui_text_colored(lua_State* L) {
    const char* text = tostr(L, 1);
    const auto color = static_cast<ImU32>(luaL_checkinteger(L, 2) & 0xFFFFFFFF);
    if (g_imgui_active) {
        ImGui::PushStyleColor(ImGuiCol_Text, color);
        ImGui::TextUnformatted(text);
        ImGui::PopStyleColor();
    }
    return 0;
}

// imgui.button(label [, breite, hoehe]) -> geklickt
int l_imgui_button(lua_State* L) {
    const char* label = luaL_checkstring(L, 1);
    const auto w = static_cast<float>(luaL_optnumber(L, 2, 0));
    const auto h = static_cast<float>(luaL_optnumber(L, 3, 0));
    lua_pushboolean(L, g_imgui_active && ImGui::Button(label, ImVec2(w, h)));
    return 1;
}

int l_imgui_checkbox(lua_State* L) {
    const char* label = luaL_checkstring(L, 1);
    bool value = lua_toboolean(L, 2) != 0;
    const bool changed = g_imgui_active && ImGui::Checkbox(label, &value);
    lua_pushboolean(L, changed);
    lua_pushboolean(L, value);
    return 2;
}

int l_imgui_input_text(lua_State* L) {
    const char* label = luaL_checkstring(L, 1);
    size_t len = 0;
    const char* value = luaL_optlstring(L, 2, "", &len);
    char buffer[1024];
    const size_t n = std::min(len, sizeof(buffer) - 1);
    std::memcpy(buffer, value, n);
    buffer[n] = '\0';
    const bool changed = g_imgui_active && ImGui::InputText(label, buffer, sizeof(buffer));
    lua_pushboolean(L, changed);
    lua_pushstring(L, buffer);
    return 2;
}

int l_imgui_slider_float(lua_State* L) {
    const char* label = luaL_checkstring(L, 1);
    auto value = static_cast<float>(luaL_checknumber(L, 2));
    const auto min = static_cast<float>(luaL_checknumber(L, 3));
    const auto max = static_cast<float>(luaL_checknumber(L, 4));
    const bool changed = g_imgui_active && ImGui::SliderFloat(label, &value, min, max);
    lua_pushboolean(L, changed);
    lua_pushnumber(L, value);
    return 2;
}

int l_imgui_tree_node(lua_State* L) {
    const char* label = luaL_checkstring(L, 1);
    lua_pushboolean(L, g_imgui_active && ImGui::TreeNode(label));
    return 1;
}

int l_imgui_tree_pop(lua_State*) {
    if (g_imgui_active) {
        ImGui::TreePop();
    }
    return 0;
}

int l_imgui_collapsing_header(lua_State* L) {
    const char* label = luaL_checkstring(L, 1);
    lua_pushboolean(L, g_imgui_active && ImGui::CollapsingHeader(label));
    return 1;
}

int l_imgui_same_line(lua_State*) {
    if (g_imgui_active) {
        ImGui::SameLine();
    }
    return 0;
}

int l_imgui_separator(lua_State*) {
    if (g_imgui_active) {
        ImGui::Separator();
    }
    return 0;
}

int l_imgui_spacing(lua_State*) {
    if (g_imgui_active) {
        ImGui::Spacing();
    }
    return 0;
}

// imgui.begin_window(name [, open [, flags]]) -> offen
// Wie in REFramework: end_window() immer aufrufen. Rueckgabe false, wenn
// der Benutzer das Fenster geschlossen hat.
int l_imgui_begin_window(lua_State* L) {
    const char* name = luaL_checkstring(L, 1);
    const bool has_open = !lua_isnoneornil(L, 2);
    bool open = has_open ? lua_toboolean(L, 2) != 0 : true;
    const auto flags = static_cast<ImGuiWindowFlags>(luaL_optinteger(L, 3, 0));
    if (g_imgui_active) {
        ImGui::Begin(name, has_open ? &open : nullptr, flags);
    }
    lua_pushboolean(L, open);
    return 1;
}

int l_imgui_end_window(lua_State*) {
    if (g_imgui_active) {
        ImGui::End();
    }
    return 0;
}

// imgui.begin_child(id, breite, hoehe) / imgui.end_child() - Bereich mit eigener Scrollleiste
int l_imgui_begin_child(lua_State* L) {
    const char* id = luaL_checkstring(L, 1);
    const auto w = static_cast<float>(luaL_optnumber(L, 2, 0));
    const auto h = static_cast<float>(luaL_optnumber(L, 3, 0));
    lua_pushboolean(L, g_imgui_active && ImGui::BeginChild(id, ImVec2(w, h), ImGuiChildFlags_Borders));
    return 1;
}

int l_imgui_end_child(lua_State*) {
    if (g_imgui_active) {
        ImGui::EndChild();
    }
    return 0;
}

// imgui.set_next_window_pos(x, y [, pivot_x, pivot_y]) - in Pixeln, Pivot 0..1 (1,1 = rechte untere Ecke)
int l_imgui_set_next_window_pos(lua_State* L) {
    const auto x = static_cast<float>(luaL_checknumber(L, 1));
    const auto y = static_cast<float>(luaL_checknumber(L, 2));
    const auto px = static_cast<float>(luaL_optnumber(L, 3, 0));
    const auto py = static_cast<float>(luaL_optnumber(L, 4, 0));
    if (g_imgui_active) {
        ImGui::SetNextWindowPos(ImVec2(x, y), ImGuiCond_Always, ImVec2(px, py));
    }
    return 0;
}

// imgui.set_next_window_size(breite, hoehe) - 0 = automatisch
int l_imgui_set_next_window_size(lua_State* L) {
    const auto w = static_cast<float>(luaL_checknumber(L, 1));
    const auto h = static_cast<float>(luaL_checknumber(L, 2));
    if (g_imgui_active) {
        ImGui::SetNextWindowSize(ImVec2(w, h), ImGuiCond_Always);
    }
    return 0;
}

int l_imgui_set_next_window_bg_alpha(lua_State* L) {
    const auto a = static_cast<float>(luaL_checknumber(L, 1));
    if (g_imgui_active) {
        ImGui::SetNextWindowBgAlpha(a);
    }
    return 0;
}

// imgui.push_font_scale(faktor) / imgui.pop_font_scale() - groessere Schrift
int l_imgui_push_font_scale(lua_State* L) {
    const auto f = static_cast<float>(luaL_checknumber(L, 1));
    if (g_imgui_active) {
        ImGui::PushFont(nullptr, ImGui::GetStyle().FontSizeBase * f);
    }
    return 0;
}

int l_imgui_pop_font_scale(lua_State*) {
    if (g_imgui_active) {
        ImGui::PopFont();
    }
    return 0;
}

int l_imgui_text_wrapped(lua_State* L) {
    const char* text = luaL_tolstring(L, 1, nullptr);
    if (g_imgui_active) {
        ImGui::TextWrapped("%s", text);
    }
    return 0;
}

// imgui.display_size() -> breite, hoehe des Bildes in Pixeln
int l_imgui_display_size(lua_State* L) {
    const ImVec2 s = ImGui::GetCurrentContext() != nullptr ? ImGui::GetIO().DisplaySize : ImVec2(0, 0);
    lua_pushnumber(L, s.x);
    lua_pushnumber(L, s.y);
    return 2;
}

int l_imgui_set_clipboard(lua_State* L) {
    const char* text = luaL_checkstring(L, 1);
    if (g_imgui_active) {
        ImGui::SetClipboardText(text);
    }
    return 0;
}

// ---- mem ------------------------------------------------------------------
// Speicherzugriff mit Pruefung ueber VirtualQuery: Ungueltige Adressen
// liefern nil statt eines Absturzes.

bool range_ok(uintptr_t addr, size_t size, bool write) {
    constexpr DWORD kReadable = PAGE_READONLY | PAGE_READWRITE | PAGE_WRITECOPY | PAGE_EXECUTE_READ |
                                PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY;
    constexpr DWORD kWritable = PAGE_READWRITE | PAGE_WRITECOPY | PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY;
    if (addr == 0 || addr + size < addr) {
        return false;
    }
    while (size > 0) {
        MEMORY_BASIC_INFORMATION mbi{};
        if (VirtualQuery(reinterpret_cast<const void*>(addr), &mbi, sizeof(mbi)) == 0) {
            return false;
        }
        if (mbi.State != MEM_COMMIT || (mbi.Protect & (PAGE_GUARD | PAGE_NOACCESS)) != 0 ||
            (mbi.Protect & (write ? kWritable : kReadable)) == 0) {
            return false;
        }
        const uintptr_t region_end = reinterpret_cast<uintptr_t>(mbi.BaseAddress) + mbi.RegionSize;
        if (region_end - addr >= size) {
            return true;
        }
        size -= region_end - addr;
        addr = region_end;
    }
    return true;
}

uintptr_t check_addr(lua_State* L, int idx) {
    return static_cast<uintptr_t>(luaL_checkinteger(L, idx));
}

template <typename T>
void push_value(lua_State* L, T v) {
    if constexpr (std::is_floating_point_v<T>) {
        lua_pushnumber(L, static_cast<lua_Number>(v));
    } else {
        lua_pushinteger(L, static_cast<lua_Integer>(v));
    }
}

template <typename T>
int l_mem_read(lua_State* L) {
    const uintptr_t addr = check_addr(L, 1);
    T v{};
    if (!safe_get(addr, v)) {
        lua_pushnil(L);
        return 1;
    }
    push_value(L, v);
    return 1;
}

template <typename T>
int l_mem_write(lua_State* L) {
    const uintptr_t addr = check_addr(L, 1);
    T v{};
    if constexpr (std::is_floating_point_v<T>) {
        v = static_cast<T>(luaL_checknumber(L, 2));
    } else {
        v = static_cast<T>(luaL_checkinteger(L, 2));
    }
    lua_pushboolean(L, safe_write(addr, &v, sizeof(T)));
    return 1;
}

// mem.read_string(addr [, max=256]) -> string | nil
int l_mem_read_string(lua_State* L) {
    const uintptr_t addr = check_addr(L, 1);
    const auto max = static_cast<size_t>(luaL_optinteger(L, 2, 256));
    char first = 0;
    if (!safe_get(addr, first)) {
        lua_pushnil(L);
        return 1;
    }
    luaL_Buffer b;
    luaL_buffinit(L, &b);
    for (size_t i = 0; i < max; ++i) {
        char c = 0;
        if (!safe_get(addr + i, c) || c == '\0') {
            break;
        }
        luaL_addchar(&b, c);
    }
    luaL_pushresult(&b);
    return 1;
}

// mem.read_bytes(addr, n) -> string | nil (ganzer Block oder nichts)
int l_mem_read_bytes(lua_State* L) {
    const uintptr_t addr = check_addr(L, 1);
    const auto n = static_cast<size_t>(luaL_checkinteger(L, 2));
    luaL_argcheck(L, n <= 16u * 1024 * 1024, 2, "hoechstens 16 MB");
    std::string buf(n, '\0');
    if (!safe_read(buf.data(), addr, n)) {
        lua_pushnil(L);
        return 1;
    }
    lua_pushlstring(L, buf.data(), buf.size());
    return 1;
}

// mem.write_bytes(addr, string) -> bool
int l_mem_write_bytes(lua_State* L) {
    const uintptr_t addr = check_addr(L, 1);
    size_t n = 0;
    const char* data = luaL_checklstring(L, 2, &n);
    lua_pushboolean(L, safe_write(addr, data, n));
    return 1;
}

int l_mem_readable(lua_State* L) {
    const uintptr_t addr = check_addr(L, 1);
    const auto size = static_cast<size_t>(luaL_optinteger(L, 2, 1));
    lua_pushboolean(L, range_ok(addr, size, false));
    return 1;
}

int l_mem_base(lua_State* L) {
    lua_pushinteger(L, static_cast<lua_Integer>(exe_info().base));
    return 1;
}

// mem.module(name) -> Basisadresse | nil
int l_mem_module(lua_State* L) {
    const char* name = luaL_checkstring(L, 1);
    HMODULE m = GetModuleHandleA(name);
    if (m == nullptr) {
        lua_pushnil(L);
    } else {
        lua_pushinteger(L, static_cast<lua_Integer>(reinterpret_cast<uintptr_t>(m)));
    }
    return 1;
}

// mem.scan("8B 0D ?? ?? ?? ?? 85 C9" [, start, size]) -> Adresse | nil
// Sucht ein Byte-Muster (Standard: in re0hd.exe). Muster sind robuster als
// feste Adressen, wenn das Spiel ein Update bekommt.
int l_mem_scan(lua_State* L) {
    const char* pattern = luaL_checkstring(L, 1);
    const uintptr_t start = lua_isnoneornil(L, 2) ? exe_info().base : check_addr(L, 2);
    const size_t size = lua_isnoneornil(L, 3) ? exe_info().size : static_cast<size_t>(luaL_checkinteger(L, 3));

    // Muster parsen: -1 = Platzhalter
    int bytes[256];
    int count = 0;
    for (const char* p = pattern; *p != '\0';) {
        if (*p == ' ') {
            ++p;
            continue;
        }
        if (count >= 256) {
            return luaL_error(L, "mem.scan: Muster zu lang (max. 256 Bytes)");
        }
        if (*p == '?') {
            bytes[count++] = -1;
            while (*p == '?') {
                ++p;
            }
            continue;
        }
        char hex[3] = {p[0], p[1], '\0'};
        char* end = nullptr;
        const long v = std::strtol(hex, &end, 16);
        if (end != hex + 2) {
            return luaL_error(L, "mem.scan: ungueltiges Muster bei '%s'", p);
        }
        bytes[count++] = static_cast<int>(v);
        p += 2;
    }
    if (count == 0 || size < static_cast<size_t>(count)) {
        lua_pushnil(L);
        return 1;
    }

    // Seitenweise nur lesbaren Speicher durchsuchen
    const uintptr_t end_addr = start + size;
    uintptr_t region = start;
    while (region < end_addr) {
        MEMORY_BASIC_INFORMATION mbi{};
        if (VirtualQuery(reinterpret_cast<const void*>(region), &mbi, sizeof(mbi)) == 0) {
            break;
        }
        const uintptr_t r_begin = std::max(region, reinterpret_cast<uintptr_t>(mbi.BaseAddress));
        const uintptr_t r_end = std::min(end_addr, static_cast<uintptr_t>(reinterpret_cast<uintptr_t>(mbi.BaseAddress) + mbi.RegionSize));
        if (range_ok(r_begin, 1, false) && r_end - r_begin >= static_cast<uintptr_t>(count)) {
            const auto* mem = reinterpret_cast<const uint8_t*>(r_begin);
            const size_t n = r_end - r_begin - static_cast<size_t>(count);
            for (size_t i = 0; i <= n; ++i) {
                int j = 0;
                while (j < count && (bytes[j] < 0 || mem[i + j] == bytes[j])) {
                    ++j;
                }
                if (j == count) {
                    lua_pushinteger(L, static_cast<lua_Integer>(r_begin + i));
                    return 1;
                }
            }
        }
        region = reinterpret_cast<uintptr_t>(mbi.BaseAddress) + mbi.RegionSize;
    }
    lua_pushnil(L);
    return 1;
}

// ---- remultiplayer ---------------------------------------------------------------

int l_remultiplayer_reload(lua_State*) {
    request_reload();
    return 0;
}

// remultiplayer.show_cursor() - Mauszeiger in diesem Frame zeigen (jeden Frame aufrufen)
int l_remultiplayer_show_cursor(lua_State*) {
    overlay::request_cursor();
    return 0;
}

int l_remultiplayer_menu_open(lua_State* L) {
    lua_pushboolean(L, overlay::menu_open());
    return 1;
}

int l_remultiplayer_ui_scale(lua_State* L) {
    lua_pushnumber(L, overlay::scale());
    return 1;
}

// remultiplayer.local_ips() -> { "192.168.1.20", ... } - IPv4-Adressen der aktiven Netzwerkadapter
int l_remultiplayer_local_ips(lua_State* L) {
    std::vector<std::string> ips;
    {
        ULONG size = 16 * 1024;
        std::vector<unsigned char> buf(size);
        auto* list = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buf.data());
        ULONG flags = GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER;
        ULONG r = GetAdaptersAddresses(AF_INET, flags, nullptr, list, &size);
        if (r == ERROR_BUFFER_OVERFLOW) {
            buf.resize(size);
            list = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buf.data());
            r = GetAdaptersAddresses(AF_INET, flags, nullptr, list, &size);
        }
        if (r == NO_ERROR) {
            for (auto* a = list; a != nullptr; a = a->Next) {
                if (a->OperStatus != IfOperStatusUp || a->IfType == IF_TYPE_SOFTWARE_LOOPBACK) {
                    continue;
                }
                for (auto* u = a->FirstUnicastAddress; u != nullptr; u = u->Next) {
                    const auto* sin = reinterpret_cast<const sockaddr_in*>(u->Address.lpSockaddr);
                    char text[INET_ADDRSTRLEN]{};
                    if (InetNtopA(AF_INET, &sin->sin_addr, text, sizeof(text)) != nullptr &&
                        std::strncmp(text, "169.254.", 8) != 0) {
                        ips.emplace_back(text);
                    }
                }
            }
        }
    }
    lua_createtable(L, static_cast<int>(ips.size()), 0);
    for (size_t i = 0; i < ips.size(); ++i) {
        lua_pushstring(L, ips[i].c_str());
        lua_rawseti(L, -2, static_cast<lua_Integer>(i + 1));
    }
    return 1;
}

// ---- Aufbau ---------------------------------------------------------------

void set_funcs(lua_State* L, const char* global, const luaL_Reg* funcs) {
    lua_newtable(L);
    luaL_setfuncs(L, funcs, 0);
    lua_setglobal(L, global);
}

void set_string_field(lua_State* L, const char* key, const std::string& value) {
    lua_pushlstring(L, value.data(), value.size());
    lua_setfield(L, -2, key);
}

void set_int_field(lua_State* L, const char* key, lua_Integer value) {
    lua_pushinteger(L, value);
    lua_setfield(L, -2, key);
}

void register_api(lua_State* L) {
    static const luaL_Reg re_funcs[] = {
        {"on_frame", l_re_on_frame},
        {"on_draw_ui", l_re_on_draw_ui},
        {nullptr, nullptr},
    };
    set_funcs(L, "re", re_funcs);

    static const luaL_Reg log_funcs[] = {
        {"info", l_log_info},
        {"warn", l_log_warn},
        {"error", l_log_error},
        {"debug", l_log_info},
        {nullptr, nullptr},
    };
    set_funcs(L, "log", log_funcs);
    lua_pushcfunction(L, l_log_info);
    lua_setglobal(L, "print");  // print() landet ebenfalls im Log

    static const luaL_Reg imgui_funcs[] = {
        {"text", l_imgui_text},
        {"text_colored", l_imgui_text_colored},
        {"button", l_imgui_button},
        {"checkbox", l_imgui_checkbox},
        {"input_text", l_imgui_input_text},
        {"slider_float", l_imgui_slider_float},
        {"tree_node", l_imgui_tree_node},
        {"tree_pop", l_imgui_tree_pop},
        {"collapsing_header", l_imgui_collapsing_header},
        {"same_line", l_imgui_same_line},
        {"separator", l_imgui_separator},
        {"spacing", l_imgui_spacing},
        {"begin_window", l_imgui_begin_window},
        {"end_window", l_imgui_end_window},
        {"set_clipboard", l_imgui_set_clipboard},
        {"set_next_window_pos", l_imgui_set_next_window_pos},
        {"set_next_window_size", l_imgui_set_next_window_size},
        {"set_next_window_bg_alpha", l_imgui_set_next_window_bg_alpha},
        {"push_font_scale", l_imgui_push_font_scale},
        {"pop_font_scale", l_imgui_pop_font_scale},
        {"text_wrapped", l_imgui_text_wrapped},
        {"display_size", l_imgui_display_size},
        {"begin_child", l_imgui_begin_child},
        {"end_child", l_imgui_end_child},
        {nullptr, nullptr},
    };
    set_funcs(L, "imgui", imgui_funcs);
    // Fensteroptionen fuer imgui.begin_window(name, open, flags)
    lua_getglobal(L, "imgui");
    lua_newtable(L);
    set_int_field(L, "no_title", ImGuiWindowFlags_NoTitleBar);
    set_int_field(L, "no_resize", ImGuiWindowFlags_NoResize);
    set_int_field(L, "no_move", ImGuiWindowFlags_NoMove);
    set_int_field(L, "no_collapse", ImGuiWindowFlags_NoCollapse);
    set_int_field(L, "no_decoration", ImGuiWindowFlags_NoDecoration);
    set_int_field(L, "auto_resize", ImGuiWindowFlags_AlwaysAutoResize);
    set_int_field(L, "no_saved_settings", ImGuiWindowFlags_NoSavedSettings);
    set_int_field(L, "no_focus_on_appearing", ImGuiWindowFlags_NoFocusOnAppearing);
    set_int_field(L, "no_inputs", ImGuiWindowFlags_NoInputs);
    set_int_field(L, "no_nav", ImGuiWindowFlags_NoNav);
    lua_setfield(L, -2, "flags");
    lua_pop(L, 1);

    static const luaL_Reg mem_funcs[] = {
        {"read_u8", l_mem_read<uint8_t>},
        {"read_u16", l_mem_read<uint16_t>},
        {"read_u32", l_mem_read<uint32_t>},
        {"read_i8", l_mem_read<int8_t>},
        {"read_i16", l_mem_read<int16_t>},
        {"read_i32", l_mem_read<int32_t>},
        {"read_f32", l_mem_read<float>},
        {"read_f64", l_mem_read<double>},
        {"read_ptr", l_mem_read<uintptr_t>},
        {"read_string", l_mem_read_string},
        {"read_bytes", l_mem_read_bytes},
        {"write_bytes", l_mem_write_bytes},
        {"write_u8", l_mem_write<uint8_t>},
        {"write_u16", l_mem_write<uint16_t>},
        {"write_u32", l_mem_write<uint32_t>},
        {"write_i32", l_mem_write<int32_t>},
        {"write_f32", l_mem_write<float>},
        {"readable", l_mem_readable},
        {"base", l_mem_base},
        {"module", l_mem_module},
        {"scan", l_mem_scan},
        {nullptr, nullptr},
    };
    set_funcs(L, "mem", mem_funcs);

    lua_newtable(L);
    set_string_field(L, "version", kRuntimeVersion);
    set_string_field(L, "build", kBuildId);
    set_string_field(L, "game", kGameId);
    set_string_field(L, "game_dir", paths().game_dir);
    set_string_field(L, "data_dir", paths().data_dir);
    set_int_field(L, "exe_base", static_cast<lua_Integer>(exe_info().base));
    set_int_field(L, "exe_size", exe_info().size);
    set_int_field(L, "exe_timestamp", exe_info().timestamp);
    set_int_field(L, "pointer_size", sizeof(void*));
    lua_pushcfunction(L, l_remultiplayer_reload);
    lua_setfield(L, -2, "reload");
    lua_pushcfunction(L, l_remultiplayer_show_cursor);
    lua_setfield(L, -2, "show_cursor");
    lua_pushcfunction(L, l_remultiplayer_menu_open);
    lua_setfield(L, -2, "menu_open");
    lua_pushcfunction(L, l_remultiplayer_ui_scale);
    lua_setfield(L, -2, "ui_scale");
    lua_pushcfunction(L, l_remultiplayer_local_ips);
    lua_setfield(L, -2, "local_ips");
    lua_setglobal(L, "remultiplayer");

    coop::net::register_lua_api(L, session());
    mt::register_lua(L);
    input::register_lua(L);

    // Suchpfade fuer require(): erst lib/, dann autorun/
    const auto& p = paths();
    const std::string search = p.lib_dir + "?.lua;" + p.lib_dir + "?\\init.lua;" + p.autorun_dir + "?.lua;" +
                               p.autorun_dir + "?\\init.lua";
    lua_getglobal(L, "package");
    set_string_field(L, "path", search);
    set_string_field(L, "cpath", "");
    lua_pop(L, 1);
}

void close_state() {
    if (g_L != nullptr) {
        lua_close(g_L);
        g_L = nullptr;
    }
    g_ref_on_frame = LUA_NOREF;
    g_ref_on_draw_ui = LUA_NOREF;
    g_script_count = 0;
}

void open_state() {
    close_state();
    g_errors.clear();
    g_error_set.clear();

    lua_State* L = luaL_newstate();
    luaL_openlibs(L);
    lua_newtable(L);
    g_ref_on_frame = luaL_ref(L, LUA_REGISTRYINDEX);
    lua_newtable(L);
    g_ref_on_draw_ui = luaL_ref(L, LUA_REGISTRYINDEX);
    g_L = L;
    register_api(L);

    // json-Bibliothek (reines Lua) als globale Tabelle `json`
    if (luaL_loadstring(L, "json = require('json')") == LUA_OK) {
        protected_call(L, 0, "remultiplayer/lib/json.lua");
    }

    // Alle Skripte in autorun/ alphabetisch laden (ohne Unterordner)
    std::vector<std::string> files;
    WIN32_FIND_DATAA fd{};
    HANDLE find = FindFirstFileA((paths().autorun_dir + "*.lua").c_str(), &fd);
    if (find != INVALID_HANDLE_VALUE) {
        do {
            if ((fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) == 0) {
                files.emplace_back(fd.cFileName);
            }
        } while (FindNextFileA(find, &fd));
        FindClose(find);
    }
    std::sort(files.begin(), files.end());

    for (const auto& name : files) {
        const std::string full = paths().autorun_dir + name;
        if (luaL_loadfile(L, full.c_str()) != LUA_OK) {
            const char* msg = lua_tostring(L, -1);
            report_error(name + ": " + (msg != nullptr ? msg : "?"));
            lua_pop(L, 1);
            continue;
        }
        if (protected_call(L, 0, name.c_str())) {
            ++g_script_count;
        }
    }
    LOG_INFO("Lua: %d von %d Skript(en) aus %s geladen", g_script_count, static_cast<int>(files.size()),
             paths().autorun_dir.c_str());
}

}  // namespace

void run_frame(bool imgui_active) {
    g_imgui_active = imgui_active;
    if (g_reload_requested) {
        g_reload_requested = false;
        open_state();
    }
    call_all(g_ref_on_frame, "re.on_frame", false);
    g_imgui_active = false;
}

void draw_ui() {
    g_imgui_active = true;
    call_all(g_ref_on_draw_ui, "re.on_draw_ui", true);
    g_imgui_active = false;
}

void request_reload() {
    g_reload_requested = true;
}

std::vector<std::string> errors() {
    return g_errors;
}

int script_count() {
    return g_script_count;
}

}  // namespace remultiplayer::lua_host
