-- rift.lua — grietas y arena del legendario. Port de js/systems/rift.js.
--
-- De vez en cuando (pocas veces por partida) se abre una GRIETA cerca de ti.
-- Dura TTL segundos; si entras, te lleva a una arena cerrada en el Mundo
-- Distorsión, contra un Pokémon LEGENDARIO.
--
--   ganas    el legendario suelta tickets (el ×10, la mitad de las veces) y
--            monedas, y te llevas un VÍNCULO
--            (fusiona movimientos, ver Player.fuse); a los pocos segundos vuelves
--            al mapa donde estabas y se elige la fusión
--   pierdes  (caes o se acaba el tiempo) vuelves sin premio, con algo de vida;
--            la partida sigue
--
-- Mientras dura la arena, los enemigos del mapa se guardan (EnemyMgr.stash) y
-- no aparecen nuevos; al volver todo sigue como estaba.
--
--   G.Rift.reset()  update(dt, pl, t)  drawable() -> { y, draw } o nil
--   G.Rift.inArena() -> bool   rift() -> { x, y, ttl, t } o nil   arena() -> tabla o nil
--   G.Rift.timeLeft()          arrow() -> x, y, dist, timeLeft (o nil): flecha hacia la grieta
--   G.Rift.enter()             entra ya en la arena (si no estás en una)
--   G.Rift.leave()             abandona la arena (cuenta como perdida)
--   G.Rift.debugOpen()  debugArena(type)  debugNextType(type)
local U = G.U
local R = {}
G.Rift = R

local floor, min, max, cos, sin, random = math.floor, math.min, math.max, math.cos, math.sin, love.math.random
local lg = love.graphics

-- (0.14 hasta el 11-10-2026: más grietas para que se vean los vínculos)
-- Menos azar (12-10-2026): cada vez que no sale, la siguiente es más
-- probable (20 %, 40 %, 60 %, 80 %, 100 %): como mucho 2,5 min sin grieta.
local CHECK, CHANCE, TTL = 30, 0.2, 45
local ARENA_R, ARENA_TIME, FROM = 11, 120, 75
R.TTL, R.ARENA_TIME = TTL, ARENA_TIME

local rift = nil           -- { x, y, ttl, t }
local arena = nil          -- { tx, ty, r, dex, shiny, type, x, y, backX, backY, biome, t, phase, endT, bossId }
local checkT, asked, downT = CHECK, false, 0
local misses = 0           -- intentos seguidos sin grieta (cada uno la hace más probable)
local nextType = nil       -- pruebas/vídeos: tipo de la próxima arena
local legendPool = nil     -- legendarios con sprite (se calcula una vez)

-- Clima de cada arena (como ARENA_THEMES[type].weather en tiles.js). Si
-- data/tiles.lua trae G.Tiles.ARENA_THEMES, se usa ese.
local ARENA_WEATHER = { fire = 'sun', water = 'rain', electric = 'rain', ice = 'snow',
                        ground = 'sand', rock = 'sand', ghost = 'fog' }
local RANGED_TYPES = { psychic = true, electric = true, ghost = true, fairy = true,
                       fire = true, water = true, ice = true, dragon = true }

local function TS() return ((G.Tiles and G.Tiles.T) or 16) * G.Sprites.PX end

function R.reset()
    rift = nil; arena = nil
    checkT = CHECK; asked = false; downT = 0; misses = 0
end

-- ---------------- grieta en el mapa ----------------

local PX_OPTS = { vy = -40, life = 0.6 }

local function show(x, y, ttl)
    rift = { x = x, y = y, ttl = ttl, t = 0 }
    asked = false
    -- (El aviso grande lo dibuja la interfaz mientras rift.t < 4,5 s.)
    G.Audio.sfx('rift')
    G.FX.ring(x, y, 6, 80, '#b48aff', 0.7, 5)
end

local function open()
    local pl = G.Game.player()
    if not pl then return end
    for _ = 1, 24 do
        local a = random() * 6.2832
        local d = U.rand(380, 560)
        local x, y = pl.x + cos(a) * d, pl.y + sin(a) * d * 0.85
        if G.World.isFree(x, y, 22) then
            show(x, y, TTL)
            return
        end
    end
