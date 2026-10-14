-- fx.lua — partículas, números de daño y efectos (port de js/entities/fx.js).
-- Todo lo puramente visual vive aquí. Nada de esto afecta al gameplay.
--
-- Todo se dibuja en la rejilla de píxeles del juego (G.Sprites.PX): las
-- partículas son cuadrados, los anillos elipses, y los golpes y rayos se
-- construyen con polígonos y rectángulos más los sprites de G.VFX.
--
-- Rendimiento 3DS: cada lista es un POOL de tablas que se reutilizan. Los
-- registros activos ocupan los índices 1..n; al borrar se intercambia con el
-- último (el orden no importa) y la tabla queda libre para el siguiente.
local U = G.U
local F = {}
G.FX = F

local lg = love.graphics
local floor, ceil, sin, cos, atan2, min, max, pi = math.floor, math.ceil, math.sin, math.cos, math.atan2, math.min, math.max, math.pi
local random = love.math.random
local TAU = 6.2832
local PX = G.Sprites and G.Sprites.PX or 2

-- Topes (PORT.md §10) y densidad de partículas (la web en calidad media usa 0.65).
local CAP_PARTS, CAP_SPRITES, CAP_TEXTS, CAP_RINGS, CAP_SLASHES, CAP_BEAMS = 150, 60, 24, 20, 12, 8
F.density = 0.6

-- ---------------- pools ----------------

local parts, nParts = {}, 0
local sprites, nSprites = {}, 0
local texts, nTexts = {}, 0
local rings, nRings = {}, 0
local slashes, nSlashes = {}, 0
local beams, nBeams = {}, 0

-- Saca el registro libre que sigue al último activo (o lo crea la primera vez).
local function take(pool, n)
    local r = pool[n + 1]
    if not r then r = {}; pool[n + 1] = r end
    return r
end

-- Quita el activo i intercambiándolo con el último: la tabla sigue en el pool.
local function drop(pool, i, n)
    pool[i], pool[n] = pool[n], pool[i]
    return n - 1
end

function F.clear()
    nParts, nSprites, nTexts, nRings, nSlashes, nBeams = 0, 0, 0, 0, 0, 0
end

local function snap(v) return floor(v / PX + 0.5) * PX end

-- Tablas de opciones fijas para F.sp (no se crean en cada golpe).
local SP_IMPACT_SLASH = { life = 0.2, scale = 1.5, frameRate = 12, fade = false }
local SP_JAWS         = { life = 0.24, scale = 1.5, frameRate = 9, fade = false }
local SP_CLAW         = { life = 0.2, scale = 1.5, angle = 0 }
local SP_LEAF         = { vx = 0, vy = 0, life = 0.45, spin = 0, grav = 60 }
local SP_IMPACT_SMALL = { life = 0.12, scale = 1 }
local SP_IMPACT_BIG   = { life = 0.18, scale = 1.5 }
-- Opciones reutilizadas para G.VFX.draw en el dibujo.
local vopts = { angle = 0, scale = 1, alpha = 1, frame = 0 }
-- Puntos del zigzag del rayo eléctrico (reutilizados).
local pts, ptsN = {}, 0

-- ---------------- partículas ----------------

-- Partícula cuadrada. o: { vx, vy, life, size (en píxeles de arte), grav, drag }
function F.px(x, y, color, o)
    if nParts >= CAP_PARTS then return end
    nParts = nParts + 1
    local p = take(parts, nParts - 1)
    p.x, p.y, p.color, p.t = x, y, color, 0
    if o then
        p.vx, p.vy = o.vx or 0, o.vy or 0
        p.life = o.life or 0.4
        p.s = (o.size or 1) * PX
        p.grav = o.grav or 0
        if o.drag == nil then p.drag = 0.9 else p.drag = o.drag end
    else
        p.vx, p.vy, p.life, p.s, p.grav, p.drag = 0, 0, 0.4, PX, 0, 0.9
    end
