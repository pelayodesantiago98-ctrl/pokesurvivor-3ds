-- evolution.lua — evolución del compañero DURANTE la partida (idea tomada de
-- Poké World Survivors): al nivel 16 pasa a su primera evolución y al 36 a la
-- segunda, con las cadenas de PokeAPI (data/evolutions.lua). Solo dura la run:
-- la colección no cambia. Las formas evolucionadas suben vida y ataque, cambian
-- de tipos (y por tanto de movimientos ofrecidos) y permiten la evolución de
-- movimientos con objeto (ver moves.evoInfo).
local U = G.U
local E = {}
G.Evolution = E

local NEXT = require("data.evolutions")
E.LEVELS = { 16, 36 }          -- nivel de la 1ª y 2ª evolución

-- Siguiente evolución con sprite disponible (en ramas como Eevee, la primera).
function E.nextOf(dex)
    local list = NEXT[dex]
    if not list then return nil end
    for i = 1, #list do
        local d = list[i]
        if G.DEX_BY[d] and G.Sprites.meta(d) then return d end
    end
    return nil
end

-- Cadena completa a partir de un dex (para la ficha): { dex, evo1, evo2 }.
function E.chainOf(dex)
    local out = { dex }
    local cur = dex
    for i = 1, 2 do
        cur = E.nextOf(cur)
        if not cur then break end
        out[#out + 1] = cur
    end
    return out
end

function E.evolve(pl, nxt)
    local old = pl.mon
    local mon = G.DEX_BY[nxt]
    if not mon then return false end
    pl.mon = mon
    pl.dex = nxt
    pl.form = (pl.form or 1) + 1
    pl._preloadEvo = false
    -- Stats de la forma nueva: la vida extra se suma (y se recupera un cuarto).
    local dHp = mon.hp - old.hp
    pl.maxHp = pl.maxHp + dHp
    pl.hp = math.min(pl.maxHp, pl.hp + math.max(0, dHp) + pl.maxHp * 0.25)
    pl.baseSpd = mon.spd
    pl.baseAtk = mon.atk
    local dir = pl.anim and pl.anim.dir or 0
    pl.anim = G.Sprites.Animator.new(nxt, 1, pl.shiny, true)
    pl.anim.dir = dir
    pl.r = G.Sprites.bodyRadius(nxt)
    pl.bodyH = G.Sprites.bodyHeight(nxt)
    pl.invuln = math.max(pl.invuln or 0, 1.5)
    G.FX.ring(pl.x, pl.y, 8, 140, "#ffffff", 0.9, 6)
    G.FX.burst(pl.x, pl.y - pl.bodyH * 0.5, "#9ae6ff", 46, 260)
    G.Camera.kick(0.5)
    G.Audio.sfx("legend")
    G.Spawner.say("¡" .. old.name .. " ha evolucionado a " .. mon.name .. "!", 3.4, true)
    G.Progress.event("evolvePokemon", { dex = nxt })
    return true
end

-- Llamar cada fotograma de juego: precarga la forma siguiente y evoluciona al nivel.
function E.update(pl)
    pl.form = pl.form or 1
    if pl.form > #E.LEVELS or pl.dead then return end
    local lvl = E.LEVELS[pl.form]
    if pl.level < lvl - 2 then return end
    local nxt = E.nextOf(pl.dex)
    if not nxt then return end
    if not pl._preloadEvo then
        pl._preloadEvo = true
        G.Sprites.preload({ nxt }, true)
        if pl.shiny then G.Sprites.preload({ nxt }, false, true) end
    end
    if pl.level >= lvl then E.evolve(pl, nxt) end
end