end

local start   -- (definida abajo)

local function enter()
    if asked then return end
    asked = true
    start()
end

-- ---------------- arena ----------------

local function pool(forceType)
    if not legendPool then
        legendPool = {}
        for i = 1, #G.DEX do
            local p = G.DEX[i]
            if p.leg and G.Sprites.meta(p.dex) then legendPool[#legendPool + 1] = p end
        end
    end
    if forceType then
        local f = {}
        for i = 1, #legendPool do
            if U.contains(legendPool[i].types, forceType) then f[#f + 1] = legendPool[i] end
        end
        if #f > 0 then return f end
    end
    return legendPool
end

local function arenaWeather(type)
    local th = G.Tiles and G.Tiles.ARENA_THEMES and G.Tiles.ARENA_THEMES[type]
    if th then return th.weather end
    return ARENA_WEATHER[type]
end

-- Viaje a la arena: guarda el mapa, cambia el bioma y te coloca al sur.
local function begin(cfg)
    local pl = G.Game.player()
    local ts = TS()
    arena = {
        tx = cfg.tx, ty = cfg.ty, r = cfg.r, dex = cfg.dex, shiny = cfg.shiny, type = cfg.type,
        x = cfg.tx * ts + ts / 2, y = cfg.ty * ts + ts / 2,
        backX = pl.x, backY = pl.y, biome = G.World.biome(),
        t = 0, phase = 'fight', endT = 0, bossId = 0
    }
    rift = nil; asked = false; downT = 0
    G.EnemyMgr.stash()
    G.Projectiles.clear()
    G.Combat.clearFields()
    G.Hazards.clear()
    G.World.setArena({ tx = cfg.tx, ty = cfg.ty, r = cfg.r, type = cfg.type })
    G.World.setBiome(G.Tiles.arenaBiome(cfg.type), true)
    -- Cada arena trae su clima (el volcán, sol; el glaciar, nieve...).
    local wx = arenaWeather(cfg.type)
    if wx then G.Weather.force(wx, ARENA_TIME + 15) end
    -- Tú al sur de la arena; el legendario aparece al norte.
    pl.x = arena.x; pl.y = arena.y + ts * 3
    G.Camera.x = pl.x; G.Camera.y = pl.y
    G.Game.flash('#c9a6ff', 0.9)
    G.Audio.sfx('rift')
    G.Spawner.sayZone('Grieta · ' .. ((G.Tiles.ARENA_THEMES[arena.type] or {}).name or ''))
end

local function spawnLegend()
    local mon = G.DEX_BY[arena.dex]
    local t = G.Game.time()
    local ts = TS()
    local ranged = false
    for i = 1, #mon.types do if RANGED_TYPES[mon.types[i]] then ranged = true end end
    local lk = G.Enemies.late(t)             -- tiempo extra (ver G.Enemies.late)
    local dk = lk ^ 0.7
    local def = {
        dex = mon.dex, name = mon.name,
        hp = U.round((3200 + t * 9) * lk),
        spd = U.round(U.clamp(48 + (mon.spd - 78) * 0.6, 48, 105)),
        dmg = U.round((36 + t / 20) * dk), xp = U.round(500 + t * 1.2),
        behavior = ranged and 'ranged' or 'charger',
        shotDmg = U.round((18 + t / 40) * dk), shotCd = 0.9, range = 300
    }
    local e = G.Enemy.new(def, arena.x, arena.y - ts * 3.5, { hp = 1, spd = 1, dmg = 1 }, true)
    e.legend = true
    -- Choca con las paredes y columnas como tú: si volara por encima de las
    -- rocas, tus disparos no podrían alcanzarle (bug de Celebi).
    e.flying = false
    if arena.shiny then e:makeShiny() end
    G.EnemyMgr.add(e)
    arena.bossId = e.id
    G.Spawner.say('¡' .. e.name .. (e.shiny and ' shiny' or '') .. ' te esperaba en la grieta!', 3.2)
    G.Camera.kick(1.1)
    G.Audio.sfx('boss')
end

-- Elige legendario y lugar, y empieza.
start = function(forceType)
    if arena then return end
    forceType = forceType or nextType
    nextType = nil
    local list = pool(forceType)
    if #list == 0 then return end
    -- Los legendarios que aún no has vencido salen 4 veces más (menos repetidos).
    -- (Las claves de `legends` pueden ser números o textos si vienen del JSON.)
    local beaten = (G.DB.save and G.DB.save.legends) or {}
    local function weight(p)
        if beaten[p.dex] ~= nil or beaten[tostring(p.dex)] ~= nil then return 1 end
        return 4
    end
    local total = 0
    for i = 1, #list do total = total + weight(list[i]) end
    local r, mi = random() * total, 1
    while mi < #list do
        r = r - weight(list[mi])
        if r <= 0 then break end
        mi = mi + 1
    end
    local mon = list[mi]
    local type = forceType
    if not type then
        -- La arena es la de uno de sus tipos, al azar (y que exista como arena).
        type = U.pick(mon.types)
        local types = G.Tiles and G.Tiles.ARENA_TYPES
        if types and not U.contains(types, type) then type = 'normal' end
    end
    local cfg = {
        tx = 5000 + floor(random() * 3000), ty = 5000 + floor(random() * 3000), r = ARENA_R,
        dex = mon.dex, shiny = G.Sprites.hasShiny(mon.dex) and random() < 1 / 512,
        type = type
    }
    begin(cfg)
    spawnLegend()
end

-- Nadie sale del círculo de la arena (por si algo empuja demasiado).
local function keepInside()
    local ts = TS()
    local lim = (arena.r - 1.4) * ts
    local all = G.EnemyMgr.all()
    for i = 1, #all do
        local e = all[i]
        local dx, dy = e.x - arena.x, e.y - arena.y
        local d = U.hypot(dx, dy)
        if d > lim then e.x = arena.x + dx / d * lim; e.y = arena.y + dy / d * lim end
    end
end

local function won()
    if not arena or arena.phase ~= 'fight' then return end
    arena.phase = 'won'; arena.endT = 5
    G.Progress.event('rift', { type = arena.type })
    G.Pickups.pullAll()
    G.Spawner.say('¡Has vencido a ' .. G.DEX_BY[arena.dex].name .. '! Recoge el premio…', 3.4, true)
    G.Audio.sfx('legend')
    local pl = G.Game.player()
    if pl then
        pl.bonds = pl.bonds + 1
        G.FX.dmgText(pl.x, pl.y - pl.bodyH - 10, '¡Vínculo!', '#ff8ad8', true)
        G.FX.ring(pl.x, pl.y, 8, 90, '#ff8ad8', 0.7, 5)
    end
end

local function lost()
    if not arena or arena.phase ~= 'fight' then return end
    arena.phase = 'lost'; arena.endT = 1.2
    G.Spawner.say('La grieta te ha expulsado…', 2.6, true)
    G.Audio.sfx('back')
end

-- Vuelta al mapa.
local function finish()
    local pl = G.Game.player()
    local a = arena
    arena = nil
    G.World.setArena(nil)
    G.World.setBiome(a.biome, true)
    G.Weather.clear()
    G.EnemyMgr.restore()
    G.Projectiles.clear()
    G.Combat.clearFields()
    G.Hazards.clear()
    pl.x = a.backX; pl.y = a.backY
    if pl.dead then pl:revive(0.3) end
    G.Camera.x = pl.x; G.Camera.y = pl.y
    G.Game.flash('#c9a6ff', 0.8)
    local st = G.Stages and G.Stages.current()
    G.Spawner.sayZone(st and st.name or G.World.biomeName())
    if pl.bonds > 0 and G.Game.offerBond then G.Game.offerBond() end
end

local function arenaTick(dt, pl)
    arena.t = arena.t + dt
    if arena.phase == 'fight' then
        keepInside()
        local boss = G.EnemyMgr.get(arena.bossId)
        if not boss or boss.dead then won() return end
        downT = pl.dead and (downT + dt) or 0
        if downT > 1.4 or arena.t > ARENA_TIME then lost() end
        return
    end
    arena.endT = arena.endT - dt
    if arena.endT <= 0 then finish() end
end

function R.update(dt, pl, time)
    if rift then
        rift.t = rift.t + dt
        rift.ttl = rift.ttl - dt
        if rift.ttl <= 0 then rift = nil return end
        if not arena and not pl.dead and U.dist2(pl.x, pl.y, rift.x, rift.y - 10) < 30 * 30 then enter() end
        -- Chispas que suben de la grieta.
        if rift and random() < 0.3 then
            G.FX.px(rift.x + U.rand(-14, 14), rift.y - U.rand(10, 80), '#d9c2ff', PX_OPTS)
        end
    elseif not arena and time > FROM and not (G.Judgment.applies() and time >= G.Judgment.AT - 120) then
        -- (Desde 2 min antes de la Sentencia de Arceus ya no se abren grietas.)
        checkT = checkT - dt
        if checkT <= 0 then
            checkT = CHECK
            -- Con un jefe vivo no cuenta como intento.
            if not G.EnemyMgr.bossAlive() then
                if random() < CHANCE * (1 + misses) then misses = 0; open()
                else misses = misses + 1 end
            end
        end
    end
    if arena then arenaTick(dt, pl) end
end

-- ---------------- dibujo ----------------

local poly = {}           -- vértices reutilizados
local drawableT = { y = 0 }

-- La grieta: una raja violeta vertical que late (4 fotogramas), con su halo.
function drawableT.draw()
    local r = rift
    if not r then return end
    local fadeIn, fadeOut = min(1, r.t * 2), min(1, r.ttl / 1.5)
    local a = fadeIn * fadeOut
    local f = floor(r.t * 8) % 4
    local h = 60 + f * 3
    local x, y = r.x, r.y
    U.setColor('#7b3cff', 0.25 * a)
    lg.ellipse("fill", x, y, 34, 12)
    poly[1], poly[2] = x - 7, y - h * 0.5
    poly[3], poly[4] = x + 1, y - h
    poly[5], poly[6] = x + 9, y - h * 0.55
    poly[7], poly[8] = x + 4, y - 4
    poly[9], poly[10] = x - 3, y - 8
    poly[11], poly[12] = x - 10, y - h * 0.4
    U.setColor('#2a1452', 0.95 * a)
    lg.polygon("fill", poly)
    U.setColor('#b48aff', 0.9 * a)
    lg.setLineWidth(2)
    lg.polygon("line", poly)
    U.setColor('#ffffff', 0.6 * a)
    lg.line(x, y - h * 0.9, x - 1, y - 12)
    lg.setLineWidth(1)
    lg.setColor(1, 1, 1, 1)
end

-- La grieta, para ordenarla por Y con el resto de la escena (tabla reutilizada).
function R.drawable()
    if not rift then return nil end
    drawableT.y = rift.y
    return drawableT
end

-- Datos para la flecha de la interfaz: x, y (mundo), distancia al jugador y
-- segundos que le quedan a la grieta; nil si no hay grieta (o ya estás dentro).
function R.arrow()
    if not rift or arena then return nil end
    local pl = G.Game.player()
    local d = pl and U.dist(pl.x, pl.y, rift.x, rift.y) or 0
    return rift.x, rift.y - 10, d, max(0, rift.ttl)
end

-- ---------------- estado ----------------

function R.inArena() return arena ~= nil end
function R.rift() return rift end
function R.arena() return arena end
function R.timeLeft() return arena and max(0, ARENA_TIME - arena.t) or 0 end
-- Fase de la arena: 'fight' | 'won' | 'lost' | nil
function R.phase() return arena and arena.phase or nil end

-- Entra ya en la arena (si no estás en una). Si hay grieta abierta, la cierra.
function R.enter() if not arena then start() end end

-- Abandona la arena: cuenta como perdida y vuelves enseguida.
function R.leave()
    if not arena then return end
    if arena.phase == 'fight' then lost() end
    arena.endT = 0
end

function R.debugOpen() open() end
-- Para pruebas: arena de un tipo ya.
function R.debugArena(type) start(type) end
-- Para vídeos: la próxima grieta en la que entres será de este tipo.
function R.debugNextType(type) nextType = type end
