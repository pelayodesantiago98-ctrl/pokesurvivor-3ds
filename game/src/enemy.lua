-- enemy.lua — Pokémon salvajes y su gestor (port de js/entities/enemy.js).
-- (x, y) son los PIES. Animaciones de Mundo Misterioso:
--   Walk al moverse · Idle parado · Charge apuntando una embestida ·
--   Attack al embestir o al golpearte · Shoot al disparar · Hurt al recibir ·
--   Faint al caer (se queda en el suelo y se desvanece).
--
-- Los voladores, los fantasma y los jefes ignoran el terreno. El resto choca
-- con paredes y objetos, va más lento en el agua y se quema en la lava.
--
-- El gestor mantiene una rejilla espacial (reconstruida cada fotograma) para la
-- separación entre enemigos y las colisiones de proyectiles. Sin cooperativo.
local U = G.U
local lg = love.graphics
local floor, max, min, sqrt, abs, atan2, cos, sin, random =
    math.floor, math.max, math.min, math.sqrt, math.abs, math.atan2, math.cos, math.sin, love.math.random

local nextId = 1
local NORMAL_TYPES = { 'normal' }
local SC1 = { hp = 1, spd = 1, dmg = 1 }
local SUP = { healer = 'heart', shielder = 'shield', summoner = 'friends' }
local KEEPS = { ranged = true, fan = true, beamer = true, zoner = true, healer = true, summoner = true }
local RANGED_ALL = { 'rain', 'beam', 'nova', 'volley' }

-- Tablas de opciones reutilizadas (nada de basura por fotograma).
local playOpts = { speed = 1, hold = false }
local drawOpts = { flash = false, alpha = 1 }
local pxOpts = { vy = -12, life = 0.35 }
local okScratch = {}            -- ataques de cerca posibles del jefe
local shScratch = {}            -- vecinos a escudar

local function play(anim, name, speed, hold)
    playOpts.speed = speed or 1
    playOpts.hold = hold or false
    anim:play(name, playOpts)
end

--- Los jefes se agrandan hasta ~110 de alto, según lo grande que ya sea su sprite.
--- En múltiplos de 0,5 para que cada píxel de arte ocupe un número entero de píxeles.
local function bossScale(dex)
    local m = G.Sprites.animMeta(dex, 'Idle')
    local h = (m and m.ay or 30) * G.Sprites.PX
    return U.clamp(U.round(110 / h * 2) / 2, 1, 2)
end

local function hasAny(T, a, b, c, d, e)
    for i = 1, #T do
        local t = T[i]
        if t == a or t == b or t == c or t == d or t == e then return true end
    end
    return false
end

-- ============================================================ Enemy

local Enemy = {}
Enemy.__index = Enemy
G.Enemy = Enemy

