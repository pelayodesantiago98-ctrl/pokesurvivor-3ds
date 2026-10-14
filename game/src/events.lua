-- events.lua — eventos a mitad de partida y duendes del tesoro.
-- Port de js/systems/events.js (sin cooperativo).
--
-- Cada 4-5 minutos (nunca con un jefe vivo ni en la grieta) pasa uno de estos:
--
--   horde   Horda de un tipo: 30 s en los que todos los que salen son de un
--           mismo tipo (si tu tipo les gana, es tu momento)
--   gold    Hora dorada: 30 s de enemigos dorados que dan el doble de
--           experiencia y a veces sueltan monedas
--   lost    Pokémon perdido: lo tocas, te sigue y lo llevas hasta la marca.
--           Los enemigos le hacen daño; si cae (o tardas más de 2 min), se va.
--           Premio: cura la mitad de la vida, monedas, un ticket y, 1 de cada
--           5 veces, se une a tu colección.
--
-- Duendes del tesoro (1-2 por partida, ver Enemy behavior 'thief'): un
-- Meowth cargado de monedas (o, 1 de cada 4, un Gholdengo con un ticket ×10)
-- que huye y se escapa a los 15 s si no lo atrapas.
--
--   G.Events.reset()  update(dt, pl, t)  drawables() -> lista { {y, draw}, ... } (reutilizada)
--   G.Events.bag() -> defs de la horda o nil (lo usa G.Enemies.bagAt)
--   G.Events.golden      CAMPO booleano: ¿hora dorada en curso?   G.Events.isGolden()
--   G.Events.current() -> 'horde' | 'gold' | 'lost' | nil
--   G.Events.info() -> id, segundosQueQuedan, tipo (para el rótulo de la interfaz) o nil
--   G.Events.lost() -> tabla del Pokémon perdido o nil
--   G.Events.lostArrow() -> x, y, etiqueta, dist (flecha hacia el perdido o la marca) o nil
local U = G.U
local E = {}
G.Events = E

local min, max, abs, sin, cos, atan2, random = math.min, math.max, math.abs, math.sin, math.cos, math.atan2, love.math.random
local lg = love.graphics

local EVERY0, EVERY1, DUR, LOST_TIME = 240, 300, 30, 120
local THIEF_FIRST0, THIEF_FIRST1, THIEF_NEXT0, THIEF_NEXT1, THIEF_LIFE = 120, 240, 240, 360, 15
local INF = math.huge

local nextT, cur, last, thiefT, thieves = 0, nil, nil, 0, 0
local curT = { id = nil, t = 0, dur = 0, type = nil, defs = nil }     -- tabla reutilizada
local lost = nil          -- { dex, name, x, y, hp, maxHp, state, tx, ty, t, anim, r, hitCd, grant, flash, moving }
local lostPool = nil      -- candidatos a perderse (se calcula una vez)
E.golden = false

-- Sorteo adelantado: PRE_T segundos antes de cada evento se decide cuál toca (y qué
-- Pokémon salen) y sus hojas de sprites se van cargando de una en una
-- (G.Sprites.preloadSoon). Antes se cargaban todas de golpe al empezar: en la 3DS,
-- ~40 ms por hoja, y una horda trae 4 (un tirón de 0,2 s).
local PRE_T = 6
local pre = { id = nil, type = nil, defs = nil, mon = nil, t = 0 }
local preDex = {}
local THIEF_DEX = { 52, 1000 }   -- Meowth y Gholdengo (duendes del tesoro)
local thiefPre = false

local function clearPre()
    pre.id, pre.type, pre.defs, pre.mon = nil, nil, nil, nil
    for i = #preDex, 1, -1 do preDex[i] = nil end
end

function E.reset()
    nextT = U.rand(EVERY0, EVERY1)
    cur = nil; last = nil; lost = nil
    thiefT = U.rand(THIEF_FIRST0, THIEF_FIRST1); thieves = 0
    E.golden = false
    clearPre(); thiefPre = false
end

