#include "mt_explorer.hpp"

#include <windows.h>

#include <lua.hpp>

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstring>
#include <string>
#include <unordered_map>
#include <vector>

#include "log.hpp"
#include "runtime.hpp"
#include "safe_mem.hpp"

namespace remods::mt {
namespace {

struct Range {
    uintptr_t begin = 0;
    uintptr_t end = 0;
    bool contains(uintptr_t v) const { return v >= begin && v < end; }
};

Range g_text;
Range g_rdata;
Range g_data;
bool g_sections_ready = false;

struct DtiInfo {
    std::string name;
    uint32_t words[8]{};  // rohe Daten ab der DTI-Adresse
};
std::unordered_map<uintptr_t, DtiInfo> g_dti;         // DTI-Adresse -> Infos
std::unordered_map<std::string, uintptr_t> g_by_name;  // Name -> DTI-Adresse (erster Treffer)
int g_duplicate_names = 0;

// Feld-Offsets im DTI-Objekt, die auf andere DTI-Objekte zeigen (Statistik)
constexpr int kLinkOffsets[] = {0x08, 0x0C, 0x10, 0x14};
int g_link_hits[4]{};
int g_parent_offset = 0x10;  // Annahme, wird nach der Statistik gewaehlt

std::unordered_map<uintptr_t, uintptr_t> g_vtable_cache;  // vtable -> DTI (0 = kein MtObject)
int g_slot_hits[16]{};                                     // an welchem vtable-Platz getDTI gefunden wurde

std::unordered_map<uintptr_t, std::vector<uintptr_t>> g_instances;  // DTI -> Objekte
constexpr size_t kMaxInstancesPerClass = 512;
size_t g_instance_total = 0;

void init_sections() {
    if (g_sections_ready) {
        return;
    }
    const uintptr_t base = exe_info().base;
    const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
    const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS*>(base + static_cast<uintptr_t>(dos->e_lfanew));
    const IMAGE_SECTION_HEADER* sec = IMAGE_FIRST_SECTION(nt);
    for (unsigned i = 0; i < nt->FileHeader.NumberOfSections; ++i, ++sec) {
        char name[9]{};
        std::memcpy(name, sec->Name, 8);
        Range r{base + sec->VirtualAddress, base + sec->VirtualAddress + sec->Misc.VirtualSize};
        if (std::strcmp(name, ".text") == 0) {
            g_text = r;
        } else if (std::strcmp(name, ".rdata") == 0) {
            g_rdata = r;
        } else if (std::strcmp(name, ".data") == 0) {
            g_data = r;
        }
    }
    g_sections_ready = true;
    LOG_INFO("MT: .text %08X-%08X, .rdata %08X-%08X, .data %08X-%08X", static_cast<unsigned>(g_text.begin),
             static_cast<unsigned>(g_text.end), static_cast<unsigned>(g_rdata.begin), static_cast<unsigned>(g_rdata.end),
             static_cast<unsigned>(g_data.begin), static_cast<unsigned>(g_data.end));
}

// Liest einen Klassennamen (Bezeichner) an addr. Leer, wenn es keiner ist.
std::string read_identifier(uintptr_t addr) {
    char buf[96]{};
    if (!safe_read(buf, addr, sizeof(buf) - 1)) {
        return {};
    }
    size_t len = 0;
    while (len < sizeof(buf) - 1 && buf[len] != '\0') {
        const unsigned char c = static_cast<unsigned char>(buf[len]);
        if (!(std::isalnum(c) || c == '_' || c == ':')) {
            return {};
        }
        ++len;
    }
    if (len < 2 || len >= sizeof(buf) - 1 || !std::isalpha(static_cast<unsigned char>(buf[0]))) {
        return {};
    }
    return std::string{buf, len};
}

// Liest einen Speicherbereich blockweise (fehlerhafte Bloecke werden uebersprungen).
template <typename Fn>
void for_each_block(uintptr_t begin, uintptr_t end, std::vector<uint32_t>& buffer, Fn&& fn) {
    constexpr size_t kBlock = 1 << 20;  // 1 MB
    for (uintptr_t p = begin; p < end; p += kBlock) {
        const size_t n = std::min<size_t>(kBlock, end - p) & ~size_t{3};
        if (n == 0) {
            break;
        }
        buffer.resize(n / 4);
        if (safe_read(buffer.data(), p, n)) {
            fn(p, buffer);
        }
    }
}

void find_dtis() {
    init_sections();
    g_dti.clear();
    g_by_name.clear();
    g_vtable_cache.clear();
    g_duplicate_names = 0;
    std::fill(std::begin(g_link_hits), std::end(g_link_hits), 0);
    std::fill(std::begin(g_slot_hits), std::end(g_slot_hits), 0);

    // Kandidat: [vtable in .rdata][Zeiger auf Namen in .rdata] in .data
    std::vector<uint32_t> buf;
    for_each_block(g_data.begin, g_data.end, buf, [&](uintptr_t block, const std::vector<uint32_t>& words) {
        for (size_t i = 1; i + 8 < words.size(); ++i) {
            if (!g_rdata.contains(words[i]) || !g_rdata.contains(words[i - 1])) {
                continue;
            }
            std::string name = read_identifier(words[i]);
            if (name.empty()) {
                continue;
            }
            const uintptr_t dti = block + (i - 1) * 4;
            DtiInfo info;
            info.name = std::move(name);
            std::memcpy(info.words, &words[i - 1], sizeof(info.words));
            if (g_by_name.count(info.name) == 0) {
                g_by_name[info.name] = dti;
            } else {
                ++g_duplicate_names;
            }
            g_dti.emplace(dti, std::move(info));
        }
    });

    // Statistik: Welche Felder zeigen auf andere DTI-Objekte?
    for (const auto& [addr, info] : g_dti) {
        for (int k = 0; k < 4; ++k) {
            if (g_dti.count(info.words[kLinkOffsets[k] / 4]) != 0) {
                ++g_link_hits[k];
            }
        }
    }
    // Eltern-Zeiger: Die meisten Klassen haben genau einen Elternteil. Wir
    // nehmen das Feld mit den meisten Treffern (Annahme, siehe mt.info()).
    int best = 2;
    for (int k = 0; k < 4; ++k) {
        if (g_link_hits[k] > g_link_hits[best]) {
            best = k;
        }
    }
    g_parent_offset = kLinkOffsets[best];
    LOG_INFO("MT: %d DTI-Kandidaten (%d doppelte Namen). Verweise auf DTI: +08=%d +0C=%d +10=%d +14=%d",
             static_cast<int>(g_dti.size()), g_duplicate_names, g_link_hits[0], g_link_hits[1], g_link_hits[2],
             g_link_hits[3]);
}

// DTI zu einer vtable: sucht in den ersten Eintraegen "mov eax, <DTI>; ret".
uintptr_t dti_of_vtable(uintptr_t vt) {
    const auto it = g_vtable_cache.find(vt);
    if (it != g_vtable_cache.end()) {
        return it->second;
    }
    uintptr_t result = 0;
    for (int slot = 0; slot < 16; ++slot) {
        uint32_t fn = 0;
        if (!safe_get(vt + static_cast<uintptr_t>(slot) * 4, fn) || !g_text.contains(fn)) {
            break;  // Ende der vtable
        }
        uint8_t code[6]{};
        if (!safe_read(code, fn, sizeof(code)) || code[0] != 0xB8 || code[5] != 0xC3) {
            continue;
        }
        uint32_t imm = 0;
        std::memcpy(&imm, code + 1, 4);
        if (g_dti.count(imm) != 0) {
            result = imm;
            ++g_slot_hits[slot];
            break;
        }
    }
    g_vtable_cache.emplace(vt, result);
    return result;
}

const char* name_of_dti(uintptr_t dti) {
    const auto it = g_dti.find(dti);
    return it != g_dti.end() ? it->second.name.c_str() : nullptr;
}

uintptr_t class_dti_of(uintptr_t obj) {
    uint32_t vt = 0;
    if (!safe_get(obj, vt) || !g_rdata.contains(vt)) {
        return 0;
    }
    return dti_of_vtable(vt);
}

void scan_block(uintptr_t block, const std::vector<uint32_t>& words) {
    for (size_t i = 0; i < words.size(); ++i) {
        const uint32_t v = words[i];
        if (!g_rdata.contains(v)) {
            continue;
        }
        const uintptr_t dti = dti_of_vtable(v);
        if (dti == 0) {
            continue;
        }
        auto& list = g_instances[dti];
        if (list.size() < kMaxInstancesPerClass) {
            list.push_back(block + i * 4);
        }
        ++g_instance_total;
    }
}

struct ScanResult {
    double ms = 0;
    double scanned_mb = 0;
};

ScanResult scan_all() {
    LARGE_INTEGER freq{}, t0{}, t1{};
    QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&t0);

