#include "d3d9_hook.hpp"

#include <windows.h>

#include <d3d9.h>

#include <atomic>

#include "log.hpp"

namespace remods::d3d9 {
namespace {

// vtable-Indizes (Reihenfolge der Methoden in d3d9.h)
constexpr int kD3D9CreateDevice = 16;  // IDirect3D9::CreateDevice
constexpr int kDeviceReset = 16;       // IDirect3DDevice9::Reset
constexpr int kDevicePresent = 17;     // IDirect3DDevice9::Present

using CreateDevice_t = HRESULT(STDMETHODCALLTYPE*)(IDirect3D9*, UINT, D3DDEVTYPE, HWND, DWORD,
                                                    D3DPRESENT_PARAMETERS*, IDirect3DDevice9**);
using Reset_t = HRESULT(STDMETHODCALLTYPE*)(IDirect3DDevice9*, D3DPRESENT_PARAMETERS*);
using Present_t = HRESULT(STDMETHODCALLTYPE*)(IDirect3DDevice9*, const RECT*, const RECT*, HWND, const RGNDATA*);

Callbacks g_callbacks;
CreateDevice_t g_orig_create_device = nullptr;

// Je nach Device-Art (z. B. D3DCREATE_PUREDEVICE) kann die vtable eine
// andere sein. Wir merken uns pro vtable die Originalfunktionen.
struct DeviceVtable {
    void** vtable = nullptr;
    Present_t present = nullptr;
    Reset_t reset = nullptr;
};
constexpr int kMaxVtables = 4;
DeviceVtable g_vtables[kMaxVtables];
std::atomic<int> g_vtable_count{0};

void** vtable_of(void* com_object) {
    return *static_cast<void***>(com_object);
}

const DeviceVtable* find_vtable(IDirect3DDevice9* device) {
    void** vt = vtable_of(device);
    const int count = g_vtable_count.load();
    for (int i = 0; i < count; ++i) {
        if (g_vtables[i].vtable == vt) {
            return &g_vtables[i];
        }
    }
    return nullptr;
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

HRESULT STDMETHODCALLTYPE hk_present(IDirect3DDevice9* device, const RECT* src, const RECT* dst, HWND wnd,
                                     const RGNDATA* dirty) {
    static bool logged = false;
    if (!logged) {
        logged = true;
        LOG_INFO("Erster Present-Aufruf (Device %p) - Overlay wird gestartet", static_cast<void*>(device));
    }
    const DeviceVtable* vt = find_vtable(device);
    if (g_callbacks.on_present != nullptr) {
        g_callbacks.on_present(device);
    }
    return vt->present(device, src, dst, wnd, dirty);
}

HRESULT STDMETHODCALLTYPE hk_reset(IDirect3DDevice9* device, D3DPRESENT_PARAMETERS* params) {
    const DeviceVtable* vt = find_vtable(device);
    if (g_callbacks.on_before_reset != nullptr) {
        g_callbacks.on_before_reset();
    }
    const HRESULT hr = vt->reset(device, params);
    LOG_INFO("Device-Reset (%s, hr=0x%08lX)", SUCCEEDED(hr) ? "ok" : "fehlgeschlagen", static_cast<unsigned long>(hr));
    if (g_callbacks.on_after_reset != nullptr) {
        g_callbacks.on_after_reset(SUCCEEDED(hr));
    }
    return hr;
}

// Patcht Present/Reset in der vtable dieses Devices (einmal pro vtable).
void hook_device(IDirect3DDevice9* device, const char* origin) {
    void** vt = vtable_of(device);
    if (find_vtable(device) != nullptr) {
        return;
    }
    const int index = g_vtable_count.load();
    if (index >= kMaxVtables) {
        LOG_ERROR("Zu viele verschiedene Device-vtables");
        return;
    }
    DeviceVtable& entry = g_vtables[index];
    entry.vtable = vt;
    entry.present = reinterpret_cast<Present_t>(vt[kDevicePresent]);
    entry.reset = reinterpret_cast<Reset_t>(vt[kDeviceReset]);
    // Erst den Eintrag sichtbar machen, dann patchen: Ein Hook-Aufruf findet
    // so immer die Originalfunktion.
    g_vtable_count.store(index + 1);

    const bool ok = write_slot(&vt[kDevicePresent], reinterpret_cast<void*>(&hk_present)) &&
                    write_slot(&vt[kDeviceReset], reinterpret_cast<void*>(&hk_reset));
    LOG_INFO("Device-vtable %p gehookt (%s): %s", static_cast<void*>(vt), origin, ok ? "ok" : "FEHLER");
}

HRESULT STDMETHODCALLTYPE hk_create_device(IDirect3D9* d3d, UINT adapter, D3DDEVTYPE type, HWND focus, DWORD flags,
                                           D3DPRESENT_PARAMETERS* params, IDirect3DDevice9** out) {
    const HRESULT hr = g_orig_create_device(d3d, adapter, type, focus, flags, params, out);
    LOG_INFO("Spiel erstellt D3D9-Device: hr=0x%08lX, Flags=0x%08lX, %s, %ux%u", static_cast<unsigned long>(hr),
             static_cast<unsigned long>(flags), params != nullptr && params->Windowed ? "Fenster" : "Vollbild",
             params != nullptr ? params->BackBufferWidth : 0, params != nullptr ? params->BackBufferHeight : 0);
    if (SUCCEEDED(hr) && out != nullptr && *out != nullptr) {
        hook_device(*out, "CreateDevice");
    }
    return hr;
}

}  // namespace

bool install(const Callbacks& callbacks) {
    g_callbacks = callbacks;

    IDirect3D9* d3d = Direct3DCreate9(D3D_SDK_VERSION);
    if (d3d == nullptr) {
        LOG_ERROR("Direct3DCreate9 fehlgeschlagen");
        return false;
    }

    // 1) Spaeter erzeugte Devices abfangen. Die vtable von IDirect3D9 teilen
    //    sich alle IDirect3D9-Objekte des Prozesses.
    void** d3d_vt = vtable_of(d3d);
    g_orig_create_device = reinterpret_cast<CreateDevice_t>(d3d_vt[kD3D9CreateDevice]);
    if (!write_slot(&d3d_vt[kD3D9CreateDevice], reinterpret_cast<void*>(&hk_create_device))) {
        LOG_WARN("IDirect3D9::CreateDevice konnte nicht gehookt werden");
        g_orig_create_device = nullptr;
    }

    // 2) Falls das Spiel sein Device schon erstellt hat: vtable ueber ein
    //    Dummy-Device holen (gleiche Klasse => gleiche vtable).
    WNDCLASSEXW wc{};
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = DefWindowProcW;
    wc.hInstance = GetModuleHandleW(nullptr);
    wc.lpszClassName = L"REModsDummyWindow";
    RegisterClassExW(&wc);
    HWND wnd = CreateWindowExW(0, wc.lpszClassName, L"", WS_OVERLAPPEDWINDOW, 0, 0, 16, 16, nullptr, nullptr,
                               wc.hInstance, nullptr);

    D3DPRESENT_PARAMETERS pp{};
    pp.Windowed = TRUE;
    pp.SwapEffect = D3DSWAPEFFECT_DISCARD;
    pp.BackBufferFormat = D3DFMT_UNKNOWN;
    pp.hDeviceWindow = wnd;

    // Ueber das Original erzeugen, sonst landet das Dummy in unserem Hook.
    auto create = g_orig_create_device != nullptr ? g_orig_create_device
                                                  : reinterpret_cast<CreateDevice_t>(d3d_vt[kD3D9CreateDevice]);
    IDirect3DDevice9* dummy = nullptr;
    HRESULT hr = create(d3d, D3DADAPTER_DEFAULT, D3DDEVTYPE_NULLREF, wnd,
                        D3DCREATE_SOFTWARE_VERTEXPROCESSING | D3DCREATE_DISABLE_DRIVER_MANAGEMENT, &pp, &dummy);
    if (FAILED(hr)) {
        hr = create(d3d, D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL, wnd, D3DCREATE_SOFTWARE_VERTEXPROCESSING, &pp, &dummy);
    }
    if (SUCCEEDED(hr) && dummy != nullptr) {
        hook_device(dummy, "Dummy-Device");
        dummy->Release();
    } else {
        LOG_WARN("Dummy-Device fehlgeschlagen (hr=0x%08lX) - verlasse mich auf den CreateDevice-Hook",
                 static_cast<unsigned long>(hr));
    }

    DestroyWindow(wnd);
    UnregisterClassW(wc.lpszClassName, wc.hInstance);
    // d3d absichtlich nicht freigeben: Waere es das letzte IDirect3D9-Objekt,
    // koennte d3d9.dll intern aufraeumen. Ein Objekt mehr stoert nicht.
    return true;
}

}  // namespace remods::d3d9
