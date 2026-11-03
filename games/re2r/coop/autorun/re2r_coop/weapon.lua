-- re2r_coop/weapon.lua
--
-- Waffenmodell fuer die Puppe. Die echte Waffe des Spielers ist ein eigenes
-- GameObject (z. B. "wp0000") als Kind der Figur am Gelenk "r_weapon", mit
-- Mesh, Schusslogik (app.ropeway.implement.Gun), Huelsen, Sound und Treffern.
-- Die Puppe bekommt nur das Modell: ein neues GameObject mit via.render.Mesh,
-- sonst wuerde sie womoeglich selbst schiessen.
--
-- Bestaetigt im Spiel am 3. November 2026 (Leon, Matilda/VP70):
--   - Mesh SectionRoot/Character/Weapon/wp0000/wp0000_VP70.mesh, Material .mdf2
--   - via.GameObject.create(name) + createComponent(via.render.Mesh), setMesh /
--     set_Material mit Holdern aus sdk.create_resource -> sichtbar
--   - Transform.set_Parent(Puppe) + set_ParentJoint("r_weapon") + lokale Drehung
--     wie beim Spieler (0.5, 0.5, -0.5, -0.5) -> sitzt wie beim Spieler
-- UNBESTAETIGT: andere Waffen, Waffenwechsel, Messer (kein wp-Kind?).

local game = require("re2r_coop.game")

local weapon = {}

weapon.JOINT = "r_weapon"

local try_call = game.try_call

-- Waffe des eigenen Spielers: { mesh=, mdf=, qx=, qy=, qz=, qw=, x=, y=, z= } oder nil.
function weapon.read(player)
    local tr = try_call(player, "get_Transform")
    local child = try_call(tr, "get_Child")
    while child ~= nil do
        local go = try_call(child, "get_GameObject")
        local name = try_call(go, "get_Name") or ""
        if name:match("^wp%d%d%d%d") and try_call(child, "get_ParentJoint") == weapon.JOINT then
            local mesh = try_call(go, "getComponent(System.Type)", sdk.typeof("via.render.Mesh"))
            local m = try_call(mesh, "getMesh")
            local mt = try_call(mesh, "get_Material")
            local mesh_path = try_call(m, "get_ResourcePath")
            local mdf_path = try_call(mt, "get_ResourcePath")
            if mesh_path ~= nil and mdf_path ~= nil then
                local q = try_call(child, "get_LocalRotation")
                local p = try_call(child, "get_LocalPosition")
                return {
                    mesh = mesh_path, mdf = mdf_path,
                    qx = q and q.x or 0, qy = q and q.y or 0, qz = q and q.z or 0, qw = q and q.w or 1,
                    x = p and p.x or 0, y = p and p.y or 0, z = p and p.z or 0,
                }
            end
        end
        child = try_call(child, "get_Next")
    end
    return nil
end

function weapon.key(info)
    if info == nil then
        return ""
    end
    return info.mesh .. "|" .. info.mdf
end

local function holder(res_type, holder_type, path)
    local res = sdk.create_resource(res_type, path)
    if res == nil then
        error("Ressource nicht geladen: " .. path)
    end
    if res.add_ref then
        res = res:add_ref()
    end
    local h = res:create_holder(holder_type)
    if h ~= nil and h.add_ref then
        h = h:add_ref()
    end
    return h
end

-- Modell erzeugen und an die Hand der Puppe haengen. Gibt das GameObject zurueck.
function weapon.attach(parent_transform, info)
    local create = sdk.find_type_definition("via.GameObject"):get_method("create(System.String)")
    local go = create:call(nil, "coop_weapon")
    if go == nil then
        error("GameObject fuer Waffe nicht erzeugt")
    end
    if go.add_ref then
        go = go:add_ref()
    end
    local mesh = go:call("createComponent(System.Type)", sdk.typeof("via.render.Mesh"))
    mesh:call("setMesh", holder("via.render.MeshResource", "via.render.MeshResourceHolder", info.mesh))
    mesh:call("set_Material", holder("via.render.MeshMaterialResource", "via.render.MeshMaterialResourceHolder", info.mdf))
    local tr = go:call("get_Transform")
    tr:call("set_Parent", parent_transform)
    tr:call("set_ParentJoint", weapon.JOINT)
    tr:call("set_LocalPosition", Vector3f.new(info.x or 0, info.y or 0, info.z or 0))
    tr:call("set_LocalRotation", Quaternion.new(info.qw or 1, info.qx or 0, info.qy or 0, info.qz or 0))
    return go
end

function weapon.destroy(go)
    if go ~= nil and try_call(go, "get_Valid") == true then
        pcall(go.call, go, "destroy", go)
    end
end

-- Felder fuer ANIM_BANKS <-> Waffen-Info.
function weapon.to_msg(info, msg)
    info = info or {}
    msg.weapon_mesh, msg.weapon_mdf = info.mesh or "", info.mdf or ""
    msg.wqx, msg.wqy, msg.wqz, msg.wqw = info.qx or 0, info.qy or 0, info.qz or 0, info.qw or 1
    msg.wx, msg.wy, msg.wz = info.x or 0, info.y or 0, info.z or 0
    return msg
end

function weapon.from_msg(msg)
    if msg.weapon_mesh == nil or msg.weapon_mesh == "" then
        return nil
    end
    return {
        mesh = msg.weapon_mesh, mdf = msg.weapon_mdf,
        qx = msg.wqx, qy = msg.wqy, qz = msg.wqz, qw = msg.wqw,
        x = msg.wx, y = msg.wy, z = msg.wz,
    }
end

return weapon