end

-- Igual que F.px pero sin tabla de opciones (para los bucles de aquí dentro).
local function pxv(x, y, color, vx, vy, life, size, grav)
    if nParts >= CAP_PARTS then return end
    nParts = nParts + 1
    local p = take(parts, nParts - 1)
    p.x, p.y, p.color, p.t = x, y, color, 0
    p.vx, p.vy, p.life = vx or 0, vy or 0, life or 0.4
    p.s = (size or 1) * PX
    p.grav = grav or 0
    p.drag = 0.9
end

function F.burst(x, y, color, n, power)
    n = n or 8; power = power or 110
    n = max(1, floor(n * F.density + 0.5))
    for _ = 1, n do
        local a = random() * TAU
        local s = U.rand(power * 0.35, power)
        pxv(x, y, color, cos(a) * s, sin(a) * s, U.rand(0.22, 0.5), random() < 0.35 and 2 or 1)
    end
end

function F.spark(x, y, color, dirX, dirY, n)
    n = max(1, floor((n or 4) * F.density + 0.5))
    local base = atan2(dirY, dirX)
    for _ = 1, n do
        local a = base + U.rand(-0.9, 0.9)
        local s = U.rand(60, 170)
        pxv(x, y, color, cos(a) * s, sin(a) * s, U.rand(0.14, 0.32))
    end
end

-- Sprite de efecto suelto. o: { vx, vy, life, scale, angle, spin, grav, frameRate, fade }
function F.sp(shape, pal, x, y, o)
    if nSprites >= CAP_SPRITES then return end
    nSprites = nSprites + 1
    local s = take(sprites, nSprites - 1)
    s.twinkle = false
    s.shape, s.pal, s.x, s.y, s.t = shape, pal, x, y, 0
    if o then
        s.vx, s.vy = o.vx or 0, o.vy or 0
        s.life = o.life or 0.4
        s.scale = o.scale or 1
        s.angle = o.angle or 0
        s.spin = o.spin or 0
        s.grav = o.grav or 0
        s.fr = o.frameRate or 10
        s.fade = o.fade ~= false
    else
        s.vx, s.vy, s.life, s.scale, s.angle, s.spin, s.grav, s.fr, s.fade = 0, 0, 0.4, 1, 0, 0, 0, 10, true
    end
end

-- Centelleo de shiny (cruz de píxeles que nace y se apaga).
function F.twinkle(x, y)
    if nSprites >= CAP_SPRITES then return end
    nSprites = nSprites + 1
    local s = take(sprites, nSprites - 1)
    s.twinkle = true
    s.x, s.y, s.vx, s.vy, s.t = x, y, 0, -8, 0
    s.life = U.rand(0.45, 0.7)
    s.spin, s.grav, s.angle = 0, 0, 0
end

-- Partículas de estela de los proyectiles, según el material.
function F.trail(kind, pal, x, y, vx, vy)
    if random() > F.density then return end                    -- menos estela en consola
    local P = G.VFX.PAL[pal] or G.VFX.PAL.normal
    local back = atan2(-vy, -vx)
    if kind == 'ember' then
        pxv(x + U.rand(-3, 3), y + U.rand(-3, 3), random() < 0.5 and P[4] or P[3], cos(back) * 30, -40, 0.35)
    elseif kind == 'drip' then
        pxv(x + U.rand(-3, 3), y + U.rand(-3, 3), P[4], cos(back) * 20, 10, 0.35, 1, 260)
    elseif kind == 'spark' then
        pxv(x + U.rand(-6, 6), y + U.rand(-6, 6), random() < 0.5 and P[5] or P[4], U.rand(-60, 60), U.rand(-60, 60), 0.16)
    elseif kind == 'bubbles' then
        pxv(x + U.rand(-3, 3), y + U.rand(-3, 3), P[4], 0, -35, 0.45, random() < 0.3 and 2 or 1)
    elseif kind == 'dirt' then
        pxv(x + U.rand(-3, 3), y + U.rand(-3, 3), random() < 0.5 and P[3] or P[2], cos(back) * 25, -20, 0.35, 1, 300)
    elseif kind == 'wisp' then
        pxv(x + U.rand(-6, 6), y + U.rand(-6, 6), random() < 0.5 and P[2] or P[3], 0, -30, 0.5, 2)
    end
