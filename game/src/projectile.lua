-- projectile.lua — proyectiles y orbes (port de js/entities/projectile.js).
-- Una sola lista para todo lo que vuela: disparos del jugador, disparos
-- enemigos y los orbes que giran alrededor del Pokémon (los orbes son
-- proyectiles con `orb`, anclados al jugador y que vuelven a golpear cada
-- `rehit` segundos).
--
-- Viven en el plano del SUELO (como los pies de las entidades) y se dibujan
-- elevados G.LIFT unidades con su sombra debajo. Las paredes y los objetos
-- sólidos los paran (ver combat.lua).
--
-- Campos de un proyectil (los mismos que en el JS): id, x, y, vx, vy, dmg, r,
-- life, t, pierce, hits {[id]=true}, friendly, color, homing, slow, burn, poison,
-- knock, orb, rehit, hitLog {[id]=tiempo}, phits {[id]=true}; opcionales: owner,
-- vis, mtype, ghost, mid, boom, bsp, back, oa, orad, ospeed, px, py, trailT.
local U = G.U
local P = {}
G.Projectiles = P

local lg = love.graphics
local floor, sin, cos, atan2, min, sqrt, pi = math.floor, math.sin, math.cos, math.atan2, math.min, math.sqrt, math.pi
local HUGE = math.huge

local list = {}
local nextId = 1

function P.clear()
    for i = #list, 1, -1 do list[i] = nil end
end
function P.all() return list end