local function say(text, secs) G.Spawner.say(text, secs, true) end

local function setCur(id, dur, type, defs)
    curT.id = id; curT.t = 0; curT.dur = dur; curT.type = type; curT.defs = defs
    cur = curT
    E.golden = (id == 'gold')
end

local function endEvent()
    if not cur then return end
    cur = nil
    E.golden = false
end

local function announce()
    if not cur then return end
    if cur.id == 'horde' then say('¡Horda de tipo ' .. U.TYPE_NAME[cur.type] .. '!', 3)
    elseif cur.id == 'gold' then say('¡Hora dorada! Doble de experiencia', 3)
    elseif lost then say('¡Un ' .. lost.name .. ' se ha perdido! Búscalo y llévalo a la marca', 3.4) end
    G.Audio.sfx(cur.id == 'gold' and 'shiny' or 'surge')
end

-- ---------------- Pokémon perdido ----------------

local function makeLost(o)
    local mon = G.DEX_BY[o.dex]
    lost = {
        dex = o.dex, name = mon and mon.name or '', x = o.x, y = o.y, tx = o.tx, ty = o.ty,
        hp = o.hp, maxHp = 100, state = o.state, grant = o.grant,
        t = 0, hitCd = 0, flash = 0, moving = false,
        anim = G.Sprites.Animator.new(o.dex, 1), r = G.Sprites.bodyRadius(o.dex)
    }
end

