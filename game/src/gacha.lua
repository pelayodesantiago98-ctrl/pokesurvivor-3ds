-- gacha.lua — un banner por generación. Port de js/systems/gacha.js.
-- Lógica pura: no toca la interfaz (la pantalla inferior enseña los resultados).
--
-- 9 banners (Kanto ... Paldea). Cada uno con su propio pity.
-- Probabilidades por tirada:  1★ 45% · 2★ 30% · 3★ 17% · 4★ 6.5% · 5★ 1.5%
-- Garantías:
--   - la tirada ×10 trae al menos un 4★ o superior
--   - a las 70 tiradas sin 5★ en ese banner, el siguiente es 5★ seguro
-- Shiny: 1 de cada 100 tiradas sale en su versión shiny.
-- Repetidos: se convierten en Pokémonedas (los shiny repetidos, el triple).
--
-- Se tira con TICKETS (se consiguen jugando):
--   ×1   1 ticket
--   ×10  10 tickets normales, o 1 ticket ×10 (eliges con qué)
--
--   G.Gacha.pull(gen, n, payWith) -> lista de { dex, rarity, shiny, isNew, coins } o nil, motivo
--       (payWith: 't1' tickets normales (por defecto) · 't10' un ticket ×10, solo para n = 10)
--       Opera sobre G.DB.save: cobra, da los Pokémon, suma las monedas de los
--       repetidos, actualiza pity y stats.pulls, comprueba logros y guarda.
--   G.Gacha.costOf(n, payWith) -> t1, t10 (lo que gastaría) o nil si no te llega
--   G.Gacha.banner(gen) -> { gen, name, color, featured = {dex...}, pity } (tabla cacheada; pity al día)
--   G.Gacha.featured(gen) -> los 3 ★5 más fuertes   pool(rarity, gen) -> lista de Pokémon
--   G.Gacha.refund(rarity, shiny) -> monedas por repetido   REFUND, RATES, PITY_5, SHINY_RATE
--   G.Gacha.RARITY_NAME, RARITY_COLOR, BANNERS
local U = G.U
local Ga = {}
G.Gacha = Ga

local random = love.math.random

Ga.RATES = { { 1, 45 }, { 2, 30 }, { 3, 17 }, { 4, 6.5 }, { 5, 1.5 } }
Ga.PITY_5 = 70
Ga.SHINY_RATE = 1 / 100
Ga.REFUND = { [1] = 15, [2] = 30, [3] = 60, [4] = 120, [5] = 300 }
Ga.RARITY_NAME = { [1] = 'Común', [2] = 'Poco común', [3] = 'Rara', [4] = 'Épica', [5] = 'Legendaria' }
Ga.RARITY_COLOR = { [1] = '#9fb1c9', [2] = '#5fe08a', [3] = '#4fb4ff', [4] = '#c47bff', [5] = '#ffcb3d' }
Ga.BANNERS = {
    { gen = 1, name = 'Kanto',   color = { '#3a1d6e', '#1b2f78', '#0f4d6e' } },
    { gen = 2, name = 'Johto',   color = { '#5a2a1a', '#7a3d1f', '#2d4a6e' } },
    { gen = 3, name = 'Hoenn',   color = { '#0f4d6e', '#1b6a5a', '#2a3d78' } },
    { gen = 4, name = 'Sinnoh',  color = { '#2a2a5e', '#3d3d8a', '#5a2a6e' } },
    { gen = 5, name = 'Teselia', color = { '#1a1a2a', '#3a3a4e', '#2a4a6e' } },
    { gen = 6, name = 'Kalos',   color = { '#4a1a3a', '#2a3a7a', '#1a5a7a' } },
    { gen = 7, name = 'Alola',   color = { '#7a3a1a', '#1a6a6a', '#2a4a8a' } },
    { gen = 8, name = 'Galar',   color = { '#4a1a5a', '#1a3a6a', '#6a1a3a' } },
    { gen = 9, name = 'Paldea',  color = { '#6a2a1a', '#4a1a5a', '#1a4a6a' } }
}

local forceShiny = 0           -- para pruebas y vídeos: las N próximas salen shiny
local poolCache = {}           -- "gen:rarity" -> lista (G.DEX no cambia)
local allCache = {}            -- gen -> todos los del banner
local featCache = {}           -- gen -> dex de los destacados

local function inBanner(p, gen) return p.gen == gen and G.Sprites.meta(p.dex) ~= nil end

