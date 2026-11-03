-- serial (Lua-Werte <-> Bytes) und transfer (Stuecke, Pruefsumme)
local serial = require("remultiplayer_coop.serial")
local transfer = require("remultiplayer_coop.transfer")

local function same(a, b, path)
    path = path or "wert"
    assert(type(a) == type(b), path .. ": Typ " .. type(a) .. " ~= " .. type(b))
    if type(a) ~= "table" then
        assert(a == b and math.type(a) == math.type(b), path .. ": " .. tostring(a) .. " ~= " .. tostring(b))
        return
    end
    for k, v in pairs(a) do
        same(v, b[k], path .. "." .. tostring(k))
    end
    for k in pairs(b) do
        assert(a[k] ~= nil, path .. "." .. tostring(k) .. " zu viel")
    end
end

-- Roundtrip aller Werttypen
local tree = {
    t = "app.ropeway.GameClock.GameSaveData", id = 1,
    f = {
        small = 5, neg = -100, mid = 70000, big = 8468177972, huge = -9007199254740993,
        float = 0.1, inf = math.huge, zero = 0.0, flag = true, off = false,
        text = "Leon", empty = "", umlaut = "Gr\195\182\195\159e",
        list = { 1, 2, { 3, 4 }, "x" },
        mixed = { 10, 20, extra = "y", [100] = 1 },
    },
}
local data = serial.encode(tree)
local back = assert(serial.decode(data))
same(tree, back)
assert(math.type(back.f.zero) == "float" and math.type(back.f.small) == "integer")

-- Wiederholte Zeichenketten werden nur einmal gespeichert
local many = {}
for i = 1, 1000 do
    many[i] = { t = "app.ropeway.gimmick.action.SetItem.SetItemSaveData", n = i }
end
local small = serial.encode(many)
assert(#small < 1000 * 15, "Zeichenketten nicht zusammengefasst: " .. #small)
same(many, assert(serial.decode(small)))

-- Kaputte Daten
assert(serial.decode("XXXX") == nil)
assert(serial.decode(data:sub(1, #data - 3)) == nil)
assert(serial.decode(data .. "\0") == nil)
assert(not pcall(serial.encode, { f = print }), "Funktion muss abgelehnt werden")

-- transfer: teilen, durcheinander zusammensetzen, Pruefsumme
assert(transfer.adler32("Wikipedia") == 0x11E60398)
local payload = string.rep(data, 40)
local begin, chunks = transfer.split(payload, 7, "Leon, Polizeistation")
assert(begin.chunks == #chunks and begin.size == #payload and begin.chunks > 1)
local rx = transfer.receiver(begin)
for i = #chunks, 1, -1 do
    assert(rx:add(chunks[i]))
end
assert(not rx:add({ transfer = 8, index = 0, data = "x" }), "fremde Uebertragung angenommen")
assert(rx:complete() and rx:progress() == 1)
assert(assert(rx:result()) == payload)
-- verfaelschtes Stueck
local rx2 = transfer.receiver(begin)
for i, c in ipairs(chunks) do
    rx2:add(i == 1 and { transfer = 7, index = 0, data = ("Z"):rep(#c.data) } or c)
end
local res, err = rx2:result()
assert(res == nil and err:find("Pruefsumme"), tostring(err))

print("serial_test: alles ok")