end

-- Número de daño o aviso de texto. value: número o cadena. big: grande y dura más.
function F.dmgText(x, y, value, color, big)
    color = color or '#ffffff'
    big = big or false
    if type(value) == "number" then value = tostring(floor(value + 0.5)) end
    if nTexts >= CAP_TEXTS then
        -- Con cientos de golpes por segundo no se leen igual: los grandes
        -- (¡Muy eficaz!, jefes) siempre entran, sustituyendo al más viejo.
        if not big then return end
        local oldest, ok = 1, -1
        for i = 1, nTexts do
            local k = texts[i].t / texts[i].life
            if k > ok then ok = k; oldest = i end
        end
        nTexts = drop(texts, oldest, nTexts)
    end
    nTexts = nTexts + 1
    local t = take(texts, nTexts - 1)
    t.x, t.y, t.vy, t.t = x + U.rand(-6, 6), y, -46, 0
    t.life = big and 0.95 or 0.62
    t.s, t.color, t.big = value, color, big
end

-- Anillo de onda.
function F.ring(x, y, r0, r1, color, life, width)
    if nRings >= CAP_RINGS then return end
    nRings = nRings + 1
    local r = take(rings, nRings - 1)
    r.x, r.y, r.r0, r.r1, r.color = x, y, r0, r1, color
    r.life, r.t, r.width = life or 0.3, 0, width or 3
end

-- Golpe cuerpo a cuerpo. fx: { pal, melee } (ver G.VFX.forMove).
function F.slash(x, y, angle, radius, arc, color, fx)
    local pal = (fx and fx.pal) or 'normal'
    if nSlashes < CAP_SLASHES then
        nSlashes = nSlashes + 1
        local s = take(slashes, nSlashes - 1)
        s.x, s.y, s.angle, s.radius, s.arc, s.pal, s.color = x, y, angle, radius, arc, pal, color
        s.t, s.life = 0, 0.22
    end
    local melee = fx and fx.melee
    if not melee then return end
    local mx, my = x + cos(angle) * radius * 0.7, y + sin(angle) * radius * 0.7
    if melee == 'impact' then
        F.sp('impact', pal, mx, my, SP_IMPACT_SLASH)
    elseif melee == 'jaws' then
        F.sp('jaws', pal, mx, my, SP_JAWS)
    elseif melee == 'claw' then
        SP_CLAW.angle = angle - pi / 4
        F.sp('claw', pal, mx, my, SP_CLAW)
    elseif melee == 'vine' or melee == 'feather' then
        local p = melee == 'feather' and 'flying' or pal
        for _ = 1, 4 do
            local a = angle + U.rand(-arc / 2, arc / 2)
            local r = radius * U.rand(0.5, 1)
            SP_LEAF.vx, SP_LEAF.vy, SP_LEAF.spin = cos(a) * 40, sin(a) * 40 + 20, U.rand(-8, 8)
            F.sp('leaf', p, x + cos(a) * r, y + sin(a) * r, SP_LEAF)
        end
    end
end

-- Rayo recto. fx: { pal, beam } — beam = forma que viaja por él o 'lightning'.
function F.beam(x, y, angle, len, width, color, fx)
    local pal = (fx and fx.pal) or 'normal'
    if nBeams < CAP_BEAMS then
        nBeams = nBeams + 1
        local b = take(beams, nBeams - 1)
        b.x, b.y, b.angle, b.len, b.width, b.pal, b.color = x, y, angle, len, width, pal, color
        b.shape = fx and fx.beam or nil
        b.t, b.life, b.seed = 0, 0.2, floor(random() * 100)
    end
    F.sp('impact', pal, x + cos(angle) * 10, y + sin(angle) * 10, SP_IMPACT_SMALL)
    F.sp('impact', pal, x + cos(angle) * len, y + sin(angle) * len, SP_IMPACT_BIG)
