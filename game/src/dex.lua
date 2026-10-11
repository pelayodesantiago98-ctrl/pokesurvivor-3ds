-- dex.lua — carga la Pokédex generada (data/pokedex.lua) en G.DEX y G.DEX_BY.
-- Mismos campos que pokedex.js: dex, name, types, hp, spd, atk, rarity, bst,
-- starter, gen, leg (siempre booleano).
G.DEX = require("data.pokedex")

G.DEX_BY = {}
for i = 1, #G.DEX do
    local p = G.DEX[i]
    G.DEX_BY[p.dex] = p
end

function G.getPokemon(dex) return G.DEX_BY[dex] end
