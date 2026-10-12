-- difficulty.lua — modos de dificultad: Fácil, Medio, Difícil y Extremo.
-- Multiplican la vida y el daño de todos los enemigos (jefes y legendarios
-- incluidos), el ritmo de aparición y las monedas que ganas al acabar.
-- Se guarda en save.difficulty (por defecto, Medio).
local D = {}
G.Difficulty = D

D.LIST = {
    { id = "easy",    name = "Fácil",   hp = 0.70, dmg = 0.60, rate = 0.85, reward = 0.75, color = "#3c9c54" },
    { id = "normal",  name = "Medio",   hp = 1.00, dmg = 1.00, rate = 1.00, reward = 1.00, color = "#3c6cc4" },
    { id = "hard",    name = "Difícil", hp = 1.40, dmg = 1.35, rate = 1.15, reward = 1.40, color = "#e08838" },
    { id = "extreme", name = "Extremo", hp = 1.90, dmg = 1.80, rate = 1.30, reward = 2.00, color = "#d04848" },
}
local BY = {}
for i, d in ipairs(D.LIST) do BY[d.id] = d; d.index = i end

function D.get()
    local s = G.DB and G.DB.save
    return (s and BY[s.difficulty]) or BY.normal
end

-- Siguiente modo (o el anterior con step = -1); lo guarda.
function D.cycle(step)
    local cur = D.get()
    local i = (cur.index - 1 + (step or 1)) % #D.LIST + 1
    G.DB.save.difficulty = D.LIST[i].id
    G.DB.commit()
    return D.LIST[i]
end

return D
