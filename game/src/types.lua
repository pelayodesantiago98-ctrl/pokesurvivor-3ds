-- types.lua — tabla de tipos (port de js/data/types.js).
-- La de los juegos (6.ª gen. en adelante), pero SUAVIZADA para un survivor,
-- donde sólo llevas un ataque activo y no puedes cambiar de Pokémon:
--
--   juegos   ×2      ×0,5    ×0 (inmune)
--   aquí     ×1,6    ×0,6    ×0,3
--
-- Con dos tipos se multiplican (×1,6 · ×1,6 = ×2,56), con tope en [×0,3, ×2,4].
-- Se usa en los dos sentidos: tus ataques contra los enemigos y los de los
-- enemigos contra ti (su tipo principal, o el de su disparo).
local U = G.U
local T = {}
G.Types = T

-- atacante -> { defensor = multiplicador de los juegos } (los ×1 no se apuntan)
local CHART = {
    normal   = { rock = 0.5, ghost = 0, steel = 0.5 },
    fire     = { fire = 0.5, water = 0.5, grass = 2, ice = 2, bug = 2, rock = 0.5, dragon = 0.5, steel = 2 },
    water    = { fire = 2, water = 0.5, grass = 0.5, ground = 2, rock = 2, dragon = 0.5 },
    electric = { water = 2, electric = 0.5, grass = 0.5, ground = 0, flying = 2, dragon = 0.5 },
    grass    = { fire = 0.5, water = 2, grass = 0.5, poison = 0.5, ground = 2, flying = 0.5, bug = 0.5, rock = 2, dragon = 0.5, steel = 0.5 },
    ice      = { fire = 0.5, water = 0.5, grass = 2, ice = 0.5, ground = 2, flying = 2, dragon = 2, steel = 0.5 },
    fighting = { normal = 2, ice = 2, poison = 0.5, flying = 0.5, psychic = 0.5, bug = 0.5, rock = 2, ghost = 0, dark = 2, steel = 2, fairy = 0.5 },
    poison   = { grass = 2, poison = 0.5, ground = 0.5, rock = 0.5, ghost = 0.5, steel = 0, fairy = 2 },
    ground   = { fire = 2, electric = 2, grass = 0.5, poison = 2, flying = 0, bug = 0.5, rock = 2, steel = 2 },
    flying   = { electric = 0.5, grass = 2, fighting = 2, bug = 2, rock = 0.5, steel = 0.5 },
    psychic  = { fighting = 2, poison = 2, psychic = 0.5, dark = 0, steel = 0.5 },
    bug      = { fire = 0.5, grass = 2, fighting = 0.5, poison = 0.5, flying = 0.5, psychic = 2, ghost = 0.5, dark = 2, steel = 0.5, fairy = 0.5 },
    rock     = { fire = 2, ice = 2, fighting = 0.5, ground = 0.5, flying = 2, bug = 2, steel = 0.5 },
    ghost    = { normal = 0, psychic = 2, ghost = 2, dark = 0.5 },
    dragon   = { dragon = 2, steel = 0.5, fairy = 0 },
    dark     = { fighting = 0.5, psychic = 2, ghost = 2, dark = 0.5, fairy = 0.5 },
    steel    = { fire = 0.5, water = 0.5, electric = 0.5, ice = 2, rock = 2, steel = 0.5, fairy = 2 },
    fairy    = { fire = 0.5, fighting = 2, poison = 0.5, dragon = 2, dark = 2, steel = 0.5 }
}
T.CHART = CHART

local SOFT = { [2] = 1.6, [0.5] = 0.6, [0] = 0.3 }
local MIN, MAX = 0.3, 2.4

-- Multiplicador de un ataque de tipo `atk` contra un Pokémon de tipos `def` (lista).
function T.mult(atk, def)
    local row = CHART[atk]
    if not row or not def then return 1 end
    local m = 1
    for i = 1, #def do
        local v = row[def[i]]
        if v ~= nil then m = m * SOFT[v] end
    end
    return U.clamp(m, MIN, MAX)
end

-- 'super' | 'weak' | nil, para enseñar el aviso.
function T.label(m)
    if m > 1.05 then return 'super' end
    if m < 0.95 then return 'weak' end
    return nil
end
