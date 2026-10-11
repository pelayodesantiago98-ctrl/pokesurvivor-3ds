-- pickup.lua — orbes de experiencia y objetos (port de js/entities/pickup.js).
-- Los orbes se quedan quietos hasta que entras en el radio del imán; entonces
-- aceleran hacia ti. Para que no se acumulen cientos, al pasar de MAX se
-- fusionan los de XP. Sin cooperativo: un solo jugador.
--
-- Campos de un pickup: id, kind, x, y, value, vx, vy, t, pulled.
local U = G.U
local K = {}
G.Pickups = K

local lg = love.graphics
local sin, cos, abs, sqrt, max, ceil = math.sin, math.cos, math.abs, math.sqrt, math.max, math.ceil
local random = love.math.random
local TAU = 6.2832

local list = {}
local free = {}                 -- tablas recicladas de pickups recogidos
local MAX = 160
K.MAX = MAX
local nextId = 1

K.KIND = {
    xp       = { color = '#7fe0ff', glow = '#2a8fd0', r = 4.5 },
    xpBig    = { color = '#ffd95e', glow = '#c08a10', r = 7 },
    heal     = { color = '#5fe08a', glow = '#1f8f4d', r = 6.5 },
    magnet   = { color = '#ff9ed8', glow = '#b03d84', r = 6.5 },
    bomb     = { color = '#ff7b3d', glow = '#b03d10', r = 6.5 },
    coin     = { color = '#ffd23f', glow = '#b8860b', r = 5.5 },
    ticket   = { color = '#ffd23f', glow = '#c08a10', r = 7 },
    ticket10 = { color = '#c47bff', glow = '#8a3fd0', r = 8 },
    item     = { color = '#ffd23f', glow = '#c08a10', r = 9 },      -- value = id del objeto
}
local KIND = K.KIND
-- Icono de cada clase (baya, imán, bomba, tickets); los objetos usan su propio id.
local ICON = { heal = 'berry', magnet = 'magnet', bomb = 'bomb', ticket = 'ticket', ticket10 = 'ticket10' }

local BOSS_T10 = 1 / 3            -- ticket ×10 de un jefe normal (el legendario, siempre)
local TICKET_RATE = 1 / 400       -- probabilidad de que un Pokémon normal suelte un ticket

function K.clear()
    for i = #list, 1, -1 do free[#free + 1] = list[i]; list[i] = nil end
end
function K.all() return list end

local function isXp(p) return p.kind == 'xp' or p.kind == 'xpBig' end