local function getLostPool()
    if not lostPool then
        lostPool = {}
        for i = 1, #G.DEX do
            local p = G.DEX[i]
            if p.rarity <= 3 and not p.leg and G.Sprites.meta(p.dex) and not G.Sprites.hovers(p.dex) then
                lostPool[#lostPool + 1] = p
            end
        end
    end
    return lostPool
end

--- @param mon  el Pokémon ya sorteado (sorteo adelantado) o nil
local function spawnLost(pl, mon)
    local pool = getLostPool()
    if #pool == 0 then return false end
    mon = mon or U.pick(pool)
    local ax, ay, bx, by = nil, nil, nil, nil
    for _ = 1, 20 do
        local a = random() * 6.2832
        local d = U.rand(220, 300)
        local x, y = pl.x + cos(a) * d, pl.y + sin(a) * d * 0.8
        if G.World.isFree(x, y, 16) then ax, ay = x, y break end
    end
    if not ax then return false end
    for _ = 1, 30 do
        local a = random() * 6.2832
        local d = U.rand(700, 850)
        local x, y = ax + cos(a) * d, ay + sin(a) * d * 0.85
        if G.World.isFree(x, y, 30) then bx, by = x, y break end
    end
    if not bx then return false end
    makeLost({ dex = mon.dex, x = ax, y = ay, tx = bx, ty = by, state = 'wait', hp = 100, grant = random() < 0.2 })
    G.Sprites.preload({ mon.dex })
    return true
end

-- Cura, y si toca, el Pokémon se une a tu colección.
local function reward(dex, grant)
    local pl = G.Game.player()
    if pl and not pl.dead then
        pl:heal(pl.maxHp * 0.5)
        G.FX.ring(pl.x, pl.y, 6, 70, '#5fe08a', 0.5, 3)
    end
    local mon = G.DEX_BY[dex]
    local name = mon and mon.name or ''
    if lost then G.FX.burst(lost.tx, lost.ty - 10, '#7dffb0', 24, 180)
    elseif pl then G.FX.burst(pl.x, pl.y, '#7dffb0', 24, 180) end
    G.Audio.sfx('legend')
    if grant and G.Game.onRescue then G.Game.onRescue(dex, name)
    else say('¡Has llevado a ' .. name .. ' a casa! Te lo agradece', 3.2) end
end

local function rescued()
    local L = lost
    for _ = 1, 12 do G.Pickups.drop('coin', L.tx + U.rand(-40, 40), L.ty + U.rand(-30, 30), 5) end
    G.Pickups.drop('ticket', L.tx, L.ty - 12, 1)
    reward(L.dex, L.grant)
    lost = nil
    endEvent()
end

local function gone(msg)
    say(msg, 3)
    lost = nil
    endEvent()
end

local function lostTick(dt, pl)
    local L = lost
    L.t = L.t + dt
    L.anim:update(dt)

    if L.state == 'wait' then
        local rr = pl.r + L.r + 18
        if not pl.dead and U.dist2(pl.x, pl.y, L.x, L.y) < rr * rr then
            L.state = 'follow'
            say('¡' .. L.name .. ' te sigue! Llévalo a la marca verde', 3)
            G.Audio.sfx('confirm')
        end
        L.moving = false
    else
        local d = U.dist(L.x, L.y, pl.x, pl.y)
        local keep = pl.r + L.r + 14
        L.moving = d > keep
        if L.moving then
            local sp = min(d - keep, max(120, pl:spd() * 1.15) * dt)
            local nx, ny = U.norm(pl.x - L.x, pl.y - L.y)
            L.x = L.x + nx * sp; L.y = L.y + ny * sp
            G.World.collide(L)
            L.anim.dir = G.Sprites.dirFromAngle(atan2(ny, nx))
        end
        if U.dist2(L.x, L.y, L.tx, L.ty) < 56 * 56 then rescued() return end
    end
    L.anim:loop(L.moving and 'Walk' or 'Idle')

    -- Los enemigos que lo tocan le hacen daño.
    L.hitCd = L.hitCd - dt
    if L.hitCd <= 0 then
        local hits = G.EnemyMgr.queryCircle(L.x, L.y, L.r)
        local dmg, n = 0, 0
        for i = 1, #hits do
            local e = hits[i]
            if not e.dead and e.behavior ~= 'thief' then n = n + 1; dmg = dmg + 4 + e.dmg * 0.12 end
        end
        if n > 0 then
            L.hitCd = 0.5
            L.hp = L.hp - min(30, dmg)
            L.flash = 0.1
            G.FX.burst(L.x, L.y - 10, '#ff5f6d', 4, 60)
            if L.hp <= 0 then gone('¡' .. L.name .. ' se ha asustado y ha huido…!') return end
        end
    end
    if L.flash > 0 then L.flash = L.flash - dt end
    if L.t > LOST_TIME then gone(L.name .. ' se ha cansado de esperar y se ha ido…') end
end

-- ---------------- duende del tesoro ----------------

local function spawnThief(pl, time)
    local gold = random() < 0.25
    local dex = gold and 1000 or 52
    local mon = G.DEX_BY[dex]
    if not mon or not G.Sprites.meta(dex) then
        -- Sin Gholdengo: Meowth.
        dex = 52; gold = false; mon = G.DEX_BY[dex]
        if not mon or not G.Sprites.meta(dex) then return end
    end
    G.Sprites.preload({ dex })
    local def = { dex = dex, name = mon.name, behavior = 'thief',
                  hp = U.round(60 * (1 + time / 95) * (gold and 1.5 or 1)),
                  spd = 92, dmg = 0, xp = 10, loot = gold and 'ticket10' or 'coins' }
    for _ = 1, 12 do
        local a = random() * 6.2832
        local d = U.rand(230, 300)
        local x, y = pl.x + cos(a) * d, pl.y + sin(a) * d * 0.8
        if G.World.isFree(x, y, 14) then
            local e = G.Enemy.new(def, x, y, { hp = 1, spd = 1, dmg = 1 }, false)
            e.life = THIEF_LIFE
            G.EnemyMgr.add(e)
            G.FX.ring(x, y, 4, 40, '#ffd23f', 0.5, 3)
            G.Spawner.say(gold and ('¡Un ' .. mon.name .. ' con un ticket ×10! ¡Atrápalo antes de que huya!')
                               or ('¡Un ' .. mon.name .. ' cargado de monedas! ¡Atrápalo antes de que huya!'), 3.2)
            G.Audio.sfx('shiny')
            return
        end
    end
end

-- ---------------- ciclo ----------------

-- Sorteo de la horda: tipo y Pokémon (type, defs) o nil si no hay tipo posible.
local function rollHorde(time)
    local types = G.Enemies.hordeTypes(time)
    if #types == 0 then return nil end
    local type = U.pick(types)
    return type, G.Enemies.hordeDefs(type, time)
end

-- Qué evento toca (nunca el mismo dos veces seguidas).
local function pickId()
    local ids = {}
    if last ~= 'horde' then ids[#ids + 1] = 'horde' end
    if last ~= 'gold' then ids[#ids + 1] = 'gold' end
    if last ~= 'lost' then ids[#ids + 1] = 'lost' end
    return U.pick(ids)
end

-- Sortea ya el próximo evento y pone a cargar sus hojas (una por fotograma).
local function preRoll(time)
    clearPre()
    pre.id = pickId(); pre.t = time
    if pre.id == 'horde' then
        pre.type, pre.defs = rollHorde(time)
        if pre.defs then for i = 1, #pre.defs do preDex[i] = pre.defs[i].dex end end
    elseif pre.id == 'lost' then
        local pool = getLostPool()
        if #pool > 0 then pre.mon = U.pick(pool); preDex[1] = pre.mon.dex end
    end
    if #preDex > 0 then G.Sprites.preloadSoon(preDex, false) end
end

local function start(id, time, pl)
    last = id
    if id == 'horde' then
        local type, defs = pre.type, pre.defs
        if not defs then type, defs = rollHorde(time) end
        if not defs then return start('gold', time, pl) end
        local dexes = {}
        for i = 1, #defs do dexes[i] = defs[i].dex end
        G.Sprites.preload(dexes)          -- (ya cargadas si dio tiempo: no cuesta nada)
        setCur(id, DUR, type, defs)
        G.Spawner.burst(6)
    elseif id == 'gold' then
        setCur(id, DUR, nil, nil)
        local all = G.EnemyMgr.all()
        for i = 1, #all do all[i]:makeGolden() end
    else
        if not spawnLost(pl, pre.mon) then return end
        setCur(id, INF, nil, nil)
    end
    announce()
end

function E.update(dt, pl, time)
    if cur then
        cur.t = cur.t + dt
        if cur.id ~= 'lost' and cur.t >= cur.dur then endEvent() end
    end
    if lost then lostTick(dt, pl) end
    if G.Rift.inArena() or G.Judgment.active() then return end

    if thieves < 2 then
        thiefT = thiefT - dt
        -- (Sus hojas, unos segundos antes y de una en una.)
        if thiefT <= PRE_T and not thiefPre then thiefPre = true; G.Sprites.preloadSoon(THIEF_DEX, false) end
        if thiefT <= 0 then
            if G.EnemyMgr.bossAlive() then thiefT = 8
            else
                spawnThief(pl, time)
                thieves = thieves + 1
                thiefT = U.rand(THIEF_NEXT0, THIEF_NEXT1)
                thiefPre = false
            end
        end
    end

    if cur then return end
    nextT = nextT - dt
    -- Sorteo adelantado (otra vez si el evento se retrasó mucho por un jefe).
    if nextT <= PRE_T and (not pre.id or time - pre.t > 30) then preRoll(time) end
    if nextT > 0 then return end
    if G.EnemyMgr.bossAlive() then nextT = 10 return end
    nextT = U.rand(EVERY0, EVERY1)
    start(pre.id or pickId(), time, pl)
    clearPre()
end

-- Lo que sale durante una horda (lo usa G.Enemies.bagAt).
function E.bag()
    if cur and cur.id == 'horde' and cur.defs and #cur.defs > 0 then return cur.defs end
    return nil
end

--- Marca en `keep` ({dex=true}) las hojas que los eventos necesitan pronto o ya
--- (el perdido, lo sorteado por adelantado, los duendes a punto de salir), para
--- que el spawner no las suelte (y se vuelvan a cargar de golpe).
function E.keepDex(keep)
    if lost then keep[lost.dex] = true end
    for i = 1, #preDex do keep[preDex[i]] = true end
    if thiefPre then for i = 1, #THIEF_DEX do keep[THIEF_DEX[i]] = true end end
end

function E.isGolden() return E.golden end
function E.current() return cur and cur.id or nil end
function E.lost() return lost end

-- Para el rótulo de la interfaz: id, segundos que quedan (entero) y tipo (horda).
function E.info()
    if not cur or cur.id == 'lost' then return nil end
    return cur.id, max(0, math.ceil(cur.dur - cur.t)), cur.type
end

-- Flecha hacia el Pokémon perdido (o hacia la marca, si ya te sigue):
-- x, y (mundo), etiqueta y distancia en metros (32 unidades); nil si no hay.
function E.lostArrow()
    local L = lost
    if not L then return nil end
    local pl = G.Game.player()
    local x, y, label
    if L.state == 'wait' then x, y, label = L.x, L.y - 10, L.name
    else x, y, label = L.tx, L.ty, 'Marca' end
    local d = pl and U.round(U.dist(pl.x, pl.y, x, y) / 32) or 0
    return x, y, label, d
end

-- ---------------- dibujo ----------------

local EMPTY = {}
local drawOpts = { flash = false }
local goalD = { y = 0 }
local monD = { y = 0 }
local both = { goalD, monD }

-- La marca verde (en el suelo, debajo de todo).
function goalD.draw()
    local L = lost
    if not L then return end
    local now = U.now()
    local k = 0.5 + sin(now * 4) * 0.5
    U.setColor('#5fe08a', 0.25 + k * 0.15)
    G.Sprites.ellipse(L.tx, L.ty, 56, 40)
    U.setColor('#7dffb0', 0.9)
    lg.setLineWidth(2)
    G.Sprites.ellipseLine(L.tx, L.ty, 56, 40)
    lg.setLineWidth(1)
    lg.setColor(1, 1, 1, 1)
    G.Icons.draw('heart', U.round(L.tx - 8), U.round(L.ty - 30 - k * 6), 16)
end

-- El Pokémon perdido con su barra de vida y el "!" si espera.
function monD.draw()
    local L = lost
    if not L then return end
    local now = U.now()
    U.setColor('#7dffb0', 0.3)
    G.Sprites.ellipse(L.x, L.y, L.r * 1.5, L.r * 0.6)
    G.Sprites.drawShadow(L.dex, L.x, L.y, 1)
    drawOpts.flash = L.flash > 0
    L.anim:draw(L.x, L.y, drawOpts)
    local h = G.Sprites.bodyHeight(L.dex, 1)
    if L.state == 'wait' then
        -- "!" que bota encima: está esperando a que lo toques. (Dentro de la cámara
        -- todo va a escala 0.5: el texto se dibuja al doble para que se lea.)
        local by = L.y - h - 14 - abs(sin(now * 5)) * 6
        lg.push()
        lg.translate(U.round(L.x), U.round(by))
        lg.scale(2, 2)
        lg.setColor(0, 0, 0, 1)
        lg.print('!', -2, -7)
        U.setColor('#7dffb0')
        lg.print('!', -3, -8)
        lg.pop()
    end
    local w, y = 30, L.y - h - 6
    lg.setColor(0, 0, 0, 0.6)
    lg.rectangle("fill", L.x - w / 2, y, w, 3.4)
    U.setColor('#5fe08a')
    lg.rectangle("fill", L.x - w / 2, y, w * max(0, L.hp / L.maxHp), 3.4)
    lg.setColor(1, 1, 1, 1)
end

-- El Pokémon perdido y la marca, para ordenarlos por Y con el resto (lista reutilizada).
function E.drawables()
    local L = lost
    if not L then return EMPTY end
    goalD.y = L.ty - 4000          -- en el suelo, debajo de todo
    monD.y = L.y
    return both
end

-- Para pruebas.
function E.debugStart(id) start(id, G.Game.time(), G.Game.player()) end
function E.debugThief() spawnThief(G.Game.player(), G.Game.time()) end
