-- hazards.lua — ataques con aviso de los enemigos (port de js/systems/hazards.js).
-- Un peligro se dibuja primero en el suelo como AVISO (se va llenando) y, al
-- cumplirse el tiempo, golpea al jugador si está dentro:
--
--   zone  círculo (zonas de Tierra/Fuego/Veneno, explosiones, caídas de salto)
--   beam  rayo recto desde el enemigo (Eléctrico, Psíquico, Dragón, Hielo)
--
-- Campos: kind, x, y, r | angle, len, w, delay, dmg, type, color, t, hit, endT
-- y, para los de Arceus (src/judgment.lua): pct (quitan ese % de la vida),
-- pure (sin tipos ni defensa) y vis = 'pillar' (la Sentencia cae como un pilar de luz).
-- (endT = lo que dura tras estallar; en el JS se llamaba `end`, palabra
-- reservada en Lua).
local U = G.U
local H = {}
G.Hazards = H

local lg = love.graphics
local sin, cos, abs, min = math.sin, math.cos, math.abs, math.min
local floor = math.floor

local list = {}

-- h: { kind, x, y, r | angle, len, w, delay, dmg, type, color }. Devuelve h.
function H.add(h)
    h.t = 0
    h.hit = false
    h.endT = h.endT or 0.3
    list[#list + 1] = h
    return h
end

function H.clear()
    for i = #list, 1, -1 do list[i] = nil end
end

function H.all() return list end
function H.count() return #list end

-- ¿El círculo (x, y, r) toca el peligro?
function H.inside(h, x, y, r)
    if h.kind == 'zone' then
        local rr = h.r + r * 0.6
        return U.dist2(x, y, h.x, h.y) < rr * rr
    end
    local ca, sa = cos(h.angle), sin(h.angle)
    local px, py = x - h.x, y - h.y
    local along = px * ca + py * sa
    if along < -r or along > h.len + r then return false end
    return abs(-px * sa + py * ca) <= h.w / 2 + r * 0.6
end

-- Opciones del sfx del rayo (tabla reutilizada: se cambia `type` antes de llamar).
local SFX_BEAM = { kind = 'beam', type = 'normal' }

local function detonate(h)
    local near = G.Camera.sees(h.x, h.y, 120)
    if h.vis == 'pillar' then
        -- Pilar de luz que cae del cielo (la Sentencia de Arceus).
        G.FX.beam(h.x, h.y, -math.pi / 2, 420, h.r * 1.1, h.color, G.VFX.forType('electric'))
        G.FX.ring(h.x, h.y, 4, h.r * 1.3, '#fff3c8', 0.4, 5)
        G.FX.burst(h.x, h.y - 6, h.color, 10, 180)
        if near then G.Audio.sfx('judge'); G.Camera.kick(0.2) end
    elseif h.kind == 'zone' then
        G.FX.ring(h.x, h.y, 4, h.r, h.color, 0.35, 5)
        G.FX.burst(h.x, h.y - 6, h.color, floor(h.r / 3 + 0.5), 160)
        if near then
            G.Audio.sfx('break')
            if h.r > 60 then G.Camera.kick(0.35) end
        end
    else
        G.FX.beam(h.x, h.y - G.LIFT, h.angle, h.len, h.w, h.color, G.VFX.forType(h.type or (h.pure and 'electric' or 'normal')))
        if near then SFX_BEAM.type = h.type; G.Audio.sfx('shot', SFX_BEAM) end
    end
end

function H.update(dt)
    local pl = G.Game and G.Game.player and G.Game.player()
    for i = #list, 1, -1 do
        local h = list[i]
        h.t = h.t + dt
        if not h.hit and h.t >= h.delay then
            h.hit = true
            detonate(h)
            if pl and not pl.dead and H.inside(h, pl.x, pl.y, pl.r) then
                pl.invuln = 0
                pl:hurt(h.pct and math.max(h.dmg, pl.maxHp * h.pct) or h.dmg, h.type, h.pure)
            end
        end
        if h.hit and h.t >= h.delay + h.endT then U.removeSwap(list, i) end
    end
end

-- Avisos en el suelo (debajo de los Pokémon). Sin setLineDash: línea normal.
function H.draw()
    local blink = sin(U.now() * 16.67) > 0
    local cam = G.Camera
    for i = 1, #list do
        local h = list[i]
        if not h.hit and cam.sees(h.x, h.y, (h.kind == 'zone') and h.r or h.len) then
            local k = min(1, h.t / h.delay)
            local col = h.color
            if h.kind == 'zone' then
                U.setColor(col, 0.16)
                lg.ellipse("fill", h.x, h.y, h.r, h.r * 0.75)
                U.setColor(col, 0.32)
                lg.ellipse("fill", h.x, h.y, h.r * k, h.r * 0.75 * k)
                U.setColor(col, (k > 0.75 and blink) and 0.95 or 0.6)
                lg.setLineWidth(2)
                lg.ellipse("line", h.x, h.y, h.r, h.r * 0.75)
            else
                lg.push()
                lg.translate(h.x, h.y)
                lg.rotate(h.angle)
                U.setColor(col, 0.14)
                lg.rectangle("fill", 0, -h.w / 2, h.len, h.w)
                U.setColor(col, 0.34)
                lg.rectangle("fill", 0, -h.w / 2 * k, h.len, h.w * k)
                U.setColor(col, (k > 0.75 and blink) and 0.95 or 0.55)
                lg.setLineWidth(2)
                lg.rectangle("line", 0, -h.w / 2, h.len, h.w)
                lg.pop()
            end
        end
    end
    lg.setLineWidth(1)
    lg.setColor(1, 1, 1, 1)
end