local function push(o)
    o.id = nextId; nextId = nextId + 1
    list[#list + 1] = o
    if #list > MAX then
        -- Fusiona dos orbes de XP para no crecer sin límite.
        local i = nil
        for k = 1, #list do if isXp(list[k]) then i = k break end end
        if i then
            local a = list[i]
            U.removeSwap(list, i)
            for k = 1, #list do
                local p = list[k]
                if isXp(p) then p.value = p.value + a.value; p.kind = 'xpBig' break end
            end
            free[#free + 1] = a
        else
            free[#free + 1] = list[1]
            U.removeSwap(list, 1)
        end
    end
end

local function orb(kind, x, y, value)
    local o = free[#free]
    if o then free[#free] = nil else o = {} end
    local a = random() * TAU
    local s = U.rand(10, 46)
    o.kind, o.x, o.y, o.value = kind, x, y, value
    o.vx, o.vy = cos(a) * s, sin(a) * U.rand(10, 46)
    o.t = random() * 6.28
    o.pulled = false
    return o
end

-- Imán: todo vuela hacia el jugador.
function K.pullAll()
    for i = 1, #list do list[i].pulled = true end
end

function K.dropXp(x, y, value, boss, legend)
    if boss then
        -- Los jefes revientan en un montón de orbes grandes + recompensas.
        for _ = 1, 14 do
            local a, d = random() * TAU, U.rand(10, 70)
            push(orb('xpBig', x + cos(a) * d, y + sin(a) * d, ceil(value / 14)))
        end
        push(orb('heal', x + 24, y, 0))
        push(orb('magnet', x - 24, y, 0))
        -- Ticket ×10: siempre el legendario de la grieta; un jefe normal, 1 de cada 3 veces.
        if legend or random() < BOSS_T10 then push(orb('ticket10', x, y - 20, 1)) end
        return
    end
    push(orb(value >= 20 and 'xpBig' or 'xp', x, y, value))
    if random() < TICKET_RATE then push(orb('ticket', x + U.rand(-6, 6), y, 1)) end

    -- Drops ocasionales.
    local r = random()
    if r < 0.012 then push(orb('heal', x + U.rand(-8, 8), y, 0))
    elseif r < 0.020 then push(orb('magnet', x, y, 0))
    elseif r < 0.026 then push(orb('bomb', x, y, 0)) end
end

-- Suelta un objeto suelto: 'heal' | 'magnet' | 'bomb' | 'coin' | 'ticket' | 'ticket10' | 'item'.
function K.drop(kind, x, y, value)
    push(orb(kind, x, y, value or 0))
end

-- @param pl         el jugador (uno solo)
-- @param onCollect  onCollect(pickup, jugador); el pickup ya está fuera de la lista
function K.update(dt, pl, onCollect)
    if not pl then return end
    local mag2 = pl.magnet * pl.magnet
    for i = #list, 1, -1 do
        local p = list[i]
        p.t = p.t + dt * 4
        local dx, dy = pl.x - p.x, pl.y - p.y
        local d2 = dx * dx + dy * dy

        if p.pulled or d2 < mag2 then
            p.pulled = true
            local d = sqrt(d2)
            if d < 1e-6 then d = 1 end
            local pull = 240 + 1400 / d
            p.vx = U.damp(p.vx, (dx / d) * pull, 7, dt)
            p.vy = U.damp(p.vy, (dy / d) * pull, 7, dt)
        else
            local k = 0.02 ^ dt
            p.vx = p.vx * k
            p.vy = p.vy * k
        end

        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt

        if d2 < 15 * 15 then
            U.removeSwap(list, i)
            if onCollect then onCollect(p, pl) end
            free[#free + 1] = p
        end
    end
end

function K.draw()
    local cam = G.Camera
    for i = 1, #list do
        local p = list[i]
        if cam.sees(p.x, p.y, 30) then
            local k = KIND[p.kind] or KIND.xp
            local bounce = abs(sin(p.t * 0.8)) * 3
            local r = k.r
            local y = p.y - 6 - bounce

            lg.setColor(0, 0, 0, 0.28)
            lg.ellipse("fill", p.x, p.y, r * 0.9, r * 0.35)

            U.setColor(k.glow, 0.3)
            lg.circle("fill", p.x, y, r * 2)

            if p.kind == 'xp' or p.kind == 'xpBig' then
                U.setColor(k.color)
                lg.polygon("fill", p.x, y - r, p.x + r * 0.78, y, p.x, y + r, p.x - r * 0.78, y)
                lg.setColor(1, 1, 1, 0.8)
                lg.circle("fill", p.x - r * 0.25, y - r * 0.3, r * 0.28)
            elseif p.kind == 'coin' then
                -- Moneda que gira: elipse que se estrecha.
                local sx = max(0.25, abs(cos(p.t * 0.9)))
                U.setColor(k.color)
                lg.ellipse("fill", p.x, y, r * sx, r)
                U.setColor('#b8860b')
                lg.ellipse("fill", p.x, y, r * sx * 0.5, r * 0.5)
                lg.setColor(1, 1, 1, 0.8)
                lg.circle("fill", p.x - r * 0.25, y - r * 0.3, r * 0.28)
            else
                -- Baya, imán, bomba, tickets y objetos: su icono pixel art.
                local sz = (p.kind == 'ticket10' or p.kind == 'item') and 24 or 18
                if p.kind == 'item' then
                    -- Objeto: brillo dorado latiendo, para que se vea desde lejos.
                    U.setColor('#ffe14d', 0.35 + sin(p.t * 1.5) * 0.15)
                    lg.circle("fill", p.x, y, 18)
                end
                lg.setColor(1, 1, 1, 1)
                G.Icons.draw(p.kind == 'item' and p.value or ICON[p.kind], p.x - sz / 2, y - sz / 2 - 1, sz)
            end
        end
    end
    lg.setColor(1, 1, 1, 1)
end

function K.count() return #list end
