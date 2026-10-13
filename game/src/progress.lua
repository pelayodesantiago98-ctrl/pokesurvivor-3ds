-- progress.lua — misiones, logros y estadísticas de la partida guardada.
-- Port de js/systems/progress.js (sin ranking ni DOM).
-- El juego avisa de lo que pasa con G.Progress.event(tipo, datos):
--
--   kill      { types, boss, legend }
--   chest     cofre con candado abierto
--   item      { id }        objeto equipado
--   evolve    { move }      movimiento evolucionado
--   rift      { type }      pelea de grieta ganada
--   runEnd    { time, level, coins, types }
--   missionDone { daily }   (lo lanza claim)
--
-- y esto actualiza en la partida guardada:
--   stats.bossesTotal · riftWins · evolutions · missionsDone
--   legends{dex} · arenas{tipo} · itemsFound{id} · evoMoves{id} · ach{id}
--   missions { day, daily[], rerolled, week, weekly[] }
--
-- Misiones: 3 diarias + 2 semanales, sorteadas con una semilla de la fecha y
-- la partida. El premio se recoge a mano; los logros se dan solos.
--
-- Avisos: notify() encola { title, sub, ach } en G.Progress.toasts; la interfaz
-- los enseña y los va quitando (G.Progress.popToast()). No se reproduce sonido
-- aquí: lo hace la interfaz al mostrarlos ('legend' si lleva `ach`, 'confirm' si no).
--
--   G.Progress.ensure(s)  event(kind, d)  kill(e)  claim(m, weekly)  reroll(i)  checkAch()
--   G.Progress.titles() -> lista   pending() -> n   text(m)  done(m)  rewardText(r)  grant(r)
--   G.Progress.periodIds() -> { d = 'dYYYYMMDD', w = 'wYYYY-WW' }
local U = G.U
local P = {}
G.Progress = P

local floor, max = math.floor, math.max
local TYPES = U.TYPES
local achT = -1e9
local EMPTY = {}
P.toasts = {}

-- ---------------- fechas (día y semana ISO, hora local) ----------------

local function p2(n) if n < 10 then return '0' .. n end return tostring(n) end

local function isoWeek(y, m, d)
    local t = os.time({ year = y, month = m, day = d, hour = 12 })
    local wday = tonumber(os.date("%w", t))              -- 0 = domingo
    local day = (wday == 0) and 7 or wday
    local th = t + (4 - day) * 86400                      -- jueves de esta semana
    local ty = tonumber(os.date("%Y", th))
    local y0 = os.time({ year = ty, month = 1, day = 1, hour = 12 })
    local week = math.ceil((floor((th - y0) / 86400 + 0.5) + 1) / 7)
    return ty, week
end

local ids = { d = '', w = '' }
function P.periodIds()
    local t = os.date("*t")
    local wy, ww = isoWeek(t.year, t.month, t.day)
    ids.d = 'd' .. t.year .. p2(t.month) .. p2(t.day)
    ids.w = 'w' .. wy .. '-' .. p2(ww)
    return ids
end

-- ---------------- generador determinista (semilla de texto) ----------------
-- Lua 5.1 no tiene operadores de bits: aritmética modular de 32 bits.

local M32 = 4294967296
local function mulmod32(a, b)
    local hi, lo = floor(a / 65536), a % 65536
    return ((hi * b) % 65536 * 65536 + lo * b) % M32
end

local function rng(seedStr)
    local h = 2166136261
    for i = 1, #seedStr do
        h = (h + seedStr:byte(i)) % M32
        h = mulmod32(h, 16777619)
    end
    return function()
        h = (mulmod32(h, 1664525) + 1013904223) % M32
        return floor(h / 65536) / 65536            -- los 16 bits altos: [0, 1)
    end
end

-- ---------------- misiones ----------------

