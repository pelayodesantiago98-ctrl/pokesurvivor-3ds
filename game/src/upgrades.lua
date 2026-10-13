-- upgrades.lua — mejoras permanentes entre runs (port de js/data/upgrades.js).
-- Se compran con Pokémonedas en el menú. `unit` es lo que da cada nivel.
local U = G.U
local Up = {}
G.Upgrades = Up

local LIST = {
    { id = 'hp',     icon = 'heart',  name = 'Vitalidad',  unit = '+8 vida',           max = 10, base = 60,   grow = 1.35 },
    { id = 'atk',    icon = 'fist',   name = 'Fuerza',     unit = '+4% daño',          max = 10, base = 80,   grow = 1.38 },
    { id = 'spd',    icon = 'boot',   name = 'Zancada',    unit = '+3% velocidad',     max = 8,  base = 70,   grow = 1.4 },
    { id = 'cd',     icon = 'clock',  name = 'Reflejos',   unit = '-3% recarga',       max = 8,  base = 90,   grow = 1.42 },
    { id = 'def',    icon = 'shield', name = 'Coraza',     unit = '+2% defensa',       max = 8,  base = 80,   grow = 1.4 },
    { id = 'regen',  icon = 'sprout', name = 'Síntesis',   unit = '+0.2 vida/s',       max = 5,  base = 120,  grow = 1.5 },
    { id = 'magnet', icon = 'magnet', name = 'Imán',       unit = '+12% recogida',     max = 6,  base = 50,   grow = 1.4 },
    { id = 'xp',     icon = 'book',   name = 'Sabiduría',  unit = '+5% experiencia',   max = 8,  base = 100,  grow = 1.42 },
    { id = 'coins',  icon = 'coin',   name = 'Fortuna',    unit = '+8% Pokémonedas',   max = 8,  base = 120,  grow = 1.45 },
    { id = 'moves',  icon = 'cards',  name = 'Repertorio', unit = 'Empiezas con 2 movimientos', max = 1, base = 1500, grow = 1 },
    -- Nuevas (web, 12-10-2026). En la 3DS se suman a los 2 repetir + 2 vetar
    -- gratis de la pantalla de cartas; el Veto deja elegir aquí movimientos
    -- que no salen nunca en las cartas (save.pban[dex], ver ui/menu.lua).
    { id = 'crit',   icon = 'star',   name = 'Crítico',    unit = '+3% crítico (x1,5)', max = 10, base = 90,   grow = 1.4 },
    { id = 'reroll', icon = 'up',     name = 'Repetir',    unit = '+1 repetir cartas',  max = 5,  base = 150,  grow = 1.6 },
    { id = 'ban',    icon = 'ban',    name = 'Veto',       unit = '+1 mov. vetado',     max = 3,  base = 300,  grow = 1.9 }
}
Up.LIST = LIST

local BY = {}
for i = 1, #LIST do BY[LIST[i].id] = LIST[i] end
Up.BY = BY

-- Precio del siguiente nivel (lvl = niveles ya comprados), redondeado a decenas.
function Up.cost(id, lvl)
    local u = BY[id]
    return U.round(u.base * math.pow(u.grow, lvl) / 10) * 10
end

-- Niveles comprados -> modificadores para G.Player.
function Up.perks(levels)
    levels = levels or {}
    local function L(id) return levels[id] or 0 end
    return {
        hp = L('hp') * 8,
        atkMul = 1 + L('atk') * 0.04,
        spdMul = 1 + L('spd') * 0.03,
        cdMul = 1 - L('cd') * 0.03,
        dmgReduce = L('def') * 0.02,
        regen = L('regen') * 0.2,
        magnetMul = 1 + L('magnet') * 0.12,
        xpMul = 1 + L('xp') * 0.05,
        coinMul = 1 + L('coins') * 0.08,
        startMoves = 1 + L('moves'),
        crit = L('crit') * 0.03,         -- probabilidad de golpe crítico
        rerolls = L('reroll'),           -- repeticiones de cartas extra por run
        bans = L('ban')                  -- movimientos que se pueden vetar desde Mejoras
    }
end