-- Pokémon de una rareza en un banner (lista cacheada: no modificarla).
function Ga.pool(rarity, gen)
    local key = gen .. ':' .. rarity
    local list = poolCache[key]
    if list then return list end
    list = {}
    for i = 1, #G.DEX do
        local p = G.DEX[i]
        if inBanner(p, gen) and p.rarity == rarity then list[#list + 1] = p end
    end
    poolCache[key] = list
    return list
end

local function allOf(gen)
    local list = allCache[gen]
    if list then return list end
    list = {}
    for i = 1, #G.DEX do if inBanner(G.DEX[i], gen) then list[#list + 1] = G.DEX[i] end end
    allCache[gen] = list
    return list
end

-- Pool no vacío más cercano (algunas generaciones tienen rarezas casi vacías).
local NEAR = { 0, -1, 1, -2, 2, -3, 3, -4, 4 }
local function poolNear(rarity, gen)
    for i = 1, #NEAR do
        local r = rarity + NEAR[i]
        if r >= 1 and r <= 5 then
            local p = Ga.pool(r, gen)
            if #p > 0 then return r, p end
        end
    end
    return rarity, allOf(gen)
end

local function rollRarity(minR)
    minR = minR or 1
    local rates = Ga.RATES
    local total = 0
    for i = 1, #rates do if rates[i][1] >= minR then total = total + rates[i][2] end end
    local x = random() * total
    local lastR = minR
    for i = 1, #rates do
        if rates[i][1] >= minR then
            lastR = rates[i][1]
            x = x - rates[i][2]
            if x <= 0 then return lastR end
        end
    end
    return lastR
end

local function byBst(a, b) return a.bst > b.bst end

-- Los 3 más fuertes de la generación, para el cartel del banner (lista cacheada).
function Ga.featured(gen)
    local f = featCache[gen]
    if f then return f end
    local five = {}
    local p = Ga.pool(5, gen)
    for i = 1, #p do five[i] = p[i] end
    table.sort(five, byBst)
    f = {}
    for i = 1, math.min(3, #five) do f[i] = five[i].dex end
    featCache[gen] = f
    return f
end

-- ¿Qué gasta una tirada de n? → t1, t10 o nil si no te llega.
function Ga.costOf(n, use)
    local s = G.DB.save
    if not s then return nil end
    local t = s.tickets or { t1 = 0, t10 = 0 }
    if n == 10 and use == 't10' then
        if (t.t10 or 0) >= 1 then return 0, 1 end
        return nil
    end
    if (t.t1 or 0) >= n then return n, 0 end
    return nil
end

-- Monedas que da un repetido.
function Ga.refund(rarity, shiny)
    local r = Ga.REFUND[rarity] or 0
    if shiny then return r * 3 end
    return r
end

-- Datos del banner para la pantalla inferior.
local bannerCache = {}
function Ga.banner(gen)
    local b = Ga.BANNERS[gen]
    if not b then return nil end
    local info = bannerCache[gen]
    if not info then
        info = { gen = b.gen, name = b.name, color = b.color, featured = Ga.featured(gen), pity = 0, total = #allOf(gen) }
        bannerCache[gen] = info
    end
    local s = G.DB.save
    info.pity = (s and s.pity and s.pity[gen]) or 0
    return info
end

-- Hace `n` tiradas en el banner `gen`. Devuelve nil (y el motivo) si no hay
-- tickets, o la lista de resultados { dex, rarity, shiny, isNew, coins }.
function Ga.pull(gen, n, payWith)
    gen = gen or 1
    n = n or 1
    payWith = payWith or 't1'
    local s = G.DB.save
    if not s then return nil, 'sin partida' end
    if not Ga.BANNERS[gen] then return nil, 'banner desconocido' end
    local c1, c10 = Ga.costOf(n, payWith)
    if not c1 then return nil, 'No tienes tickets suficientes: consíguelos jugando' end
    if #allOf(gen) == 0 then return nil, 'banner vacío' end
    s.tickets.t1 = s.tickets.t1 - c1
    s.tickets.t10 = s.tickets.t10 - c10
    s.pity = s.pity or {}
    s.shiny = s.shiny or {}
    s.pity[gen] = s.pity[gen] or 0

    local out = {}
    local now = os.time()
    local got4 = false
    for i = 1, n do
        s.pity[gen] = s.pity[gen] + 1
        local want
        if s.pity[gen] >= Ga.PITY_5 then want = 5
        elseif n == 10 and i == n and not got4 then want = rollRarity(4)
        else want = rollRarity() end

        local rarity, list = poolNear(want, gen)
        if rarity == 5 then s.pity[gen] = 0 end
        if rarity >= 4 then got4 = true end
        local mon = U.pick(list)
        local shiny = false
        if G.Sprites.hasShiny(mon.dex) then
            if forceShiny > 0 then forceShiny = forceShiny - 1; shiny = true
            else shiny = random() < Ga.SHINY_RATE end
        end

        local isNew, coins = false, 0
        if shiny then
            isNew = s.shiny[mon.dex] == nil
            if isNew then s.shiny[mon.dex] = { at = now, from = 'gacha' }
            else coins = Ga.REFUND[rarity] * 3 end
            if not s.owned[mon.dex] then s.owned[mon.dex] = { at = now, from = 'gacha' } end
        else
            isNew = s.owned[mon.dex] == nil
            if isNew then s.owned[mon.dex] = { at = now, from = 'gacha' }
            else coins = Ga.REFUND[rarity] end
        end
        s.coins = s.coins + coins
        out[i] = { dex = mon.dex, rarity = rarity, shiny = shiny, isNew = isNew, coins = coins, refund = coins }
    end
    s.stats.pulls = (s.stats.pulls or 0) + n
    if G.Progress then G.Progress.checkAch() end
    G.DB.commit()
    return out
end

function Ga.debugForceShiny(n) forceShiny = n or 1 end