-- Proyectil del jugador (o enemigo con friendly=false). Rellena los valores
-- por defecto en la propia tabla `o` y la añade a la lista.
function P.spawn(o)
    o.id = nextId; nextId = nextId + 1
    o.x = o.x or 0; o.y = o.y or 0
    o.vx = o.vx or 0; o.vy = o.vy or 0
    o.dmg = o.dmg or 10
    o.r = o.r or 6
    o.life = o.life or 1.4
    o.t = o.t or 0
    o.pierce = o.pierce or 0
    if o.friendly == nil then o.friendly = true end
    o.color = o.color or '#ffffff'
    o.homing = o.homing or 0
    o.slow = o.slow or 0; o.burn = o.burn or 0; o.poison = o.poison or 0; o.knock = o.knock or 0
    o.orb = o.orb or false
    o.rehit = o.rehit or 0.34
    if o.friendly and not o.orb then
        if not o.hits then o.hits = {} end
        if not o.phits then o.phits = {} end
    end
    list[#list + 1] = o
    return o
end

-- Orbe anclado a un jugador (`owner`): vive mientras el movimiento esté activo.
function P.spawnOrb(o)
    o.orb = true
    o.life = HUGE
    o.pierce = HUGE
    if not o.hitLog then o.hitLog = {} end
    return P.spawn(o)
end

-- Borra los orbes de un jugador (o todos) al cambiar de movimiento activo.
function P.clearOrbs(owner)
    for i = #list, 1, -1 do
        local p = list[i]
        if p.orb and (not owner or p.owner == owner) then U.removeSwap(list, i) end
    end
end

-- Enemigo vivo más cercano a (x, y) dentro de maxDist (o nil).
function P.nearest(enemies, x, y, maxDist)
    local best, bd = nil, maxDist * maxDist
    for i = 1, #enemies do
        local e = enemies[i]
        if not e.dead then
            local d = U.dist2(x, y, e.x, e:cy())
            if d < bd then bd = d; best = e end
        end
    end
    return best
end

function P.update(dt, player, enemies)
    local cam = G.Camera
    for i = #list, 1, -1 do
        local p = list[i]
        p.t = p.t + dt
        local gone = false

        if p.orb then
            -- Gira alrededor de su jugador.
            local o = p.owner or player
            p.oa = p.oa + p.ospeed * dt
            p.x = o.x + cos(p.oa) * p.orad
            p.y = o.y + sin(p.oa) * p.orad * 0.7
        else
            if p.t >= p.life then gone = true end

            -- Bumerán: a los `boom` segundos se da la vuelta (y puede volver a
            -- golpear a los mismos) y vuelve a su dueño; al llegar, desaparece.
            if not gone and p.boom then
                local o = p.owner or player
                if not p.back and p.t >= p.boom then
                    p.back = true
                    if p.hits then for k in pairs(p.hits) do p.hits[k] = nil end else p.hits = {} end
                end
                if p.back then
                    local dx, dy = U.norm(o.x - p.x, o.y - p.y)
                    p.vx = U.damp(p.vx, dx * p.bsp, 7, dt)
                    p.vy = U.damp(p.vy, dy * p.bsp, 7, dt)
                    local rr = o.r + 8
                    if U.dist2(p.x, p.y, o.x, o.y) < rr * rr then gone = true end
                end
            end

            if not gone then
                -- Teledirigido: curva la velocidad hacia el enemigo más cercano.
                if p.homing > 0 and p.friendly then
                    local tg = P.nearest(enemies, p.x, p.y, 340)
                    if tg then
                        local dx, dy = U.norm(tg.x - p.x, tg:cy() - p.y)
                        local sp = sqrt(p.vx * p.vx + p.vy * p.vy)
                        p.vx = U.damp(p.vx, dx * sp, p.homing, dt)
                        p.vy = U.damp(p.vy, dy * sp, p.homing, dt)
                    end
                end

                p.px = p.x; p.py = p.y          -- para la colisión barrida (ver combat.lua)
                local vis = p.vis
                if vis and vis.trail and cam.sees(p.x, p.y, 20) then
                    p.trailT = (p.trailT or 0) - dt
                    if p.trailT <= 0 then
                        p.trailT = 0.04
                        G.FX.trail(vis.trail, vis.pal, p.x, p.y - G.LIFT, p.vx, p.vy)
                    end
                end
                p.x = p.x + p.vx * dt
                p.y = p.y + p.vy * dt

                -- Fuera de la vista con margen generoso -> se descarta.
                if not cam.sees(p.x, p.y, 260) then gone = true end
            end
        end

        if gone then U.removeSwap(list, i) end
    end
end

function P.remove(p)
    for i = 1, #list do
        if list[i] == p then U.removeSwap(list, i) return end
    end
end

local vopts = { angle = 0, alpha = 1, scale = 1, frame = 0 }

function P.draw()
    local L = G.LIFT
    local cam = G.Camera
    local n = #list
    -- Sombras primero, todas juntas.
    lg.setColor(0, 0, 0, 0.25)
    for i = 1, n do
        local p = list[i]
        if cam.sees(p.x, p.y, 40) then lg.ellipse("fill", p.x, p.y, p.r * 0.9, p.r * 0.38) end
    end
    -- Los disparos enemigos llevan un aro rojo en el suelo: "esto te hace daño".
    lg.setColor(1, 0.235, 0.314, 0.35)
    for i = 1, n do
        local p = list[i]
        if not p.friendly and cam.sees(p.x, p.y, 40) then lg.ellipse("fill", p.x, p.y, p.r * 1.5, p.r * 0.6) end
    end
    local VFX = G.VFX
    for i = 1, n do
        local p = list[i]
        if cam.sees(p.x, p.y, 40) then
            local v = p.vis or VFX.forType('normal')
            local shape = v.proj
            local angle = 0
            if VFX.isDir(shape) then
                if p.orb then angle = p.oa + pi / 2 else angle = atan2(p.vy, p.vx) end
            elseif VFX.spins(shape) then
                angle = p.t * 9
            end
            vopts.angle = angle
            vopts.alpha = p.orb and 1 or min(1, (p.life - p.t) * 4)
            vopts.scale = p.r >= 8 and 1.5 or 1
            vopts.frame = floor(p.t * 12)
            VFX.draw(shape, v.pal, p.x, p.y - L, vopts)
        end
    end
    lg.setColor(1, 1, 1, 1)
end

function P.count() return #list end
