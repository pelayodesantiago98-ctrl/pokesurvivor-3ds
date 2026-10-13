-- judgment.lua — La Sentencia de Arceus (minuto 30). Port de js/systems/judgment.js
-- (web, 13-10-2026), sin cooperativo.
--
-- Al llegar al minuto 30 de la arena infinita se acaba la partida "normal"
-- (como la Muerte de Vampire Survivors):
--
--   1. Animación: la pantalla se oscurece, aparece "LA SENTENCIA DE ARCEUS" con
--      su rueda dorada, destello y viaje a una arena enorme y arrasada (Ruinas
--      del Juicio). Arceus baja del cielo por un pilar de luz y cae con una onda
--      de choque. La primera vez se ve entera; después se puede saltar (A).
--      Mientras dura, el resto del juego está parado (también el reloj).
--   2. Pelea: Arceus es INVENCIBLE (no es un enemigo: los ataques no le
--      apuntan). Te persigue cada vez más deprisa; tocarle quita el 40 % de la
--      vida y lanza la Sentencia (pilares de luz), rayos en cruz y ondas, todo
--      con aviso en el suelo. Ese daño ignora tipos y defensa.
--   3. Cada 5 s acude un legendario al azar, cada uno con el DOBLE de vida y de
--      daño que el anterior. El primero, según el daño que hacías antes de la
--      Sentencia a UN enemigo (unos 3 s), para que no caiga al momento. Dan
--      experiencia, pero nada más (ni monedas, ni tickets, ni objetos).
--   4. Sin límite de tiempo: los legendarios que se acumulan acaban contigo.
--
-- Mientras dura no sale nada más (ni oleadas, ni eventos, ni clima, ni
-- grietas; desde el 28:00 ya no se abren grietas). Si a las 30:00 estás en una
-- grieta o eligiendo una carta, empieza al terminar. En el modo Fases no hay
-- Sentencia (J.applies).
--
-- Diferencias con la web (3DS): como mucho JUDGE_CAP legendarios vivos a la vez
-- (el siguiente espera; en una partida de verdad nunca se llega: el 8.º ya pega
-- 128 veces más que el 1.º) y el doble por legendario deja de crecer en 2^60
-- (para que la vida no llegue a infinito en las pruebas con el jugador inmortal).
--
--   G.Judgment.reset()  update(dt, pl, time)  cineTick(dt)  skip()
--   active() cinematic() applies() music() summary() -> { time, bosses } o nil
--   noteDmg(d, e) (Enemy:hurt)  bossDown() (Progress.kill)
--   drawable() (escena, por Y)  drawAir() (mundo, encima)  drawHud(W, H, pl, boss) (pantalla superior)
local U = G.U
local J = {}
G.Judgment = J

local lg = love.graphics
local floor, min, max, cos, sin, random = math.floor, math.min, math.max, math.cos, math.sin, love.math.random

local AT = 30 * 60
J.AT = AT
local ARENA_R = 24                  -- en tiles (la arena de la grieta: 11)
local BOSS_EVERY = 5                -- sin tope de tiempo: siguen saliendo mientras aguantes
local JUDGE_CAP = 12                -- (3DS) legendarios vivos a la vez como mucho
local TOUCH = 0.4                   -- vida que quita tocar a Arceus
local ARCEUS, SCALE = 493, 1.5
-- Línea de tiempo de la animación (segundos).
local T_TITLE, T_FLASH, T_PORT, T_DESC, T_LAND, T_BACK, T_END = 1.3, 4.7, 5.1, 5.7, 7.9, 9.1, 10.1
local GOLD = '#ffd25e'
local RANGED_TYPES = { psychic = true, electric = true, ghost = true, fairy = true,
                       fire = true, water = true, ice = true, dragon = true }
local function TS() return ((G.Tiles and G.Tiles.T) or 16) * G.Sprites.PX end

local phase = nil                   -- nil | 'cine' | 'fight'
local ct = 0                        -- reloj de la animación
local cfg = nil                     -- { tx, ty, q = { dex de los legendarios } }
local ported, landed, canSkip = false, false, false
local A = nil                       -- Arceus
local center = nil                  -- centro de la arena (mundo)
local arenaT, bossT, bossN, base, downs = 0, 0, 0, 0, 0
-- Daño a un solo enemigo por segundo (el que más recibe en cada segundo; con
-- ataques en área, sumar todo daría una vida enorme). Se guardan los últimos
-- 30 s y vale la media de los 6 mejores.
local hits, hitT, samples = {}, 0, {}
local embers = {}
local cineAnim = nil
local cam = nil
local legendPool = nil