end

-- ---------------- actualización ----------------

function F.update(dt)
    local i = 1
    while i <= nParts do
        local p = parts[i]
        p.t = p.t + dt
        if p.t >= p.life then
            nParts = drop(parts, i, nParts)
        else
            p.vy = p.vy + p.grav * dt
            p.x = p.x + p.vx * dt; p.y = p.y + p.vy * dt
            local k = p.drag ^ (dt * 60)
            p.vx = p.vx * k; p.vy = p.vy * k
            i = i + 1
        end
    end
    i = 1
    while i <= nSprites do
        local s = sprites[i]
        s.t = s.t + dt
        if s.t >= s.life then
            nSprites = drop(sprites, i, nSprites)
        else
            s.vy = s.vy + s.grav * dt
            s.x = s.x + s.vx * dt; s.y = s.y + s.vy * dt
            if s.spin ~= 0 then s.angle = s.angle + s.spin * dt end
            i = i + 1
        end
    end
    i = 1
    while i <= nTexts do
        local t = texts[i]
        t.t = t.t + dt
        if t.t >= t.life then
            nTexts = drop(texts, i, nTexts)
        else
            t.y = t.y + t.vy * dt; t.vy = t.vy * 0.94
            i = i + 1
        end
    end
    i = 1
    while i <= nRings do
        local r = rings[i]; r.t = r.t + dt
        if r.t >= r.life then nRings = drop(rings, i, nRings) else i = i + 1 end
    end
    i = 1
    while i <= nSlashes do
        local s = slashes[i]; s.t = s.t + dt
        if s.t >= s.life then nSlashes = drop(slashes, i, nSlashes) else i = i + 1 end
    end
    i = 1
    while i <= nBeams do
        local b = beams[i]; b.t = b.t + dt
        if b.t >= b.life then nBeams = drop(beams, i, nBeams) else i = i + 1 end
    end
end

-- ---------------- dibujo ----------------

-- La transparencia va a escalones (1 · ,66 · ,33) para que no parezca vectorial.
local function step(k) if k > 0.66 then return 1 elseif k > 0.33 then return 0.66 end return 0.33 end

local SEG = 16                     -- tramo del rayo (unidades de mundo)
local STEP16 = pi / 16

