-- combat.lua — ejecución de movimientos y colisiones (port de js/systems/combat.js).
-- Solo se ejecuta el movimiento ACTIVO del jugador (o el grupo de un vínculo). Cada
-- `kind` tiene aquí su implementación. Todos los ataques dañan también los objetos
-- destructibles del escenario (rocas, cofres, hierba alta).
--
-- Todo ocurre en el plano del suelo: (x, y) son pies / sombra.
-- Lo que se queda en el mapa un rato (minas, meteoros que caen, torretas, charcos
-- del rastro) vive en `fields` y se actualiza/dibuja aquí.
--
-- OJO: G.EnemyMgr.queryCircle devuelve una tabla REUTILIZADA. Aquí se copia a un
-- buffer propio (collect) antes de golpear, porque e:hurt puede desencadenar más
-- consultas (muerte, invocaciones...).
local U = G.U
local C = {}
G.Combat = C

local lg = love.graphics
local floor, sqrt, cos, sin, atan2, max, min, abs, pi = math.floor, math.sqrt, math.cos, math.sin, math.atan2, math.max, math.min, math.abs, math.pi
local random = love.math.random

local fields = {}
local buf = {}          -- copia de la consulta de enemigos
local pbuf = {}         -- props en círculo
local LIFT = G.LIFT

local function collect(x, y, r)
    local q, n = G.EnemyMgr.queryCircle(x, y, r)
    for i = 1, n do buf[i] = q[i] end
    for i = n + 1, #buf do buf[i] = nil end
    return buf, n
end

local function props(x, y, r)
    for i = #pbuf, 1, -1 do pbuf[i] = nil end
    local out = G.World.propsInCircle(x, y, r, pbuf)
    return out or pbuf
end

-- ---------------- ejecutar el movimiento activo ----------------

local TARGETED = { melee = true, beam = true, projectile = true, boomerang = true, chain = true, meteor = true, dash = true, cone = true }

local function reach(m)
    local k = m.kind
    if k == 'melee' then return m.radius + 30 end
    if k == 'beam' then return m.radius + 20 end
    if k == 'boomerang' then return m.radius + 40 end
    if k == 'chain' then return 280 end
    if k == 'meteor' then return 340 end
    if k == 'dash' then return m.radius + 60 end
    if k == 'cone' then return m.speed * m.life + 30 end
    return 520
end

-- Tabla de tipos × clima para un ataque de tipo `type` contra `e`.
local function typeK(ty, e) return G.Types.mult(ty, e.types) * G.Weather.mult(ty) end

local function hit(pl, e, dmg, col, dx, dy, knock, m)
    local k = typeK(m.type, e)
    dmg = dmg * k
    e:hurt(dmg, col, dx, dy, knock, G.Types.label(G.Types.mult(m.type, e.types)))
    pl:onDealt(dmg)
    pl.dmgDealt = pl.dmgDealt + dmg
    if m.burn and m.burn > 0 then e:applyBurn(m.burn) end
    if m.poison and m.poison > 0 then e:applyPoison(m.poison) end
    if m.slow and m.slow > 0 then e:applySlow(m.slow) end
end

local function payload(p, m)
    p.burn = m.burn or 0; p.poison = m.poison or 0; p.slow = m.slow or 0; p.knock = m.knock or 0; p.mtype = m.type
    return p
end

local function newShot(pl, m, x, y, vx, vy, col, vis)
    return payload({ x = x, y = y, vx = vx, vy = vy, dmg = m.dmg * pl:atk(), r = m.size, life = m.life,
                     pierce = floor(m.pierce or 0), color = col, homing = m.homing or 0, vis = vis, owner = pl }, m)
end

local function fireProjectiles(pl, m)
    local col = U.TYPE_COLOR[m.type]
    local vis = G.VFX.forMove(m)
    local n = max(1, floor(m.count or 1))
    local spread = m.spread or 0
    for i = 0, n - 1 do
        local off = n == 1 and 0 or (i / (n - 1) - 0.5) * spread * n
        local a = pl.aim + off + U.rand(-0.03, 0.03)
        G.Projectiles.spawn(newShot(pl, m, pl.x + cos(a) * 3, pl.y + sin(a) * 3, cos(a) * m.speed, sin(a) * m.speed, col, vis))
    end
    G.FX.spark(pl.x + cos(pl.aim) * pl.r, pl.y - LIFT + sin(pl.aim) * pl.r, col, cos(pl.aim), sin(pl.aim), 3)
end