    if (g_dti.empty()) {
        find_dtis();
    }
    g_instances.clear();
    g_instance_total = 0;

    std::vector<uint32_t> buf;
    size_t scanned = 0;
    for_each_block(g_data.begin, g_data.end, buf, scan_block);  // statische Objekte
    scanned += g_data.end - g_data.begin;

    // Heap: privater, beschreibbarer Speicher
    uintptr_t addr = 0x10000;
    while (addr < 0xFFFF0000u) {
        MEMORY_BASIC_INFORMATION mbi{};
        if (VirtualQuery(reinterpret_cast<const void*>(addr), &mbi, sizeof(mbi)) == 0) {
            break;
        }
        const uintptr_t region = reinterpret_cast<uintptr_t>(mbi.BaseAddress);
        const uintptr_t next = region + mbi.RegionSize;
        if (mbi.State == MEM_COMMIT && mbi.Type == MEM_PRIVATE && mbi.Protect == PAGE_READWRITE) {
            for_each_block(region, next, buf, scan_block);
            scanned += mbi.RegionSize;
        }
        if (next <= addr) {
            break;
        }
        addr = next;
    }

    QueryPerformanceCounter(&t1);
    ScanResult r;
    r.ms = static_cast<double>(t1.QuadPart - t0.QuadPart) * 1000.0 / static_cast<double>(freq.QuadPart);
    r.scanned_mb = static_cast<double>(scanned) / (1024.0 * 1024.0);
    LOG_INFO("MT: Speicher durchsucht (%.0f MB in %.0f ms): %u Objekte in %u Klassen", r.scanned_mb, r.ms,
             static_cast<unsigned>(g_instance_total), static_cast<unsigned>(g_instances.size()));
    return r;
}

std::string lower(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return s;
}

// ---- Lua ------------------------------------------------------------------

void push_addr_list(lua_State* L, const std::vector<uintptr_t>& list) {
    lua_createtable(L, static_cast<int>(list.size()), 0);
    for (size_t i = 0; i < list.size(); ++i) {
        lua_pushinteger(L, static_cast<lua_Integer>(list[i]));
        lua_rawseti(L, -2, static_cast<lua_Integer>(i + 1));
    }
}

int l_scan(lua_State* L) {
    const ScanResult r = scan_all();
    lua_createtable(L, 0, 5);
    lua_pushinteger(L, static_cast<lua_Integer>(g_dti.size()));
    lua_setfield(L, -2, "dti");
    lua_pushinteger(L, static_cast<lua_Integer>(g_instance_total));
    lua_setfield(L, -2, "instances");
    lua_pushinteger(L, static_cast<lua_Integer>(g_instances.size()));
    lua_setfield(L, -2, "classes_with_instances");
    lua_pushnumber(L, r.ms);
    lua_setfield(L, -2, "ms");
    lua_pushnumber(L, r.scanned_mb);
    lua_setfield(L, -2, "scanned_mb");
    return 1;
}

struct ClassRow {
    const std::string* name;
    uintptr_t dti;
    size_t count;
    uint32_t size;
};

int l_classes(lua_State* L) {
    const char* filter_c = luaL_optstring(L, 1, "");
    if (g_dti.empty()) {
        find_dtis();
    }
    std::vector<ClassRow> rows;
    {
        const std::string filter = lower(filter_c);
        for (const auto& [name, dti] : g_by_name) {
            if (!filter.empty() && lower(name).find(filter) == std::string::npos) {
                continue;
            }
            const auto inst = g_instances.find(dti);
            const auto& info = g_dti.at(dti);
            rows.push_back({&name, dti, inst != g_instances.end() ? inst->second.size() : 0,
                            info.words[0x18 / 4] & 0x7FFFFFu});  // Groesse: Annahme (untere Bits bei +18)
        }
        std::sort(rows.begin(), rows.end(), [](const ClassRow& a, const ClassRow& b) { return *a.name < *b.name; });
    }
    lua_createtable(L, static_cast<int>(rows.size()), 0);
    for (size_t i = 0; i < rows.size(); ++i) {
        lua_createtable(L, 0, 4);
        lua_pushlstring(L, rows[i].name->data(), rows[i].name->size());
        lua_setfield(L, -2, "name");
        lua_pushinteger(L, static_cast<lua_Integer>(rows[i].dti));
        lua_setfield(L, -2, "dti");
        lua_pushinteger(L, static_cast<lua_Integer>(rows[i].count));
        lua_setfield(L, -2, "count");
        lua_pushinteger(L, rows[i].size);
        lua_setfield(L, -2, "size");
        lua_rawseti(L, -2, static_cast<lua_Integer>(i + 1));
    }
    return 1;
}

int l_instances(lua_State* L) {
    const char* name = luaL_checkstring(L, 1);
    const auto it = g_by_name.find(name);
    if (it == g_by_name.end()) {
        lua_newtable(L);
        return 1;
    }
    const auto inst = g_instances.find(it->second);
    if (inst == g_instances.end()) {
        lua_newtable(L);
        return 1;
    }
    push_addr_list(L, inst->second);
    return 1;
}

int l_class_of(lua_State* L) {
    const auto addr = static_cast<uintptr_t>(luaL_checkinteger(L, 1));
    if (g_dti.empty()) {
        find_dtis();
    }
    const char* name = name_of_dti(class_dti_of(addr));
    if (name == nullptr) {
        lua_pushnil(L);
    } else {
        lua_pushstring(L, name);
    }
    return 1;
}

int l_dti_raw(lua_State* L) {
    const char* name = luaL_checkstring(L, 1);
    const auto it = g_by_name.find(name);
    if (it == g_by_name.end()) {
        lua_pushnil(L);
        return 1;
    }
    const DtiInfo& info = g_dti.at(it->second);
    lua_createtable(L, 0, 3);
    lua_pushinteger(L, static_cast<lua_Integer>(it->second));
    lua_setfield(L, -2, "addr");
    lua_createtable(L, 8, 0);
    for (int i = 0; i < 8; ++i) {
        lua_pushinteger(L, info.words[i]);
        lua_rawseti(L, -2, i + 1);
    }
    lua_setfield(L, -2, "words");
    const char* parent = name_of_dti(info.words[g_parent_offset / 4]);
    if (parent != nullptr) {
        lua_pushstring(L, parent);
        lua_setfield(L, -2, "parent");
    }
    return 1;
}

int l_refs(lua_State* L) {
    const auto value = static_cast<uint32_t>(luaL_checkinteger(L, 1));
    init_sections();
    std::vector<uintptr_t> found;
    {
        std::vector<uint32_t> buf;
        for_each_block(g_data.begin, g_data.end, buf, [&](uintptr_t block, const std::vector<uint32_t>& words) {
            for (size_t i = 0; i < words.size() && found.size() < 64; ++i) {
                if (words[i] == value) {
                    found.push_back(block + i * 4);
                }
            }
        });
    }
    push_addr_list(L, found);
    return 1;
}

int l_info(lua_State* L) {
    init_sections();
    lua_createtable(L, 0, 10);
    lua_pushinteger(L, static_cast<lua_Integer>(g_text.begin));
    lua_setfield(L, -2, "text_begin");
    lua_pushinteger(L, static_cast<lua_Integer>(g_rdata.begin));
    lua_setfield(L, -2, "rdata_begin");
    lua_pushinteger(L, static_cast<lua_Integer>(g_rdata.end));
    lua_setfield(L, -2, "rdata_end");
    lua_pushinteger(L, static_cast<lua_Integer>(g_data.begin));
    lua_setfield(L, -2, "data_begin");
    lua_pushinteger(L, static_cast<lua_Integer>(g_data.end));
    lua_setfield(L, -2, "data_end");
    lua_pushinteger(L, static_cast<lua_Integer>(g_dti.size()));
    lua_setfield(L, -2, "dti_count");
    lua_pushinteger(L, g_duplicate_names);
    lua_setfield(L, -2, "duplicate_names");
    lua_pushinteger(L, g_parent_offset);
    lua_setfield(L, -2, "parent_offset");

    lua_createtable(L, 0, 4);
    for (int k = 0; k < 4; ++k) {
        char key[8];
        std::snprintf(key, sizeof(key), "+%02X", kLinkOffsets[k]);
        lua_pushinteger(L, g_link_hits[k]);
        lua_setfield(L, -2, key);
    }
    lua_setfield(L, -2, "link_hits");

    lua_createtable(L, 16, 0);
    for (int k = 0; k < 16; ++k) {
        lua_pushinteger(L, g_slot_hits[k]);
        lua_rawseti(L, -2, k + 1);  // Index 1 = vtable-Platz 0
    }
    lua_setfield(L, -2, "getdti_slots");
    return 1;
}

}  // namespace

void register_lua(lua_State* L) {
    static const luaL_Reg funcs[] = {
        {"scan", l_scan},
        {"classes", l_classes},
        {"instances", l_instances},
        {"class_of", l_class_of},
        {"dti_raw", l_dti_raw},
        {"refs", l_refs},
        {"info", l_info},
        {nullptr, nullptr},
    };
    lua_newtable(L);
    luaL_setfuncs(L, funcs, 0);
    lua_setglobal(L, "mt");
}

}  // namespace remods::mt
