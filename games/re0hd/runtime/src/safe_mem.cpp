#include "safe_mem.hpp"

#include <windows.h>

#include <cstring>

namespace remultiplayer {

// Hinweis: In Funktionen mit __try duerfen keine C++-Objekte mit Destruktor
// stehen (MSVC C2712). Deshalb nur rohe Zeiger.

bool safe_read(void* dst, uintptr_t src, size_t n) {
    if (src == 0 || src + n < src) {
        return false;
    }
#if defined(_MSC_VER)
    __try {
        std::memcpy(dst, reinterpret_cast<const void*>(src), n);
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
#else
    MEMORY_BASIC_INFORMATION mbi{};
    if (VirtualQuery(reinterpret_cast<const void*>(src), &mbi, sizeof(mbi)) == 0 || mbi.State != MEM_COMMIT) {
        return false;
    }
    std::memcpy(dst, reinterpret_cast<const void*>(src), n);
    return true;
#endif
}

bool safe_write(uintptr_t dst, const void* src, size_t n) {
    if (dst == 0 || dst + n < dst) {
        return false;
    }
    // Schreibschutz pruefen: Code und Konstanten nie aus Versehen aendern
    MEMORY_BASIC_INFORMATION mbi{};
    if (VirtualQuery(reinterpret_cast<const void*>(dst), &mbi, sizeof(mbi)) == 0 || mbi.State != MEM_COMMIT) {
        return false;
    }
    constexpr DWORD kWritable = PAGE_READWRITE | PAGE_WRITECOPY | PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY;
    if ((mbi.Protect & kWritable) == 0 || (mbi.Protect & PAGE_GUARD) != 0) {
        return false;
    }
#if defined(_MSC_VER)
    __try {
        std::memcpy(reinterpret_cast<void*>(dst), src, n);
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
#else
    std::memcpy(reinterpret_cast<void*>(dst), src, n);
    return true;
#endif
}

#if defined(_M_IX86) && defined(_MSC_VER)
namespace {
using Fn0 = uint32_t(__thiscall*)(uintptr_t);
using Fn1 = uint32_t(__thiscall*)(uintptr_t, uint32_t);
using Fn2 = uint32_t(__thiscall*)(uintptr_t, uint32_t, uint32_t);
using Fn3 = uint32_t(__thiscall*)(uintptr_t, uint32_t, uint32_t, uint32_t);
using Fn4 = uint32_t(__thiscall*)(uintptr_t, uint32_t, uint32_t, uint32_t, uint32_t);
}  // namespace

bool safe_call_thiscall(uintptr_t fn, uintptr_t self, const uint32_t* a, int count, uint32_t* result) {
    __try {
        uint32_t r = 0;
        switch (count) {
            case 0: r = reinterpret_cast<Fn0>(fn)(self); break;
            case 1: r = reinterpret_cast<Fn1>(fn)(self, a[0]); break;
            case 2: r = reinterpret_cast<Fn2>(fn)(self, a[0], a[1]); break;
            case 3: r = reinterpret_cast<Fn3>(fn)(self, a[0], a[1], a[2]); break;
            case 4: r = reinterpret_cast<Fn4>(fn)(self, a[0], a[1], a[2], a[3]); break;
            default: return false;
        }
        *result = r;
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}
#else
bool safe_call_thiscall(uintptr_t, uintptr_t, const uint32_t*, int, uint32_t*) {
    return false;  // nur im 32-Bit-Build fuer RE0
}
#endif

}  // namespace remultiplayer