local function nova(pl, m)
    local col = U.TYPE_COLOR[m.type]
    local vis = G.VFX.forMove(m)
    local n = max(3, floor(m.count or 3))
    for i = 0, n - 1 do
        local a = (i / n) * 6.2832 + U.rand(-0.06, 0.06)
        G.Projectiles.spawn(newShot(pl, m, pl.x + cos(a) * 3, pl.y + sin(a) * 3, cos(a) * m.speed, sin(a) * m.speed, col, vis))
    end
    G.FX.ring(pl.x, pl.y, pl.r, pl.r * 4, col, 0.3, 3)
end

local function inArc(px, py, x, y, aim, half)
    local a = atan2(y - py, x - px)
    return abs(((a - aim + pi * 3) % 6.2832) - pi) <= half
end

local function melee(pl, m)
    local col = U.TYPE_COLOR[m.type]
    local half = min(m.arc, 6.2832) / 2
    G.FX.slash(pl.x, pl.y - LIFT * 0.5, pl.aim, m.radius, m.arc, col, G.VFX.forMove(m))
    local es, n = collect(pl.x, pl.y, m.radius)
    for i = 1, n do
        local e = es[i]
        if inArc(pl.x, pl.y, e.x, e.y, pl.aim, half) then
            hit(pl, e, m.dmg * pl:atk(), col, e.x - pl.x, e.y - pl.y, m.knock or 0, m)
        end
    end
    local ps = props(pl.x, pl.y, m.radius)
    for i = 1, #ps do
        local p = ps[i]
        if inArc(pl.x, pl.y, p.x, p.y, pl.aim, half) then G.World.damageProp(p, m.dmg * pl:atk(), col) end
    end
end

local function beam(pl, m)
    local col = U.TYPE_COLOR[m.type]
    local w = m.width
    local ca, sa = cos(pl.aim), sin(pl.aim)
    -- El rayo se corta en la primera pared.
    local len = m.radius
    local d = 8
    while d < m.radius do
        if G.World.isWall(pl.x + ca * d, pl.y + sa * d) then len = d break end
        d = d + 8
    end
    G.FX.beam(pl.x, pl.y - LIFT, pl.aim, len, w, col, G.VFX.forMove(m))
    G.Camera.kick(0.08)
    local mx, my = pl.x + ca * len / 2, pl.y + sa * len / 2
    local function onBeam(x, y, r)
        local px, py = x - pl.x, y - pl.y
        local along = px * ca + py * sa
        if along < -r or along > len + r then return false end
        return abs(-px * sa + py * ca) <= w / 2 + r
    end
    local es, n = collect(mx, my, len / 2 + w)
    for i = 1, n do
        local e = es[i]
        if onBeam(e.x, e.y, e.r) then hit(pl, e, m.dmg * pl:atk(), col, ca, sa, 0, m) end
    end
    local ps = props(mx, my, len / 2 + w)
    for i = 1, #ps do
        local p = ps[i]
        if onBeam(p.x, p.y, p.r) then G.World.damageProp(p, m.dmg * pl:atk(), col) end
    end
end

local spOpts = {}
local function aura(pl, m)
    local col = U.TYPE_COLOR[m.type]
    G.FX.ring(pl.x, pl.y, m.radius * 0.5, m.radius, col, 0.28, 2)
    local vis = G.VFX.forMove(m)
    if vis.aura then
        for i = 1, 5 do
            local a, r = random() * 6.2832, m.radius * U.rand(0.45, 1)
            local x, y = pl.x + cos(a) * r, pl.y + sin(a) * r * 0.8 - LIFT * 0.5
            -- Hierba Lazo tira hacia ti; veneno y sombras suben; el resto gira.
            local vx, vy
            if vis.inward then vx, vy = -cos(a) * r * 2.2, -sin(a) * r * 1.8
            elseif vis.rise then vx, vy = U.rand(-10, 10), -55
            else vx, vy = -sin(a) * 70, cos(a) * 55 end
            spOpts.vx = vx; spOpts.vy = vy; spOpts.life = 0.42
            spOpts.spin = G.VFX.spins(vis.aura) and U.rand(-6, 6) or 0
            spOpts.angle = nil; spOpts.scale = nil
            G.FX.sp(vis.aura, vis.pal, x, y, spOpts)
        end
    end
    local healed = 0
    local es, n = collect(pl.x, pl.y, m.radius)
    for i = 1, n do
        local e = es[i]
        hit(pl, e, m.dmg * pl:atk(), col, e.x - pl.x, e.y - pl.y, 0, m)
        if m.drain then healed = healed + m.drain end
    end
    local ps = props(pl.x, pl.y, m.radius)
    for i = 1, #ps do G.World.damageProp(ps[i], m.dmg * pl:atk(), col) end
    if healed > 0 then pl:heal(min(healed, 6)) end
