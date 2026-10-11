-- achievements.lua — logros, medallas y títulos (port de js/data/achievements.js).
-- Cada logro: medalla (bronce 1, plata 2, oro 3), premio al conseguirlo y, a
-- veces, un título para el perfil. Se comprueban en src/progress.lua.
--
--   value(save) -> progreso actual (número) · goal -> lo que hay que llegar
--
-- Además hay un logro por CADA legendario: vencerle en una grieta.
-- Requiere cargados antes: G.DEX / G.DEX_BY (src/dex.lua), G.Moves y G.Sprites.
--
-- Las tablas de la partida (owned, shiny, legends...) pueden venir del JSON
-- con claves numéricas o de texto ("25"): aquí se aceptan las dos.
local U = G.U
local A = {}
G.AchDefs = A

-- ¿Tiene la tabla `t` la clave `dex` (como número o como texto)?
local function hasKey(t, dex)
    if not t then return false end
    return t[dex] ~= nil or t[tostring(dex)] ~= nil
end

local function own(s)
    local n = 0
    for k in pairs(s.owned or {}) do
        if G.DEX_BY[tonumber(k)] then n = n + 1 end
    end
    return n
end
local function shinies(s) return U.count(s.shiny or {}) end
local function legends(s) return U.count(s.legends or {}) end
local function st(k) return function(s) return (s.stats and s.stats[k]) or 0 end end
local function count(k) return function(s) return U.count(s[k] or {}) end end
local bestTime = st('bestTime')
local function bestMin(s) return math.floor(bestTime(s) / 60) end

A.CATS = { { 'coleccion', 'Colección' }, { 'supervivencia', 'Supervivencia' }, { 'combate', 'Combate' },
           { 'grietas', 'Grietas' }, { 'legendarios', 'Legendarios' }, { 'otros', 'Misiones y más' } }

