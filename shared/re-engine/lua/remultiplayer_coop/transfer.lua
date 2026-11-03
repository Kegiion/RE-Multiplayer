-- remultiplayer_coop/transfer.lua
--
-- Grosse Daten (z. B. Spielstaende) in SAVE_BEGIN/SAVE_CHUNK-Nachrichten teilen
-- und beim Empfaenger wieder zusammensetzen, mit Adler-32-Pruefsumme.
-- Spielunabhaengig. Gleiche Schnittstelle wie games/re0hd/.../savesync.lua,
-- damit RE0 spaeter hierauf umsteigen kann.

local M = {}

M.CHUNK_SIZE = 8192

-- Adler-32 (wie zlib)
function M.adler32(s)
    local a, b = 1, 0
    for i = 1, #s do
        a = (a + s:byte(i)) % 65521
        b = (b + a) % 65521
    end
    return (b << 16) | a
end

-- Teilt data in Nachrichten auf: begin (SAVE_BEGIN-Felder) und chunks (SAVE_CHUNK-Felder).
function M.split(data, transfer, info)
    local chunks = {}
    for i = 1, #data, M.CHUNK_SIZE do
        chunks[#chunks + 1] = { transfer = transfer, index = #chunks, data = data:sub(i, i + M.CHUNK_SIZE - 1) }
    end
    local begin = {
        transfer = transfer, size = #data, chunks = #chunks, checksum = M.adler32(data), info = info or "",
    }
    return begin, chunks
end

local Receiver = {}
Receiver.__index = Receiver

-- Empfaenger fuer eine Uebertragung (aus SAVE_BEGIN).
function M.receiver(begin)
    return setmetatable({ begin = begin, parts = {}, count = 0 }, Receiver)
end

-- Ein SAVE_CHUNK. Gibt false zurueck, wenn das Stueck nicht dazugehoert.
function Receiver:add(chunk)
    if chunk.transfer ~= self.begin.transfer or chunk.index >= self.begin.chunks then
        return false
    end
    if self.parts[chunk.index] == nil then
        self.count = self.count + 1
    end
    self.parts[chunk.index] = chunk.data
    return true
end

function Receiver:complete()
    return self.count == self.begin.chunks
end

function Receiver:progress()
    if self.begin.chunks == 0 then
        return 1
    end
    return self.count / self.begin.chunks
end

-- Fertige Daten oder nil + Fehlermeldung.
function Receiver:result()
    if not self:complete() then
        return nil, string.format("unvollstaendig (%d von %d Stuecken)", self.count, self.begin.chunks)
    end
    local data = table.concat(self.parts, "", 0, self.begin.chunks - 1)
    if #data ~= self.begin.size then
        return nil, string.format("falsche Groesse (%d statt %d Bytes)", #data, self.begin.size)
    end
    if M.adler32(data) ~= self.begin.checksum then
        return nil, "Pruefsumme falsch"
    end
    return data
end

return M