local function make(def, r)
    local goal = def.goals[floor(r() * #def.goals) + 1]
    local param = nil
    if def.param == 'type' then param = TYPES[floor(r() * #TYPES) + 1] end
    return { id = def.id, goal = goal, param = param, prog = 0, claimed = false, told = false }
end

local function pickSet(defs, n, r, avoid)
    local pool = {}
    for i = 1, #defs do
        if not (avoid and U.contains(avoid, defs[i].id)) then pool[#pool + 1] = defs[i] end
    end
    local out = {}
    while #out < n and #pool > 0 do
        local i = floor(r() * #pool) + 1
        out[#out + 1] = make(pool[i], r)
        table.remove(pool, i)
    end
    return out
end

-- Crea las misiones del día / semana si han cambiado.
function P.ensure(s)
    if not s then return end
    local id = P.periodIds()
    local key = tostring(s.created or 0)
    s.missions = s.missions or {}
    local M = s.missions
    if M.day ~= id.d then
        M.day = id.d; M.rerolled = false
        M.daily = pickSet(G.MissionDefs.daily, 3, rng(id.d .. key))
    end
    if M.week ~= id.w then
        M.week = id.w
        M.weekly = pickSet(G.MissionDefs.weekly, 2, rng(id.w .. key))
    end
end

function P.text(m) return G.MissionDefs.BY[m.id].text(m.goal, m.param) end
function P.done(m) return m.prog >= m.goal end

local function notify(title, sub, ach)
    local q = P.toasts
    q[#q + 1] = { title = title, sub = sub or '', ach = ach }
end

local function advance(list, kind, d)
    if not list then return end
    for i = 1, #list do
        local m = list[i]
        if not m.claimed and not P.done(m) then
            local def = G.MissionDefs.BY[m.id]
            if def and def.ev == kind and not (def.match and not def.match(d, m.param)) then
                local v = def.value and def.value(d) or 1
                if def.mode == 'max' then m.prog = max(m.prog, v) else m.prog = m.prog + v end
                if P.done(m) and not m.told then
                    m.told = true
                    notify('Misión completada: ' .. P.text(m), 'Recoge el premio en Misiones')
                end
            end
        end
    end
end

-- Da un premio { coins, t1, t10 } a la partida.
function P.grant(r)
    local s = G.DB.save
    if not s or not r then return end
    s.tickets = s.tickets or { t1 = 0, t10 = 0 }
    if r.coins then s.coins = s.coins + r.coins end
    if r.t1 then s.tickets.t1 = s.tickets.t1 + r.t1 end
    if r.t10 then s.tickets.t10 = s.tickets.t10 + r.t10 end
end

-- Recoge el premio de una misión terminada.
function P.claim(m, weekly)
    local s = G.DB.save
    if not s or not m or m.claimed or not P.done(m) then return false end
    m.claimed = true
    P.grant(G.MissionDefs.BY[m.id].reward)
    s.stats.missionsDone = (s.stats.missionsDone or 0) + 1
    P.event('missionDone', { daily = not weekly })
    G.DB.commit()
    return true
end

-- Cambia la diaria i (1..3) sin terminar por otra (una vez al día).
function P.reroll(i)
    local s = G.DB.save
    if not s then return false end
    P.ensure(s)
    local M = s.missions
    local m = M.daily[i]
    if not m or M.rerolled or m.claimed then return false end
    local avoid = {}
    for k = 1, #M.daily do avoid[k] = M.daily[k].id end
    local r = rng(M.day .. 'cambio' .. os.time())
    local n = pickSet(G.MissionDefs.daily, 1, r, avoid)[1]
    if not n then return false end
    M.daily[i] = n
    M.rerolled = true
    G.DB.commit()
    return true
end

-- Texto del premio: "1 ticket ×10 · 2 tickets · 150 monedas".
function P.rewardText(r)
    local parts = {}
    if r.t10 then parts[#parts + 1] = r.t10 .. (r.t10 == 1 and ' ticket ×10' or ' tickets ×10') end
    if r.t1 then parts[#parts + 1] = r.t1 .. (r.t1 == 1 and ' ticket' or ' tickets') end
    if r.coins then parts[#parts + 1] = r.coins .. ' monedas' end
    return table.concat(parts, ' · ')
end

-- ---------------- logros ----------------

function P.checkAch()
    local s = G.DB.save
    if not s then return end
    achT = U.now()
    s.ach = s.ach or {}
    local list = G.AchDefs.LIST
    for i = 1, #list do
        local a = list[i]
        if not s.ach[a.id] and a.value(s) >= a.goal then
            s.ach[a.id] = os.time()
            P.grant(a.reward)
            notify('¡Logro: ' .. a.name .. '!', a.title and ('Nuevo título: ' .. a.title) or '', a)
        end
    end
end

-- Títulos que tienes (de los logros conseguidos).
function P.titles()
    local s = G.DB.save
    local out = {}
    if not s or not s.ach then return out end
    local list = G.AchDefs.LIST
    for i = 1, #list do
        local a = list[i]
        if a.title and s.ach[a.id] then out[#out + 1] = a.title end
    end
    return out
end

-- ---------------- eventos ----------------

function P.event(kind, d)
    local s = G.DB.save
    if not s then return end
    d = d or EMPTY
    P.ensure(s)
    local S = s.stats
    local now = os.time()
    if kind == 'kill' then
        if d.boss then S.bossesTotal = (S.bossesTotal or 0) + 1 end
        if d.legend and d.legend ~= 0 then
            s.legends = s.legends or {}
            if not s.legends[d.legend] then s.legends[d.legend] = now end
        end
    elseif kind == 'rift' then
        S.riftWins = (S.riftWins or 0) + 1
        if d.type then s.arenas = s.arenas or {}; s.arenas[d.type] = s.arenas[d.type] or now end
    elseif kind == 'evolve' then
        S.evolutions = (S.evolutions or 0) + 1
        s.evoMoves = s.evoMoves or {}
        if d.move then s.evoMoves[d.move] = s.evoMoves[d.move] or now end
    elseif kind == 'item' then
        s.itemsFound = s.itemsFound or {}
        if d.id then s.itemsFound[d.id] = s.itemsFound[d.id] or now end
    elseif kind == 'runEnd' then
        if d.group then S.groupRuns = (S.groupRuns or 0) + 1 end
    elseif kind == 'judge' then
        -- Llegas a la Sentencia de Arceus (minuto 30).
        S.judged = (S.judged or 0) + 1
    elseif kind == 'judgeEnd' then
        -- Aguantado ante Arceus (al acabar la partida): mejor tiempo y más legendarios.
        S.judgeTime = math.max(S.judgeTime or 0, math.floor(d.time or 0))
        S.judgeBosses = math.max(S.judgeBosses or 0, d.bosses or 0)
    end
    advance(s.missions.daily, kind, d)
    advance(s.missions.weekly, kind, d)
    -- Los logros se miran como mucho una vez por segundo (hay cientos de bajas).
    if kind ~= 'kill' or d.boss or (d.legend and d.legend ~= 0) then P.checkAch()
    elseif U.now() - achT > 1 then P.checkAch() end
end

-- Un enemigo ha caído (tabla de datos reutilizada: hay cientos por partida).
local killD = { types = nil, boss = false, legend = 0 }
function P.kill(e)
    -- Los legendarios de la Sentencia de Arceus no cuentan como jefes (ni para
    -- misiones ni para logros de jefes): tienen su propio contador.
    if G.Judgment.active() and e.boss then
        G.Judgment.bossDown()
        killD.types = e.types or EMPTY
        killD.boss = false
        killD.legend = 0
        P.event('kill', killD)
        return
    end
    local legend = 0
    if e.legend or (G.Rift.inArena() and e.boss) then legend = e.dex end
    killD.types = e.types or EMPTY
    killD.boss = e.boss and true or false
    killD.legend = legend
    P.event('kill', killD)
end

-- Premios de misiones por recoger (para el aviso del menú).
function P.pending()
    local s = G.DB.save
    if not s then return 0 end
    P.ensure(s)
    local n = 0
    local M = s.missions
    for i = 1, #M.daily do if P.done(M.daily[i]) and not M.daily[i].claimed then n = n + 1 end end
    for i = 1, #M.weekly do if P.done(M.weekly[i]) and not M.weekly[i].claimed then n = n + 1 end end
    return n
end

-- ---------------- avisos ----------------

P.notify = notify

-- Saca el primer aviso de la cola (o nil).
function P.popToast()
    local q = P.toasts
    if #q == 0 then return nil end
    return table.remove(q, 1)
end
