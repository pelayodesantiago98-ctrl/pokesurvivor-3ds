-- pathing.lua — los enemigos rodean rocas y lagos (port de js/systems/pathing.js).
--
-- Un "campo de distancias" por jugador: cada pocas décimas se hace un
-- recorrido en anchura (BFS) por las casillas de alrededor del jugador,
-- apuntando cuántos pasos faltan desde cada casilla hasta él. Un enemigo
-- sólo tiene que ir hacia la casilla vecina con menos pasos, y así encuentra
-- el camino alrededor de paredes, rocas, árboles y charcos peligrosos.
--
--   - 8 vecinos, sin cortar esquinas (no se cuela entre dos rocas en diagonal).
--   - Bloquean: paredes, objetos sólidos y lava/veneno/descarga.
--     El agua se puede cruzar (sólo frena).
--   - Los que flotan (G.Sprites.hovers) no lo necesitan: van en línea recta.
--
-- Coste en la 3DS: R=20 casillas de radio -> 41×41 = 1.681 casillas por
-- jugador, cada 0,35 s. Los enemigos fuera del campo van en línea recta.
-- Todas las tablas (dist, open, cola) se crean una vez y se reutilizan.
local U = G.U
local floor = math.floor
local P = {}
G.Path = P

local R = 20
local N = R * 2 + 1
local NN = N * N
local EVERY = 0.35
local UNSEEN = 32767
local fields = {}                            -- jugador -> { ox, oy, dist = {}, open = {} }
local queue = {}                             -- cola del BFS (plana, reutilizada)
for i = 1, NN do queue[i] = 0 end
local D8X = { 1, -1, 0, 0, 1, 1, -1, -1 }
local D8Y = { 0, 0, 1, -1, 1, -1, 1, -1 }
local timer = 0

local function build(pl)
    local World = G.World
    local TS = World.TS
    local px, py = floor(pl.x / TS), floor(pl.y / TS)
    local ox, oy = px - R, py - R
    local f = fields[pl]
    if not f then
        f = { ox = 0, oy = 0, dist = {}, open = {} }
        for i = 1, NN do f.dist[i] = UNSEEN; f.open[i] = false end
        fields[pl] = f
    end
    f.ox = ox; f.oy = oy
    local dist, open = f.dist, f.open
    local walkable = World.walkable
    -- Casillas transitables del área (se consultan una vez).
    for j = 0, N - 1 do
        local row = j * N
        local ty = oy + j
        for i = 0, N - 1 do
            dist[row + i + 1] = UNSEEN
            open[row + i + 1] = walkable(ox + i, ty)
        end
    end

    local start = R * N + R + 1
    open[start] = true                       -- donde está el jugador siempre cuenta
    dist[start] = 0
    local head, tail = 1, 1
    queue[1] = start
    while head <= tail do
        local c = queue[head]; head = head + 1
        local c0 = c - 1
        local cx = c0 % N
        local cy = (c0 - cx) / N
        local d = dist[c] + 1
        for k = 1, 8 do
            local nx, ny = cx + D8X[k], cy + D8Y[k]
            if nx >= 0 and ny >= 0 and nx < N and ny < N then
                local n = ny * N + nx + 1
                if open[n] and dist[n] == UNSEEN then
                    -- Diagonal: las dos casillas de al lado tienen que estar libres.
                    if k <= 4 or (open[cy * N + nx + 1] and open[ny * N + cx + 1]) then
                        dist[n] = d
                        tail = tail + 1
                        queue[tail] = n
                    end
                end
            end
        end
    end
end

-- Recalcula los campos de los jugadores vivos (como mucho cada EVERY segundos).
function P.update(dt, players)
    timer = timer - dt
    if timer > 0 then return end
    timer = EVERY
    for p in pairs(fields) do
        if not U.contains(players, p) then fields[p] = nil end
    end
    for i = 1, #players do
        local p = players[i]
        if not p.dead then build(p) end
    end
end

-- ¿Cabe un cuerpo de radio r en línea recta de (ax,ay) a (bx,by)?
local function clearLine(f, ax, ay, bx, by, r)
    local TS = G.World.TS
    local len = U.hypot(bx - ax, by - ay)
    if len < 1 then return true end
    local ux, uy = (bx - ax) / len, (by - ay) / len
    local w = math.min(r * 0.9, TS * 0.45)
    local open, ox, oy = f.open, f.ox, f.oy
    local step = TS * 0.4
    local d = 0
    while d <= len do
        local cx, cy = ax + ux * d, ay + uy * d
        for si = -1, 1 do
            local s = si * w
            local x = floor((cx - uy * s) / TS) - ox
            local y = floor((cy + ux * s) / TS) - oy
            if x < 0 or y < 0 or x >= N or y >= N then return false end
            if not open[y * N + x + 1] then return false end
        end
        d = d + step
    end
    return true
end

-- Dirección (normalizada, DOS valores) para que `e` llegue hasta `pl` rodeando
-- obstáculos, o nil si no hace falta (cerca, fuera del campo o sin camino).
function P.dirFor(e, pl)
    local f = fields[pl]
    if not f then return nil end
    local TS = G.World.TS
    local tx, ty = floor(e.x / TS) - f.ox, floor(e.y / TS) - f.oy
    if tx < 0 or ty < 0 or tx >= N or ty >= N then return nil end
    local dist, open = f.dist, f.open
    local here = dist[ty * N + tx + 1]
    if here <= 1 or here == UNSEEN then return nil end   -- pegado a ti, o sin camino: directo
    -- Con vista despejada hasta el jugador, en línea recta (más natural).
    -- Se comprueba cada 0,2 s por enemigo (es lo más caro).
    local now = U.now()
    if not e.losAt or now - e.losAt > 0.2 then
        e.losAt = now
        e.los = clearLine(f, e.x, e.y, pl.x, pl.y, e.r)
    end
    if e.los then return nil end
    -- Siguiente casilla del camino (la vecina con menos pasos, sin cortar esquinas).
    local bx, by, best = tx, ty, here
    for k = 1, 8 do
        local x, y = tx + D8X[k], ty + D8Y[k]
        if x >= 0 and y >= 0 and x < N and y < N then
            local v = dist[y * N + x + 1]
            if v < best and (k <= 4 or (open[ty * N + x + 1] and open[y * N + tx + 1])) then
                best = v; bx = x; by = y
            end
        end
    end
    if bx == tx and by == ty then return nil end
    local gx, gy = (f.ox + bx + 0.5) * TS, (f.oy + by + 0.5) * TS
    -- Si va descentrado y el atajo hasta esa casilla roza un obstáculo,
    -- primero al centro de la suya (así no se engancha en las esquinas).
    if not clearLine(f, e.x, e.y, gx, gy, e.r) then
        gx, gy = (f.ox + tx + 0.5) * TS, (f.oy + ty + 0.5) * TS
    end
    return U.norm(gx - e.x, gy - e.y)
end

function P.clear()
    for p in pairs(fields) do fields[p] = nil end
    timer = 0
end
