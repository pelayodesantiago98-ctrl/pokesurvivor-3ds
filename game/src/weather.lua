-- weather.lua — climas (evento raro). Port de js/systems/weather.js.
-- De vez en cuando (desde el minuto 2, ~1 de cada 6 minutos) llega un clima que
-- dura alrededor de un minuto. Cambia el daño según el tipo del ataque, para ti
-- y para los enemigos:
--
--   sol      Fuego ×1,5 · Agua ×0,5
--   lluvia   Agua ×1,5 · Eléctrico ×1,2 · Fuego ×0,5
--   arena    Roca, Tierra y Acero ×1,3; los demás pierden un poco de vida
--   nieve    Hielo ×1,5; los demás pierden un poco de vida y van algo más lentos
--   niebla   Fantasma, Hada y Psíquico ×1,3
--
-- Cada bioma tiene sus climas más probables (el volcán, sol y arena...).
-- Lo visual es suave a propósito: un tinte leve y pocas partículas en la
-- pantalla superior (400x240), dibujadas DESPUÉS del mundo y fuera de la cámara.
--
--   G.Weather.reset()  update(dt, t, pl)  draw(w, h, dt)
--   G.Weather.mult(type)  speedFor(types)  hurts(types)  vignette()  level()
--   G.Weather.current() -> tabla reutilizada { kind, t, dur, left, name, icon, color, hint } o nil
--   G.Weather.force(kind, dur)  clear()  stop()  KINDS
local U = G.U
local W = {}
G.Weather = W

local floor, min, max, random = math.floor, math.min, math.max, love.math.random
local lg = love.graphics

local KINDS = {
    sun  = { name = 'Sol abrasador', icon = 'wsun', color = '#ffcb3d', tint = { 255, 190, 90, 0.07 },
             mult = { fire = 1.5, water = 0.5 }, hint = 'el Fuego se potencia y el Agua se debilita' },
    rain = { name = 'Lluvia', icon = 'wrain', color = '#7fb8ff', tint = { 50, 90, 170, 0.09 },
             mult = { water = 1.5, electric = 1.2, fire = 0.5 }, hint = 'el Agua se potencia y el Fuego se debilita' },
    sand = { name = 'Tormenta de arena', icon = 'wsand', color = '#e0bf73', tint = { 200, 160, 90, 0.09 },
             mult = { rock = 1.3, ground = 1.3, steel = 1.3 }, safe = { 'rock', 'ground', 'steel' },
             hint = 'Roca, Tierra y Acero se potencian; el resto sufre' },
    snow = { name = 'Nevada', icon = 'wsnow', color = '#d8f1ff', tint = { 210, 230, 255, 0.08 },
             mult = { ice = 1.5 }, safe = { 'ice' }, slow = true,
             hint = 'el Hielo se potencia; el resto sufre y va más lento' },
    fog  = { name = 'Niebla', icon = 'wfog', color = '#c9cfdc', tint = { 190, 195, 210, 0.12 },
             mult = { ghost = 1.3, fairy = 1.3, psychic = 1.3 }, hint = 'Fantasma, Hada y Psíquico se potencian' }
}
W.KINDS = KINDS

-- Probabilidad de cada clima según el bioma (bosque, cueva, volcán). Listas de
-- pares para que el orden del sorteo sea determinista.
local BIOME_W = {
    { { 'rain', 3 }, { 'fog', 2 }, { 'sun', 1.5 }, { 'snow', 0.5 }, { 'sand', 0.5 } },
    { { 'fog', 3 }, { 'snow', 2.5 }, { 'rain', 1 }, { 'sand', 1 } },
    { { 'sun', 3 }, { 'sand', 3 }, { 'fog', 1 } }
}
local FROM, CHECK, CHANCE = 120, 60, 0.18
-- Partículas que se quieren con la vista a 1280 px de ancho (se escala al ancho real).
local WANT = { rain = 70, snow = 45, sand = 40, sun = 14, fog = 0 }

local cur = nil            -- { kind, t, dur }  (tabla reutilizada)
local curT = { kind = nil, t = 0, dur = 0 }
local checkT, chipT = CHECK, 0
local parts = {}           -- partículas en coordenadas de pantalla (tablas reutilizadas)
local nParts = 0
local info = {}            -- lo que devuelve current()

function W.reset()
    cur = nil
    checkT = CHECK
    chipT = 0
    nParts = 0
end

local function def() return cur and KINDS[cur.kind] or nil end

-- Intensidad 0..1 (entra y sale en 3 s).
local function level()
    if not cur then return 0 end
    return min(1, cur.t / 3, (cur.dur - cur.t) / 3)
end
W.level = level

-- Multiplicador de daño de un ataque de este tipo con el clima actual.
function W.mult(type)
    local d = def()
    if d and d.mult[type] then return 1 + (d.mult[type] - 1) * level() end
    return 1
end

-- ¿Le afecta el daño de arena/nieve a un Pokémon con estos tipos?
local function hurts(types)
    local d = def()
    if not d or not d.safe then return false end
    local safe = d.safe
    for i = 1, #types do
        for j = 1, #safe do if types[i] == safe[j] then return false end end
    end
    return true
end
W.hurts = hurts

-- Factor de velocidad (nieve) para un Pokémon con estos tipos.
function W.speedFor(types)
    local d = def()
    if d and d.slow and not U.contains(types, 'ice') then return 1 - 0.1 * level() end
    return 1
end

local function start(kind, dur)
    local d = KINDS[kind]
    if not d then return end
    curT.kind = kind; curT.t = 0; curT.dur = dur
    cur = curT
    G.Spawner.say(d.name .. ': ' .. d.hint, 3.4, true)
    G.Audio.sfx('biome')
end

