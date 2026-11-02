// Hook auf IDirect3DDevice9::Present und ::Reset per vtable-Patch.
#pragma once

struct IDirect3DDevice9;

namespace remods::d3d9 {

struct Callbacks {
    void (*on_present)(IDirect3DDevice9* device) = nullptr;  // vor jedem Present (Render-Thread)
    void (*on_before_reset)() = nullptr;
    void (*on_after_reset)(bool ok) = nullptr;
};

// Erstellt kurz ein Dummy-Device, um an die vtable zu kommen, und haengt
// sich zusaetzlich in IDirect3D9::CreateDevice ein (falls das Spiel ein
// Device mit anderer vtable erzeugt).
bool install(const Callbacks& callbacks);

}  // namespace remods::d3d9
