-- interact.lua — altares, manantiales, cofres con candado y trampas.
-- Port de js/systems/interact.js. Los objetos los coloca world.lua (raros, en el
-- suelo libre); aquí está lo que pasa al tocarlos. Todo se mira alrededor de TU Pokémon:
--
--   altar     da un poder de 25 s (Furia, Rayo, Imán o Prisa) y se apaga
--   spring    cura mientras estás encima; se agota y se recarga sola
--   bigchest  quédate a su lado CHEST_TIME segundos (mientras te atacan) y se
--             abre: monedas, tickets y experiencia para subir un nivel
--   trap      salta al pisarla (tú o un enemigo) y afecta a todo lo cercano:
--             veneno, pegajosa (ralentiza) o explosiva
--
-- Campos de los props que se usan (los pone G.World.makeProp, como en world.js):
--   type, x, y, r, kind (0-based: altar 0..3 = poder, trap 0..2), used, charge, open
--
--   G.Interact.update(dt, pl)   G.Interact.trapEffect(p)   G.Interact.POWERS   CHEST_TIME   POWER_TIME
local U = G.U
local I = {}
G.Interact = I

local max, min, cos, sin, random = math.max, math.min, math.cos, math.sin, love.math.random

local CHEST_TIME = 3.5
local POWER_TIME = 25
I.CHEST_TIME = CHEST_TIME
I.POWER_TIME = POWER_TIME

-- Poderes de los altares (índice = kind + 1). on/off modifican al jugador.
local POWERS = {
    { id = 'dmg', name = 'Furia', desc = 'daño ×2', color = '#ff5f6d',
      on = function(p) p.atkMul = p.atkMul * 2 end, off = function(p) p.atkMul = p.atkMul / 2 end },
    { id = 'spd', name = 'Rayo', desc = '+45% velocidad', color = '#5fd4ff',
      on = function(p) p.spdMul = p.spdMul * 1.45 end, off = function(p) p.spdMul = p.spdMul / 1.45 end },
    { id = 'mag', name = 'Imán', desc = 'atraes todo desde lejos', color = '#ff8ad8',
      on = function(p) p.magnet = p.magnet * 4 end, off = function(p) p.magnet = p.magnet / 4 end },
    { id = 'cd', name = 'Prisa', desc = '-40% recarga', color = '#ffd23f',
      on = function(p) p.cdMul = p.cdMul * 0.6 end, off = function(p) p.cdMul = p.cdMul / 0.6 end }
}
I.POWERS = POWERS

local TRAP_R = 74
local healShown, healAcc = 0, 0
local PX_HEAL = { vy = -50, life = 0.5 }         -- opciones constantes (sin tablas por fotograma)

local function spring(dt, pl, p, d2)
    if p.charge < 1 then p.charge = min(1, p.charge + dt / 45) end
    if pl.dead or d2 > 26 * 26 or p.charge <= 0.02 or pl.hp >= pl.maxHp then return end
    local before = pl.hp
    pl.hp = min(pl.maxHp, pl.hp + pl.maxHp * 0.14 * dt)
    healAcc = healAcc + (pl.hp - before)
    p.charge = max(0, p.charge - dt * 0.09)
    if random() < dt * 14 then
        G.FX.px(pl.x + U.rand(-pl.r, pl.r), pl.y - U.rand(0, pl.bodyH), '#7dffb0', PX_HEAL)
    end
    healShown = healShown - dt
    if healShown <= 0 and healAcc >= 1 then
        healShown = 0.6
        G.FX.dmgText(pl.x, pl.y - pl.bodyH - 6, '+' .. U.round(healAcc), '#5fe08a')
        healAcc = 0
        G.Audio.sfx('xp')
    end
    if p.charge <= 0.02 then G.Spawner.say('El manantial se ha secado (se recarga solo)', 2.2, true) end
end

local function usePower(pl, p)
    p.used = true
    local pw = POWERS[(p.kind or 0) + 1] or POWERS[1]
    pl:addPower(pw, POWER_TIME)
    G.FX.ring(p.x, p.y - 20, 8, 90, pw.color, 0.6, 5)
    G.FX.burst(pl.x, pl.y - pl.bodyH * 0.5, pw.color, 24, 200)
    G.Audio.sfx('legend')
    G.Spawner.say('¡Poder ' .. pw.name .. '! ' .. pw.desc .. ' durante ' .. POWER_TIME .. ' s', 3, true)
end

-- ¿Hay algún enemigo (que no vuele) pisando este punto?
local function enemyOn(x, y)
    local list = G.EnemyMgr.queryCircle(x, y, 3)
    for i = 1, #list do
        if not list[i].flying and not list[i].dead then return true end
    end
    return false
