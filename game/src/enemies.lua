-- enemies.lua — Pokémon salvajes de todas las generaciones (port de js/data/enemies.js).
--
-- Los tramos no son listas fijas: cada tramo recoge a todos los Pokémon (de
-- cualquier generación) cuyo total de stats base cae en su rango, y al empezar
-- una run se elige al azar un ELENCO de cada tramo. Así cada partida trae
-- Pokémon distintos sin tener que cargar cientos de sprites a la vez.
-- En la 3DS el elenco por tramo es de 5 (en la web, 7).
--
-- Los stats de combate salen de la plantilla del tramo, ajustados con la
-- vida y la velocidad propias de cada Pokémon.
--
-- behavior:
--   chase    va directo a por ti
--   charger  se para, apunta y embiste
--   ranged   se mantiene a distancia y dispara
--   tank     lento, mucha vida
--   ---- con personalidad ----
--   healer   cura a los de alrededor (Chansey, Blissey, Audino...)
--   shielder pone escudos a sus compañeros (Shuckle, Bronzong, Mr. Mime...)
--   summoner llama a su manada (Nidoqueen trae Nidoran, Vespiquen Combee...)
--   bomber   se acerca y explota (Voltorb, Electrode, Koffing, Geodude...)
--   beamer   rayo que avisa en el suelo antes de disparar
--   zoner    zonas de daño bajo tus pies que estallan al poco
--   fan      dispara en abanico
--   jumper   salta y cae sobre ti (la caída se ve antes en el suelo)
--   runner   corredor: muy rápido y frágil, va a donde vas a estar. Uno por
--            tramo: el más rápido del elenco.
-- Los ataques con aviso están en src/hazards.lua.
--
-- Jefes: Pokémon fuertes NO legendarios (pseudolegendarios, Slaking...), al
-- azar por franjas de poder. Los legendarios sólo salen en las grietas (src/rift.lua).
local U = G.U
local E = {}
G.Enemies = E

local floor, random = math.floor, love.math.random

local TIERS = {
    { from = 0,   bst = { 180, 330 }, hp = 17,  spd = 56, dmg = 6,   xp = 3.5, cast = 5 },
    { from = 70,  bst = { 300, 405 }, hp = 32,  spd = 62, dmg = 8.5, xp = 5,   cast = 5 },
    { from = 160, bst = { 385, 465 }, hp = 52,  spd = 60, dmg = 11,  xp = 8,   cast = 5 },
    { from = 260, bst = { 445, 515 }, hp = 88,  spd = 70, dmg = 14,  xp = 13,  cast = 5 },
    { from = 380, bst = { 495, 560 }, hp = 150, spd = 66, dmg = 22,  xp = 24,  cast = 5 },
    { from = 500, bst = { 530, 620 }, hp = 250, spd = 72, dmg = 28,  xp = 38,  cast = 5 }
}
E.TIERS = TIERS

-- Franjas de jefe: segundo en que salen, PV base y franja de BST.
local BOSS_SLOTS = {
    { at = 180, hp = 1400,  dmg = 34, xp = 220,  bst = { 490, 545 } },
    { at = 360, hp = 3200,  dmg = 42, xp = 420,  bst = { 520, 580 } },
    { at = 540, hp = 5600,  dmg = 48, xp = 680,  bst = { 540, 600 } },
    { at = 720, hp = 9000,  dmg = 56, xp = 1000, bst = { 580, 700 } },
    { at = 900, hp = 16000, dmg = 68, xp = 1800, bst = { 600, 700 } }
}
E.BOSS_SLOTS = BOSS_SLOTS

-- Stats base aproximados a partir de los de juego (inverso de fetch_pokedex).
local function baseHp(p) return (p.hp - 70) / 0.45 end
local function baseSpd(p) return (p.spd - 78) / 0.42 end

local function H(d, s) return U.hash(d, 7, s) end

-- ¿Tiene el sprite (y por tanto puede salir)?
local function hasSprite(dex) return G.Sprites.meta(dex) ~= nil end

-- Personalidades fijas de algunos Pokémon.
local function set(list) local s = {} for i = 1, #list do s[list[i]] = true end return s end
local HEAL = set({ 35, 36, 113, 173, 183, 184, 242, 301, 440, 531, 594, 700, 764, 858 })
local SHIELD = set({ 95, 122, 208, 213, 227, 306, 375, 410, 411, 436, 437, 439, 476, 703 })
local BOMB = set({ 74, 75, 76, 100, 101, 102, 109, 110, 337, 338, 343, 344 })
-- Invocador -> Pokémon de su manada.
local SUMMON = { [15] = 13, [18] = 16, [24] = 23, [28] = 27, [31] = 29, [34] = 32, [42] = 41, [51] = 50, [53] = 52,
                 [57] = 56, [59] = 58, [62] = 60, [68] = 66, [73] = 72, [78] = 77, [82] = 81, [85] = 84, [91] = 90,
                 [117] = 116, [130] = 129, [168] = 167, [169] = 41, [199] = 79, [230] = 116, [262] = 261,
                 [334] = 333, [405] = 403, [416] = 415, [462] = 81, [466] = 239, [553] = 551, [637] = 636 }