end

local function buff(pl, m)
    pl:addBuff(m.stat, m.amount, m.dur, floor(m.stacks or 0))
    local col = U.TYPE_COLOR[m.type]
    G.FX.ring(pl.x, pl.y, pl.r * 2.4, pl.r * 1.1, col, 0.35, 2.5)
    local vis = G.VFX.forMove(m)
    for i = 1, 3 do
        spOpts.vx = 0; spOpts.vy = -70; spOpts.life = 0.6; spOpts.spin = 0; spOpts.angle = nil; spOpts.scale = nil
        G.FX.sp(vis.buff or 'arrow', vis.pal, pl.x + U.rand(-pl.r * 1.4, pl.r * 1.4), pl.y - U.rand(0, pl.bodyH * 0.8), spOpts)
    end
end

-- ---------------- familias nuevas ----------------

-- Bumerán: sale hacia el enemigo, se para y vuelve a ti golpeando a la ida y a la vuelta.
local function boomerang(pl, m)
    local col, vis = U.TYPE_COLOR[m.type], G.VFX.forMove(m)
    local n, spread = max(1, floor(m.count or 1)), m.spread or 0.5
    local out = m.radius / m.speed                       -- segundos de ida
    for i = 0, n - 1 do
        local a = pl.aim + (n == 1 and 0 or (i / (n - 1) - 0.5) * spread * min(n, 3))
        local p = newShot(pl, m, pl.x, pl.y, cos(a) * m.speed, sin(a) * m.speed, col, vis)
        p.life = out * 4 + 1.5; p.pierce = 999; p.boom = out; p.bsp = m.speed * 1.1
        G.Projectiles.spawn(p)
    end
end

-- Cadena: golpea a un enemigo y salta a los siguientes más cercanos (cada salto, algo menos).
local done = {}
local function chain(pl, m)
    local col, vis = U.TYPE_COLOR[m.type], G.VFX.forMove(m)
    local cur = pl.target
    if not (cur and not cur.dead and cur.hurt) then cur = G.Projectiles.nearest(G.EnemyMgr.all(), pl.x, pl.y, reach(m)) end
    if not cur then return end
    local fx, fy, k = pl.x, pl.y - LIFT, 1
    for key in pairs(done) do done[key] = nil end
    local n = max(1, floor(m.count or 1))
    local i = 0
    while i < n and cur do
        i = i + 1
        done[cur.id] = true
        local tx, ty = cur.x, cur.y - cur.bodyH * 0.5
        G.FX.beam(fx, fy, atan2(ty - fy, tx - fx), U.hypot(tx - fx, ty - fy), 10, col, vis)
        -- Infortunio: más daño a quien ya sufre un estado.
        local hex = (m.hex and (cur.burn > 0 or cur.poison > 0 or cur.slow > 0)) and m.hex or 1
        hit(pl, cur, m.dmg * pl:atk() * k * hex, col, tx - fx, ty - fy, 0, m)
        k = k * 0.85
        fx, fy = tx, ty
        local best, bd = nil, m.radius * m.radius
        local es, cnt = collect(cur.x, cur.y, m.radius)
        for j = 1, cnt do
            local e = es[j]
            if not done[e.id] then
                local d = U.dist2(cur.x, cur.y, e.x, e.y)
                if d < bd then bd = d; best = e end
            end
        end
        cur = best
    end
    G.Camera.kick(0.05)
end

local function countOwn(kind, pl)
    local n = 0
    for i = 1, #fields do
        local f = fields[i]
        if f.kind == kind and f.owner == pl and not f.gone then n = n + 1 end
    end
    return n
end

-- Las más viejas de un tipo se van cuando hay más de `keep`.
local function trimOwn(kind, pl, keep)
    local n = countOwn(kind, pl)
    for i = 1, #fields do
        if n <= keep then break end
        local f = fields[i]
        if f.kind == kind and f.owner == pl and not f.gone then f.gone = true; n = n - 1 end
    end
end

