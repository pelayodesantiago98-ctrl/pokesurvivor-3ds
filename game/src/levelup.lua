-- levelup.lua — las tres cartas de subida de nivel (port de js/systems/levelup.js).
-- Tipos de carta: new (movimiento nuevo), evo (evolución), up (mejorar uno que
-- tienes), stat (mejora permanente de la run).
local U = G.U
local L = {}
G.LevelUp = L

local STATS = {
    { id = 'hp',   icon = 'heart',  title = 'Vigor',       desc = '+20 de vida máxima (y la recupera).',
      apply = function(pl) pl:addMaxHp(20) end },
    { id = 'atk',  icon = 'fist',   title = 'Potencia',    desc = '+10% de daño con todos los movimientos.',
      apply = function(pl) pl.atkMul = pl.atkMul * 1.10 end },
    { id = 'spd',  icon = 'boot',   title = 'Carrera',     desc = '+7% de velocidad de movimiento.',
      apply = function(pl) pl.spdMul = pl.spdMul * 1.07 end },
    { id = 'cd',   icon = 'clock',  title = 'Reflejos',    desc = '-8% de recarga en todos los movimientos.',
      apply = function(pl) pl.cdMul = pl.cdMul * 0.92 end },
    { id = 'def',  icon = 'shield', title = 'Coraza',      desc = '+6% de reducción de daño recibido.',
      apply = function(pl) pl.dmgReduce = math.min(0.7, pl.dmgReduce + 0.06) end },
    { id = 'rgn',  icon = 'sprout', title = 'Síntesis',    desc = '+0.9 de vida regenerada por segundo.',
      apply = function(pl) pl.regenFlat = pl.regenFlat + 0.9 end },
    { id = 'mag',  icon = 'magnet', title = 'Imán',        desc = '+30% de radio de recogida de experiencia.',
      apply = function(pl) pl.magnet = pl.magnet * 1.30 end },
    { id = 'xp',   icon = 'book',   title = 'Aprendizaje', desc = '+12% de experiencia ganada.',
      apply = function(pl) pl.xpMul = pl.xpMul * 1.12 end },
    { id = 'heal', icon = 'berry',  title = 'Baya Zidra',  desc = 'Recupera el 45% de tu vida ahora mismo.',
      apply = function(pl) pl:heal(pl.maxHp * 0.45) end },
}
L.STATS = STATS

-- Construye el conjunto de cartas candidatas, con pesos.
local function candidates(pl)
    local out = {}

    -- Movimientos nuevos
    if #pl.slots < pl.maxMoves then
        -- Con 2 potenciadores ya no se ofrecen más.
        local buffs = 0
        for _, m in ipairs(pl.moves) do if m.kind == 'buff' then buffs = buffs + 1 end end
        local pool = {}
        for _, id in ipairs(G.Moves.poolFor(pl.mon)) do
            if not pl:hasMove(id) and not (buffs >= 2 and G.Moves.BY_ID[id].kind == 'buff') then pool[#pool + 1] = id end
        end
        for _, id in ipairs(U.pickN(pool, 6)) do
            local d = G.Moves.BY_ID[id]
            out[#out + 1] = {
                w = 10, type = 'new', key = 'new:' .. id,
                icon = 'move:' .. id, color = U.TYPE_COLOR[d.type],
                tag = 'Nuevo · ' .. U.TYPE_NAME[d.type],
                title = d.name, desc = d.desc,
                apply = function(p) p:addMove(id) end,
            }
        end
    end

    -- Evoluciones: movimiento al máximo + su condición cumplida
    local waiting = {}
    for _, m in ipairs(pl.moves) do
        local ev = G.Moves.evoInfo(m, pl.statsTaken, pl)
        if ev then
            if not ev.ready then
                waiting[ev.needs] = m
            else
                local mm = m
                out[#out + 1] = {
                    w = 40, type = 'evo', key = 'evo:' .. m.id,
                    icon = 'move:' .. m.id, color = '#ffd23f', tag = 'EVOLUCIÓN',
                    title = m.name .. ' > ' .. ev.name, desc = ev.text,
                    apply = function(p)
                        G.Moves.evolve(mm)
                        G.FX.ring(p.x, p.y, 8, 120, '#ffd23f', 0.8, 6)
                        G.FX.burst(p.x, p.y - p.bodyH * 0.5, '#ffe14d', 40, 240)
                        G.Audio.sfx('legend')
                        G.Progress.event('evolve', { move = mm.id })
                    end,
                }
            end
        end
    end

    -- Mejoras de movimientos que ya tienes
    for _, m in ipairs(pl.moves) do
        local txt = G.Moves.nextUpText(m)
        if txt then
            local mm = m
            out[#out + 1] = {
                w = 8, type = 'up', key = 'up:' .. m.id,
                icon = 'move:' .. m.id, color = U.TYPE_COLOR[m.type],
                tag = 'Nv.' .. m.lvl .. ' > ' .. (m.lvl + 1),
                title = m.name, desc = txt,
                apply = function() G.Moves.levelUp(mm) end,
            }
        end
    end

    -- Stats: las que desbloquean una evolución salen siempre y con aviso.
    local free, forced = {}, {}
    for _, s in ipairs(STATS) do
        if waiting[s.id] then forced[#forced + 1] = s else free[#free + 1] = s end
    end
    local pickStats = U.pickN(free, 5)
    for _, s in ipairs(forced) do pickStats[#pickStats + 1] = s end
    for _, s in ipairs(pickStats) do
        local evoFor = waiting[s.id]
        local st = s
        out[#out + 1] = {
            w = evoFor and 14 or (#pl.slots < pl.maxMoves and 4 or 7),
            type = 'stat', key = 'stat:' .. s.id,
            icon = s.icon, color = evoFor and '#ffd23f' or '#8fa3c4',
            tag = evoFor and ('Evoluciona ' .. evoFor.name) or 'Mejora',
            desc2 = evoFor and 'O evoluciona tu Pokémon y lleva un objeto.' or nil,
            title = s.title, desc = s.desc,
            apply = function(p)
                st.apply(p)
                p.statsTaken[st.id] = (p.statsTaken[st.id] or 0) + 1
            end,
        }
    end

    return out
end

-- Devuelve n cartas distintas, elegidas por peso.
function L.offer(pl, n)
    n = n or 3
    local pool = candidates(pl)
    local picked, used = {}, {}
    -- Si hay una evolución lista, su carta dorada sale siempre.
    for i, c in ipairs(pool) do
        if c.type == 'evo' then
            table.remove(pool, i)
            used[c.key] = true
            picked[#picked + 1] = c
            break
        end
    end
    while #picked < n and #pool > 0 do
        local total = 0
        for _, c in ipairs(pool) do total = total + c.w end
        local r, idx = love.math.random() * total, 1
        for i, c in ipairs(pool) do
            r = r - c.w
            if r <= 0 then idx = i break end
        end
        local c = table.remove(pool, idx)
        if not used[c.key] then
            used[c.key] = true
            picked[#picked + 1] = c
        end
    end
    return picked
end