-- ¿Tiene alguno de los tipos dados? (hasta 7 argumentos, sin varargs)
local function has(t, a, b, c, d, e, f, g)
    for i = 1, #t do
        local x = t[i]
        if x == a or x == b or x == c or x == d or x == e or x == f or x == g then return true end
    end
    return false
end

local behaviorCache = {}   -- dex -> behavior (es determinista por Pokémon)

local function behaviorOf(p)
    local cached = behaviorCache[p.dex]
    if cached then return cached end
    local t, h = p.types, H(p.dex, 11)
    local r
    if HEAL[p.dex] then r = 'healer'
    elseif SHIELD[p.dex] then r = 'shielder'
    elseif BOMB[p.dex] then r = 'bomber'
    elseif SUMMON[p.dex] and hasSprite(SUMMON[p.dex]) then r = 'summoner'
    -- Enjambres: algunos Bicho llaman a más de los suyos (desde el principio).
    elseif has(t, 'bug') and h >= 0.6 and h < 0.78 then r = 'summoner'
    elseif has(t, 'electric', 'psychic', 'dragon', 'ice') and h < 0.18 then r = 'beamer'
    elseif has(t, 'fire', 'ground', 'poison') and h < 0.18 then r = 'zoner'
    elseif has(t, 'water', 'grass', 'bug', 'fairy') and h >= 0.18 and h < 0.32 then r = 'fan'
    elseif has(t, 'fighting', 'ground', 'normal', 'rock') and h >= 0.42 and h < 0.56 then r = 'jumper'
    elseif has(t, 'psychic', 'electric', 'ghost', 'fairy') and h < 0.4 then r = 'ranged'
    elseif has(t, 'fire', 'water', 'poison', 'ice') and h < 0.22 then r = 'ranged'
    elseif has(t, 'fighting', 'normal', 'ground', 'rock', 'dragon', 'steel', 'dark') and h < 0.4 then r = 'charger'
    elseif baseHp(p) > 95 and baseSpd(p) < 50 then r = 'tank'
    else r = 'chase' end
    behaviorCache[p.dex] = r
    return r
end
E.behaviorOf = behaviorOf

-- Equivale a (+x.toFixed(2)) del JS.
local function round2(x) return floor(x * 100 + 0.5) / 100 end

-- Construye la definición de enemigo de un Pokémon para un tramo.
-- `ti` es el índice del tramo EMPEZANDO EN 0 (como en el JS: entra en las fórmulas).
local function defFor(p, tier, ti)
    local hpK = U.clamp(baseHp(p) / 65, 0.7, 1.6)
    local spdK = U.clamp(0.75 + baseSpd(p) / 260, 0.75, 1.3)
    local behavior = behaviorOf(p)
    local tank = behavior == 'tank'
    local d = {
        dex = p.dex, name = p.name, behavior = behavior,
        hp = U.round(tier.hp * hpK * (tank and 1.5 or 1)),
        spd = U.round(tier.spd * spdK * (tank and 0.7 or 1)),
        dmg = U.round(tier.dmg * (tank and 1.2 or 1)),
        xp = math.max(3, U.round(tier.xp * (tank and 1.3 or 1)))
    }
    -- Los que pelean de lejos: daño del disparo, recarga y distancia.
    local cd
    if behavior == 'ranged' then cd = 2.2 - ti * 0.15
    elseif behavior == 'fan' then cd = 3.2 - ti * 0.15
    elseif behavior == 'beamer' then cd = 4.4 - ti * 0.2
    elseif behavior == 'zoner' then cd = 4.6 - ti * 0.2
    elseif behavior == 'healer' then cd = 3.5
    elseif behavior == 'summoner' then cd = 7 end
    if cd then
        d.shotDmg = U.round(tier.dmg * (behavior == 'fan' and 0.7 or 0.8))
        d.shotCd = round2(cd)
        local base = 190
        if behavior == 'beamer' then base = 260
        elseif behavior == 'healer' or behavior == 'summoner' then base = 230 end
        d.range = base + ti * 6
    end
    if behavior == 'summoner' then d.minion = SUMMON[p.dex] end
    if behavior == 'fan' then d.fanN = (ti < 2) and 3 or 5 end                 -- abanico más ancho más adelante
    if behavior == 'zoner' then d.zones = (ti < 2) and 1 or ((ti < 4) and 2 or 3) end -- más zonas más adelante
    if behavior == 'bomber' then d.spd = U.round(d.spd * 1.25); d.hp = U.round(d.hp * 0.8) end
    return d