-- Minas: se quedan en el suelo y estallan cuando un enemigo las pisa.
local function mines(pl, m)
    local col, vis = U.TYPE_COLOR[m.type], G.VFX.forMove(m)
    local n = max(1, floor(m.count or 1))
    for i = 1, n do
        local a, d = random() * 6.2832, n == 1 and 0 or U.rand(18, 46)
        fields[#fields + 1] = { kind = 'mine', owner = pl, m = m, col = col, vis = vis, x = pl.x + cos(a) * d, y = pl.y + sin(a) * d * 0.8,
                                t = 0, arm = 0.35, life = m.dur or 7, r = m.radius, dmg = m.dmg * pl:atk() }
    end
    trimOwn('mine', pl, 4 + n * 2)
end

-- Meteoros: caen del cielo sobre enemigos cercanos (la sombra avisa dónde).
local near = {}
local function meteors(pl, m)
    local col, vis = U.TYPE_COLOR[m.type], G.VFX.forMove(m)
    local n = max(1, floor(m.count or 1))
    local es, cnt = collect(pl.x, pl.y, reach(m))
    for i = #near, 1, -1 do near[i] = nil end
    for i = 1, cnt do near[i] = es[i] end
    U.shuffle(near)
    for i = 1, n do
        local e = near[i]
        local x = e and (e.x + U.rand(-8, 8)) or (pl.x + U.rand(-140, 140))
        local y = e and (e.y + U.rand(-6, 6)) or (pl.y + U.rand(-110, 110))
        fields[#fields + 1] = { kind = 'meteor', owner = pl, m = m, col = col, vis = vis, x = x, y = y, t = -(i - 1) * 0.09, fall = 0.5,
                                r = m.radius, dmg = m.dmg * pl:atk() }
    end
end

-- Torreta: deja algo en el suelo que dispara solo un rato.
local function turret(pl, m)
    local col, vis = U.TYPE_COLOR[m.type], G.VFX.forMove(m)
    local a = pl.aim + pi + U.rand(-0.6, 0.6)
    fields[#fields + 1] = { kind = 'turret', owner = pl, m = m, col = col, vis = vis, x = pl.x + cos(a) * 26, y = pl.y + sin(a) * 20,
                            t = 0, life = m.dur or 6, shotT = 0.3, dmg = m.dmg * pl:atk(), kick = 0 }
    trimOwn('turret', pl, max(1, floor(m.count or 1)))
    G.FX.ring(pl.x, pl.y, 4, 30, col, 0.3, 2)
end

-- Distancia² del punto (cx, cy) al segmento (ax, ay)-(bx, by).
local function segDist2(ax, ay, bx, by, cx, cy)
    local dx, dy = bx - ax, by - ay
    local l2 = dx * dx + dy * dy
    local t = l2 > 0 and ((cx - ax) * dx + (cy - ay) * dy) / l2 or 0
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local qx, qy = ax + dx * t - cx, ay + dy * t - cy
    return qx * qx + qy * qy
end

-- Embestida: cruzas como un rayo hacia el enemigo y golpeas a todo lo del camino.
local function dash(pl, m)
    local col, vis = U.TYPE_COLOR[m.type], G.VFX.forMove(m)
    local ca, sa = cos(pl.aim), sin(pl.aim)
    local sx, sy = pl.x, pl.y
    local len = 0
    local d = 8
    while d <= m.radius do
        if not G.World.isFree(sx + ca * d, sy + sa * d, pl.r * 0.8, pl) then break end
        len = d
        d = d + 8
    end
    -- Estela: varias copias del golpe a lo largo del recorrido.
    local dd = 0
    while dd <= len do
        spOpts.vx = 0; spOpts.vy = 0; spOpts.life = 0.22; spOpts.spin = 0; spOpts.angle = pl.aim; spOpts.scale = nil
        G.FX.sp(vis.proj or 'streak', vis.pal, sx + ca * dd, sy + sa * dd - LIFT * 0.6, spOpts)
        dd = dd + 22
    end
    G.FX.slash(sx + ca * len, sy + sa * len - LIFT * 0.5, pl.aim, 34, 2.2, col, vis)
    pl.x = sx + ca * len; pl.y = sy + sa * len
    G.World.collide(pl)
    pl.invuln = max(pl.invuln or 0, 0.3)
    local w = m.width or 34
    local mx, my = sx + ca * len / 2, sy + sa * len / 2
    local es, n = collect(mx, my, len / 2 + w)
    for i = 1, n do
        local e = es[i]
        if segDist2(sx, sy, pl.x, pl.y, e.x, e.y) <= (w / 2 + e.r) ^ 2 then hit(pl, e, m.dmg * pl:atk(), col, ca, sa, m.knock or 0, m) end
    end
    local ps = props(mx, my, len / 2 + w)
    for i = 1, #ps do
        local p = ps[i]
        if segDist2(sx, sy, pl.x, pl.y, p.x, p.y) <= (w / 2 + p.r) ^ 2 then G.World.damageProp(p, m.dmg * pl:atk(), col) end
    end
    G.Camera.kick(0.12)
