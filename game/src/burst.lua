-- burst.lua — ataque Burst (idea de Pokémon Survivor Burst): una barra que se carga
-- al derrotar enemigos (más con los jefes) y, llena, lanza el ataque definitivo del
-- tipo de tu Pokémon contra todo lo que hay en pantalla. Botón en la pantalla
-- táctil o X en el mando.
local U = G.U
local B = {}
G.Burst = B

B.GAIN_KILL = 0.025          -- por enemigo derrotado (40 para llenarla)
B.GAIN_BOSS = 0.30           -- por jefe
B.BOSS_MUL = 0.35            -- los jefes reciben menos

-- Ataque definitivo de cada tipo (nombres de los juegos).
B.NAMES = {
    normal = "Hiperrayo", fire = "Llamarada", water = "Hidrobomba", grass = "Planta Feroz",
    electric = "Trueno", ice = "Ventisca", fighting = "A Bocajarro", poison = "Lanza Mugre",
    ground = "Terremoto", flying = "Ataque Aéreo", psychic = "Psicoataque", bug = "Megacuerno",
    rock = "Avalancha", ghost = "Bola Sombra", dragon = "Enfado", dark = "Juego Sucio",
    steel = "Cabeza de Hierro", fairy = "Fuerza Lunar",
}

function B.add(pl, k)
    if not pl or pl.dead then return end
    local was = (pl.burst or 0) >= 1
    pl.burst = math.min(1, (pl.burst or 0) + k)
    if not was and pl.burst >= 1 then
        G.Audio.sfx("confirm")
        G.Spawner.say("¡Burst listo! Toca BURST (o X)", 2.4, true)
    end
end

function B.ready(pl) return pl ~= nil and not pl.dead and (pl.burst or 0) >= 1 end

function B.fire(pl)
    if not B.ready(pl) or G.Game.state() ~= "playing" then return false end
    pl.burst = 0
    local ty = pl.mon.types[1]
    local col = U.TYPE_COLOR[ty] or "#ffffff"
    local dmg = (50 + pl.level * 12) * (pl.baseAtk or 1)
    local R = G.Camera.outerRadius()
    local R2 = R * R
    local all = G.EnemyMgr.all()
    for i = 1, #all do
        local e = all[i]
        if not e.dead and U.dist2(e.x, e.y, pl.x, pl.y) <= R2 then
            local k = (e.boss or e.legend) and B.BOSS_MUL or 1
            e:hurt(dmg * k * G.Types.mult(ty, e.types), col, e.x - pl.x, e.y - pl.y, 160)
        end
    end
    pl.invuln = math.max(pl.invuln or 0, 1.0)
    G.FX.ring(pl.x, pl.y, 10, R, col, 0.9, 12)
    G.FX.ring(pl.x, pl.y, 6, R * 0.6, "#ffffff", 0.6, 6)
    G.FX.burst(pl.x, pl.y - (pl.bodyH or 20) * 0.5, col, 60, 320)
    G.Game.flash(col, 0.35)
    G.Camera.kick(1.2)
    G.Audio.sfx("legend")
    G.Spawner.say("¡" .. (B.NAMES[ty] or "Burst") .. "!", 2.2, true)
    G.Progress.event("burst", {})
    if G_SOAK then print(string.format("BURST %s t=%d nivel=%d", B.NAMES[ty] or "?", G.Game.time(), pl.level)) end
    return true
end

return B