local LIST = {
    -- ---------- colección ----------
    { id = 'own1', cat = 'coleccion', tier = 1, name = 'Primer compañero', desc = 'Ten 1 Pokémon.', value = own, goal = 1, reward = { coins = 100 } },
    { id = 'own10', cat = 'coleccion', tier = 1, name = 'Pequeño equipo', desc = 'Ten 10 Pokémon.', value = own, goal = 10, reward = { t1 = 2 } },
    { id = 'own50', cat = 'coleccion', tier = 2, name = 'Coleccionista', desc = 'Ten 50 Pokémon.', value = own, goal = 50, reward = { t1 = 5 }, title = 'Coleccionista' },
    { id = 'own100', cat = 'coleccion', tier = 2, name = 'Cien amigos', desc = 'Ten 100 Pokémon.', value = own, goal = 100, reward = { t10 = 1 } },
    { id = 'own250', cat = 'coleccion', tier = 3, name = 'Maestro Pokémon', desc = 'Ten 250 Pokémon.', value = own, goal = 250, reward = { t10 = 2 }, title = 'Maestro Pokémon' },
    { id = 'own500', cat = 'coleccion', tier = 3, name = 'Enciclopedia', desc = 'Ten 500 Pokémon.', value = own, goal = 500, reward = { t10 = 3 } },
    { id = 'ownAll', cat = 'coleccion', tier = 3, name = 'Profesor Pokémon', desc = 'Ten todos los Pokémon del juego.', value = own, goal = 966, reward = { t10 = 10 }, title = 'Profesor Pokémon' },
    { id = 'shiny1', cat = 'coleccion', tier = 1, name = 'Algo brilla', desc = 'Consigue 1 shiny.', value = shinies, goal = 1, reward = { t1 = 3 }, title = 'Brillante' },
    { id = 'shiny5', cat = 'coleccion', tier = 2, name = 'Ojo para el brillo', desc = 'Consigue 5 shinies.', value = shinies, goal = 5, reward = { t10 = 1 } },
    { id = 'shiny20', cat = 'coleccion', tier = 3, name = 'Cazashinies', desc = 'Consigue 20 shinies.', value = shinies, goal = 20, reward = { t10 = 2 }, title = 'Cazashinies' },
    { id = 'pulls100', cat = 'coleccion', tier = 2, name = 'Tragaperras', desc = 'Haz 100 tiradas en el gacha.', value = st('pulls'), goal = 100, reward = { t10 = 1 }, title = 'Afortunado' },

    -- ---------- supervivencia ----------
    { id = 'time5', cat = 'supervivencia', tier = 1, name = 'Calentando', desc = 'Aguanta 5 minutos.', value = bestMin, goal = 5, reward = { coins = 200 } },
    { id = 'time10', cat = 'supervivencia', tier = 2, name = 'Duro de pelar', desc = 'Aguanta 10 minutos.', value = bestMin, goal = 10, reward = { t1 = 4 } },
    { id = 'time15', cat = 'supervivencia', tier = 2, name = 'Resistente', desc = 'Aguanta 15 minutos.', value = bestMin, goal = 15, reward = { t10 = 1 } },
    { id = 'time20', cat = 'supervivencia', tier = 3, name = 'Superviviente', desc = 'Aguanta 20 minutos.', value = bestMin, goal = 20, reward = { t10 = 2 }, title = 'Superviviente' },
    { id = 'lvl20', cat = 'supervivencia', tier = 1, name = 'Creciendo', desc = 'Llega al nivel 15 en una run.', value = st('bestLevel'), goal = 15, reward = { t1 = 2 } },
    { id = 'lvl40', cat = 'supervivencia', tier = 3, name = 'Imparable', desc = 'Llega al nivel 30 en una run.', value = st('bestLevel'), goal = 30, reward = { t10 = 1 }, title = 'Imparable' },
    { id = 'runs50', cat = 'supervivencia', tier = 2, name = 'Explorador', desc = 'Juega 50 runs.', value = st('runs'), goal = 50, reward = { t10 = 1 }, title = 'Explorador' },

    -- ---------- combate ----------
    { id = 'kills1k', cat = 'combate', tier = 1, name = 'Primeros combates', desc = 'Derrota a 1.000 Pokémon.', value = st('totalKills'), goal = 1000, reward = { t1 = 2 } },
    { id = 'kills10k', cat = 'combate', tier = 2, name = 'Veterano', desc = 'Derrota a 10.000 Pokémon.', value = st('totalKills'), goal = 10000, reward = { t10 = 1 }, title = 'Veterano' },
    { id = 'kills100k', cat = 'combate', tier = 3, name = 'Leyenda viva', desc = 'Derrota a 100.000 Pokémon.', value = st('totalKills'), goal = 100000, reward = { t10 = 3 }, title = 'Leyenda viva' },
    { id = 'boss1', cat = 'combate', tier = 1, name = 'Matagigantes', desc = 'Derrota a un jefe.', value = st('bossesTotal'), goal = 1, reward = { t1 = 2 } },
    { id = 'boss25', cat = 'combate', tier = 2, name = 'Cazajefes', desc = 'Derrota a 25 jefes.', value = st('bossesTotal'), goal = 25, reward = { t10 = 1 }, title = 'Cazajefes' },
    { id = 'boss100', cat = 'combate', tier = 3, name = 'Terror de los jefes', desc = 'Derrota a 100 jefes.', value = st('bossesTotal'), goal = 100, reward = { t10 = 2 } },
    { id = 'evo1', cat = 'combate', tier = 1, name = 'Evolución', desc = 'Evoluciona un movimiento.', value = st('evolutions'), goal = 1, reward = { t1 = 3 } },
    { id = 'evo25', cat = 'combate', tier = 2, name = 'Evolucionista', desc = 'Evoluciona 25 movimientos.', value = st('evolutions'), goal = 25, reward = { t10 = 1 }, title = 'Evolucionista' },
    { id = 'evoAll', cat = 'combate', tier = 3, name = 'Maestro de movimientos', desc = 'Evoluciona los 47 movimientos distintos.', value = count('evoMoves'), goal = 47, reward = { t10 = 3 }, title = 'Maestro de movimientos' },
    { id = 'items5', cat = 'combate', tier = 1, name = 'Bolsa llena', desc = 'Encuentra 5 objetos distintos.', value = count('itemsFound'), goal = 5, reward = { t1 = 3 } },
    { id = 'itemsAll', cat = 'combate', tier = 2, name = 'Coleccionista de objetos', desc = 'Encuentra los 11 objetos.', value = count('itemsFound'), goal = 11, reward = { t10 = 1 }, title = 'Anticuario' },

    -- ---------- grietas ----------
    { id = 'rift1', cat = 'grietas', tier = 1, name = 'Al otro lado', desc = 'Gana tu primera pelea en una grieta.', value = st('riftWins'), goal = 1, reward = { t1 = 3 }, title = 'Valiente' },
    { id = 'rift10', cat = 'grietas', tier = 2, name = 'Saltagrietas', desc = 'Gana 10 peleas en grietas.', value = st('riftWins'), goal = 10, reward = { t10 = 1 } },
    { id = 'arenas', cat = 'grietas', tier = 3, name = 'Viajero de grietas', desc = 'Gana en las 18 arenas (una por tipo).', value = count('arenas'), goal = 18, reward = { t10 = 2 }, title = 'Viajero de grietas' },

    -- ---------- legendarios (contador; los individuales se añaden abajo) ----------
    { id = 'leg10', cat = 'legendarios', tier = 2, name = 'Cazalegendarios', desc = 'Vence a 10 legendarios distintos.', value = legends, goal = 10, reward = { t10 = 1 }, title = 'Cazalegendarios' },
    { id = 'leg30', cat = 'legendarios', tier = 3, name = 'Domador de mitos', desc = 'Vence a 30 legendarios distintos.', value = legends, goal = 30, reward = { t10 = 2 } },
    { id = 'legAll', cat = 'legendarios', tier = 3, name = 'Leyenda', desc = 'Vence a todos los legendarios.', value = legends, goal = 87, reward = { t10 = 5 }, title = 'Leyenda' },

    -- ---------- misiones y más ----------
    { id = 'mis10', cat = 'otros', tier = 1, name = 'Cumplidor', desc = 'Completa 10 misiones.', value = st('missionsDone'), goal = 10, reward = { t1 = 3 } },
    { id = 'mis50', cat = 'otros', tier = 2, name = 'Constante', desc = 'Completa 50 misiones.', value = st('missionsDone'), goal = 50, reward = { t10 = 1 }, title = 'Constante' },
    { id = 'mis200', cat = 'otros', tier = 3, name = 'Incansable', desc = 'Completa 200 misiones.', value = st('missionsDone'), goal = 200, reward = { t10 = 3 } },
    { id = 'group1', cat = 'otros', tier = 1, name = 'En compañía', desc = 'Juega una partida en grupo.', value = st('groupRuns'), goal = 1, reward = { t1 = 2 } },
    { id = 'group10', cat = 'otros', tier = 2, name = 'Compañero fiel', desc = 'Juega 10 partidas en grupo.', value = st('groupRuns'), goal = 10, reward = { t10 = 1 }, title = 'Compañero fiel' }
}
A.LIST = LIST

