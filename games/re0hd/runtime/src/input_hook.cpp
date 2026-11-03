#include "input_hook.hpp"

#include <windows.h>

#define DIRECTINPUT_VERSION 0x0800
#include <dinput.h>

#include <lua.hpp>

#include <atomic>
#include <cstring>
#include <mutex>
#include <unordered_map>

#include "log.hpp"

namespace remultiplayer::input {
namespace {

// vtable-Indizes von IDirectInputDevice8 (Reihenfolge in dinput.h)
constexpr int kGetCapabilities = 3;
constexpr int kGetDeviceState = 9;
constexpr int kGetDeviceData = 10;

using GetCapabilities_t = HRESULT(STDMETHODCALLTYPE*)(void*, LPDIDEVCAPS);
using GetDeviceState_t = HRESULT(STDMETHODCALLTYPE*)(void*, DWORD, LPVOID);
using GetDeviceData_t = HRESULT(STDMETHODCALLTYPE*)(void*, DWORD, LPDIDEVICEOBJECTDATA, LPDWORD, DWORD);

// ANSI- und Unicode-Geraete haben verschiedene vtables
struct DeviceVtable {
    void** vtable = nullptr;
    GetCapabilities_t caps = nullptr;
    GetDeviceState_t state = nullptr;
    GetDeviceData_t data = nullptr;
};
constexpr int kMaxVtables = 4;
DeviceVtable g_vtables[kMaxVtables];
std::atomic<int> g_vtable_count{0};

std::atomic<bool> g_block_keyboard{false};
std::atomic<bool> g_block_mouse{false};
std::atomic<uint8_t> g_inject[256];
std::atomic<uint8_t> g_real_keys[256];

std::mutex g_type_mutex;
std::unordered_map<void*, BYTE> g_device_types;  // Geraet -> DI8DEVTYPE_*

// Statistik fuer die Forschung
std::atomic<uint32_t> g_state_calls[3];  // Tastatur, Maus, andere
std::atomic<uint32_t> g_data_calls[3];

const DeviceVtable* find_vtable(void* device) {
    void** vt = *static_cast<void***>(device);
    const int count = g_vtable_count.load();
    for (int i = 0; i < count; ++i) {
        if (g_vtables[i].vtable == vt) {
            return &g_vtables[i];
        }
    }
    return nullptr;
}

BYTE device_type(void* device, const DeviceVtable* vt) {
    {
        std::lock_guard lock{g_type_mutex};
        const auto it = g_device_types.find(device);
        if (it != g_device_types.end()) {
            return it->second;
        }
    }
    DIDEVCAPS caps{};
    caps.dwSize = sizeof(caps);
    BYTE type = 0;
    if (SUCCEEDED(vt->caps(device, &caps))) {
        type = GET_DIDEVICE_TYPE(caps.dwDevType);
    }
    std::lock_guard lock{g_type_mutex};
    g_device_types[device] = type;
    return type;
}

int stat_index(BYTE type) {
    return type == DI8DEVTYPE_KEYBOARD ? 0 : type == DI8DEVTYPE_MOUSE ? 1 : 2;
}

HRESULT STDMETHODCALLTYPE hk_get_device_state(void* device, DWORD size, LPVOID data) {
    const DeviceVtable* vt = find_vtable(device);
    const HRESULT hr = vt->state(device, size, data);
    if (FAILED(hr) || data == nullptr) {
        return hr;
    }
    const BYTE type = device_type(device, vt);
    ++g_state_calls[stat_index(type)];
    auto* bytes = static_cast<uint8_t*>(data);
    if (type == DI8DEVTYPE_KEYBOARD && size >= 256) {
        for (int i = 0; i < 256; ++i) {
            g_real_keys[i].store(bytes[i]);
        }
        if (g_block_keyboard.load()) {
            std::memset(bytes, 0, 256);
        }
        for (int i = 0; i < 256; ++i) {
            if (g_inject[i].load() != 0) {
                bytes[i] = 0x80;
            }
        }
    } else if (type == DI8DEVTYPE_MOUSE && g_block_mouse.load()) {
        std::memset(bytes, 0, size);
    }
    return hr;
}

HRESULT STDMETHODCALLTYPE hk_get_device_data(void* device, DWORD object_size, LPDIDEVICEOBJECTDATA objects,
                                             LPDWORD count, DWORD flags) {
    const DeviceVtable* vt = find_vtable(device);
    const HRESULT hr = vt->data(device, object_size, objects, count, flags);
    if (FAILED(hr) || count == nullptr) {
        return hr;
    }
    const BYTE type = device_type(device, vt);
    ++g_data_calls[stat_index(type)];
    // Gepufferte Ereignisse verwerfen, solange das Menue offen ist
    const bool blocked = (type == DI8DEVTYPE_KEYBOARD && g_block_keyboard.load()) ||
                         (type == DI8DEVTYPE_MOUSE && g_block_mouse.load());
    if (blocked && objects != nullptr) {
        *count = 0;
    }
    return hr;
}

bool write_slot(void** slot, void* value) {
    DWORD old = 0;
    if (!VirtualProtect(slot, sizeof(void*), PAGE_READWRITE, &old)) {
        return false;
    }
    *slot = value;
    VirtualProtect(slot, sizeof(void*), old, &old);
    return true;
}

void hook_device_vtable(void* device, const char* origin) {
    if (find_vtable(device) != nullptr) {
        return;
    }
    const int index = g_vtable_count.load();
    if (index >= kMaxVtables) {
        return;
    }
    void** vt = *static_cast<void***>(device);
    DeviceVtable& entry = g_vtables[index];
    entry.vtable = vt;
    entry.caps = reinterpret_cast<GetCapabilities_t>(vt[kGetCapabilities]);
    entry.state = reinterpret_cast<GetDeviceState_t>(vt[kGetDeviceState]);
    entry.data = reinterpret_cast<GetDeviceData_t>(vt[kGetDeviceData]);
    g_vtable_count.store(index + 1);
    const bool ok = write_slot(&vt[kGetDeviceState], reinterpret_cast<void*>(&hk_get_device_state)) &&
                    write_slot(&vt[kGetDeviceData], reinterpret_cast<void*>(&hk_get_device_data));
    LOG_INFO("DirectInput: Geraete-vtable %p gehookt (%s): %s", static_cast<void*>(vt), origin, ok ? "ok" : "FEHLER");
}

using DirectInput8Create_t = HRESULT(WINAPI*)(HINSTANCE, DWORD, REFIID, LPVOID*, LPUNKNOWN);

// Ein Dummy-Tastaturgeraet erzeugen, um an die vtable zu kommen.
template <typename DI, typename DEV>
void hook_variant(DirectInput8Create_t create, REFIID iid, const char* name) {
    DI* di = nullptr;
    if (FAILED(create(GetModuleHandleW(nullptr), DIRECTINPUT_VERSION, iid, reinterpret_cast<void**>(&di), nullptr)) ||
        di == nullptr) {
        LOG_WARN("DirectInput: %s konnte nicht erstellt werden", name);
        return;
    }
    DEV* dev = nullptr;
    if (SUCCEEDED(di->CreateDevice(GUID_SysKeyboard, &dev, nullptr)) && dev != nullptr) {
        hook_device_vtable(dev, name);
        dev->Release();
    } else {
        LOG_WARN("DirectInput: Tastatur (%s) konnte nicht erstellt werden", name);
    }
    di->Release();
}

}  // namespace

bool install() {
    for (auto& k : g_inject) {
        k.store(0);
    }
    // dinput8.dll ist unser Loader, der an die echte DLL weiterreicht
    HMODULE dinput = GetModuleHandleW(L"dinput8.dll");
    auto create = dinput != nullptr
                      ? reinterpret_cast<DirectInput8Create_t>(GetProcAddress(dinput, "DirectInput8Create"))
                      : nullptr;
    if (create == nullptr) {
        LOG_ERROR("DirectInput: DirectInput8Create nicht gefunden");
        return false;
    }
    hook_variant<IDirectInput8W, IDirectInputDevice8W>(create, IID_IDirectInput8W, "Unicode");
    hook_variant<IDirectInput8A, IDirectInputDevice8A>(create, IID_IDirectInput8A, "ANSI");
    return g_vtable_count.load() > 0;
}

void set_blocked(bool keyboard, bool mouse) {
    g_block_keyboard.store(keyboard);
    g_block_mouse.store(mouse);
}

namespace {

int check_dik(lua_State* L, int idx) {
    const lua_Integer dik = luaL_checkinteger(L, idx);
    luaL_argcheck(L, dik >= 0 && dik < 256, idx, "DIK-Code 0..255 erwartet");
    return static_cast<int>(dik);
}

int l_set_key(lua_State* L) {
    const int dik = check_dik(L, 1);
    g_inject[dik].store(lua_toboolean(L, 2) ? 1 : 0);
    return 0;
}

int l_clear(lua_State*) {
    for (auto& k : g_inject) {
        k.store(0);
    }
    return 0;
}

int l_key_down(lua_State* L) {
    const int dik = check_dik(L, 1);
    lua_pushboolean(L, (g_real_keys[dik].load() & 0x80) != 0);
    return 1;
}

int l_stats(lua_State* L) {
    lua_createtable(L, 0, 7);
    static const char* state_keys[3] = {"state_keyboard", "state_mouse", "state_other"};
    static const char* data_keys[3] = {"data_keyboard", "data_mouse", "data_other"};
    for (int i = 0; i < 3; ++i) {
        lua_pushinteger(L, g_state_calls[i].load());
        lua_setfield(L, -2, state_keys[i]);
        lua_pushinteger(L, g_data_calls[i].load());
        lua_setfield(L, -2, data_keys[i]);
    }
    lua_pushboolean(L, g_block_keyboard.load() || g_block_mouse.load());
    lua_setfield(L, -2, "blocked");
    return 1;
}

}  // namespace

void register_lua(lua_State* L) {
    static const luaL_Reg funcs[] = {
        {"set_key", l_set_key},
        {"clear", l_clear},
        {"key_down", l_key_down},
        {"stats", l_stats},
        {nullptr, nullptr},
    };
    lua_newtable(L);
    luaL_setfuncs(L, funcs, 0);
    lua_setglobal(L, "input");
}

}  // namespace remultiplayer::input