function J.reset()
    phase = nil; ct = 0; cfg = nil; ported = false; landed = false; canSkip = false
    A = nil; center = nil; arenaT = 0; bossT = 0; bossN = 0; base = 0; downs = 0
    hits = {}; hitT = 0; samples = {}; embers = {}; cam = nil; cineAnim = nil
end

function J.active() return phase ~= nil end
function J.cinematic() return phase == 'cine' end
-- Sólo en la arena infinita (en el modo Fases cada fase tiene su final).
function J.applies() return not (G.Stages and G.Stages.active()) end

-- Lo que suena: nada en la animación hasta que aterriza.
function J.music()
    if phase == 'cine' and ct < T_LAND then return nil end
    return 'judgment'
end

-- Para el resumen de la partida.
function J.summary()
    if phase == 'fight' then return { time = arenaT, bosses = downs } end
    return nil
end

-- Daño hecho a un enemigo (lo llama Enemy:hurt).
function J.noteDmg(d, e)
    if phase then return end
    hits[e.id] = (hits[e.id] or 0) + d
end

local function sampleDps(dt)
    hitT = hitT + dt
    if hitT < 1 then return end
    local best = 0
    for k, v in pairs(hits) do
        if v > best then best = v end
        hits[k] = nil
    end
    samples[#samples + 1] = best / hitT
    if #samples > 30 then table.remove(samples, 1) end
    hitT = 0
end

local function singleDps()
    local s = {}
    for i = 1, #samples do s[i] = samples[i] end
    table.sort(s, function(a, b) return a > b end)
    local n, sum = min(6, #s), 0
    for i = 1, n do sum = sum + s[i] end
    return n > 0 and sum / n or 0
end

-- Sprites: el compañero, Arceus, los legendarios vivos y los próximos.
local function gcSprites()
    local pl = G.Game.player()
    local keep, keepFull = { [ARCEUS] = true }, {}
    if pl then keep[pl.dex] = true; keepFull[pl.dex] = true end
    local all = G.EnemyMgr.all()
    for i = 1, #all do keep[all[i].dex] = true end
    if cfg then for i = 0, 3 do keep[cfg.q[(bossN + i) % #cfg.q + 1]] = true end end
    G.Sprites.gc(keep, keepFull)
end

-- ---------------- arranque ----------------

local function begin(c)
    if phase then return end
    cfg = c
    phase = 'cine'; ct = 0
    local s = G.DB.save
    -- La primera vez se ve entera.
    canSkip = (s and s.stats and (s.stats.judged or 0) > 0) and true or false
    cineAnim = G.Sprites.Animator.new(ARCEUS, 1)
    G.Audio.music(nil)
end

-- Elige la arena y los legendarios, y empieza.
local function start()
    if not legendPool then
        legendPool = {}
        for i = 1, #G.DEX do
            local p = G.DEX[i]
            if p.leg and p.dex ~= ARCEUS and G.Sprites.meta(p.dex) then legendPool[#legendPool + 1] = p end
        end
    end
    if #legendPool == 0 then return end
    local q = {}
    for i = 1, 40 do q[i] = U.pick(legendPool).dex end
    begin({ tx = -6000 - floor(random() * 2000), ty = -6000 - floor(random() * 2000), q = q })
end

-- Viaje a la arena (a mitad de la animación, tapado por el destello).
local function port()
    ported = true
    local pl = G.Game.player()
    local ts = TS()
    G.Rift.reset()
    G.EnemyMgr.stash()
    G.Projectiles.clear()
    G.Combat.clearFields()
    G.Hazards.clear()
    G.Pickups.clear()
    G.Events.reset()
    G.Weather.clear()
    G.World.setArena({ tx = cfg.tx, ty = cfg.ty, r = ARENA_R, type = 'judgment' })
    G.World.setBiome(G.Tiles.arenaBiome('judgment'), true)
    center = { x = cfg.tx * ts + ts / 2, y = cfg.ty * ts + ts / 2 }
    pl.x = center.x; pl.y = center.y + ts * 3
    G.Camera.x = pl.x; G.Camera.y = pl.y
    gcSprites()
    local first = { ARCEUS }
    for i = 1, 4 do first[#first + 1] = cfg.q[i] end
    G.Sprites.preload(first, false)
    local anim = G.Sprites.Animator.new(ARCEUS, SCALE)
    anim.dir = 0
    A = { x = center.x, y = center.y - ts * 5, lift = 900, anim = anim,
          r = G.Sprites.bodyRadius(ARCEUS, SCALE) * 0.9, bodyH = G.Sprites.bodyHeight(ARCEUS, SCALE),
          cd = 2.2, cast = nil, touchCd = 0, spin = 0, last = nil }
    G.Spawner.sayZone('Ruinas del Juicio')
end

-- Arceus toca el suelo.
local ATTACK08 = { speed = 0.8 }
local function land(quiet)
    if landed or not A then return end
    landed = true
    A.lift = 0
    A.anim:play('Attack', ATTACK08)
    if quiet then return end
    G.Camera.kick(1.2)
    G.Game.flash('#fff3c8', 0.7)
    G.Audio.sfx('land')
    for i = 0, 3 do
        G.FX.ring(A.x, A.y, 10 + i * 20, 260 + i * 140, (i % 2 == 1) and '#fff3c8' or GOLD, 0.5 + i * 0.25, 8 - i)
    end
    G.FX.burst(A.x, A.y - 20, GOLD, 40, 360)
    G.FX.burst(A.x, A.y - 10, '#ffffff', 20, 240)
end

-- Fin de la animación: empieza la pelea.
local function fight()
    phase = 'fight'
    if not ported then port() end
    land(true)
    arenaT = 0; bossT = 1.2; bossN = 0; downs = 0
    G.Progress.event('judge')
    -- Vida del primer legendario: unos 3 s de tu daño a un enemigo (y un mínimo).
    local t = G.Game.time()
    base = max((3200 + t * 9) * 0.35, singleDps() * 3)
    G.Spawner.say('¡Huye de Arceus! Es invencible', 3, true)
end

local function doSkip()
    if phase ~= 'cine' then return end
    if not ported then port() end
    land(true)
    ct = T_BACK
end

-- Salta la animación (botón A / START / B), si se puede.
function J.skip()
    if phase ~= 'cine' or not canSkip or ct >= T_BACK then return end
    doSkip()
end
function J.canSkip() return phase == 'cine' and canSkip and ct < T_BACK end

-- ---------------- cada fotograma ----------------

local PX_FALL = { vy = 100, life = 0.9 }
local PX_UP = { vy = -30, life = 0.6 }

-- Durante la animación (el resto del juego está parado).
function J.cineTick(dt)
    local prev = ct
    ct = ct + dt
    local function at(x) return prev < x and ct >= x end
    local pl = G.Game.player()
    if cineAnim then cineAnim:update(dt) end
    if at(0.01) then G.Audio.sfx('quake'); G.Camera.kick(0.9) end
    if ct < T_FLASH and random() < dt * 3 then G.Camera.kick(0.15) end
    if at(T_TITLE) then G.Audio.sfx('toll') end
    if at(T_TITLE + 1.7) then G.Audio.sfx('toll') end
    if at(T_FLASH) then G.Game.flash('#ffffff', 0.9) end
    if at(T_PORT) and not ported then port() end
    if at(T_DESC) then G.Audio.sfx('descend') end
    if A and not landed then
        -- Bajada: lenta al principio y frenando al final (como si se posara).
        local k = U.clamp((ct - T_DESC) / (T_LAND - T_DESC), 0, 1)
        A.lift = 900 * (1 - k) ^ 2.2
        A.anim:loop('Idle')
        if ct > T_DESC and random() < dt * 20 then
            PX_FALL.vy = U.rand(60, 160)
            G.FX.px(A.x + U.rand(-60, 60), A.y - A.lift - U.rand(0, 200), random() < 0.5 and GOLD or '#fff3c8', PX_FALL)
        end
        if at(T_LAND) then land() end
    end
    if A then A.anim:update(dt); A.spin = A.spin + dt end
    -- Cámara: tu Pokémon; sube despacio hacia Arceus mientras baja y vuelve.
    local tx, ty = pl.x, pl.y
    if ported and A and ct < T_BACK then tx = A.x; ty = A.y - 60 end
    if not cam or at(T_PORT) or (ported and not cam.ported) then cam = { x = G.Camera.x, y = G.Camera.y, ported = ported } end
    cam.x = U.damp(cam.x, tx, 2.2, dt); cam.y = U.damp(cam.y, ty, 2.2, dt)
    G.Camera.follow(cam.x, cam.y, dt)
    if ct >= T_END then cam = nil; fight() end
end

-- ---------------- Arceus ----------------

local function hz(o)
    o.type = nil; o.pure = true; o.dmg = 1; o.color = o.color or GOLD
    G.Hazards.add(o)
end

local PLAY = { speed = 1 }
local function playA(anim, speed) PLAY.speed = speed; A.anim:play(anim, PLAY) end

-- Ataques de Arceus: todos avisan en el suelo y quitan un % de la vida.
local function cast(id, tg)
    A.last = id
    local c = { id = id, t = 0, wind = 0.7 }
    A.cast = c
    if id == 'rain' then
        -- La Sentencia: pilares de luz sobre ti (más cuanto más dura).
        local n = 4 + min(6, floor(arenaT / 10))
        for i = 0, n - 1 do
            local a = random() * 6.2832
            local d = (i > 0) and U.rand(40, 150) or 0
            hz({ kind = 'zone', x = tg.x + cos(a) * d, y = tg.y + sin(a) * d * 0.8, r = 44, delay = 1.25 + i * 0.09, pct = 0.3, vis = 'pillar' })
        end
        playA('Shoot', 0.9)
    elseif id == 'cross' then
        -- Rayos en cruz que barren la arena.
        local a0 = math.atan2(tg.y - A.y, tg.x - A.x) + (random() < 0.5 and 0 or math.pi / 4)
        local n = arenaT > 30 and 8 or 4
        for i = 0, n - 1 do
            hz({ kind = 'beam', x = A.x, y = A.y, angle = a0 + i * 6.2832 / n, len = 1700, w = 34, delay = 1.1, pct = 0.35, color = '#fff3b0' })
        end
        c.wind = 1.1
        playA('Charge', 0.9)
    else
        -- Onda alrededor de él (si estás demasiado cerca).
        hz({ kind = 'zone', x = A.x, y = A.y, r = 170, delay = 0.85, pct = 0.4 })
        c.wind = 0.85
        playA('Charge', 1.2)
    end
    G.FX.ring(A.x, A.y, A.r, A.r * 3, GOLD, c.wind, 3)
end

local function castTick(dt, tg)
    local c = A.cast
    c.t = c.t + dt
    if tg then A.anim.dir = G.Sprites.dirFromAngle(math.atan2(tg.y - A.y, tg.x - A.x)) end
    if c.t >= c.wind and not c.done then
        c.done = true
        playA(c.id == 'nova' and 'Attack' or 'Shoot', 1.2)
    end
    if c.t >= c.wind + 0.35 then
        A.cast = nil
        A.cd = max(1.4, 3.2 - arenaT * 0.025)
    end
end

local function arceusTick(dt, pl)
    local tg = (pl and not pl.dead) and pl or nil
    if A.cast then castTick(dt, tg) return end
    if not tg then A.anim:loop('Idle') return end
    -- Más lento que tú al principio; a los ~35 s ya te alcanza.
    local k = min(1.22, 0.74 + arenaT * 0.013)
    local spd = max(70, tg:spd() * k)
    local dx, dy = U.norm(tg.x - A.x, tg.y - A.y)
    A.x = A.x + dx * spd * dt; A.y = A.y + dy * spd * dt
    A.anim.dir = G.Sprites.dirFromAngle(math.atan2(dy, dx))
    A.anim:loop('Walk', max(0.8, spd / 90))
    if random() < dt * 10 then G.FX.px(A.x + U.rand(-20, 20), A.y - U.rand(0, A.bodyH), GOLD, PX_UP) end
    A.cd = A.cd - dt
    if A.cd <= 0 then
        local d = U.dist(A.x, A.y, tg.x, tg.y)
        local id
        if d < 210 and random() < 0.6 then id = 'nova' else id = (A.last == 'rain') and 'cross' or 'rain' end
        cast(id, tg)
    end
end

-- Tocar a Arceus.
local function touch(pl)
    if not pl or pl.dead or A.touchCd > 0 then return end
    local rr = A.r + pl.r
    if U.dist2(A.x, A.y, pl.x, pl.y) > rr * rr then return end
    A.touchCd = 0.9
    pl.invuln = 0
    pl:hurt(pl.maxHp * TOUCH, nil, true)
    G.Camera.kick(0.6)
    G.FX.ring(pl.x, pl.y, 6, 70, GOLD, 0.4, 4)
    playA('Attack', 1.4)
end

-- Nadie sale de la arena (Arceus y los legendarios).
local function clampIn(o, lim)
    local dx, dy = o.x - center.x, o.y - center.y
    local d = U.hypot(dx, dy)
    if d > lim then o.x = center.x + dx / d * lim; o.y = center.y + dy / d * lim end
end
local function keepInside()
    local lim = (ARENA_R - 1.4) * TS()
    clampIn(A, lim)
    local all = G.EnemyMgr.all()
    for i = 1, #all do clampIn(all[i], lim) end
end

-- ---------------- legendarios ----------------

local function aliveJudges()
    local n = 0
    local all = G.EnemyMgr.all()
    for i = 1, #all do if all[i].judge and not all[i].dead then n = n + 1 end end
    return n
end

local function spawnBoss()
    local dex = cfg.q[bossN % #cfg.q + 1]
    local mon = G.DEX_BY[dex]
    if not mon then bossN = bossN + 1 return end
    local t = G.Game.time()
    local ts = TS()
    local pl = G.Game.player()
    -- Lejos de ti (en el borde de la arena).
    local x, y = center.x, center.y
    for _ = 1, 16 do
        local a, d = random() * 6.2832, (ARENA_R - U.rand(3, 6)) * ts
        x = center.x + cos(a) * d; y = center.y + sin(a) * d
        if not pl or U.dist2(pl.x, pl.y, x, y) > 280 * 280 then break end
    end
    local k = 2 ^ min(60, bossN)          -- cada uno, el doble que el anterior
    local ranged = false
    for i = 1, #mon.types do if RANGED_TYPES[mon.types[i]] then ranged = true end end
    local def = {
        dex = dex, name = mon.name,
        hp = U.round(base * k),
        spd = U.round(U.clamp(48 + (mon.spd - 78) * 0.6, 48, 105)),
        dmg = U.round((36 + t / 20) * k), xp = U.round(500 + t * 1.2),
        behavior = ranged and 'ranged' or 'charger',
        shotDmg = U.round((18 + t / 40) * k), shotCd = 0.9, range = 300
    }
    local e = G.Enemy.new(def, x, y, { hp = 1, spd = 1, dmg = 1 }, true)
    e.judge = true
    e.flying = false
    G.EnemyMgr.add(e)
    bossN = bossN + 1
    gcSprites()
    G.Sprites.preload({ cfg.q[(bossN + 3) % #cfg.q + 1] }, false)
    G.FX.ring(x, y, 8, 120, GOLD, 0.6, 5)
    G.FX.burst(x, y - 30, '#fff3c8', 16, 200)
    G.Spawner.say('¡' .. e.name .. ' acude a la Sentencia!', 1.8)
    G.Audio.sfx('rift')
end

-- Ha caído un legendario de la arena.
function J.bossDown() if phase == 'fight' then downs = downs + 1 end end

-- Ceniza y chispas que caen (en la pantalla superior, 400x240).
local function ember(dt)
    if #embers < 40 and random() < dt * 25 then
        local spark = random() < 0.3
        embers[#embers + 1] = { x = random() * 400, y = -4, vx = U.rand(-12, 5), vy = U.rand(10, 28), life = U.rand(5, 10),
                                s = spark and 1 or 2, a = spark and 0.9 or 0.45, c = spark and '#ffb347' or '#8a8078' }
    end
    for i = #embers, 1, -1 do
        local e = embers[i]
        e.x = e.x + e.vx * dt; e.y = e.y + e.vy * dt; e.life = e.life - dt
        if e.life <= 0 or e.y > 250 then table.remove(embers, i) end
    end
end

-- En la pelea (lo llama game.lua en cada fotograma de juego).
function J.update(dt, pl, time)
    if not phase then
        sampleDps(dt)                       -- (para la vida del primer legendario)
        if J.applies() and time >= AT and not G.Rift.inArena() then start() end
        return
    end
    if phase ~= 'fight' then return end
    arenaT = arenaT + dt
    A.touchCd = A.touchCd - dt; A.spin = A.spin + dt
    arceusTick(dt, pl)
    keepInside()
    bossT = bossT - dt
    if bossT <= 0 then
        if aliveJudges() >= JUDGE_CAP then bossT = 1
        else bossT = BOSS_EVERY; spawnBoss() end
    end
    A.anim:update(dt)
    touch(pl)
    ember(dt)
end

-- ---------------- dibujo ----------------

-- La rueda de Arceus: aro dorado con 12 joyas que gira.
local GEMS = { '#ff6b4d', '#4fa8ff', '#5fe08a', '#ffe14d', '#b37bff', '#c9d2de' }
local function wheel(x, y, R, rot, alpha)
    U.setColor(GOLD, alpha * 0.35)
    lg.setLineWidth(max(4, R * 0.14))
    lg.circle('line', x, y, R)
    U.setColor(GOLD, alpha)
    lg.setLineWidth(max(2, R * 0.07))
    lg.circle('line', x, y, R)
    lg.setLineWidth(max(1, R * 0.025))
    lg.circle('line', x, y, R * 0.82)
    for i = 0, 11 do
        local a = rot + i * 6.2832 / 12
        local ca, sa = cos(a), sin(a)
        local function p(r, t) return x + ca * r - sa * t, y + sa * r + ca * t end
        local x1, y1 = p(R * 1.02, 0)
        local x2, y2 = p(R * 0.91, -R * 0.07)
        local x3, y3 = p(R * 0.8, 0)
        local x4, y4 = p(R * 0.91, R * 0.07)
        U.setColor(GEMS[i % #GEMS + 1], alpha)
        lg.polygon('fill', x1, y1, x2, y2, x3, y3, x4, y4)
    end
    lg.setLineWidth(1)
    lg.setColor(1, 1, 1, 1)
end

-- Arceus, ordenado por Y con el resto de la escena.
local drawableT = { y = 0 }
function drawableT.draw()
    local lift = A.lift
    local near = U.clamp(1 - lift / 900, 0, 1)
    -- Sombra que crece mientras baja.
    lg.setColor(0, 0, 0, 0.15 + near * 0.3)
    lg.ellipse('fill', A.x, A.y, 44 * (0.4 + near * 0.6), 16 * (0.4 + near * 0.6))
    -- Aura dorada en el suelo.
    if lift < 40 then
        U.setColor(GOLD, 0.22 + sin(U.now() * 3) * 0.06)
        lg.ellipse('fill', A.x, A.y, A.r * 2.2, A.r * 0.8)
    end
    -- La rueda dorada detrás de él.
    wheel(A.x, A.y - lift - A.bodyH * 0.55, A.bodyH * 0.62, A.spin * 0.6, 0.55)
    A.anim:draw(A.x, A.y - lift)
end
function J.drawable()
    if not A or not ported then return nil end
    drawableT.y = A.y
    return drawableT
end

-- Por encima de todo (en el mundo): el pilar de luz por el que baja.
function J.drawAir()
    if not A or not ported or phase ~= 'cine' then return end
    local a = U.clamp((ct - T_PORT) / 0.6, 0, 1) * U.clamp((T_LAND + 0.6 - ct) / 0.6, 0, 1)
    if a <= 0 then return end
    local top, bot = G.Camera.top() - 40, A.y + 6
    local near = U.clamp(1 - A.lift / 900, 0, 1)
    local w = 40 + near * 40 + sin(ct * 9) * 6
    -- (Sin degradados: capas cada vez más estrechas y claras.)
    for i = 1, 4 do
        local k = 1 - (i - 1) * 0.22
        U.setColor(i < 3 and GOLD or '#fff8dc', a * 0.22)
        lg.rectangle('fill', A.x - w * k, top, w * 2 * k, max(0, bot - top))
    end
    -- Resplandor en el suelo, donde va a caer.
    U.setColor('#fff3c8', a * (0.25 + near * 0.4))
    lg.ellipse('fill', A.x, A.y, w * 1.5, w * 0.54)
    U.setColor(GOLD, a * (0.2 + near * 0.3))
    lg.ellipse('fill', A.x, A.y, w * 0.9, w * 0.32)
    lg.setColor(1, 1, 1, 1)
end

local function font(size) return G.UI.font(size) end

-- Texto dorado con borde.
local function goldText(s, x, y, size, alpha)
    local f = font(size)
    lg.setFont(f)
    local w = f:getWidth(s)
    local x0 = floor(x - w / 2)
    U.setColor('#2a1500', alpha)
    for dx = -2, 2, 2 do for dy = -2, 2, 2 do lg.print(s, x0 + dx, y + dy) end end
    U.setColor('#c7771a', alpha)
    lg.print(s, x0, y + 1)
    U.setColor(GOLD, alpha)
    lg.print(s, x0, y)
end

-- Título que aparece letra a letra (cada una cae y se asienta).
local function title(raw, cx, y, size, t0, alpha)
    local f = font(size)
    lg.setFont(f)
    local x = cx - f:getWidth(raw) / 2
    -- (Recorre caracteres UTF-8 enteros, no bytes.)
    local i = 0
    for ch in raw:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
        local cw = f:getWidth(ch)
        local p = U.clamp((ct - t0 - i * 0.055) / 0.28, 0, 1)
        if p > 0 and ch ~= ' ' then
            goldText(ch, x + cw / 2, y - (1 - p) * 14, size, alpha * p)
        end
        x = x + cw
        i = i + 1
    end
end

local CINE_DRAW = { flash = true, alpha = 1 }
local function drawCine(W, H)
    local t = ct
    -- Se oscurece todo (hasta el viaje).
    if t < T_PORT + 0.1 then
        lg.setColor(10 / 255, 6 / 255, 2 / 255, U.clamp(t / 1.1, 0, 1) * 0.86)
        lg.rectangle('fill', 0, 0, W, H)
    end
    -- "LA SENTENCIA DE ARCEUS"
    local a = U.clamp((t - T_TITLE + 0.3) / 0.5, 0, 1) * U.clamp((T_FLASH + 0.2 - t) / 0.35, 0, 1)
    if a > 0 then
        local cx, cy, R = W / 2, H * 0.3, min(W, H) * 0.2
        -- Rayos de luz que giran.
        for i = 0, 15 do
            local an = t * 0.18 + i * 6.2832 / 16
            local ex, ey = cx + cos(an) * W, cy + sin(an) * W
            local px, py = -sin(an) * R * 0.16 * 3, cos(an) * R * 0.16 * 3
            U.setColor('#ffd66e', a * 0.12)
            lg.polygon('fill', cx, cy, ex + px, ey + py, ex - px, ey - py)
        end
        wheel(cx, cy - R * 0.05, R, t * 0.35, a * 0.9)
        -- Arceus en silueta de luz, detrás de su rueda.
        if cineAnim then
            local rise = (1 - U.clamp((t - T_TITLE + 0.3) / 0.8, 0, 1)) * R * 0.3
            CINE_DRAW.alpha = a * 0.85
            cineAnim.scale = 1
            cineAnim:draw(cx, cy + R * 0.75 + rise, CINE_DRAW)
        end
        local ty = cy + R + 10
        title('LA SENTENCIA', cx, ty, 22, T_TITLE, a)
        title('DE ARCEUS', cx, ty + 26, 16, T_TITLE + 0.75, a)
        local b = a * U.clamp((t - T_TITLE - 1.6) / 0.6, 0, 1)
        if b > 0 then
            lg.setFont(font(10))
            U.setColor('#f3e2b0', b)
            lg.printf('El tiempo se ha agotado…', 0, ty + 48, W, 'center')
        end
    end
    -- Franjas negras de cine durante la bajada.
    if t > T_PORT then
        local k = U.clamp((t - T_PORT) / 0.5, 0, 1) * U.clamp((T_END - t) / 0.6, 0, 1)
        local bh = floor(H * 0.11 * k + 0.5)
        lg.setColor(0, 0, 0, 1)
        lg.rectangle('fill', 0, 0, W, bh)
        lg.rectangle('fill', 0, H - bh, W, bh)
    end
    -- ¡Ha descendido!
    local b = U.clamp((t - T_LAND - 0.15) / 0.3, 0, 1) * U.clamp((T_END - t) / 0.5, 0, 1)
    if b > 0 then
        goldText('¡ARCEUS HA DESCENDIDO!', W / 2, floor(H * 0.2), 22, b)
        lg.setFont(font(10))
        U.setColor('#000000', b * 0.8)
        lg.printf('Es invencible: huye y aguanta todo lo que puedas', 1, floor(H * 0.2) + 31, W, 'center')
        U.setColor('#ffe9b0', b)
        lg.printf('Es invencible: huye y aguanta todo lo que puedas', 0, floor(H * 0.2) + 30, W, 'center')
    end
    if canSkip and t < T_BACK then
        lg.setFont(font(10))
        U.setColor('#f3e2b0', 0.55 + sin(t * 4) * 0.2)
        lg.printf('A: saltar', 0, H - 14, W - 8, 'right')
    end
    lg.setColor(1, 1, 1, 1)
end

-- Pelea: cielo rojizo, ceniza, contador y flecha a Arceus.
local function drawFight(W, H, pl, boss)
    -- Bordes rojizos (sin degradado radial: bandas cada vez más tenues).
    for i = 0, 3 do
        local k = 0.09 - i * 0.02
        lg.setColor(120 / 255, 40 / 255, 10 / 255, k)
        local m = 10 + i * 10
        lg.rectangle('fill', 0, 0, W, m)
        lg.rectangle('fill', 0, H - m, W, m)
        lg.rectangle('fill', 0, m, m, H - 2 * m)
        lg.rectangle('fill', W - m, m, m, H - 2 * m)
    end
    for i = 1, #embers do
        local e = embers[i]
        U.setColor(e.c, min(1, e.life) * e.a)
        lg.rectangle('fill', floor(e.x), floor(e.y), e.s, e.s)
    end
    -- Contador bajo el reloj (y bajo la barra del jefe, si la hay).
    lg.setFont(font(10))
    local txt = 'SENTENCIA · ' .. U.mmss(arenaT) .. ' · JEFES ' .. downs
    local y = boss and 58 or 24
    U.setColor('#000000', 0.7)
    lg.printf(txt, 1, y + 1, W, 'center')
    U.setColor(GOLD)
    lg.printf(txt, 0, y, W, 'center')
    -- Flecha hacia Arceus si no se ve.
    local sx, sy = G.Camera.toScreen(A.x, A.y - A.bodyH * 0.5)
    if sx < 0 or sx > W or sy < 0 or sy > H then
        local M = 22
        local ex, ey = U.clamp(sx, M, W - M), U.clamp(sy, M + 36, H - M - 20)
        local an = math.atan2(sy - ey, sx - ex)
        local beat = 0.5 + sin(U.now() / 0.12) * 0.5
        U.setColor('#ff6a3d', 0.2 + beat * 0.25)
        lg.circle('fill', ex, ey, 13 + beat * 3)
        U.setColor(beat > 0.5 and '#fff3c8' or GOLD)
        lg.polygon('fill', ex + cos(an) * 17, ey + sin(an) * 17,
                   ex + cos(an + 2.45) * 9, ey + sin(an + 2.45) * 9,
                   ex + cos(an - 2.45) * 9, ey + sin(an - 2.45) * 9)
        local lbl = 'ARCEUS · ' .. U.round(U.dist(pl.x, pl.y, A.x, A.y) / 32) .. ' m'
        local tw = font(10):getWidth(lbl)
        local lx, ly = ex - cos(an) * 24 - tw / 2, ey - sin(an) * 20 - 5
        U.setColor('#000000', 0.75)
        lg.rectangle('fill', lx - 2, ly - 1, tw + 4, 12)
        U.setColor(GOLD)
        lg.print(lbl, lx, ly)
    end
    lg.setColor(1, 1, 1, 1)
end

-- Pantalla superior (encima del mundo). Devuelve true si tapa el HUD normal
-- (durante la animación).
function J.drawHud(W, H, pl, boss)
    if phase == 'cine' then drawCine(W, H) return true end
    if phase == 'fight' then drawFight(W, H, pl, boss) end
    return false
end

-- Para pruebas: la Sentencia ya.
function J.debugStart() if not phase then start() end end
function J.debug() return { base = base, single = singleDps(), samples = #samples, bosses = bossN, downs = downs, t = arenaT } end