-- Un logro por legendario (con sprite): "Vence a Mewtwo"...
local function legendValue(dex)
    return function(s) if hasKey(s.legends, dex) then return 1 end return 0 end
end
local totalLegends = 0
for i = 1, #G.DEX do
    local p = G.DEX[i]
    if p.leg and G.Sprites.meta(p.dex) then
        totalLegends = totalLegends + 1
        LIST[#LIST + 1] = { id = 'leg_' .. p.dex, cat = 'legendarios', tier = 2, dex = p.dex, name = 'Vence a ' .. p.name,
                            desc = 'Derrota a ' .. p.name .. ' en una grieta.', value = legendValue(p.dex), goal = 1,
                            reward = { t1 = 1 } }
    end
end

-- Metas que dependen de los datos del juego.
local evoTotal = U.count(G.Moves.EVO)
local BY = {}
for i = 1, #LIST do
    local a = LIST[i]
    if a.id == 'legAll' then a.goal = totalLegends; a.desc = 'Vence a los ' .. totalLegends .. ' legendarios.' end
    if a.id == 'ownAll' then a.goal = #G.DEX; a.desc = 'Ten los ' .. #G.DEX .. ' Pokémon del juego.' end
    if a.id == 'evoAll' then a.goal = evoTotal; a.desc = 'Evoluciona los ' .. evoTotal .. ' movimientos distintos.' end
    BY[a.id] = a
end
A.BY = BY