end

-- Rastro: vas dejando charcos que dañan a lo que pasa por encima.
local function trailPatch(pl, m)
    local col, vis = U.TYPE_COLOR[m.type], G.VFX.forMove(m)
    local last = pl.lastPatch
    if last and U.dist2(last.x, last.y, pl.x, pl.y) < (m.radius * 0.9) ^ 2 and last.t < 1 then return end
    local f = { kind = 'patch', owner = pl, m = m, col = col, vis = vis, x = pl.x, y = pl.y, t = 0, life = m.dur or 3, r = m.radius,
                tick = 0, dmg = m.dmg * pl:atk() }
    fields[#fields + 1] = f
    pl.lastPatch = f
    trimOwn('patch', pl, 18)
end

-- Abanico corto: muchos disparos rápidos que no llegan lejos (aliento, chorro...).
local function cone(pl, m)
    local col, vis = U.TYPE_COLOR[m.type], G.VFX.forMove(m)
    local n, arc = max(2, floor(m.count or 2)), m.arc or 0.9
    for i = 0, n - 1 do
        local a = pl.aim + (i / (n - 1) - 0.5) * arc + U.rand(-0.05, 0.05)
        local sp = m.speed * U.rand(0.85, 1.1)
        local p = newShot(pl, m, pl.x + cos(a) * 4, pl.y + sin(a) * 4, cos(a) * sp, sin(a) * sp, col, vis)
        p.life = m.life * U.rand(0.85, 1.05)
        G.Projectiles.spawn(p)
    end
    G.FX.spark(pl.x + cos(pl.aim) * pl.r, pl.y - LIFT + sin(pl.aim) * pl.r, col, cos(pl.aim), sin(pl.aim), 5)
end

-- Orbes que giran alrededor mientras el movimiento está activo.
local orbs = {}
local ORBCAST = { kind = 'orbit', cd = 1.6 }
local function orbit(pl, m, dt, now)
    local col = U.TYPE_COLOR[m.type]
    local want = max(1, floor(m.count or 1))
    -- Cada movimiento de órbita tiene sus orbes (puede haber dos en un vínculo).
    local all = G.Projectiles.all()
    local n = 0
    for i = 1, #all do
        local p = all[i]
        if p.orb and p.owner == pl and p.mid == m.id then n = n + 1; orbs[n] = p end
    end
    for i = #orbs, n + 1, -1 do orbs[i] = nil end
    local relayout = n ~= want
    local base = n > 0 and orbs[1].oa or now * m.speed
    for i = want + 1, n do G.Projectiles.remove(orbs[i]) end
    for i = n, want - 1 do
        G.Projectiles.spawnOrb(payload({ owner = pl, mid = m.id, x = pl.x, y = pl.y, r = m.size, color = col, vis = G.VFX.forMove(m),
                                         dmg = m.dmg * pl:atk(), oa = (i / want) * 6.2832, orad = m.radius, ospeed = m.speed,
                                         rehit = max(0.12, m.cd) }, m))
    end
    -- Recoge los vivos y ajusta sus números a las mejoras.
    n = 0
    for i = 1, #all do
        local p = all[i]
        if p.orb and p.owner == pl and p.mid == m.id then n = n + 1; orbs[n] = p end
    end
    for i = #orbs, n + 1, -1 do orbs[i] = nil end
    for i = 1, n do
        local p = orbs[i]
        p.dmg = m.dmg * pl:atk(); p.orad = m.radius; p.ospeed = m.speed; p.r = m.size
        if relayout then p.oa = base + ((i - 1) / n) * 6.2832 end
    end
    -- Animación de concentración de vez en cuando, para que se note vivo.
    pl.orbCastT = (pl.orbCastT or 0) - dt
    if pl.orbCastT <= 0 then pl.orbCastT = 1.6; pl:cast(ORBCAST) end
end

local function run(pl, m)
    local k = m.kind
    if k == 'projectile' then fireProjectiles(pl, m)
    elseif k == 'melee' then melee(pl, m)
    elseif k == 'beam' then beam(pl, m)
    elseif k == 'nova' then nova(pl, m)
    elseif k == 'aura' then aura(pl, m)
    elseif k == 'buff' then buff(pl, m)
    elseif k == 'boomerang' then boomerang(pl, m)
    elseif k == 'chain' then chain(pl, m)
    elseif k == 'mine' then mines(pl, m)
    elseif k == 'meteor' then meteors(pl, m)
    elseif k == 'turret' then turret(pl, m)
    elseif k == 'dash' then dash(pl, m)
    elseif k == 'trail' then trailPatch(pl, m)
    elseif k == 'cone' then cone(pl, m) end
end

local function tickMove(dt, pl, m, now)
    if m.kind == 'orbit' then orbit(pl, m, dt, now) return end
    m.t = m.t - dt
    if m.t > 0 then return end
    -- Los ataques que necesitan blanco esperan a tenerlo (no gastes animación al aire).
    if TARGETED[m.kind] and not (pl.target and U.dist(pl.x, pl.y, pl.target.x, pl.target.y) <= reach(m)) then
        m.t = 0.05
        return
    end
    m.t = max(0.05, m.cd * pl.cdMul)
    pl:cast(m)
    m.castAt = U.now()
    run(pl, m)
end

function C.tick(dt, pl, now)
    if pl.dead then return end
    local g = pl:activeGroup()
    for i = 1, #g do tickMove(dt, pl, g[i], now) end
end

-- ---------------- campos ----------------

-- Daño de un campo (mina, meteoro, charco) a todo lo que hay en su círculo.
local function blast(f, r, k)
    k = k or 1
    local pl, m = f.owner, f.m
    local es, n = collect(f.x, f.y, r)
    for i = 1, n do
        local e = es[i]
        hit(pl, e, f.dmg * k, f.col, e.x - f.x, e.y - f.y, m.knock or 0, m)
    end
    local ps = props(f.x, f.y, r)
    for i = 1, #ps do G.World.damageProp(ps[i], f.dmg * k, f.col) end
end

function C.updateFields(dt)
    for i = #fields, 1, -1 do
        local f = fields[i]
        f.t = f.t + dt
        if f.gone or not f.owner or (f.life and f.t >= f.life and f.kind ~= 'mine') then
            table.remove(fields, i)
        elseif f.kind == 'mine' then
            local armed = f.t >= f.arm
            local trig = false
            if armed then
                local _, n = G.EnemyMgr.queryCircle(f.x, f.y, 14)
                trig = n > 0
            end
            if trig or f.t >= f.life then
                G.FX.ring(f.x, f.y, 4, f.r, f.col, 0.3, 4)
                G.FX.burst(f.x, f.y - 6, f.col, 10, 150)
                if G.Camera.sees(f.x, f.y, 40) then G.Audio.sfx('break') end
                blast(f, f.r, trig and 1 or 0.5)
                table.remove(fields, i)
            end
        elseif f.kind == 'meteor' then
            if f.t >= f.fall then
                G.FX.ring(f.x, f.y, 4, f.r, f.col, 0.35, 4)
                G.FX.burst(f.x, f.y - 6, f.col, 12, 170)
                if G.Camera.sees(f.x, f.y, 40) then G.Audio.sfx('break'); G.Camera.kick(0.12) end
                blast(f, f.r)
                table.remove(fields, i)
            end
        elseif f.kind == 'turret' then
            f.shotT = f.shotT - dt
            if f.shotT <= 0 then
                local m = f.m
                local tg = G.Projectiles.nearest(G.EnemyMgr.all(), f.x, f.y, m.range or 300)
                f.shotT = tg and (m.rate or 0.6) or 0.15
                if tg then
                    local a = atan2(tg.y - f.y, tg.x - f.x)
                    local sp = m.speed or 300
                    local p = payload({ x = f.x, y = f.y, vx = cos(a) * sp, vy = sin(a) * sp, dmg = f.dmg, r = m.size or 6, life = 1.4,
                                        pierce = floor(m.pierce or 0), color = f.col, vis = f.vis, owner = f.owner }, m)
                    G.Projectiles.spawn(p)
                    f.kick = 0.12
                end
            end
            if f.kick > 0 then f.kick = f.kick - dt end
        elseif f.kind == 'patch' then
            f.tick = f.tick - dt
            if f.tick <= 0 then f.tick = 0.5; blast(f, f.r) end
            if f.vis.aura and random() < dt * 3 and G.Camera.sees(f.x, f.y, 20) then
                spOpts.vx = 0; spOpts.vy = -40; spOpts.life = 0.4; spOpts.spin = 0; spOpts.angle = nil; spOpts.scale = nil
                G.FX.sp(f.vis.aura, f.vis.pal, f.x + U.rand(-f.r, f.r) * 0.6, f.y - 4, spOpts)
            end
        end
    end
end

local drawOpts = {}
-- Lo de los campos que va en el suelo (debajo de los Pokémon).
function C.drawGroundFields()
    local now = U.now()
    for i = 1, #fields do
        local f = fields[i]
        if G.Camera.sees(f.x, f.y, 60) then
            if f.kind == 'patch' then
                local a = min(1, (f.life - f.t) * 2, f.t * 6)
                U.setColor(f.col, 0.32 * a)
                lg.ellipse('fill', f.x, f.y, f.r, f.r * 0.62)
                U.setColor(f.col, 0.5 * a)
                lg.setLineWidth(1.5)
                lg.ellipse('line', f.x, f.y, f.r * 0.8, f.r * 0.5)
                lg.setLineWidth(1)
            elseif f.kind == 'mine' then
                local armed = f.t >= f.arm
                local blink = armed and sin(now * 8 + f.x) > 0.3
                U.setColor(f.col, 0.18)
                lg.ellipse('fill', f.x, f.y, f.r * 0.45, f.r * 0.28)
                lg.setColor(1, 1, 1, 1)
                drawOpts.scale = 1; drawOpts.alpha = blink and 1 or 0.75; drawOpts.frame = 0; drawOpts.angle = 0
                G.VFX.draw(f.vis.proj, f.vis.pal, f.x, f.y - 4, drawOpts)
            elseif f.kind == 'meteor' then
                local k = U.clamp(f.t / f.fall, 0, 1)
                lg.setColor(0, 0, 0, 0.2 + k * 0.3)
                lg.ellipse('fill', f.x, f.y, f.r * (0.3 + k * 0.7), f.r * 0.6 * (0.3 + k * 0.7))
                U.setColor(f.col, 0.6)
                lg.setLineWidth(1.5)
                lg.ellipse('line', f.x, f.y, f.r, f.r * 0.6)
                lg.setLineWidth(1)
            elseif f.kind == 'turret' then
                lg.setColor(0, 0, 0, 0.3)
                lg.ellipse('fill', f.x, f.y, 11, 4.5)
            end
        end
    end
    lg.setColor(1, 1, 1, 1)
end

-- Lo de los campos que va por encima (meteoros cayendo, torretas).
function C.drawAirFields()
    local now = U.now()
    for i = 1, #fields do
        local f = fields[i]
        if G.Camera.sees(f.x, f.y, 200) then
            if f.kind == 'meteor' and f.t > 0 then
                local k = U.clamp(f.t / f.fall, 0, 1)
                drawOpts.scale = 1.5; drawOpts.alpha = 1; drawOpts.frame = floor(now * 12); drawOpts.angle = atan2(170, -40)
                G.VFX.draw(f.vis.proj, f.vis.pal, f.x + (1 - k) * 40, f.y - (1 - k) * 170 - 6, drawOpts)
            elseif f.kind == 'turret' then
                local fade = min(1, (f.life - f.t) * 2, f.t * 5)
                local bob = sin(now * 4 + f.x) * 2 - (f.kick > 0 and 2 or 0)
                drawOpts.scale = 1.5; drawOpts.alpha = fade; drawOpts.frame = floor(now * 8); drawOpts.angle = 0
                G.VFX.draw(f.vis.proj, f.vis.pal, f.x, f.y - 16 + bob, drawOpts)
            end
        end
    end
    lg.setColor(1, 1, 1, 1)
end

function C.clearFields(owner)
    if owner then
        for i = #fields, 1, -1 do if fields[i].owner == owner then table.remove(fields, i) end end
    else
        for i = #fields, 1, -1 do fields[i] = nil end
    end
end

function C.fieldCount() return #fields end

-- ---------------- colisiones ----------------

local impactOpts = { life = 0.12, scale = 1 }

function C.resolve(dt, pl, now)
    local projectiles = G.Projectiles.all()
    local W = G.World

    for i = #projectiles, 1, -1 do
        local p = projectiles[i]
        local removed = false

        if not p.friendly then
            -- Disparos enemigos: paredes y objetos sólidos dan cobertura.
            if W.projectileBlock(p.x, p.y, p.r) then
                G.FX.burst(p.x, p.y - LIFT, p.color, 5, 70)
                U.removeSwap(projectiles, i)
            elseif U.dist2(p.x, p.y, pl.x, pl.y) < (p.r + pl.r) * (p.r + pl.r) then
                pl:hurt(p.dmg, p.mtype)
                G.FX.burst(p.x, p.y - LIFT, p.color, 7, 110)
                U.removeSwap(projectiles, i)
            end
        else
            if not p.orb then
                local block = W.projectileBlock(p.x, p.y, p.r)
                if block == 'wall' or (block and not block.destructible) then
                    G.FX.burst(p.x, p.y - LIFT, p.color, 5, 80)
                    U.removeSwap(projectiles, i)
                    removed = true
                end
            end
            if not removed then
                -- Objetos del escenario (rocas, cofres, hierba).
                local consumed = false
                local ps = props(p.x, p.y, p.r)
                for j = 1, #ps do
                    local prop = ps[j]
                    if p.orb then
                        local k = -prop.id
                        local last = p.hitLog[k] or -99
                        if now - last >= p.rehit then
                            p.hitLog[k] = now
                            W.damageProp(prop, p.dmg, p.color)
                        end
                    elseif not p.phits[prop.id] then
                        p.phits[prop.id] = true
                        W.damageProp(prop, p.dmg, p.color)
                        -- La hierba no frena; lo sólido sí gasta perforación.
                        if prop.solid then
                            if p.pierce > 0 then p.pierce = p.pierce - 1 else consumed = true break end
                        end
                    end
                end
                if consumed then
                    G.FX.burst(p.x, p.y - LIFT, p.color, 5, 80)
                    U.removeSwap(projectiles, i)
                    removed = true
                end
            end
            if not removed then
                -- Enemigos. Colisión BARRIDA: se comprueba todo el tramo recorrido en este fotograma.
                local sx = (p.orb or p.px == nil) and p.x or p.px
                local sy = (p.orb or p.py == nil) and p.y or p.py
                local half = U.hypot(p.x - sx, p.y - sy) / 2
                local es, n = collect((sx + p.x) / 2, (sy + p.y) / 2, half + p.r)
                for j = 1, n do
                    local e = es[j]
                    if segDist2(sx, sy, p.x, p.y, e.x, e.y) <= (p.r + e.r) * (p.r + e.r) then
                        local skip = false
                        if p.orb then
                            local last = p.hitLog[e.id] or -99
                            if now - last < p.rehit then skip = true else p.hitLog[e.id] = now end
                        else
                            if p.hits[e.id] then skip = true else p.hits[e.id] = true end
                        end
                        if not skip then
                            local k = p.mtype and typeK(p.mtype, e) or 1
                            e:hurt(p.dmg * k, p.color, (p.vx ~= 0 and p.vx or (e.x - pl.x)), (p.vy ~= 0 and p.vy or (e.y - pl.y)), p.knock,
                                   p.mtype and G.Types.label(G.Types.mult(p.mtype, e.types)) or nil)
                            if random() < 0.5 then G.FX.sp('impact', p.vis and p.vis.pal or 'normal', e.x, e.y - e.bodyH * 0.5, impactOpts) end
                            pl.dmgDealt = pl.dmgDealt + p.dmg * k
                            pl:onDealt(p.dmg * k)
                            if p.burn > 0 then e:applyBurn(p.burn) end
                            if p.poison > 0 then e:applyPoison(p.poison) end
                            if p.slow > 0 then e:applySlow(p.slow) end
                            if not p.orb then
                                if p.pierce > 0 then p.pierce = p.pierce - 1
                                else
                                    G.FX.burst(p.x, p.y - LIFT, p.color, 5, 80)
                                    U.removeSwap(projectiles, i)
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Contacto enemigo <-> jugador
    if pl.dead then return end
    local es, n = collect(pl.x, pl.y, pl.r + 40)
    for i = 1, n do
        local e = es[i]
        if U.dist2(e.x, e.y, pl.x, pl.y) <= (e.r + pl.r) * (e.r + pl.r) and e.touchCd <= 0 and e.behavior ~= 'thief' then
            e.touchCd = 0.55
            e:strike(pl)
            pl:hurt(e.dmg, e.atkType)
            if pl:hasItem('rockyhelmet') then e:hurt(15 + pl.level * 4, '#9aa6b5', e.x - pl.x, e.y - pl.y, 80) end
            local nx, ny = U.norm(e.x - pl.x, e.y - pl.y)
            e.kx = e.kx + nx * 150; e.ky = e.ky + ny * 150
        end
    end
end