end
E.defFor = defFor

-- Todos los candidatos de un tramo (sin legendarios ni míticos).
function E.candidates(tier)
    local out = {}
    local DEX = G.DEX
    for i = 1, #DEX do
        local p = DEX[i]
        if p.rarity < 5 and p.bst >= tier.bst[1] and p.bst <= tier.bst[2] and hasSprite(p.dex) then
            out[#out + 1] = p
        end
    end
    return out
end

-- ---------------- elenco de la run ----------------

local PLAIN = set({ 'chase', 'charger', 'ranged', 'tank' })
local SUPPORT = { 'healer', 'shielder', 'summoner' }
local SUPPORT_SET = set(SUPPORT)

-- Filtra `all` con un predicado (solo al sortear la run, no por fotograma).
local function filter(all, fn)
    local out = {}
    for i = 1, #all do if fn(all[i]) then out[#out + 1] = all[i] end end
    return out
end

-- Elenco de un tramo: siempre un "apoyo" (curandero, escudo o invocador) y,
-- desde el segundo tramo, también uno de los que atacan con aviso. En el
-- primero no hay más personalidades (para ir aprendiendo).
local function castFor(tier)
    local all = E.candidates(tier)
    -- Primero el tipo de apoyo (a partes iguales) y luego el Pokémon.
    local kinds = {}
    for i = 1, #SUPPORT do
        local k = SUPPORT[i]
        for j = 1, #all do
            if behaviorOf(all[j]) == k then kinds[#kinds + 1] = k; break end
        end
    end
    local sk = (#kinds > 0) and kinds[floor(random() * #kinds) + 1] or nil
    local pick = {}
    if sk then
        pick = U.pickN(filter(all, function(p) return behaviorOf(p) == sk end), 1)
    end
    if tier.from > 0 then
        local extra = U.pickN(filter(all, function(p)
            local k = behaviorOf(p)
            return not PLAIN[k] and not SUPPORT_SET[k]
        end), 1)
        for i = 1, #extra do pick[#pick + 1] = extra[i] end
    end
    local rest
    if tier.from == 0 then
        rest = U.pickN(filter(all, function(p) return not U.contains(pick, p) and PLAIN[behaviorOf(p)] end),
                       tier.cast - #pick)
    else
        rest = U.pickN(filter(all, function(p) return not U.contains(pick, p) end), tier.cast - #pick)
    end
    for i = 1, #rest do pick[#pick + 1] = rest[i] end
    return pick
end

local cast = nil      -- { { from, list = { def } } }
local bosses = nil    -- { def de jefe }
local bagCacheT, bagCache = nil, nil   -- caché de bagAt por segundo entero

-- Sortea el elenco de una run nueva.
function E.rollRun()
    cast = {}
    bagCacheT, bagCache = nil, nil
    for ti = 1, #TIERS do
        local tier = TIERS[ti]
        local mons = castFor(tier)
        local list = {}
        for i = 1, #mons do list[i] = defFor(mons[i], tier, ti - 1) end
        cast[ti] = { from = tier.from, list = list }
    end
    -- Un corredor por tramo: el más rápido de los "normales".
    for ti = 1, #cast do
        local list, r = cast[ti].list, nil
        for i = 1, #list do
            local d = list[i]
            if (d.behavior == 'chase' or d.behavior == 'charger' or d.behavior == 'tank')
               and (r == nil or d.spd > r.spd) then r = d end
        end
        if r then r.behavior = 'runner'; r.spd = U.round(r.spd * 1.6); r.hp = U.round(r.hp * 0.7) end
    end
    local used = {}
    bosses = {}
    local DEX = G.DEX
    for si = 1, #BOSS_SLOTS do
        local slot = BOSS_SLOTS[si]
        local pool = {}
        for i = 1, #DEX do
            local p = DEX[i]
            if not p.leg and hasSprite(p.dex) and not used[p.dex]
               and p.bst >= slot.bst[1] and p.bst <= slot.bst[2] then pool[#pool + 1] = p end
        end
        if #pool == 0 then
            for i = 1, #DEX do
                local p = DEX[i]
                if not p.leg and hasSprite(p.dex) and not used[p.dex] and p.bst >= 580 then pool[#pool + 1] = p end
            end
        end
        local p = U.pick(pool)
        used[p.dex] = true
        local bh = behaviorOf(p)
        if bh ~= 'ranged' then bh = (baseSpd(p) > 90) and 'charger' or 'chase' end
        bosses[si] = {
            at = slot.at, dex = p.dex, name = p.name,
            -- (Desde 2026-10-10 más duros: ×1,35 de vida y ×1,2 de daño.)
            hp = U.round(slot.hp * 1.35), spd = U.round(U.clamp(40 + baseSpd(p) * 0.5, 40, 100)),
            dmg = U.round(slot.dmg * 1.2), xp = slot.xp,
            behavior = bh,
            shotDmg = U.round(slot.dmg * 0.55), shotCd = 1.1, range = 260
        }
    end
    return { cast = cast, bosses = bosses }
end

-- Tiempo extra (web, 12-10-2026). Hasta el minuto 60 todo sigue igual; desde
-- ahí la vida (y algo menos el daño) crece cada vez más deprisa, como en otros
-- "survivors". Antes crecía en línea recta y, con las mejoras al máximo, las
-- mejores builds aguantaban sin fin.
--   minuto   60    75    90    105   120   150
--   vida    x1   x1,09 x1,4  x2,1  x3,8  x21    (además de la subida normal)
-- (En la web se quitó al llegar la Sentencia de Arceus del minuto 30; aquí se
-- mantiene: vale para todo lo que siga saliendo pasada la hora.)
E.LATE_FROM = 60
local LATE_K = 0.000374
function E.late(t)
    local m = math.max(0, t / 60 - E.LATE_FROM)
    return math.exp(math.min(30, LATE_K * m * m))
end

function E.scale(t)
    local k = E.late(t)
    return { hp = (1 + t / 95) * k, dmg = (1 + t / 420) * k ^ 0.7, spd = 1 + math.min(0.35, t / 1400) }
end

-- Los jefes ya traen su vida base creciente (1.400 ... 16.000), así que
-- escalan mucho más suave: con la curva normal el último llegaba a 168.000 PV.
function E.bossScale(t)
    local k = E.late(t)
    return { hp = (1 + t / 600) * k, dmg = (1 + t / 600) * k ^ 0.7, spd = 1 }
end

-- Índice (1-based, en E.TIERS) del tramo que toca en el segundo `t`.
function E.tierAt(t)
    local ti = 1
    for i = 1, #TIERS do if t >= TIERS[i].from then ti = i end end
    return ti
end

local NO_HORDE = set({ 'bomber', 'healer', 'shielder', 'summoner' })

-- Tipos con bastantes Pokémon en el tramo actual para una horda (src/events.lua).
function E.hordeTypes(t)
    local all = filter(E.candidates(TIERS[E.tierAt(t)]), function(p) return not NO_HORDE[behaviorOf(p)] end)
    local out = {}
    local TYPES = U.TYPES
    for i = 1, #TYPES do
        local ty, n = TYPES[i], 0
        for j = 1, #all do if U.contains(all[j].types, ty) then n = n + 1 end end
        if n >= 3 then out[#out + 1] = ty end
    end
    return out
end

-- Hasta 4 Pokémon de un tipo, con los stats del tramo actual.
function E.hordeDefs(type, t)
    local ti = E.tierAt(t)
    local pool = filter(E.candidates(TIERS[ti]), function(p)
        return U.contains(p.types, type) and not NO_HORDE[behaviorOf(p)]
    end)
    local mons = U.pickN(pool, 4)
    local out = {}
    for i = 1, #mons do out[i] = defFor(mons[i], TIERS[ti], ti - 1) end
    return out
end

-- Bolsa de enemigos disponibles en el segundo `t` (lista de defs, con repeticiones
-- según peso). No modificar la tabla devuelta: se cachea por segundo entero.
function E.bagAt(t)
    -- Durante una horda de un tipo sólo salen los de ese tipo (src/events.lua).
    local horde = G.Events and G.Events.bag and G.Events.bag()
    if horde then return horde end
    if not cast then E.rollRun() end
    local sec = floor(t)
    if bagCache and bagCacheT == sec then return bagCache end
    local bag = {}
    for ti = 1, #cast do
        local tier = cast[ti]
        if t >= tier.from then
            local w = (t - tier.from > 260) and 3 or 10       -- los tramos viejos pierden peso
            local list = tier.list
            for i = 1, #list do
                for _ = 1, w do bag[#bag + 1] = list[i] end
            end
        end
    end
    if #bag == 0 then bag = cast[1].list end
    bagCacheT, bagCache = sec, bag
    return bag
end

-- dex del elenco que aparecerán pronto (para precargar sprites).
function E.upcomingDex(t, ahead)
    ahead = ahead or 60
    if not cast then E.rollRun() end
    local out = {}
    for ti = 1, #cast do
        local tier = cast[ti]
        if tier.from <= t + ahead then
            for i = 1, #tier.list do out[#out + 1] = tier.list[i].dex end
        end
    end
    for i = 1, #bosses do
        if bosses[i].at <= t + ahead then out[#out + 1] = bosses[i].dex end
    end
    return out
end

-- Getters del JS -> funciones.
function E.BOSSES() if not bosses then E.rollRun() end return bosses end
function E.cast() if not cast then E.rollRun() end return cast end