local function drawBeam(b, now)
    local k = 1 - b.t / b.life
    local P = G.VFX.PAL[b.pal] or G.VFX.PAL.normal
    local a = floor(b.angle / STEP16 + 0.5) * STEP16
    local alpha = step(k)
    lg.push()
    lg.translate(snap(b.x), snap(b.y))
    lg.rotate(a)
    if b.shape == 'lightning' then
        -- Zigzag que se redibuja cada fotograma.
        local n = 2
        pts[1], pts[2] = 0, 0
        local tt = floor(now * 30)
        local d = SEG
        while d < b.len - SEG do
            pts[n + 1] = d
            pts[n + 2] = snap((U.hash(d, tt, b.seed) - 0.5) * b.width)
            n = n + 2
            d = d + SEG
        end
        pts[n + 1], pts[n + 2] = b.len, 0
        n = n + 2
        for j = n + 1, ptsN do pts[j] = nil end          -- quita puntos viejos
        ptsN = n
        lg.setLineWidth(PX * 2); U.setColor(P[4], alpha); lg.line(pts)
        lg.setLineWidth(PX);     U.setColor(P[5], alpha); lg.line(pts)
        lg.setLineWidth(1)
    else
        -- Cuerpo del rayo a bloques, con el borde vibrando.
        local d = 0
        while d < b.len do
            local w = min(SEG, b.len - d)
            local wob = 0.7 + 0.3 * sin(d * 0.18 + now * 30 + b.seed)
            local hw = max(PX, snap(b.width / 2 * wob * (0.6 + 0.4 * k)))
            local h3 = snap(hw * 0.55)
            U.setColor(P[2], alpha); lg.rectangle("fill", d, -hw - PX, w, hw * 2 + PX * 2)
            U.setColor(P[3], alpha); lg.rectangle("fill", d, -hw, w, hw * 2)
            U.setColor(P[4], alpha); lg.rectangle("fill", d, -h3, w, h3 * 2)
            U.setColor(P[5], alpha); lg.rectangle("fill", d, -PX, w, PX * 2)
            d = d + SEG
        end
        -- Sprites que viajan por el rayo (llamas, gotas, cristales, ondas).
        if b.shape then
            local gap = 26
            local d2 = (now * 420) % gap
            vopts.angle, vopts.scale, vopts.alpha = 0, 1.5, alpha
            while d2 < b.len - 6 do
                local yo = sin(d2 * 0.3 + b.seed) * b.width * 0.18
                vopts.frame = floor(d2 / gap + now * 12)
                G.VFX.draw(b.shape, b.pal, d2, yo, vopts)
                d2 = d2 + gap
            end
        end
    end
    lg.pop()
end

-- Arco del golpe: trapecios convexos por tramo (contorno, cuerpo y filo).
local function arcQuad(x, y, a0, a1, ro, ri)
    lg.polygon("fill", x + cos(a0) * ro, y + sin(a0) * ro, x + cos(a1) * ro, y + sin(a1) * ro,
                       x + cos(a1) * ri, y + sin(a1) * ri, x + cos(a0) * ri, y + sin(a0) * ri)
end

local function drawSlash(s)
    local k = 1 - s.t / s.life
    local P = G.VFX.PAL[s.pal] or G.VFX.PAL.normal
    local half = min(s.arc, TAU) / 2
    local r = s.radius * (0.72 + 0.28 * (1 - k))
    local n = max(6, ceil(r * half * 2 / (PX * 5)))
    local alpha = step(k)
    local da = half * 2 / n
    local a0 = s.angle - half
    for i = 0, n - 1 do
        local aa = a0 + i * da
        local ab = aa + da
        local th = sin(pi * (i + 0.5) / n) * 3 * k * PX         -- grosor del cuerpo
        U.setColor(P[1], alpha); arcQuad(s.x, s.y, aa, ab, r + PX * 2, r - th - PX)
        U.setColor(P[3], alpha); arcQuad(s.x, s.y, aa, ab, r + PX, r - th)
        U.setColor(P[5], alpha); arcQuad(s.x, s.y, aa, ab, r + PX, r)
    end
end

local function drawRing(r)
    local k = r.t / r.life
    local rad = r.r0 + (r.r1 - r.r0) * k
    lg.setLineWidth(r.width >= 4 and PX * 2 or PX)
    U.setColor(r.color, step(1 - k))
    G.Sprites.ellipseLine(snap(r.x), snap(r.y), rad, rad * 0.9)
end

