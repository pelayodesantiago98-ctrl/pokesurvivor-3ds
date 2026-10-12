-- stages.lua — modo Fases (idea tomada de Poké World Survivors): 8 fases de 10
-- minutos con 20 oleadas fijas de 30 s, 3-4 jefes a tiempos fijos y un jefe final
-- cuya derrota supera la fase y desbloquea la siguiente. Los datos vienen de
-- data/stages.lua (generado de giovanneluna/poke-survivors, MIT).
--
-- El generador de oleadas (spawner.lua) pregunta aquí la bolsa, el ritmo, el tope
-- y los jefes cuando hay una fase activa; si no, usa la arena infinita de siempre.
local U = G.U
local S = {}
G.Stages = S

S.LIST = require("data.stages")
local WAVE_T = 30
local cur = nil      -- { def, idx, waveBags, bossDefs, finalBoss, cleared }

function S.start(i)
    local def = S.LIST[i]
    if not def then return false end
    cur = { def = def, idx = i, waveBags = {}, bossDefs = nil, finalBoss = nil, cleared = false }
    return true
end

function S.stop() cur = nil end
function S.active() return cur ~= nil end
function S.current() return cur and cur.def or nil end
function S.index() return cur and cur.idx or nil end
function S.cleared() return cur ~= nil and cur.cleared end

local function waveAt(t)
    local n = #cur.def.waves
    local w = math.floor(t / WAVE_T) + 1
    if w > n then w = n end
    if w < 1 then w = 1 end
    return w
end

-- Tramo de stats (1..6) según la oleada: cada 4 oleadas sube uno; las fases
-- avanzadas empiezan más arriba (uno más cada 3 fases: con uno cada 2, la fase 7
-- arrancaba en el tramo 4 y te tumbaban a los 10 s a nivel 1).
local function tierFor(w)
    local base = math.floor((cur.idx - 1) / 3)
    return math.min(#G.Enemies.TIERS, base + math.floor((w - 1) / 4) + 1)
end

-- Multiplicadores de dificultad de la fase (vida / daño de los enemigos).
local function hpMul() return 1 + 0.25 * (cur.idx - 1) end
local function dmgMul() return 1 + 0.06 * (cur.idx - 1) end

-- Bolsa de definiciones de enemigo de la oleada actual (cacheada por oleada).
function S.bagAt(t)
    local w = waveAt(t)
    local bag = cur.waveBags[w]
    if bag then return bag end
    bag = {}
    local wave = cur.def.waves[w]
    local ti = tierFor(w)
    local tier = G.Enemies.TIERS[ti]
    for i = 1, #wave do
        local e = wave[i]
        local p = G.DEX_BY[e[1]]
        if p and G.Sprites.meta(p.dex) then
            local def = G.Enemies.defFor(p, tier, ti - 1)
            def.hp = U.round(def.hp * hpMul())
            def.dmg = U.round(def.dmg * dmgMul())
            for k = 1, e[2] do bag[#bag + 1] = def end
        end
    end
    if #bag == 0 then bag = G.Enemies.bagAt(t) end
    cur.waveBags[w] = bag
    return bag
end

-- Enemigos por segundo: el ritmo de la web (ms entre apariciones) rebajado para la 3DS.
function S.rate(t)
    local wave = cur.def.waves[waveAt(t)]
    return math.min(6, 1000 / wave.rate) * 0.32
end

-- Tope de enemigos a la vez.
function S.cap(t)
    local wave = cur.def.waves[waveAt(t)]
    return math.min(G.Spawner.CAP, math.floor(wave.cap * 0.4) + 6)
end

-- Jefes de la fase con el formato de G.Enemies.BOSSES() (+ final = true en el último).
function S.bosses()
    if cur.bossDefs then return cur.bossDefs end
    local out = {}
    local slots = G.Enemies.BOSS_SLOTS
    local n = #cur.def.bosses
    for i, b in ipairs(cur.def.bosses) do
        local p = G.DEX_BY[b.dex]
        local slot = slots[math.min(i + math.floor((cur.idx - 1) / 2), #slots)]
        local baseSpd = (p.spd - 78) / 0.42
        local beh = G.Enemies.behaviorOf and G.Enemies.behaviorOf(p) or "chase"
        out[i] = {
            at = b.at, dex = p.dex, name = p.name,
            hp = U.round(slot.hp * 1.35 * hpMul() * (i == n and 1.3 or 1)),
            spd = U.round(U.clamp(40 + baseSpd * 0.5, 40, 100)),
            dmg = U.round(slot.dmg * 1.2 * dmgMul()), xp = slot.xp,
            behavior = beh == "ranged" and "ranged" or (baseSpd > 90 and "charger" or "chase"),
            shotDmg = U.round(slot.dmg * 0.55), shotCd = 1.1, range = 260,
            final = (i == n),
        }
    end
    cur.bossDefs = out
    return out
end

-- El spawner avisa de qué enemigo es el jefe final; al caer, fase superada.
function S.setFinalBoss(e) cur.finalBoss = e end

function S.update(dt)
    if not cur or cur.cleared then return end
    if cur.finalBoss and cur.finalBoss.dead then cur.cleared = true end
end

-- dex que van a aparecer en los próximos `ahead` segundos (precarga de sprites).
local upcoming = {}
function S.upcomingDex(t, ahead)
    for i = #upcoming, 1, -1 do upcoming[i] = nil end
    local seen = {}
    local w0, w1 = waveAt(t), waveAt(t + (ahead or 60))
    for w = w0, w1 do
        local wave = cur.def.waves[w]
        for i = 1, #wave do
            local d = wave[i][1]
            if not seen[d] then seen[d] = true; upcoming[#upcoming + 1] = d end
        end
    end
    for _, b in ipairs(cur.def.bosses) do
        if b.at <= t + (ahead or 60) + 30 and not seen[b.dex] then seen[b.dex] = true; upcoming[#upcoming + 1] = b.dex end
    end
    return upcoming
end

-- Progreso guardado: fases superadas y mejores tiempos.
function S.progress()
    local s = G.DB.save
    s.stages = s.stages or {}
    return s.stages
end
function S.isCleared(i)
    local p = S.progress()
    local e = p[i] or p[tostring(i)]
    return e ~= nil and e.cleared == true
end
function S.isUnlocked(i) return i == 1 or S.isCleared(i - 1) end
function S.markCleared(i, time)
    local p = S.progress()
    local e = p[i] or p[tostring(i)] or {}
    e.cleared = true
    e.best = math.min(e.best or 1e9, math.floor(time))
    p[i] = e
end