function Enemy.new(def, x, y, sc, boss)
    boss = boss and true or false
    local self = setmetatable({}, Enemy)
    self.id = nextId; nextId = nextId + 1
    self.def = def
    self.dex = def.dex
    local mon = G.DEX_BY[def.dex]
    self.name = (mon and mon.name) or def.name
    self.x, self.y = x, y
    self.boss = boss
    self.scale = boss and bossScale(def.dex) or 1
    self.anim = G.Sprites.Animator.new(def.dex, self.scale)
    self.r = G.Sprites.bodyRadius(def.dex, self.scale)
    self.bodyH = G.Sprites.bodyHeight(def.dex, self.scale)

    self.maxHp = U.round(def.hp * sc.hp)
    self.hp = self.maxHp
    self.spd = def.spd * sc.spd
    self.dmg = def.dmg * sc.dmg
    self.xp = def.xp
    self.behavior = def.behavior

    local types = mon and mon.types
    self.types = (types and #types > 0) and types or NORMAL_TYPES
    self.atkType = self.types[1]          -- tipo de sus golpes (tabla de tipos)
    -- Vuelan por encima de rocas y agua sólo los que FLOTAN en su sprite (un
    -- Rowlet camina aunque sea Volador). Los jefes, por su tamaño, también.
    self.flying = (boss or G.Sprites.hovers(def.dex)) and true or false

    self.flash = 0
    self.slow, self.slowT = 0, 0
    self.burn, self.burnT, self.burnTick = 0, 0, 0
    self.poison, self.poisonT, self.poisonTick = 0, 0, 0
    self.lavaTick = 0
    self.kx, self.ky = 0, 0
    self.touchCd = 0
    self.dead = false
    self.fade = 0              -- tiempo de desvanecimiento tras caer

    -- embestida
    self.phase = 'walk'; self.pt = 0; self.dx = 0; self.dy = 0
    -- distancia
    self.shotCd = def.shotCd and U.rand(0.3, def.shotCd) or 0
    -- desatasco
    self.stuckT = 0; self.sideT = 0; self.side = 1
    self.bob = random() * 6.28
    self.shiny = false
    self.sparkT = 0
    -- personalidades
    self.sc = sc                        -- escala de la run (para sus invocaciones)
    self.shield, self.shieldT = 0, 0    -- escudo que absorbe daño
    self.skillCd = U.rand(1, 4)         -- escudos / saltos
    self.minions = {}
    self.jump = nil                     -- { sx, sy, tx, ty, t, dur }
    self.jumpLift = 0
    self.zig = 0                        -- zigzag del duende del tesoro
    self.life = nil                     -- segundos que le quedan al duende (lo pone events)
    self.golden = false
    self.legend = nil
    self.ai = nil                       -- cerebro de jefe (bossInit)
    -- Rezagados: si se quedan atrás, fuera de la vista, mientras huyes,
    -- vuelven a salir por delante (ver EnemyMgr.update).
    self.lagT = 0
    return self
end

function Enemy:cy() return self.y end

--- Lo convierte en shiny: otro sprite, más aguante y mucha más XP.
function Enemy:makeShiny()
    self.shiny = true
    self.anim = G.Sprites.Animator.new(self.dex, self.scale, true)
    self.maxHp = self.maxHp * 2; self.hp = self.maxHp
    self.xp = self.xp * 5
    G.Sprites.preload({ self.dex })
end

--- Hora dorada (events): doble de experiencia y a veces monedas.
function Enemy:makeGolden()
    if self.golden or self.boss or self.behavior == 'thief' then return end
    self.golden = true
    self.xp = self.xp * 2
end

--- @param eff  'super' | 'weak' | nil (tabla de tipos, sólo para enseñarlo)
function Enemy:hurt(amount, color, dirX, dirY, knock, eff)
    if self.dead then return end
    color = color or '#fff'
    dirX = dirX or 0; dirY = dirY or 0; knock = knock or 0
    local d = max(1, U.round(amount))
    -- Escudo: absorbe primero.
    if self.shield > 0 then
        local a = min(self.shield, d)
        self.shield = self.shield - a
        if a >= d then
            G.FX.dmgText(self.x, self.y - self.bodyH - 4, d, '#9fd8ff')
            self.flash = 0.05
            return
        end
        amount = d - a
    end
    self.hp = self.hp - max(1, U.round(amount))
    self:showHurt(d, color, dirX, dirY, eff)
    if knock > 0 and not self.boss then
        local nx, ny = U.norm(dirX, dirY)
        self.kx = self.kx + nx * knock
        self.ky = self.ky + ny * knock
    end
    if self.hp <= 0 then self:die() end
end

--- Lo que se VE al recibir un golpe.
function Enemy:showHurt(d, color, dirX, dirY, eff)
    self.flash = 0.09
    -- Muy eficaz: número amarillo y grande. Poco eficaz: gris.
    local col = color
    if eff == 'super' then col = '#ffe14d' elseif eff == 'weak' then col = '#a3abb8' end
    G.FX.dmgText(self.x, self.y - self.bodyH - 4, d, col, self.boss or eff == 'super')
    G.FX.spark(self.x, self.y - self.bodyH * 0.5, color, dirX or 0, dirY or 0, 3)
    if not self.anim:busy() and self.phase ~= 'dash' then play(self.anim, 'Hurt') end
    G.Audio.sfx('hit')
end

function Enemy:applySlow(factor, dur)
    self.slow = max(self.slow, factor)
    self.slowT = max(self.slowT, dur or 1.2)
end

function Enemy:applyBurn(stacks)
    self.burn = min(8, self.burn + (stacks or 1)); self.burnT = 3
end

function Enemy:applyPoison(stacks)
    self.poison = min(8, self.poison + (stacks or 1)); self.poisonT = 4
end

function Enemy:die()
    if self.dead then return end
    self.dead = true
    self.fade = 0.9
    play(self.anim, 'Faint', 1, true)
    local col = self.boss and '#ffd95e' or '#ffffff'
    local cy = self.y - self.bodyH * 0.5
    G.FX.burst(self.x, cy, col, self.boss and 34 or 9, self.boss and 260 or 120)
    G.FX.ring(self.x, self.y, self.r, self.r * (self.boss and 6 or 2.6), col, self.boss and 0.6 or 0.3, self.boss and 6 or 3)
    if self.boss then
        G.Camera.kick(0.9)
        for i = 1, 10 do G.Pickups.drop('coin', self.x + U.rand(-40, 40), self.y + U.rand(-30, 30), 5) end
        -- Los jefes siempre sueltan un objeto equipable.
        G.Pickups.drop('item', self.x - 26, self.y - 10, G.Items.roll())
    end
    G.Pickups.dropXp(self.x, self.y, self.xp, self.boss, self.legend and true or false)
    if self.golden and random() < 0.35 then G.Pickups.drop('coin', self.x + 6, self.y - 4, 3) end
    -- Duende del tesoro: Meowth suelta monedas; Gholdengo, un ticket ×10.
    if self.behavior == 'thief' then
        local n = self.def.loot == 'ticket10' and 6 or 20
        for i = 1, n do G.Pickups.drop('coin', self.x + U.rand(-36, 36), self.y + U.rand(-26, 26), 5) end
        if self.def.loot == 'ticket10' then G.Pickups.drop('ticket10', self.x, self.y - 12, 1) end
        G.FX.ring(self.x, self.y, self.r, self.r * 5, '#ffd23f', 0.6, 4)
    end
    if self.legend then
        -- El legendario de la grieta: además del ticket ×10 de todo jefe.
        G.Pickups.drop('ticket10', self.x + 20, self.y - 16, 1)
        for i = 1, 3 do G.Pickups.drop('ticket', self.x + U.rand(-30, 30), self.y + U.rand(-20, 20), 1) end
        for i = 1, 10 do G.Pickups.drop('coin', self.x + U.rand(-50, 50), self.y + U.rand(-35, 35), 8) end
    end
    G.Audio.sfx(self.boss and 'bossDown' or 'faint')
    if self.shiny then
        G.FX.burst(self.x, cy, '#ffe9a0', 30, 220)
        G.FX.ring(self.x, self.y, self.r, self.r * 7, '#9ae6ff', 0.7, 5)
        if G.Game and G.Game.onShinyCaught then G.Game.onShinyCaught(self) end
    end
end

function Enemy:update(dt, pl)
    -- Fuera de pantalla no hace falta animar (sí moverse y pensar).
    local seen = G.Camera.sees(self.x, self.y, 120)
    if seen or self.dead then self.anim:update(dt) end
    if self.flash > 0 then self.flash = self.flash - dt end
    if self.dead then self.fade = self.fade - dt; return end
    if self.shiny and seen then
        self.sparkT = self.sparkT - dt
        if self.sparkT <= 0 then
            self.sparkT = 0.22
            G.FX.twinkle(self.x + U.rand(-self.r, self.r) * 1.2, self.y - U.rand(4, self.bodyH * 1.1))
        end
    end
    if self.touchCd > 0 then self.touchCd = self.touchCd - dt end
    self.bob = self.bob + dt * 6

    -- --- estados ---
    if self.slowT > 0 then
        self.slowT = self.slowT - dt
        if self.slowT <= 0 then self.slow = 0 end
    end
    if self.burn > 0 then
        self.burnT = self.burnT - dt; self.burnTick = self.burnTick - dt
        if self.burnTick <= 0 then self.burnTick = 0.5; self:hurt(1.6 * self.burn * (1 + pl.level * 0.06), '#ff9a4d') end
        if self.burnT <= 0 then self.burn = 0 end
    end
    if self.poison > 0 then
        self.poisonT = self.poisonT - dt; self.poisonTick = self.poisonTick - dt
        if self.poisonTick <= 0 then self.poisonTick = 0.6; self:hurt(self.maxHp * 0.012 * self.poison + 1, '#d47cf0') end
        if self.poisonT <= 0 then self.poison = 0 end
    end
    if self.dead then return end

    -- --- terreno ---
    local terrainMul = 1
    -- (El legendario está en su casa: su arena no le afecta.)
    if not self.flying and not self.legend and G.World.isLiquid(self.x, self.y) then
        local le = G.World.liquidEffect(self.types)
        if le.dmg then
            self.lavaTick = self.lavaTick - dt
            if self.lavaTick <= 0 then self.lavaTick = le.every; self:hurt(6 + self.maxHp * 0.04, le.color) end
            if self.dead then return end
        elseif le.slow then
            terrainMul = le.slow < 0.5 and 0.45 or 0.55
        end
    end

    local spd = self.spd * (1 - self.slow) * terrainMul * G.Weather.speedFor(self.types)
    local dx, dy = U.norm(pl.x - self.x, pl.y - self.y)
    local dist = U.dist(self.x, self.y, pl.x, pl.y)
    -- Duende del tesoro: huye de ti (en zigzag) en cuanto te acercas.
    if self.behavior == 'thief' then
        self.zig = self.zig + dt
        local near = dist < 300
        local a = atan2(-dy, -dx) + sin(self.zig * 2.2) * 0.7
        local k = near and 1 or 0.35
        local vx0, vy0 = cos(a) * spd * k, sin(a) * spd * k
        local ox, oy = self.x, self.y
        self.x = self.x + (vx0 + self.kx) * dt; self.y = self.y + (vy0 + self.ky) * dt
        self.kx = self.kx * 0.0015 ^ dt; self.ky = self.ky * 0.0015 ^ dt
        if G.World.collide(self) and U.hypot(self.x - ox, self.y - oy) < spd * k * dt * 0.3 then self.zig = self.zig + 1.4 end
        if random() < dt * 6 and G.Camera.sees(self.x, self.y, 0) then
            G.FX.twinkle(self.x + U.rand(-self.r, self.r), self.y - U.rand(4, self.bodyH))
        end
        self.anim.dir = G.Sprites.dirFromAngle(a)
        self.anim:loop('Walk', 1.4)
        return
    end
    -- Corredor: va a donde VAS a estar (te corta el paso si sólo huyes).
    if self.behavior == 'runner' and pl._vx ~= nil then
        local lead = U.clamp(dist / max(60, spd), 0, 1.4)
        dx, dy = U.norm(pl.x + pl._vx * lead - self.x, pl.y + pl._vy * lead - self.y)
        if G.Camera.sees(self.x, self.y, 0) and random() < dt * 10 then
            G.FX.px(self.x - dx * 8 + U.rand(-4, 4), self.y, '#e8dcc0', pxOpts)
        end
    end

    -- --- personalidad (escudos, saltos, explosión) ---
    if self.shieldT > 0 then
        self.shieldT = self.shieldT - dt
        if self.shieldT <= 0 then self.shield = 0 end
    end
    if self.jump then self:updateJump(dt); return end
    if self.behavior == 'bomber' and self.phase == 'fuse' then
        self.pt = self.pt - dt
        self.flash = (floor(self.pt * 10) % 2 ~= 0) and 0.05 or 0
        if self.pt <= 0 then self.hp = 0; self:die() end
        self.anim:loop('Idle')
        return
    end
    if self.behavior == 'bomber' and dist < self.r + pl.r + 26 then self:startFuse(); return end
    if self.behavior == 'shielder' or self.behavior == 'jumper' then
        self.skillCd = self.skillCd - dt
        if self.skillCd <= 0 then
            if self.behavior == 'shielder' then self.skillCd = 6; self:castShields()
            elseif dist < 250 then self.skillCd = U.rand(5, 7); self:startJump(pl); return
            else self.skillCd = 0.5 end
        end
    end

    -- Si lleva rato atascado contra algo, rodea por un lado.
    if self.sideT > 0 then
        self.sideT = self.sideT - dt
        local a = atan2(dy, dx) + self.side * 1.25
        dx, dy = cos(a), sin(a)
    end

    -- Camino alrededor de los obstáculos (los que no vuelan).
    if not self.flying and self.phase ~= 'dash' and self.sideT <= 0 then
        local pdx, pdy = G.Path.dirFor(self, pl)
        if pdx and not (self:keepsDistance() and dist < (self.def.range or 200) * 0.82) then dx, dy = pdx, pdy end
    end

    local vx, vy = dx * spd, dy * spd
    local animBase = 'Walk'

    if self.boss then
        vx, vy, animBase = self:bossMove(dt, pl, dist, dx, dy, spd)
    elseif self.behavior == 'charger' then
        self.pt = self.pt - dt
        if self.phase == 'walk' then
            if dist < 200 and self.pt <= 0 then
                self.phase = 'aim'; self.pt = 0.55
                play(self.anim, 'Charge', 1.6)
            end
        elseif self.phase == 'aim' then
            vx, vy = 0, 0; animBase = 'Idle'
            if self.pt <= 0 then
                self.phase = 'dash'; self.pt = 0.42
                self.dx, self.dy = dx, dy
                play(self.anim, 'Attack', 1.4)
                G.FX.ring(self.x, self.y, self.r, self.r * 2.4, '#ff6b6b', 0.25, 2)
            end
        elseif self.phase == 'dash' then
            vx, vy = self.dx * spd * 3.4, self.dy * spd * 3.4
            if self.pt <= 0 then self.phase = 'walk'; self.pt = 1.1 end
        end
    elseif self:keepsDistance() then
        local range = self.def.range or 200
        local keep = range * 0.82
        -- Recta hacia ti (no el camino) para alejarse.
        local ddx, ddy = U.norm(pl.x - self.x, pl.y - self.y)
        if dist < keep * 0.75 then vx, vy = -ddx * spd * 0.8, -ddy * spd * 0.8
        elseif dist < keep then vx, vy = vx * 0.1, vy * 0.1; animBase = 'Idle' end
        self.shotCd = self.shotCd - dt
        if self.shotCd <= 0 and dist < range then
            self.shotCd = self.def.shotCd or 2
            self:special(pl, ddx, ddy)
        end
    end

    -- --- integración ---
    local ox, oy = self.x, self.y
    self.x = self.x + self.kx * dt; self.y = self.y + self.ky * dt
    self.kx = self.kx * 0.0015 ^ dt; self.ky = self.ky * 0.0015 ^ dt
    self.x = self.x + vx * dt; self.y = self.y + vy * dt

    if not self.flying and G.World.collide(self) then
        -- ¿Ha avanzado bastante menos de lo que quería?
        local want = U.hypot(vx, vy) * dt
        local got = U.hypot(self.x - ox, self.y - oy)
        if want > 0.5 and got < want * 0.35 then
            self.stuckT = self.stuckT + dt
            if self.stuckT > 0.35 and self.sideT <= 0 then
                self.sideT = 0.7; self.stuckT = 0
                self.side = random() < 0.5 and -1 or 1
            end
        else
            self.stuckT = 0
        end
    end

    -- --- animación ---
    local moving = abs(vx) + abs(vy) > 2
    local faceA
    if self.phase == 'dash' then faceA = atan2(self.dy, self.dx)
    elseif moving then faceA = atan2(vy, vx)
    else faceA = atan2(pl.y - self.y, pl.x - self.x) end
    self.anim.dir = G.Sprites.dirFromAngle(faceA)
    if moving then self.anim:loop(animBase, max(0.6, spd / 70)) else self.anim:loop('Idle', 1) end
end

-- ---------------- jefes ----------------
-- Cada jefe (y cada legendario de las grietas) tiene 4 ataques: 2 de
-- cerca (Pisotón siempre + Embestida o Salto) y 2 de lejos según su tipo.
-- Va alternando entre ir a por ti y pelear a distancia. Todo avisa en el
-- suelo. Por debajo de la mitad de vida se enfurece: más rápido, menos
-- espera y a veces encadena dos ataques.

function Enemy:bossInit()
    local T = self.types
    local melee = { 'slam', U.hash(self.dex, 3, 7) < 0.5 and 'dash' or 'leap' }
    local pref
    if hasAny(T, 'fire', 'ground', 'poison', 'rock', 'grass') then pref = 'rain'
    elseif hasAny(T, 'electric', 'psychic', 'dragon', 'ice', 'steel') then pref = 'beam'
    elseif hasAny(T, 'fairy', 'ghost', 'water', 'flying') then pref = 'nova'
    else pref = 'volley' end
    local others = {}
    for i = 1, 4 do if RANGED_ALL[i] ~= pref then others[#others + 1] = RANGED_ALL[i] end end
    local ranged = { pref, others[(floor(U.hash(self.dex, 5, 9) * 3) % 3) + 1] }
    local far = self.behavior == 'ranged'
    self.ai = { melee = melee, ranged = ranged, farLike = far and 0.65 or 0.35, mode = far and 'far' or 'close',
                modeT = U.rand(6, 8), cd = 1.6, cast = nil, fury = false, side = random() < 0.5 and -1 or 1 }
end

--- Devuelve vx, vy, animBase.
function Enemy:bossMove(dt, pl, dist, dx, dy, spd)
    if not self.ai then self:bossInit() end
    local ai = self.ai
    if not ai.fury and self.hp < self.maxHp * 0.5 then self:enrage() end
    local k = ai.fury and 1.25 or 1
    if ai.cast then return self:bossCast(dt, pl) end
    ai.modeT = ai.modeT - dt; ai.cd = ai.cd - dt * k
    -- Alterna siempre: en su distancia favorita está más rato (7-9 s) que en la otra (4-5 s).
    if ai.modeT <= 0 then
        ai.mode = ai.mode == 'far' and 'close' or 'far'
        if (ai.mode == 'far') == (ai.farLike > 0.5) then ai.modeT = U.rand(7, 9) else ai.modeT = U.rand(4, 5) end
        ai.side = -ai.side
    end
    local vx, vy = dx * spd * k * 1.1, dy * spd * k * 1.1
    local ddx, ddy = U.norm(pl.x - self.x, pl.y - self.y)
    if ai.mode == 'far' then
        if dist < 170 then vx, vy = -ddx * spd, -ddy * spd
        elseif dist < 300 then vx, vy = -ddy * spd * 0.55 * ai.side, ddx * spd * 0.55 * ai.side end   -- te rodea
    end
    if ai.cd <= 0 then
        local id = nil
        if ai.mode == 'close' then
            local okN = 0
            for i = 1, 2 do
                local mm = ai.melee[i]
                if (mm == 'slam' and dist < 125) or (mm ~= 'slam' and dist < 320) then okN = okN + 1; okScratch[okN] = mm end
            end
            -- De vez en cuando, aunque esté cerca, también dispara.
            if okN > 0 and random() < 0.8 then id = okScratch[floor(random() * okN) + 1]
            elseif dist < 480 then id = U.pick(ai.ranged) end
        else
            if dist < 115 then id = 'slam' elseif dist < 430 then id = U.pick(ai.ranged) end
        end
        if id then self:bossStart(id, pl) end
    end
    return vx, vy, 'Walk'
end

function Enemy:enrage()
    self.ai.fury = true
    self.spd = self.spd * 1.15
    G.Spawner.say('¡' .. self.name .. ' se ha enfurecido!', 2.4)
    G.FX.ring(self.x, self.y, self.r, self.r * 5, '#ff4a4a', 0.6, 5)
    G.Camera.kick(0.5)
    G.Audio.sfx('boss')
end

function Enemy:bossStart(id, pl)
    local ai = self.ai
    local f = ai.fury and 0.8 or 1
    local ty = self.atkType
    local col = U.TYPE_COLOR[ty] or '#ff7a9e'
    local ang = atan2(pl.y - self.y, pl.x - self.x)
    local c = { id = id, t = 0, wind = 0.6 * f, after = 0.35, ang = ang, go = false, fired = false, len = 0, dur = 0 }
    ai.cast = c
    if id == 'slam' then            -- pisotón: onda alrededor
        c.wind = 0.85 * f
        G.Hazards.add({ kind = 'zone', x = self.x, y = self.y, r = 96 + self.r, delay = c.wind, dmg = self.dmg * 1.3, type = ty, color = col })
        play(self.anim, 'Charge', 1.2)
    elseif id == 'dash' then        -- embestida en línea recta
        c.wind = 0.75 * f; c.len = 330; c.dur = 0.32
        G.Hazards.add({ kind = 'beam', x = self.x, y = self.y, angle = ang, len = c.len + self.r, w = self.r * 2 + 16,
                        delay = c.wind + c.dur, dmg = self.dmg * 1.2, type = ty, color = col })
        play(self.anim, 'Charge', 1.3)
    elseif id == 'leap' then        -- salto y caída sobre ti
        self.jump = { sx = self.x, sy = self.y, tx = pl.x, ty = pl.y, t = -0.5 * f, dur = 0.65 }
        G.Hazards.add({ kind = 'zone', x = pl.x, y = pl.y, r = 82, delay = 0.5 * f + 0.65, dmg = self.dmg * 1.25, type = ty, color = col })
        play(self.anim, 'Charge', 1.4)
        ai.cast = nil; ai.cd = U.rand(1.4, 2) + 0.6
    elseif id == 'rain' then        -- zonas que caen alrededor de ti
        local n = ai.fury and 6 or 4
        for i = 0, n - 1 do
            local a = i > 0 and random() * 6.2832 or 0
            local d = i > 0 and U.rand(40, 120) or 0
            G.Hazards.add({ kind = 'zone', x = pl.x + cos(a) * d, y = pl.y + sin(a) * d * 0.8, r = 50,
                            delay = 1.05 + i * 0.12, dmg = self:shotDmg() * 1.15, type = ty, color = col })
        end
        c.wind = 0.5
        play(self.anim, 'Shoot')
    elseif id == 'beam' then        -- rayos en abanico
        local n = ai.fury and 5 or 3
        local sp = ai.fury and 0.42 or 0.5
        for i = 0, n - 1 do
            G.Hazards.add({ kind = 'beam', x = self.x, y = self.y, angle = ang + (i - (n - 1) / 2) * sp, len = 400, w = 26,
                            delay = 1.0, dmg = self:shotDmg() * 1.2, type = ty, color = col })
        end
        c.wind = 1.0; c.after = 0.25
        play(self.anim, 'Charge', 1.1)
    elseif id == 'volley' or id == 'nova' then   -- abanico / anillo de disparos
        c.wind = (id == 'nova' and 0.7 or 0.5) * f
        play(self.anim, 'Charge', 1.4)
        G.FX.ring(self.x, self.y, self.r, self.r * 2.4, col, c.wind, 2)
    end
end

--- Devuelve vx, vy, animBase.
function Enemy:bossCast(dt, pl)
    local ai = self.ai
    local c = ai.cast
    c.t = c.t + dt
    if c.id == 'dash' and c.t >= c.wind then
        if not c.go then c.go = true; play(self.anim, 'Attack', 1.6) end
        if c.t >= c.wind + c.dur then return self:bossEnd() end
        local sp = c.len / c.dur
        return cos(c.ang) * sp, sin(c.ang) * sp, 'Walk'
    end
    if c.t >= c.wind and not c.fired then
        c.fired = true
        local ax, ay = U.norm(pl.x - self.x, pl.y - self.y)
        if c.id == 'volley' then self:shoot(ax, ay, 1.1, ai.fury and 9 or 7, 0.8)
        elseif c.id == 'nova' then
            local n = ai.fury and 18 or 14
            self:shoot(ax, ay, 6.2832 * (n - 1) / n, n, 0.7)
        elseif c.id == 'slam' then play(self.anim, 'Attack', 1.4) end
    end
    if c.t >= c.wind + c.after then return self:bossEnd() end
    return 0, 0, 'Idle'
end

function Enemy:bossEnd()
    local ai = self.ai
    ai.cast = nil
    ai.cd = U.rand(1.3, 2.0)
    if ai.fury and random() < 0.35 then ai.cd = 0.3 end    -- encadena otro
    return 0, 0, 'Idle'
end

function Enemy:keepsDistance() return KEEPS[self.behavior] == true end

function Enemy:shotDmg() return (self.def.shotDmg or 10) * (self.dmg / self.def.dmg) end

--- Disparo normal de enemigo (uno, o varios en abanico).
function Enemy:shoot(ax, ay, spread, n, k)
    spread = spread or 0; n = n or 1; k = k or 1
    local sp = 190
    local ty = self.atkType
    local base = atan2(ay, ax)
    local dmg = self:shotDmg() * k
    for i = 0, n - 1 do
        local a = base + (n == 1 and 0 or (i / (n - 1) - 0.5) * spread)
        G.Projectiles.spawn({
            x = self.x, y = self.y, vx = cos(a) * sp, vy = sin(a) * sp,
            dmg = dmg, r = 7, life = 2.4, friendly = false, color = '#ff7a9e', mtype = ty,
            vis = G.VFX.forType(ty)
        })
    end
    play(self.anim, 'Shoot')
    G.FX.ring(self.x, self.y - G.LIFT, 4, 14, '#ff7a9e', 0.2, 2)
end

--- Lo que hace cada personalidad cuando le toca.
function Enemy:special(pl, dx, dy)
    local col = U.TYPE_COLOR[self.atkType] or '#ff7a9e'
    local b = self.behavior
    if b == 'fan' then
        local n = self.def.fanN or 5
        self:shoot(dx, dy, n == 3 and 0.6 or 0.9, n, 0.65)
    elseif b == 'beamer' then
        -- Rayo con aviso: primero se ve la franja en el suelo.
        G.Hazards.add({ kind = 'beam', x = self.x, y = self.y, angle = atan2(dy, dx), len = 360, w = 22,
                        delay = 1.0, dmg = self:shotDmg() * 1.05, type = self.atkType, color = col })
        play(self.anim, 'Charge', 1.2)
    elseif b == 'zoner' then
        local n = U.randInt(1, self.def.zones or 3)
        for i = 0, n - 1 do
            G.Hazards.add({ kind = 'zone', x = pl.x + (i > 0 and U.rand(-70, 70) or 0), y = pl.y + (i > 0 and U.rand(-55, 55) or 0), r = 44,
                            delay = 1.2, dmg = self:shotDmg() * 0.95, type = self.atkType, color = col })
        end
        play(self.anim, 'Shoot')
    elseif b == 'healer' then self:healAround()
    elseif b == 'summoner' then self:summon()
    else self:shoot(dx, dy) end
end

function Enemy:healAround()
    local n = 0
    local q, qn = G.EnemyMgr.queryCircle(self.x, self.y, 150)
    for i = 1, qn do
        local e = q[i]
        if not e.dead and e.hp < e.maxHp then
            -- 7 % (era 15 %: con varios curanderos curaban más de lo que pegabas).
            e.hp = min(e.maxHp, e.hp + e.maxHp * 0.07)
            G.FX.burst(e.x, e.y - e.bodyH * 0.6, '#7dffb0', 5, 60)
            n = n + 1
        end
    end
    play(self.anim, 'Charge')
    G.FX.ring(self.x, self.y, 8, 150, '#5fe08a', 0.5, 3)
    if n > 0 and G.Camera.sees(self.x, self.y, 0) then G.Audio.sfx('heal') end
end

-- Orden por distancia al que escuda (sin closures: el centro va en locales del módulo).
local sortX, sortY = 0, 0
local function byDist(a, b)
    return U.dist2(a.x, a.y, sortX, sortY) < U.dist2(b.x, b.y, sortX, sortY)
end

function Enemy:castShields()
    local q, qn = G.EnemyMgr.queryCircle(self.x, self.y, 160)
    local n = 0
    for i = 1, qn do
        local e = q[i]
        if not e.dead then n = n + 1; shScratch[n] = e end
    end
    sortX, sortY = self.x, self.y
    table.sort(shScratch, byDist)
    for i = 1, min(6, n) do
        local e = shScratch[i]
        e.shield = max(e.shield, e.maxHp * 0.35); e.shieldT = 8
    end
    for i = n, 1, -1 do shScratch[i] = nil end
    play(self.anim, 'Charge')
    G.FX.ring(self.x, self.y, 8, 160, '#7fc8ff', 0.5, 3)
end

function Enemy:summon()
    -- Quita de la lista los esbirros caídos o que ya no están.
    local ms = self.minions
    local n = 0
    for i = 1, #ms do
        local m = ms[i]
        if not m.dead and G.EnemyMgr.get(m.id) then n = n + 1; ms[n] = m end
    end
    for i = #ms, n + 1, -1 do ms[i] = nil end
    -- Con el tope general de enemigos (menos Pokémon en pantalla), con un pequeño margen.
    if n >= 4 or G.EnemyMgr.count() > G.Spawner.CAP + 15 then return end
    local dex = self.def.minion or self.dex
    local mon = G.DEX_BY[dex]
    local def = { dex = dex, name = mon and mon.name or '', hp = U.round(self.def.hp * 0.35), spd = U.round(self.def.spd * 1.1),
                  dmg = U.round(self.def.dmg * 0.6), xp = max(1, U.round(self.def.xp * 0.25)), behavior = 'chase' }
    for i = 1, 2 do
        local a = random() * 6.2832
        local m = Enemy.new(def, self.x + cos(a) * 30, self.y + sin(a) * 22, self.sc or SC1)
        G.EnemyMgr.add(m)
        ms[#ms + 1] = m
        G.FX.burst(m.x, m.y - 8, '#c47bff', 8, 90)
    end
    play(self.anim, 'Charge')
    G.FX.ring(self.x, self.y, 8, 50, '#c47bff', 0.4, 3)
end

function Enemy:startFuse()
    self.phase = 'fuse'; self.pt = 1.0
    G.Hazards.add({ kind = 'zone', x = self.x, y = self.y, r = 62, delay = 1.0, dmg = self.dmg * 1.4, type = self.atkType, color = '#ff7b3d' })
end

function Enemy:startJump(pl)
    local tx, ty = pl.x, pl.y
    self.jump = { sx = self.x, sy = self.y, tx = tx, ty = ty, t = -0.45, dur = 0.6 }
    play(self.anim, 'Charge', 1.4)
    G.Hazards.add({ kind = 'zone', x = tx, y = ty, r = 50, delay = 1.05, dmg = self.dmg * 1.2, type = self.atkType,
                    color = U.TYPE_COLOR[self.atkType] or '#ff7a9e' })
end

--- Salto: se agacha, vuela en arco y cae donde estabas.
function Enemy:updateJump(dt)
    local j = self.jump
    j.t = j.t + dt
    if j.t < 0 then self.anim:loop('Idle'); return end
    local k = min(1, j.t / j.dur)
    self.x = j.sx + (j.tx - j.sx) * k
    self.y = j.sy + (j.ty - j.sy) * k
    self.jumpLift = sin(k * math.pi) * 46
    self.anim.dir = G.Sprites.dirFromAngle(atan2(j.ty - j.sy, j.tx - j.sx))
    if k >= 1 then
        self.jump = nil; self.jumpLift = 0
        if not self.flying then G.World.collide(self) end
        play(self.anim, 'Attack', 1.4)
    end
end

--- Lo llama combat.lua cuando te toca: anima el golpe.
function Enemy:strike(pl)
    if not self.anim:busy() then
        self.anim.dir = G.Sprites.dirFromAngle(atan2(pl.y - self.y, pl.x - self.x))
        play(self.anim, 'Attack', 1.5)
    end
end

function Enemy:draw()
    local alpha = self.dead and U.clamp(self.fade / 0.5, 0, 1) or 1
    if alpha <= 0 then return end

    local gold = self.golden or self.behavior == 'thief'
    if (self.boss or self.shiny or gold) and not self.dead then
        local a = ((gold and not self.boss) and 0.32 or 0.22) + sin(self.bob * 0.5) * 0.06
        local col
        if self.ai and self.ai.fury then col = '#ff4a4a'
        elseif self.shiny then col = '#9ae6ff'
        elseif gold then col = '#ffd23f'
        else col = '#ffd95e' end
        U.setColor(col, a)
        lg.ellipse('fill', self.x, self.y, self.r * 1.6, self.r * 0.6)
    end

    G.Sprites.drawShadow(self.dex, self.x, self.y, self.scale)
    -- Los que flotan ya van en el aire en su sprite: sólo se mecen un poco.
    -- (Y los que saltan, en arco.)
    local lift = ((self.flying and not self.boss) and (1 + sin(self.bob) * 1.5) or 0) + self.jumpLift
    drawOpts.flash = self.flash > 0
    drawOpts.alpha = alpha
    self.anim:draw(self.x, self.y - lift, drawOpts)

    if self.dead then lg.setColor(1, 1, 1, 1); return end

    -- Escudo: burbuja azul.
    if self.shield > 0 then
        local a = 0.35 + sin(self.bob) * 0.08
        lg.setColor(127 / 255, 200 / 255, 1, 0.14 * a)
        lg.ellipse('fill', self.x, self.y - self.bodyH * 0.45, self.r * 1.5, self.bodyH * 0.65)
        U.setColor('#9fd8ff', a)
        lg.setLineWidth(2)
        lg.ellipse('line', self.x, self.y - self.bodyH * 0.45, self.r * 1.5, self.bodyH * 0.65)
        lg.setLineWidth(1)
    end

    if self.burn > 0 or self.poison > 0 then
        U.setColor(self.burn > 0 and '#ff8a3d' or '#c86bdc', 0.45)
        lg.ellipse('fill', self.x, self.y, self.r * 1.2, self.r * 0.5)
    end

    -- Apoyos: icono encima, para saber a quién ir primero.
    local sup = SUP[self.behavior]
    if sup then
        G.Icons.draw(sup, U.round(self.x - 6), U.round(self.y - self.bodyH - (self.hp < self.maxHp and 26 or 18)), 12)
    end

    if self.boss or self.hp < self.maxHp then
        local w = self.boss and 90 or max(22, self.r * 2)
        local y = self.y - self.bodyH - 10
        lg.setColor(0, 0, 0, 0.6)
        lg.rectangle('fill', self.x - w / 2, y, w, 3.4)
        U.setColor(self.boss and '#ffcb3d' or '#ff5f6d')
        lg.rectangle('fill', self.x - w / 2, y, w * max(0, self.hp / self.maxHp), 3.4)
    end
    lg.setColor(1, 1, 1, 1)
end

-- ============================================================ gestor

local M = {}
G.EnemyMgr = M

local list = {}                 -- vivos
local corpses = {}              -- cayendo / desvaneciéndose
local byId = {}
local CELL = 52
local MAX_CORPSES = 30
-- Segundos que un rezagado tiene que llevar fuera de la vista antes de volver por delante.
local LAG_T = 2.5

-- Rejilla: grid[key] = celda (lista de enemigos). Las celdas se reciclan de un
-- pool entre fotogramas; nunca se crean tablas nuevas en régimen estacionario.
local grid = {}
local usedKeys, usedCells, nUsed = {}, {}, 0
local cellPool, nPool = {}, 0
local qout, qn = {}, 0          -- resultado reutilizado de queryCircle
local dout, dn = {}, 0          -- resultado reutilizado de drawables
local shOut, shn = {}, 0        -- resultado reutilizado de shinies
local stashed = nil

-- cx, cy pueden ser negativos: se desplazan 2048 para que la clave sea única.
local function key(cx, cy) return (cx + 2048) * 4096 + (cy + 2048) end

local function clearGrid()
    for i = 1, nUsed do
        local cell = usedCells[i]
        for n = #cell, 1, -1 do cell[n] = nil end
        grid[usedKeys[i]] = nil
        nPool = nPool + 1; cellPool[nPool] = cell
        usedCells[i] = nil; usedKeys[i] = nil
    end
    nUsed = 0
end

local function cellFor(k)
    local cell = grid[k]
    if cell then return cell end
    if nPool > 0 then
        cell = cellPool[nPool]; cellPool[nPool] = nil; nPool = nPool - 1
    else
        cell = {}
    end
    grid[k] = cell
    nUsed = nUsed + 1; usedKeys[nUsed] = k; usedCells[nUsed] = cell
    return cell
end

function M.clear()
    list = {}; corpses = {}; byId = {}
    clearGrid()
    qn = 0; dn = 0; shn = 0
    for i = #qout, 1, -1 do qout[i] = nil end
    for i = #dout, 1, -1 do dout[i] = nil end
    for i = #shOut, 1, -1 do shOut[i] = nil end
end

function M.all() return list end

function M.add(e)
    list[#list + 1] = e
    byId[e.id] = e
    return e
end

function M.get(id) return byId[id] end

-- --- arena de la grieta ---

--- Guarda los enemigos del mapa mientras dura la arena.
function M.stash()
    stashed = {}
    for i = 1, #list do
        local e = list[i]
        if not e.dead then stashed[#stashed + 1] = e; byId[e.id] = nil end
    end
    list = {}; corpses = {}
end

--- Al volver: quita los de la arena y devuelve los del mapa.
function M.restore()
    for i = 1, #list do byId[list[i].id] = nil end
    list = {}; corpses = {}
    if stashed then for i = 1, #stashed do M.add(stashed[i]) end end
    stashed = nil
end

function M.rebuildGrid()
    clearGrid()
    for i = 1, #list do
        local e = list[i]
        if not e.dead then
            local cell = cellFor(key(floor(e.x / CELL), floor(e.y / CELL)))
            cell[#cell + 1] = e
        end
    end
end

--- Enemigos vivos cuyo círculo toca este círculo. Devuelve (lista, n).
--- ¡La lista es una tabla REUTILIZADA: se invalida en la siguiente llamada!
--- No llames a queryCircle (ni a nada que lo haga) mientras la recorres sin
--- copiarla antes.
function M.queryCircle(x, y, r)
    for i = 1, qn do qout[i] = nil end
    local n = 0
    local c0x, c1x = floor((x - r) / CELL) - 1, floor((x + r) / CELL) + 1
    local c0y, c1y = floor((y - r) / CELL) - 1, floor((y + r) / CELL) + 1
    for cy = c0y, c1y do
        for cx = c0x, c1x do
            local b = grid[key(cx, cy)]
            if b then
                for j = 1, #b do
                    local e = b[j]
                    if not e.dead then
                        local rr = r + e.r
                        if U.dist2(x, y, e.x, e.y) <= rr * rr then n = n + 1; qout[n] = e end
                    end
                end
            end
        end
    end
    qn = n
    return qout, n
end

local function separate(dt)
    for i = 1, #list do
        local e = list[i]
        if not e.dead then
            local cx, cy = floor(e.x / CELL), floor(e.y / CELL)
            local px, py, n = 0, 0, 0
            for j = -1, 1 do
                for k = -1, 1 do
                    local b = grid[key(cx + k, cy + j)]
                    if b then
                        for q = 1, #b do
                            local o = b[q]
                            if o ~= e and not o.dead then
                                local mn = (e.r + o.r) * 0.82
                                local dx, dy = e.x - o.x, e.y - o.y
                                local d2 = dx * dx + dy * dy
                                if d2 <= mn * mn and d2 >= 1e-4 then
                                    local d = sqrt(d2)
                                    local f = (mn - d) / mn
                                    px = px + (dx / d) * f; py = py + (dy / d) * f
                                    n = n + 1
                                    if n > 6 then break end
                                end
                            end
                        end
                    end
                end
            end
            if n > 0 then
                e.x = e.x + px * 42 * dt
                e.y = e.y + py * 42 * dt
                if not e.flying then G.World.collide(e) end
            end
        end
    end
end

--- El jugador vivo más cercano (los caídos no atraen a nadie). Acepta una lista
--- de jugadores o uno solo.
function M.nearestPlayer(players, x, y)
    if players.dead ~= nil then
        if players.dead then return nil end
        return players
    end
    local best, bd = nil, math.huge
    for i = 1, #players do
        local p = players[i]
        if not p.dead then
            local d = U.dist2(x, y, p.x, p.y)
            if d < bd then bd = d; best = p end
        end
    end
    return best
end

local function drop(i, e)
    U.removeSwap(list, i)
    byId[e.id] = nil
end

--- @param pl  el jugador (las estadísticas de la run se apuntan en él).
function M.update(dt, pl)
    -- Velocidad suavizada del jugador (la usan corredores y rezagados).
    if pl._px ~= nil and dt > 0 then
        local k = min(1, dt * 5)
        pl._vx = pl._vx + ((pl.x - pl._px) / dt - pl._vx) * k
        pl._vy = pl._vy + ((pl.y - pl._py) / dt - pl._vy) * k
        if abs(pl.x - pl._px) > 200 or abs(pl.y - pl._py) > 200 then pl._vx = 0; pl._vy = 0 end    -- teletransporte
    else
        pl._vx = 0; pl._vy = 0
    end
    pl._px = pl.x; pl._py = pl.y

    M.rebuildGrid()
    for i = 1, #list do list[i]:update(dt, pl) end
    separate(dt)

    local inArena = G.Rift.inArena()
    local R = G.Camera.outerRadius() + 40
    local R2 = R * R
    local sp = U.hypot(pl._vx, pl._vy)
    for i = #list, 1, -1 do
        local e = list[i]
        if e.dead then
            pl.kills = pl.kills + 1
            if e.boss then pl.bosses = pl.bosses + 1 end
            G.Progress.kill(e)
            corpses[#corpses + 1] = e
            drop(i, e)
        else
            local gone = false
            -- El duende del tesoro se escapa si no lo atrapas a tiempo.
            if e.behavior == 'thief' and e.life then
                e.life = e.life - dt
                if e.life <= 0 then
                    G.FX.burst(e.x, e.y - 10, '#ffd23f', 16, 140)
                    G.Spawner.say('¡' .. e.name .. ' se ha escapado!', 2.4)
                    drop(i, e)
                    gone = true
                end
            end
            if not gone and not (e.boss or e.shiny or inArena) then
                -- Rezagados: los que se quedan atrás mientras corres y llevan un rato
                -- FUERA DE LA VISTA vuelven a salir por delante de ti. Así no se puede
                -- huir sin más, y nunca desaparece uno que estés viendo.
                local d2 = U.dist2(e.x, e.y, pl.x, pl.y)
                local unseen = d2 > R2 and not G.Camera.sees(e.x, e.y, 60)
                local behind = sp > 40 and ((e.x - pl.x) * pl._vx + (e.y - pl.y) * pl._vy) < -0.2 * sqrt(d2) * sp
                if unseen and behind then e.lagT = e.lagT + dt
                elseif not unseen then e.lagT = 0 end
                if (unseen and e.lagT > LAG_T) or d2 > 1400 * 1400 then
                    e.lagT = 0
                    if not G.Spawner.ahead(e, pl) then drop(i, e) end
                end
            end
        end
    end
    for i = #corpses, 1, -1 do
        local c = corpses[i]
        c:update(dt, pl)
        if c.fade <= 0 then U.removeSwap(corpses, i) end
    end
    while #corpses > MAX_CORPSES do table.remove(corpses, 1) end
end

--- Lo que hay que dibujar ordenado por Y junto al resto de la escena.
--- Devuelve (lista, n); la lista es una tabla REUTILIZADA entre llamadas.
function M.drawables(cam)
    for i = 1, dn do dout[i] = nil end
    local n = 0
    for i = 1, #corpses do
        local e = corpses[i]
        if cam.sees(e.x, e.y, 80) then n = n + 1; dout[n] = e end
    end
    for i = 1, #list do
        local e = list[i]
        if cam.sees(e.x, e.y, 80) then n = n + 1; dout[n] = e end
    end
    dn = n
    return dout, n
end

function M.bossAlive()
    for i = 1, #list do
        local e = list[i]
        if e.boss and not e.dead then return true end
    end
    return false
end

--- Shinies vivos. Devuelve (lista, n); la lista es una tabla REUTILIZADA.
function M.shinies()
    for i = 1, shn do shOut[i] = nil end
    local n = 0
    for i = 1, #list do
        local e = list[i]
        if e.shiny and not e.dead then n = n + 1; shOut[n] = e end
    end
    shn = n
    return shOut, n
end

function M.count() return #list end
