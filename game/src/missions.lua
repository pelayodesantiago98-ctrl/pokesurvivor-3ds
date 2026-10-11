-- missions.lua — plantillas de misiones diarias y semanales (port de js/data/missions.js).
-- Cada día salen 3 diarias y cada semana 2 semanales, con objetivos y tipos
-- sorteados. Se completan jugando y el premio se recoge en la pantalla de
-- Misiones. La lógica está en src/progress.lua.
--
--   ev      evento que la hace avanzar (ver G.Progress.event)
--   match   (datos, parámetro) -> ¿cuenta este evento?
--   value   datos -> cuánto vale; con mode 'max' se queda el mayor, con
--           'add' (por defecto) se suma (1 si no hay value)
--   param   'type': sortea un tipo Pokémon para la misión
--   text    (n, param) -> texto del objetivo
local U = G.U
local MD = {}
G.MissionDefs = MD

local function T(t) return U.TYPE_NAME[t] end
local function min(d) return math.floor(d.time / 60) end
local function isBoss(d) return d.boss and true or false end
local function isDaily(d) return d.daily and true or false end
local function hasType(d, t) return U.contains(d.types, t) end

-- Equivale a n.toLocaleString('es'): separador de miles con punto a partir de 5 cifras.
local function fmtEs(n)
    local s = tostring(math.floor(n))
    if #s < 5 then return s end
    local out = ''
    while #s > 3 do
        out = '.' .. s:sub(-3) .. out
        s = s:sub(1, -4)
    end
    return s .. out
end
MD.fmtEs = fmtEs

local daily = {
    { id = 'kill', ev = 'kill', goals = { 300, 500, 800 }, reward = { t1 = 2, coins = 150 },
      text = function(n) return 'Derrota a ' .. n .. ' Pokémon' end },
    { id = 'killType', ev = 'kill', param = 'type', goals = { 30, 50, 80 }, reward = { t1 = 2, coins = 200 },
      match = hasType, text = function(n, t) return 'Derrota a ' .. n .. ' Pokémon de tipo ' .. T(t) end },
    { id = 'survive', ev = 'runEnd', mode = 'max', value = min, goals = { 5, 7, 9 }, reward = { t1 = 3, coins = 200 },
      text = function(n) return 'Aguanta ' .. n .. ' minutos en una run' end },
    { id = 'level', ev = 'runEnd', mode = 'max', value = function(d) return d.level end, goals = { 8, 12, 15 }, reward = { t1 = 2, coins = 200 },
      text = function(n) return 'Llega al nivel ' .. n .. ' en una run' end },
    { id = 'boss', ev = 'kill', match = isBoss, goals = { 1, 2 }, reward = { t1 = 3, coins = 250 },
      text = function(n) if n == 1 then return 'Derrota a un jefe' end return 'Derrota a ' .. n .. ' jefes' end },
    { id = 'chest', ev = 'chest', goals = { 1, 2 }, reward = { t1 = 2, coins = 200 },
      text = function(n) if n == 1 then return 'Abre un cofre con candado' end return 'Abre ' .. n .. ' cofres con candado' end },
    { id = 'coins', ev = 'runEnd', value = function(d) return d.coins end, goals = { 100, 200, 300 }, reward = { t1 = 2, coins = 150 },
      text = function(n) return 'Recoge ' .. n .. ' monedas en tus runs' end },
    { id = 'playType', ev = 'runEnd', param = 'type', mode = 'max', value = min, goals = { 3 }, reward = { t1 = 3, coins = 200 },
      match = hasType, text = function(n, t) return 'Aguanta ' .. n .. ' minutos con un Pokémon de tipo ' .. T(t) end },
    { id = 'item', ev = 'item', goals = { 1 }, reward = { t1 = 2, coins = 150 },
      text = function() return 'Encuentra un objeto equipable' end },
    { id = 'evolve', ev = 'evolve', goals = { 1 }, reward = { t1 = 3, coins = 250 },
      text = function() return 'Evoluciona un movimiento' end }
}
MD.daily = daily

local weekly = {
    { id = 'wkill', ev = 'kill', goals = { 4000, 6000 }, reward = { t10 = 1, coins = 800 },
      text = function(n) return 'Derrota a ' .. fmtEs(n) .. ' Pokémon' end },
    { id = 'wrift', ev = 'rift', goals = { 1, 2 }, reward = { t10 = 1, coins = 1000 },
      text = function(n) if n == 1 then return 'Gana una pelea en una grieta' end return 'Gana ' .. n .. ' peleas en grietas' end },
    { id = 'wboss', ev = 'kill', match = isBoss, goals = { 4, 6 }, reward = { t10 = 1, coins = 900 },
      text = function(n) return 'Derrota a ' .. n .. ' jefes' end },
    { id = 'wsurvive', ev = 'runEnd', mode = 'max', value = min, goals = { 12, 15 }, reward = { t10 = 1, coins = 1000 },
      text = function(n) return 'Aguanta ' .. n .. ' minutos en una run' end },
    { id = 'wevolve', ev = 'evolve', goals = { 3, 5 }, reward = { t10 = 1, coins = 900 },
      text = function(n) return 'Evoluciona ' .. n .. ' movimientos' end },
    { id = 'wdaily', ev = 'missionDone', match = isDaily, goals = { 8, 12 }, reward = { t10 = 1, coins = 800 },
      text = function(n) return 'Completa ' .. n .. ' misiones diarias' end }
}
MD.weekly = weekly

local BY = {}
for i = 1, #daily do BY[daily[i].id] = daily[i] end
for i = 1, #weekly do BY[weekly[i].id] = weekly[i] end
MD.BY = BY
