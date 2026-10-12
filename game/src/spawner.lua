-- spawner.lua — oleadas, jefes y shinies (port de js/systems/spawner.js, sin cooperativo).
-- Los enemigos aparecen en un anillo justo fuera de la vista. Cada ~45 s hay una
-- "marea" desde un lado concreto. Cada enemigo tiene 1/4096 de salir shiny.
local U = G.U
local S = {}
G.Spawner = S

local floor, cos, sin, max, min = math.floor, math.cos, math.sin, math.max, math.min
local random = love.math.random

-- Tope de enemigos a la vez (3DS: 40). Al llegar al tope, los que siguen saliendo son
-- "élite" (más vida, daño y experiencia), así la dificultad no baja.
S.CAP = 40
local ELITE_FROM = 0.85
-- Menos Pokémon pero más fuertes (la pantalla no se satura).
local DENSITY, DMG_K, XP_K = 0.24, 2.4, 5.6
local function hpK(t) return 3.3 + min(1.7, t / 210) end
S.SHINY_RATE = 1 / 4096

local acc, bossIdx, surgeT, announce, announceT, preloadT, gcT = 0, 1, 32, nil, 0, 0, 0
local forceShiny = 0
local keep = {}          -- dex a conservar en memoria
local keepFull = {}

function S.reset()
    acc = 0; bossIdx = 1; surgeT = 32; announce = nil; announceT = 0; preloadT = 0; gcT = 10
    G.Enemies.rollRun()
    local up = G.Stages.active() and G.Stages.upcomingDex(0, 80) or G.Enemies.upcomingDex(0, 80)
    G.Sprites.preload(up, false)
end

-- Enemigos por segundo según el minuto de la run.
function S.rate(t)
    return (1.6 + t * 0.028 + (t / 60) ^ 1.6 * 0.5) * DENSITY
end

local function ringPoint(pl, angle)
    local d = G.Camera.outerRadius() + U.rand(10, 70)
    return pl.x + cos(angle) * d, pl.y + sin(angle) * d * 0.9
end

-- Punto del anillo donde quepa: no dentro de paredes ni en el agua.
local function freePoint(pl, angle, flying)
    for i = 0, 7 do
        local a = angle + (i == 0 and 0 or U.rand(-0.9, 0.9))
        local x, y = ringPoint(pl, a)
        if flying or G.World.isFree(x, y, 14) then return x, y end
    end
    return nil
end

local scaledT = { hp = 1, spd = 1, dmg = 1 }
local function scaled(sc, k)
    scaledT.hp = sc.hp * k; scaledT.spd = sc.spd; scaledT.dmg = sc.dmg
    return scaledT
end

local function rollShiny(dex)
    if not G.Sprites.hasShiny(dex) then return false end
    if forceShiny > 0 then forceShiny = forceShiny - 1 return true end
    return random() < S.SHINY_RATE
end

local function spawnOne(pl, t, angle)
    local def = U.pick(G.Stages.active() and G.Stages.bagAt(t) or G.Enemies.bagAt(t))
    local x, y = freePoint(pl, angle or (random() * 6.2832), G.Sprites.hovers(def.dex))
    if not x then return nil end
    local shiny = rollShiny(def.dex)
    local e = G.Enemy.new(def, x, y, scaled(G.Enemies.scale(t), hpK(t)))
    e.dmg = e.dmg * DMG_K; e.xp = U.round(e.xp * XP_K)
    if G.EnemyMgr.count() >= S.CAP * ELITE_FROM then
        e.maxHp = U.round(e.maxHp * 1.6); e.hp = e.maxHp; e.dmg = e.dmg * 1.25; e.xp = U.round(e.xp * 1.6)
    end
    if shiny then e:makeShiny() end
    if G.Events.golden then e:makeGolden() end
    G.EnemyMgr.add(e)
    if shiny then
        S.say('¡Un ' .. e.name .. ' shiny anda cerca!', 3.4)
        G.Audio.sfx('shiny')
    end
    return e
end

local function spawnBoss(pl, t, b)
    local x, y = ringPoint(pl, random() * 6.2832)
    local e = G.Enemy.new(b, x, y, scaled(G.Enemies.bossScale(t), 1), true)
    if rollShiny(b.dex) then e:makeShiny() end
    G.EnemyMgr.add(e)
    if b.final then G.Stages.setFinalBoss(e) end
    S.say('¡' .. e.name .. (e.shiny and ' shiny' or '') .. (b.final and ' (jefe final)' or ' salvaje') .. ' apareció!', 3.2)
    G.Camera.kick(1.1)
    G.Audio.sfx('boss')
    return e
end