-- Deja que el clima se desvanezca (3 s).
function W.stop()
    if not cur then return end
    cur.dur = min(cur.dur, cur.t + 3)
end

local function pick(biome)
    local w = BIOME_W[(biome % #BIOME_W) + 1]
    local total = 0
    for i = 1, #w do total = total + w[i][2] end
    local r = random() * total
    for i = 1, #w do
        r = r - w[i][2]
        if r <= 0 then return w[i][1] end
    end
    return 'rain'
end

function W.update(dt, time, pl)
    if cur then
        cur.t = cur.t + dt
        if cur.t >= cur.dur then cur = nil end
    elseif time > FROM and not G.Rift.inArena() and not G.Judgment.active() then
        checkT = checkT - dt
        if checkT <= 0 then
            checkT = CHECK
            if random() < CHANCE then
                start(pick(G.World.biome()), U.round(U.rand(55, 75)))
            end
        end
    end
    -- Arena y nieve: te van quitando un poco de vida (nunca te dejan KO).
    chipT = chipT - dt
    if chipT <= 0 then
        chipT = 2
        if pl and not pl.dead and hurts(pl.mon.types) and level() > 0.5 then
            local d = max(1, pl.maxHp * 0.012)
            if pl.hp > d + 1 then
                pl.hp = pl.hp - d
                G.FX.dmgText(pl.x, pl.y - pl.bodyH - 4, '-' .. U.round(d), def().color)
            end
        end
        if cur and def().safe and level() > 0.5 then
            local all = G.EnemyMgr.all()
            for i = 1, #all do
                local e = all[i]
                if not e.dead and not e.boss and hurts(e.types or U.TYPES) then
                    e.hp = e.hp - (e.maxHp * 0.02 + 1)
                    e.flash = 0.05
                    if e.hp <= 0 then e:die() end
                end
            end
        end
    end
end

-- ---------------- dibujo (en pantalla, tras el mundo) ----------------

local function spawn(p, kind, w, h, anywhere)
    p.t = 0
    if kind == 'rain' then
        p.x = random() * (w + 60); p.y = anywhere and random() * h or -10
        p.vx = -120; p.vy = 720; p.a = 0.5; p.c = '#cfe2ff'; p.life = 9
    elseif kind == 'snow' then
        p.x = random() * w; p.y = anywhere and random() * h or -10
        p.vx = U.rand(-20, 20); p.vy = U.rand(40, 80); p.a = 0.7; p.c = '#ffffff'; p.life = 20
    elseif kind == 'sand' then
        p.x = anywhere and random() * w or w + 20; p.y = random() * h
        p.vx = U.rand(-520, -380); p.vy = U.rand(20, 60); p.a = 0.4; p.c = '#e8cf8f'; p.life = 9
    else
        -- sol: motas de luz que suben despacio
        p.x = random() * w; p.y = anywhere and random() * h or h + 5
        p.vx = U.rand(-8, 8); p.vy = -U.rand(15, 30); p.a = 0.45; p.c = '#fff1b0'; p.life = 12
    end
end

-- Partículas suaves y un tinte leve. w, h = tamaño de la pantalla superior (400x240).
function W.draw(w, h, dt)
    local d = def()
    local k = level()
    if not d or k <= 0 then nParts = 0 return end
    local tint = d.tint
    lg.setColor(tint[1] / 255, tint[2] / 255, tint[3] / 255, tint[4] * k)
    lg.rectangle("fill", 0, 0, w, h)

    local kind = cur.kind
    -- Las velocidades están pensadas para 1280 px de ancho: se escalan a la pantalla.
    local sc = w / 1280
    local want = WANT[kind] * k * sc
    while nParts < want do
        nParts = nParts + 1
        local p = parts[nParts]
        if not p then p = {}; parts[nParts] = p end
        spawn(p, kind, w, h, true)
    end
    if nParts > want + 4 then nParts = math.ceil(want) end
    local s = max(1, U.round(w / 640))          -- un "píxel" del juego
    for i = 1, nParts do
        local p = parts[i]
        p.x = p.x + p.vx * sc * dt; p.y = p.y + p.vy * sc * dt; p.t = p.t + dt
        if p.y > h + 20 or p.x < -40 or p.x > w + 40 or p.t > p.life then
            spawn(p, kind, w, h, false)
        else
            U.setColor(p.c, p.a * k)
            if kind == 'rain' then
                for j = 0, 3 do
                    lg.rectangle("fill", U.round(p.x - j * s * 0.5), U.round(p.y - j * s * 1.5), s * 0.5, s * 1.5)
                end
            elseif kind == 'sand' then
                lg.rectangle("fill", U.round(p.x), U.round(p.y), s * 3, s * 0.5)
            else
                lg.rectangle("fill", U.round(p.x), U.round(p.y), s, s)
            end
        end
    end
    lg.setColor(1, 1, 1, 1)
end

-- Clima en curso (tabla REUTILIZADA, no guardarla) o nil.
function W.current()
    if not cur or level() <= 0 then return nil end
    local d = KINDS[cur.kind]
    info.kind = cur.kind; info.t = cur.t; info.dur = cur.dur
    info.left = max(0, cur.dur - cur.t)
    info.name = d.name; info.icon = d.icon; info.color = d.color; info.hint = d.hint
    info.level = level()
    return info
end

-- Niebla: 0..1 para la viñeta de la pantalla superior.
function W.vignette()
    if cur and cur.kind == 'fog' then return level() end
    return 0
end

-- Pone un clima ya (la arena de la grieta).
function W.force(kind, dur) start(kind, dur or 60) end

-- Quita el clima de golpe (al salir de la arena).
function W.clear() cur = nil; nParts = 0 end

function W.debugStart(kind, dur) start(kind or 'rain', dur or 60) end