-- Cruz de píxeles del shiny (port de G.Icons.twinkle de la web).
local ARM, TIP = '#fff3a8', '#9ae6ff'
local function drawTwinkle(x, y, phase)
    local st = (phase < 0.15 or phase >= 0.82) and 0 or (phase < 0.32 or phase >= 0.62) and 1 or 2
    local X, Y = snap(x), snap(y)
    lg.setColor(1, 1, 1, 1)
    lg.rectangle("fill", X, Y, PX, PX)
    if st >= 1 then
        U.setColor(ARM)
        lg.rectangle("fill", X + PX, Y, PX, PX); lg.rectangle("fill", X - PX, Y, PX, PX)
        lg.rectangle("fill", X, Y + PX, PX, PX); lg.rectangle("fill", X, Y - PX, PX, PX)
    end
    if st >= 2 then
        lg.rectangle("fill", X + PX * 2, Y, PX, PX); lg.rectangle("fill", X - PX * 2, Y, PX, PX)
        lg.rectangle("fill", X, Y + PX * 2, PX, PX); lg.rectangle("fill", X, Y - PX * 2, PX, PX)
        U.setColor(TIP)
        lg.rectangle("fill", X + PX * 3, Y, PX, PX); lg.rectangle("fill", X - PX * 3, Y, PX, PX)
        lg.rectangle("fill", X, Y + PX * 3, PX, PX); lg.rectangle("fill", X, Y - PX * 3, PX, PX)
        lg.rectangle("fill", X + PX, Y + PX, PX, PX); lg.rectangle("fill", X - PX, Y + PX, PX, PX)
        lg.rectangle("fill", X + PX, Y - PX, PX, PX); lg.rectangle("fill", X - PX, Y - PX, PX, PX)
    end
end

function F.draw()
    local cam = G.Camera
    local now = U.now()
    -- Límites de la vista (con margen) para no dibujar lo que no se ve.
    local l, t = cam.left() - 40, cam.top() - 40
    local r, b = l + cam.w + 80, t + cam.h + 80

    for i = 1, nBeams do drawBeam(beams[i], now) end
    for i = 1, nSlashes do drawSlash(slashes[i]) end
    for i = 1, nRings do drawRing(rings[i]) end
    lg.setLineWidth(1)

    for i = 1, nParts do
        local p = parts[i]
        if p.x > l and p.x < r and p.y > t and p.y < b then
            U.setColor(p.color, step(1 - p.t / p.life))
            lg.rectangle("fill", snap(p.x), snap(p.y), p.s, p.s)
        end
    end

    for i = 1, nSprites do
        local s = sprites[i]
        if s.x > l and s.x < r and s.y > t and s.y < b then
            local k = 1 - s.t / s.life
            if s.twinkle then
                drawTwinkle(s.x, s.y, s.t / s.life)
            else
                vopts.angle, vopts.scale = s.angle, s.scale
                vopts.alpha = s.fade and step(k) or 1
                vopts.frame = floor(s.t * s.fr)
                G.VFX.draw(s.shape, s.pal, s.x, s.y, vopts)
            end
        end
    end

    -- Números de daño: fuente por defecto a tamaño de pantalla (1/escala de
    -- cámara), los grandes ×1.5, con contorno negro.
    if nTexts > 0 then
        local font = lg.getFont()
        local fh = font:getHeight()
        local base = 1 / cam.scale
        for i = 1, nTexts do
            local tx = texts[i]
            if tx.x > l and tx.x < r and tx.y > t and tx.y < b then
                local k = 1 - tx.t / tx.life
                local alpha = min(1, k * 2.2)
                local sc = tx.big and base * 1.5 or base
                -- (El ancho del texto se mide una vez, no en cada fotograma.)
                if tx.wf ~= font or tx.ws ~= tx.s then tx.wf, tx.ws, tx.w = font, tx.s, font:getWidth(tx.s) end
                local w = tx.w * sc
                local x, y = U.snap(tx.x - w / 2), U.snap(tx.y - fh * sc)
                local o = base                                   -- 1 píxel de pantalla
                lg.setColor(0, 0, 0, 0.75 * alpha)
                lg.print(tx.s, x + o, y, 0, sc, sc); lg.print(tx.s, x - o, y, 0, sc, sc)
                lg.print(tx.s, x, y + o, 0, sc, sc); lg.print(tx.s, x, y - o, 0, sc, sc)
                U.setColor(tx.color, alpha)
                lg.print(tx.s, x, y, 0, sc, sc)
            end
        end
    end
    lg.setColor(1, 1, 1, 1)
    lg.setBlendMode("alpha")
end

function F.count() return nParts + nSprites + nTexts end
