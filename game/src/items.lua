-- items.lua — objetos equipables, uno por run (port de js/data/items.js).
-- Se encuentran en los cofres (a veces en los normales, a menudo en los de
-- candado) y los sueltan los jefes. Sólo puedes llevar UNO; si encuentras
-- otro, eliges con cuál quedarte. Duran lo que dura la run.
--
--   on(pl)   se lo pones (lo que hace mientras lo llevas)
--   off(pl)  se lo quitas (deshace lo de on)
-- Los que reaccionan a algo (golpe mortal, daño hecho...) los mira el
-- jugador con pl:hasItem(id).
local U = G.U
local I = {}
G.Items = I

local function noop() end

local LIST = {
    { id = 'leftovers', name = 'Restos', desc = 'Recuperas un 1,5% de tu vida por segundo.',
      on = function(p) p.regenFlat = p.regenFlat + p.maxHp * 0.015; p._itemRegen = p.maxHp * 0.015 end,
      off = function(p) p.regenFlat = p.regenFlat - (p._itemRegen or 0) end },
    { id = 'choiceband', name = 'Cinta Elección', desc = '+40% de daño, pero no puedes cambiar de movimiento.',
      on = function(p) p.atkMul = p.atkMul * 1.4 end, off = function(p) p.atkMul = p.atkMul / 1.4 end },
    { id = 'quickclaw', name = 'Garra Rápida', desc = '-20% de recarga en todos tus movimientos.',
      on = function(p) p.cdMul = p.cdMul * 0.8 end, off = function(p) p.cdMul = p.cdMul / 0.8 end },
    { id = 'focussash', name = 'Banda Focus', desc = 'Un golpe que te dejaría KO te deja con 1 de vida (cada 60 s).',
      on = noop, off = noop },
    { id = 'shellbell', name = 'Cascabel Concha', desc = 'Recuperas vida con el daño que haces.',
      on = noop, off = noop },
    { id = 'amuletcoin', name = 'Moneda Amuleto', desc = '+50% de Pokémonedas al acabar la run.',
      on = function(p) p.coinMul = p.coinMul * 1.5 end, off = function(p) p.coinMul = p.coinMul / 1.5 end },
    { id = 'luckyegg', name = 'Huevo Suerte', desc = '+30% de experiencia.',
      on = function(p) p.xpMul = p.xpMul * 1.3 end, off = function(p) p.xpMul = p.xpMul / 1.3 end },
    { id = 'lifeorb', name = 'Vidasfera', desc = '+30% de daño, pero cada ataque te quita un poco de vida.',
      on = function(p) p.atkMul = p.atkMul * 1.3 end, off = function(p) p.atkMul = p.atkMul / 1.3 end },
    { id = 'choicescarf', name = 'Pañuelo Elección', desc = '+35% de velocidad.',
      on = function(p) p.spdMul = p.spdMul * 1.35 end, off = function(p) p.spdMul = p.spdMul / 1.35 end },
    { id = 'rockyhelmet', name = 'Casco Dentado', desc = 'Los que te golpean cuerpo a cuerpo reciben daño.',
      on = noop, off = noop },
    { id = 'assaultvest', name = 'Chaleco Asalto', desc = '+20% de reducción de daño recibido.',
      on = function(p) p.dmgReduce = p.dmgReduce + 0.2 end, off = function(p) p.dmgReduce = p.dmgReduce - 0.2 end }
}
I.LIST = LIST

local BY = {}
for i = 1, #LIST do BY[LIST[i].id] = LIST[i] end
I.BY = BY

-- Uno al azar, distinto del que ya llevas.
function I.roll(except)
    local pool = {}
    for i = 1, #LIST do
        if LIST[i].id ~= except then pool[#pool + 1] = LIST[i] end
    end
    return U.pick(pool).id
end
