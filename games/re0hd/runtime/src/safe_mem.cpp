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

}  // namespace remultiplayer