-- Hojas de sprites: conservar el compañero, los enemigos vivos y los que vienen pronto.
local function gcSprites(pl, t)
    for k in pairs(keep) do keep[k] = nil end
    for k in pairs(keepFull) do keepFull[k] = nil end
    keep[pl.dex] = true
    keepFull[pl.dex] = true
    local stage = G.Stages.active()
    local up = stage and G.Stages.upcomingDex(t, 60) or G.Enemies.upcomingDex(t, 60)
    for i = 1, #up do keep[up[i]] = true end
    local all = G.EnemyMgr.all()
    for i = 1, #all do keep[all[i].dex] = true end
    local bosses = stage and G.Stages.bosses() or G.Enemies.BOSSES()
    for i = 1, #bosses do if bosses[i].at <= t + 60 then keep[bosses[i].dex] = true end end
    G.Sprites.gc(keep, keepFull)
end

function S.update(dt, pl, t)
    if announceT > 0 then announceT = announceT - dt end
    S.tickZone(dt)
    -- En la arena de la grieta no sale nada más (y el reloj de jefes espera).
    if G.Rift.inArena() then return end

    local stage = G.Stages.active()

    -- Precarga lo que va a salir en el próximo minuto y descarga lo viejo.
    preloadT = preloadT - dt
    if preloadT <= 0 then
        preloadT = 10
        G.Sprites.preload(stage and G.Stages.upcomingDex(t, 60) or G.Enemies.upcomingDex(t, 60), false)
    end
    gcT = gcT - dt
    if gcT <= 0 then gcT = 10; gcSprites(pl, t) end

    -- Jefes
    local bosses = stage and G.Stages.bosses() or G.Enemies.BOSSES()
    local b = bosses[bossIdx]
    if b and t >= b.at then spawnBoss(pl, t, b); bossIdx = bossIdx + 1 end

    -- Combate de jefe: las oleadas bajan al 25% y no hay mareas.
    local bossFight = G.EnemyMgr.bossAlive()
    local cap = stage and G.Stages.cap(t) or S.CAP
    local rate = (stage and G.Stages.rate(t) or S.rate(t)) * G.Difficulty.get().rate

    -- Goteo normal
    if G.EnemyMgr.count() < cap then
        acc = acc + rate * (bossFight and 0.25 or 1) * dt
        local n = floor(acc)
        acc = acc - n
        while n > 0 and G.EnemyMgr.count() < cap do
            spawnOne(pl, t)
            n = n - 1
        end
    end

    -- Marea
    if not bossFight then surgeT = surgeT - dt end
    if surgeT <= 0 then
        surgeT = U.rand(38, 56)
        local base = random() * 6.2832
        local n = min(cap - G.EnemyMgr.count(), U.round((14 + floor(t / 22)) * 0.4))
        for i = 1, n do spawnOne(pl, t, base + U.rand(-0.55, 0.55)) end
        S.say('¡Marea de Pokémon!', 2.2)
        G.Audio.sfx('surge')
    end
end

-- Unos cuantos de golpe desde un lado (al empezar una horda).
function S.burst(n)
    local pl, t = G.Game.player(), G.Game.time()
    if not pl then return end
    local base = random() * 6.2832
    for i = 1, n do
        if G.EnemyMgr.count() >= S.CAP + 10 then break end
        spawnOne(pl, t, base + U.rand(-0.6, 0.6))
    end
end

-- Un rezagado vuelve a salir por delante del jugador, fuera de la vista.
-- Devuelve false si no hay sitio (entonces se quita).
function S.ahead(e, pl)
    local sp = U.hypot(pl._vx or 0, pl._vy or 0)
    local a0 = sp > 20 and math.atan2(pl._vy, pl._vx) or (random() * 6.2832)
    local x, y = freePoint(pl, a0 + U.rand(-0.9, 0.9), e.flying)
    if not x then return false end
    e.x = x; e.y = y; e.kx = 0; e.ky = 0
    e.phase = 'walk'; e.pt = 0; e.jump = nil; e.jumpLift = 0
    return true
end

-- Aviso grande en pantalla (también lo usan el bioma y los shinies).
function S.say(text, secs, local_)
    announce = text; announceT = secs or 2.6
end

-- Cartel de zona (nombre del bioma o de la fase): lo dibuja la interfaz superior.
local zoneText, zoneT = nil, 0
local ZONE_DUR = 3.5
function S.sayZone(text) zoneText = text; zoneT = ZONE_DUR end
function S.zone()
    if zoneT <= 0 then return nil end
    return zoneText, zoneT, ZONE_DUR
end
function S.tickZone(dt) if zoneT > 0 then zoneT = zoneT - dt end end

local bannerT = {}
function S.banner()
    if announceT > 0 then bannerT.text = announce; bannerT.t = announceT return bannerT end
    return nil
end

function S.debugForceShiny(n) forceShiny = n or 1 end