end

-- La búsqueda (radio 720, varios trozos del mapa) se repite 5 veces por segundo; lo
-- de cada objeto, en cada fotograma. Un objeto roto deja de estar en el mapa pero
-- puede seguir un momento en la lista: se salta (p.gone, lo pone world.lua).
local near, searchT = {}, 0
function I.clear()
    for i = #near, 1, -1 do near[i] = nil end
    searchT = 0
end
function I.update(dt, pl)
    if not pl then return end
    searchT = searchT - dt
    if searchT <= 0 then
        searchT = 0.2
        local found = G.World.specialsNear(pl.x, pl.y, 720)
        for i = 1, #found do near[i] = found[i] end
        for i = #near, #found + 1, -1 do near[i] = nil end
    end
    for i = 1, #near do
        local p = near[i]
        local t = (not p.gone) and p.type or nil
        local py = (t == 'spring' or t == 'trap') and p.y - 8 or p.y
        local d2 = t and U.dist2(pl.x, pl.y, p.x, py) or 0
        if t == 'spring' then
            spring(dt, pl, p, d2)
        elseif t == 'altar' then
            -- Contando el tamaño de tu Pokémon: uno grande (Reshiram, Zekrom...) choca
            -- con el altar antes de llegar a 30 y no lo podía activar.
            local rr = max(30, p.r + pl.r + 14)
            if not p.used and not pl.dead and d2 < rr * rr then usePower(pl, p) end
        elseif t == 'bigchest' then
            local rr = max(46, p.r + pl.r + 24)
            if not pl.dead and d2 < rr * rr then
                if p.open == 0 then G.Audio.sfx('select') end
                p.open = p.open + dt
                if p.open >= CHEST_TIME then p.open = 0; G.World.breakProp(p) end
            elseif p.open > 0 then
                p.open = max(0, p.open - dt * 1.5)
            end
        elseif t == 'trap' then
            if not pl.dead and d2 < 13 * 13 then G.World.breakProp(p)
            elseif enemyOn(p.x, p.y - 8) then G.World.breakProp(p) end
        end
    end
end

local TRAP_COL = { '#c86bdc', '#8bd94a', '#ff7b3d' }
local TRAP_PAL = { 'poison', 'grass', 'fire' }
local SP_OPTS = { vy = 0, life = 0 }

-- Una trampa salta (la llama G.World.breakProp al romperla). Daña a los enemigos
-- de alrededor y a ti si estás dentro.
function I.trapEffect(p)
    local x, y, k = p.x, p.y - 8, p.kind or 0
    local col = TRAP_COL[k + 1]
    local pal = TRAP_PAL[k + 1]
    local boom = (k == 2)
    G.FX.ring(x, y, 6, TRAP_R, col, 0.5, boom and 7 or 4)
    G.FX.burst(x, y - 6, col, boom and 40 or 22, boom and 260 or 140)
    for _ = 1, (boom and 10 or 7) do
        local a = random() * 6.2832
        local r = U.rand(8, TRAP_R * 0.8)
        SP_OPTS.vy = boom and -30 or -45
        SP_OPTS.life = U.rand(0.4, 0.8)
        G.FX.sp(boom and 'impact' or 'blob', pal, x + cos(a) * r, y + sin(a) * r * 0.7 - 6, SP_OPTS)
    end
    G.Audio.sfx(boom and 'boss' or 'surge')
    if boom and U.dist2(x, y, G.Camera.x, G.Camera.y) < 500 * 500 then G.Camera.kick(0.7) end

    local pl = G.Game.player()
    local lvl = pl and pl.level or 1
    local list = G.EnemyMgr.queryCircle(x, y, TRAP_R)
    for i = 1, #list do
        local e = list[i]
        if k == 0 then e:applyPoison(5); e:hurt(14 + lvl * 3, '#d47cf0')
        elseif k == 1 then e:applySlow(0.65, 4.5); e:hurt(4, '#8bd94a')
        else e:hurt(90 + lvl * 18, '#ff7b3d', e.x - x, e.y - y, 220) end
    end
    if pl and not pl.dead and U.dist2(x, y, pl.x, pl.y) < (TRAP_R * 0.7) * (TRAP_R * 0.7) then
        pl.invuln = 0
        if k == 0 then pl:hurt(pl.maxHp * 0.1)
        elseif k == 1 then
            pl.slowT = 3.5
            G.FX.dmgText(pl.x, pl.y - pl.bodyH - 6, '¡Pegajoso!', '#8bd94a')
        else pl:hurt(pl.maxHp * 0.2) end
    end
end
