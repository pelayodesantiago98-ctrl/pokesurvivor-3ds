-- player.lua — el Pokémon que controlas (port de js/entities/player.js).
-- (x, y) son los PIES. Sólo UN hueco está activo a la vez: se dispara solo y se
-- cambia con cycle/setActive. Cada disparo reproduce la animación de ataque de
-- Mundo Misterioso que le toca (Attack, Shoot o Charge).
--
-- Diferencias con el JS: los getters atk/spd/reduction/regen son MÉTODOS
-- (pl:atk()...); `active` es un índice 1-based en `slots`; `sashT` y `castAt`
-- van en segundos (U.now()); sin cooperativo (netUpdate, tag, remote).
local U = G.U
local lg = love.graphics
local floor, max, min, atan2, cos, sin, random = math.floor, math.max, math.min, math.atan2, math.cos, math.sin, love.math.random

local Player = {}
Player.__index = Player
G.Player = Player

-- Segundos que hay que estar junto a un compañero caído para levantarlo.
Player.REVIVE_TIME = 3
-- Tamaño máximo de un grupo de vínculo.
Player.BOND_MAX = 4

local EMPTY = {}                       -- grupo vacío de sólo lectura
local BUFF_KEYS = { 'atk', 'spd', 'def', 'regen' }
local BUFF_COL = { atk = '#ff6b4d', spd = '#7fe0ff', def = '#b0b8c8', regen = '#5fe08a' }
-- Animación de PMD por familia de movimiento.
local ANIM = { melee = 'Attack', beam = 'Shoot', projectile = 'Shoot', nova = 'Attack',
               aura = 'Charge', buff = 'Charge', orbit = 'Charge', boomerang = 'Shoot', chain = 'Shoot',
               mine = 'Charge', meteor = 'Charge', turret = 'Charge', dash = 'Attack', trail = 'Walk', cone = 'Shoot' }
-- Las familias nuevas suenan como la parecida de las de siempre.
local SND = { boomerang = 'projectile', chain = 'beam', mine = 'nova', meteor = 'nova', turret = 'buff',
              dash = 'melee', trail = 'aura', cone = 'projectile' }

-- Tablas de opciones reutilizadas (nada de basura por fotograma).
local sfxOpts = { kind = nil, type = nil }
local playOpts = { speed = 1, hold = false }
local drawOpts = { flash = false, softFlash = true, alpha = 1, color = '#ffcb3d' }

-- (×2 y luego ×4 el 2026-10-10: se subía de nivel demasiado rápido.)
-- Experiencia para pasar del nivel `level` al siguiente. Curva más plana que la de
-- la web (antes: 8 + 6L + 1.6 L^1.75) para que se llegue a los niveles reales de
-- evolución (16, 32, 36...): nivel 16 con ~3.000 de exp y 36 con ~16.000.
function Player.xpFor(level)
    return floor((8 + level * 4 + level ^ 1.5 * 0.4) * 4)
end

--- @param mon   entrada de G.DEX
--- @param perks mejoras permanentes ya resueltas (ver data/upgrades)
function Player.new(mon, perks, shiny)
    perks = perks or EMPTY
    local self = setmetatable({}, Player)
    self.mon = mon
    self.dex = mon.dex
    self.shiny = (shiny and G.Sprites.hasShiny(mon.dex)) and true or false
    self.anim = G.Sprites.Animator.new(mon.dex, 1, self.shiny, true)
    self.x, self.y = 0, 0
    self.r = G.Sprites.bodyRadius(mon.dex)
    self.bodyH = G.Sprites.bodyHeight(mon.dex)

    self.atkMul = perks.atkMul or 1
    self.spdMul = perks.spdMul or 1
    self.cdMul = perks.cdMul or 1
    self.dmgReduce = perks.dmgReduce or 0
    self.regenFlat = perks.regen or 0
    self.magnet = 78 * (perks.magnetMul or 1)
    self.xpMul = perks.xpMul or 1
    self.coinMul = perks.coinMul or 1

    self.maxHp = mon.hp + (perks.hp or 0)
    self.hp = self.maxHp
    self.baseSpd = mon.spd
    self.baseAtk = mon.atk

    self.moves = {}            -- todos los movimientos aprendidos
    self.slots = {}            -- huecos: cada uno, una lista de movimientos que se lanzan a la vez
    self.active = 1            -- hueco activo (1-based)
    self.maxMoves = 4          -- huecos
    self.bonds = 0             -- vínculos por usar (premio de los legendarios)

    self.buffs = {
        atk = { n = 0, t = 0, amount = 0 },
        spd = { n = 0, t = 0, amount = 0 },
        def = { n = 0, t = 0, amount = 0 },
        regen = { n = 0, t = 0, amount = 0 }
    }

    self.level = 1
    self.xp = 0
    self.xpNext = Player.xpFor(1)
    -- Pantalla de mejoras (idea de Pokémon Survivor Burst): repetir la tirada y
    -- vetar cartas (lo vetado no vuelve a salir en la run).
    -- La mejora "Repetir" (web: "Cambio de cartas") suma a las 2 gratis; la de
    -- "Veto" pone en `banned` los movimientos elegidos en Mejoras (Game.startRun).
    self.rerolls, self.bans, self.banned = 2 + (perks.rerolls or 0), 2, {}
    self.critChance = perks.crit or 0   -- probabilidad de golpe crítico (Mejoras)
    self.bind = {}                      -- movimiento -> hueco fijo (1-4), elegido en Mejoras > Atajos
    self.burst = 0             -- barra del ataque Burst (0..1)
    self.kills = 0
    self.bosses = 0
    self.coins = 0             -- monedas recogidas en esta run
    self.t1, self.t10 = 0, 0   -- tickets del gacha recogidos en esta run
    self.dmgDealt = 0

    self.invuln = 0
    self.flash = 0
    self.aim = math.pi / 2
    self.moveAngle = math.pi / 2
    self.walking = false
    self.inLiquid = false
    self.lavaTick = 0
    self.attackFace = 0        -- tiempo que sigue mirando al objetivo tras atacar
    self.dead = false
    self.power = nil           -- poder de altar activo: { def, t, dur }
    self.slowT = 0             -- pegado por una trampa
    self.item = nil            -- objeto equipado (data/items), uno por run
    self.sashT = -999          -- última vez (s) que salvó la Banda Focus
    self.bellHeal = 0          -- curación pendiente del Cascabel Concha
    self.statsTaken = {}       -- mejoras de stat cogidas (condición de evolución)
    self.target = nil
    self.frozen = false        -- quieto (pausa que no para el juego)
    self.svx, self.svy = 0, 0  -- velocidad (para resbalar en el hielo)
    self.reviveT = 0
    self.orbCastT = 0
    self.lastPatch = nil
    return self
end

function Player:cy() return self.y end

-- ---------------- stats efectivos ----------------
function Player:atk()
    local b = self.buffs.atk
    return self.baseAtk * self.atkMul * (1 + b.n * b.amount)
end

function Player:spd()
    local b = self.buffs.spd
    local s = self.baseSpd * self.spdMul * (1 + b.n * b.amount) * (self.slowT > 0 and 0.5 or 1)
    local w = G.Weather.speedFor(self.mon.types)
    local slow = 1
    if self.inLiquid then slow = G.World.liquidEffect(self.mon.types).slow or 1 end
    return s * slow * w
end

function Player:reduction()
    local b = self.buffs.def
    return min(0.8, self.dmgReduce + b.n * b.amount)
end

function Player:regen()
    local b = self.buffs.regen
    return self.regenFlat + b.n * b.amount
end

-- ---------------- movimientos ----------------
function Player:addMove(id)
    if #self.slots >= self.maxMoves or self:hasMove(id) then return false end
    local m = G.Moves.instance(id, 1)
    self.moves[#self.moves + 1] = m
    local group = { m }
    self.slots[#self.slots + 1] = group
    self:arrange()
    -- Se cambia al nuevo, salvo si estás usando un vínculo (no te quita el grupo).
    local cur = self.slots[self.active]
    if not (cur and #cur > 1) then self:setActive(U.indexOf(self.slots, group) or #self.slots) end
    return true
end

-- Huecos fijos (Mejoras > Atajos): cada movimiento con hueco elegido se pone en
-- ese número para la memoria muscular (Confusión siempre en el 1...). Mientras
-- no tengas tantos movimientos, va al más cercano; los demás rellenan los
-- huecos libres en el orden en que los aprendiste.
function Player:arrange()
    local n = #self.slots
    if n < 2 or not self.bind or next(self.bind) == nil then return end
    local bind = self.bind
    local function want(g)
        local k = math.huge
        for i = 1, #g do
            local b = bind[g[i].id]
            if b and b < k then k = b end
        end
        return k
    end
    local cur = self.slots[self.active]
    local out, placed = {}, {}     -- (out tiene huecos mientras se rellena: nada de #out)
    local bound = {}
    for i = 1, n do
        local g = self.slots[i]
        if want(g) < math.huge then bound[#bound + 1] = g end
    end
    -- (Orden estable: a igual hueco, el que se aprendió antes.)
    for i = 2, #bound do
        local g, j = bound[i], i - 1
        while j >= 1 and want(bound[j]) > want(g) do bound[j + 1] = bound[j]; j = j - 1 end
        bound[j + 1] = g
    end
    for i = 1, #bound do
        local g = bound[i]
        local p = min(want(g), n)
        while p >= 1 and out[p] do p = p - 1 end          -- ocupado: el de antes
        if p < 1 then p = 1; while out[p] do p = p + 1 end end   -- o el primero libre
        out[p] = g; placed[g] = true
    end
    for i = 1, n do
        local g = self.slots[i]
        if not placed[g] then
            local p = 1
            while out[p] do p = p + 1 end
            out[p] = g; placed[g] = true
        end
    end
    self.slots = out
    if cur then self.active = U.indexOf(out, cur) or self.active end
end

function Player:hasMove(id)
    local ms = self.moves
    for i = 1, #ms do if ms[i].id == id then return true end end
    return false
end

function Player:setActive(i)
    if i < 1 or i > #self.slots or i == self.active then return end
    -- Cinta Elección: no se puede cambiar de movimiento.
    if self:hasItem('choiceband') and self.slots[self.active] then
        G.FX.dmgText(self.x, self.y - self.bodyH - 8, 'Cinta Elección', '#ff8ad8')
        return
    end
    self.active = i
    G.Projectiles.clearOrbs(self)
    G.Audio.sfx('select')
    local s = self.slots[i]
    for k = 1, #s do local m = s[k]; m.t = min(m.t, m.cd * 0.35) end
    local m = s[1]
    G.FX.ring(self.x, self.y - G.LIFT * 0.5, 6, self.r * 3.4, U.TYPE_COLOR[m.type], 0.3, 3)
end

function Player:cycle(dir)
    local n = #self.slots
    if n == 0 then return end
    self:setActive(((self.active - 1 + dir) % n) + 1)
end

-- ---------------- vínculos (fusiones) ----------------
-- Cada legendario vencido da un vínculo. Con él se juntan movimientos en un
-- solo hueco y se lanzan a la vez. Sólo crece un grupo (hasta BOND_MAX); si
-- no hay ninguno a medias, el vínculo une dos movimientos sueltos.

--- Lo que se puede hacer ahora con un vínculo: { mode = 'add'|'pair', group, loose } o nil.
function Player:bondOptions()
    local loose, grow = {}, nil
    for i = 1, #self.slots do
        local s = self.slots[i]
        if #s == 1 then loose[#loose + 1] = s[1]
        elseif #s > 1 and #s < Player.BOND_MAX and not grow then grow = s end
    end
    if grow then
        if #loose > 0 then return { mode = 'add', group = grow, loose = loose } end
        return nil
    end
    if #loose >= 2 then return { mode = 'pair', group = nil, loose = loose } end
    return nil
end

--- Junta `moves` (sueltos) en el grupo `group` (o en uno nuevo) y gasta un vínculo.
function Player:fuse(moves, group)
    local target = group
    if not target then
        for i = 1, #self.slots do
            if self.slots[i][1] == moves[1] then target = self.slots[i]; break end
        end
    end
    local cur = self.slots[self.active]
    for k = 1, #moves do
        local m = moves[k]
        if not U.contains(target, m) then
            local idx = nil
            for i = 1, #self.slots do
                local s = self.slots[i]
                if #s == 1 and s[1] == m then idx = i; break end
            end
            if idx then
                table.remove(self.slots, idx)
                target[#target + 1] = m
            end
        end
    end
    self:arrange()
    -- Se pasa al grupo, salvo con la Cinta Elección (sigues en el hueco que tenías, si queda).
    local a = U.indexOf(self.slots, cur)
    if self:hasItem('choiceband') and a then self.active = a
    else self.active = U.indexOf(self.slots, target) or 1 end
    self.bonds = max(0, self.bonds - 1)
    G.Projectiles.clearOrbs(self)
    return target
end

--- Movimientos que se lanzan ahora (el grupo del hueco activo).
function Player:activeGroup() return self.slots[self.active] or EMPTY end

function Player:activeMove() return self:activeGroup()[1] end

--- Lo llama combat.lua al lanzar un movimiento. Elige la animación de PMD y la
--- acelera si la recarga es más corta que la animación, para que encadene.
function Player:cast(m)
    -- Vidasfera: cada ataque cuesta un poco de vida (nunca te deja KO).
    if self:hasItem('lifeorb') and m.kind ~= 'orbit' and m.kind ~= 'trail' then
        self.hp = max(1, self.hp - max(1, self.maxHp * 0.01))
    end
    local anim = ANIM[m.kind] or 'Attack'
    -- El rastro no suena a cada charco (sería un zumbido constante).
    if m.kind ~= 'trail' then
        sfxOpts.kind = SND[m.kind] or m.kind
        sfxOpts.type = m.type
        G.Audio.sfx('shot', sfxOpts)
    end
    if m.kind == 'trail' then return end
    -- No reinicies una animación que va por la mitad: se vería a tirones.
    if self.anim:busy() and self.anim:progress() < 0.65 then return end
    local meta = G.Sprites.animMeta(self.dex, anim, self.anim.full)
    local len = 0.4
    if meta then
        local s = 0
        for i = 1, #meta.d do s = s + meta.d[i] end
        len = s / 60
    end
    local cd = max(0.12, m.cd * self.cdMul)
    playOpts.speed = max(1, len / (cd * 0.9))
    playOpts.hold = false
    self.anim:play(anim, playOpts)
    self.attackFace = 0.35
end

-- ---------------- daño y curación ----------------
--- @param ty    tipo del ataque (tabla de tipos y clima); sin tipo, daño tal cual
--- @param pure  daño que no baja con la defensa ni el cuerpo a cuerpo (Arceus)
function Player:hurt(amount, ty, pure)
    if self.invuln > 0 or self.dead then return end
    local eff = nil
    if ty then
        local k = G.Types.mult(ty, self.mon.types)
        eff = G.Types.label(k)
        amount = amount * k * G.Weather.mult(ty)
    end
    -- Con un ataque cuerpo a cuerpo activo se recibe un 25 % menos: hay que
    -- estar encima de los enemigos para pegar (iban muy por detrás).
    local close = 1
    local g = self:activeGroup()
    for i = 1, #g do
        if g[i].kind == 'melee' then close = 0.75 break end
    end
    local d = pure and max(1, amount) or max(1, amount * (1 - self:reduction()) * close)
    self.hp = self.hp - d
    if G_SOAK then
        -- Pruebas aceleradas: de dónde viene el último golpe (se muestra al morir).
        G_SOAK.lastHurt = string.format("d=%.0f ty=%s liq=%s pos=%d,%d hp=%.0f/%.0f  %s", d, tostring(ty),
            tostring(G.World.isLiquid(self.x, self.y)), self.x, self.y, self.hp, self.maxHp,
            (debug.traceback("", 2):gsub("\n%s*", " < "):sub(1, 260)))
    end
    self.invuln = 0.45
    self.flash = 0.14
    G.Audio.sfx('hurt')
    G.Camera.kick(0.28)
    local col = '#ff6b7a'
    if eff == 'super' then col = '#ff3048' elseif eff == 'weak' then col = '#c9a0a8' end
    G.FX.dmgText(self.x, self.y - self.bodyH - 4, '-' .. U.round(d), col, eff == 'super')
    G.FX.burst(self.x, self.y - self.bodyH * 0.5, '#ff5f6d', 6, 90)
    -- Banda Focus: aguanta el golpe con 1 de vida (una vez cada 60 s).
    if self.hp <= 0 and self:hasItem('focussash') and U.now() - self.sashT > 60 then
        self.sashT = U.now()
        self.hp = 1; self.invuln = 1.2
        G.FX.dmgText(self.x, self.y - self.bodyH - 16, '¡Banda Focus!', '#ff9a3d', true)
        G.FX.ring(self.x, self.y, 6, 70, '#ff9a3d', 0.5, 4)
    end
    if self.hp <= 0 then
        self.hp = 0; self.dead = true
        playOpts.speed = 1; playOpts.hold = true
        self.anim:play('Faint', playOpts)
        G.Projectiles.clearOrbs(self)
        self.reviveT = 0
    end
end

function Player:heal(amount)
    local before = self.hp
    self.hp = min(self.maxHp, self.hp + amount)
    local got = U.round(self.hp - before)
    if got >= 1 then G.FX.dmgText(self.x, self.y - self.bodyH - 6, '+' .. got, '#5fe08a') end
end

function Player:addMaxHp(amount)
    self.maxHp = self.maxHp + amount
    self.hp = self.hp + amount
end

--- Devuelve cuántos niveles ha subido (pueden ser varios de golpe).
function Player:gainXp(amount)
    self.xp = self.xp + amount * self.xpMul
    local leveled = 0
    while self.xp >= self.xpNext do
        self.xp = self.xp - self.xpNext
        self.level = self.level + 1
        self.xpNext = Player.xpFor(self.level)
        leveled = leveled + 1
    end
    return leveled
end

-- ---------------- objeto equipado ----------------
function Player:hasItem(id) return self.item == id end

--- Se pone un objeto (y se quita el que llevara).
function Player:equip(id)
    if self.item then G.Items.BY[self.item].off(self) end
    self.item = id
    if id then G.Items.BY[id].on(self) end
end

--- Cascabel Concha: un poco de vida por el daño que haces (tope 4/s).
function Player:onDealt(dmg)
    if self.item == 'shellbell' then self.bellHeal = min(4, self.bellHeal + dmg * 0.04) end
end

--- Poder de un altar (ver interact.lua): se aplica y se quita solo.
function Player:addPower(def, dur)
    if self.power then self.power.def.off(self) end
    def.on(self)
    self.power = { def = def, t = dur, dur = dur }
end

function Player:addBuff(stat, amount, dur, maxStacks)
    local b = self.buffs[stat]
    if not b then return end
    b.amount = amount
    b.n = min(maxStacks, b.n + 1)
    b.t = dur
end

-- ---------------- ciclo ----------------
function Player:update(dt)
    self.anim:update(dt)
    if self.dead then return end
    if self.invuln > 0 then self.invuln = self.invuln - dt end
    if self.flash > 0 then self.flash = self.flash - dt end
    if self.attackFace > 0 then self.attackFace = self.attackFace - dt end

    for k = 1, 4 do
        local b = self.buffs[BUFF_KEYS[k]]
        if b.n > 0 then
            b.t = b.t - dt
            if b.t <= 0 then b.n = 0 end
        end
    end
    if self.slowT > 0 then self.slowT = self.slowT - dt end
    if self.bellHeal > 0 then
        local h = min(self.bellHeal, 4 * dt)
        self.hp = min(self.maxHp, self.hp + h)
        self.bellHeal = self.bellHeal - h
    end
    if self.power then
        self.power.t = self.power.t - dt
        if self.power.t <= 0 then self.power.def.off(self); self.power = nil end
    end
    local rg = self:regen()
    if rg > 0 then self.hp = min(self.maxHp, self.hp + rg * dt) end

    -- --- movimiento con colisiones ---
    local ax, ay = 0, 0
    if not self.frozen then ax, ay = G.Input.axis() end
    self.walking = ax ~= 0 or ay ~= 0
    local s = self:spd()
    -- Hielo: resbalas (la velocidad cambia despacio).
    local slide = self.inLiquid and G.World.liquidEffect(self.mon.types).slide
    if slide then
        self.svx = U.damp(self.svx, ax * s * 1.15, 1.6, dt)
        self.svy = U.damp(self.svy, ay * s * 1.15, 1.6, dt)
    else
        self.svx = ax * s
        self.svy = ay * s
    end
    self.x = self.x + self.svx * dt
    self.y = self.y + self.svy * dt
    G.World.collide(self)
    if self.walking then self.moveAngle = atan2(ay, ax) end

    -- --- terreno líquido ---
    self.inLiquid = G.World.isLiquid(self.x, self.y) and true or false
    if self.inLiquid then
        local le = G.World.liquidEffect(self.mon.types)
        if le.dmg then
            self.lavaTick = self.lavaTick - dt
            if self.lavaTick <= 0 then
                self.lavaTick = le.every; self.invuln = 0
                self:hurt(max(le.flat, self.maxHp * le.dmg * 0.5))
                G.FX.burst(self.x, self.y - 4, le.color, 5, 70)
            end
        elseif self.walking and random() < dt * 8 then
            G.FX.burst(self.x, self.y, le.slide and '#ffffff' or '#b3defa', 2, 40)
        end
    end

    -- --- apuntado: enemigo más cercano; si no hay, hacia donde caminas ---
    -- Prioridad de blanco según el ataque activo:
    --   a distancia (proyectil, rayo): el jefe si está a tiro > lo que te toca > el más cercano
    --   cuerpo a cuerpo y el resto:   lo que te toca > el jefe > el más cercano
    -- Sin enemigos, apunta a la roca o cofre más cercano.
    local all = G.EnemyMgr.all()
    local m = self:activeMove()
    local ranged = m ~= nil and (m.kind == 'projectile' or m.kind == 'beam')
    local threat = G.Projectiles.nearest(all, self.x, self.y, self.r + 24)
    local boss = nil
    for i = 1, #all do
        local e = all[i]
        if e.boss and not e.dead and U.dist(self.x, self.y, e.x, e.y) < 330 then boss = e; break end
    end
    local tg
    if ranged then tg = boss or threat else tg = threat or boss end
    if not tg then tg = G.Projectiles.nearest(all, self.x, self.y, 520) end
    if not tg then tg = G.World.nearestBreakable(self.x, self.y, 200) end
    self.target = tg
    if tg then self.aim = atan2(tg.y - self.y, tg.x - self.x)
    elseif self.walking then self.aim = self.moveAngle end

    -- --- animación: mira al objetivo al atacar, si no a donde camina ---
    local face = (self.attackFace > 0 or not self.walking) and self.aim or self.moveAngle
    self.anim.dir = G.Sprites.dirFromAngle(face)
    if self.walking then self.anim:loop('Walk', s / 110) else self.anim:loop('Idle', 1) end
end

--- Vuelve a levantarse.
function Player:revive(frac)
    frac = frac or 0.5
    self.dead = false
    self.hp = max(1, self.maxHp * frac)
    self.invuln = 2
    self.reviveT = 0
    self.anim:restart('Idle')
    G.FX.ring(self.x, self.y, 6, 70, '#5fe08a', 0.5, 4)
    G.FX.burst(self.x, self.y - self.bodyH * 0.5, '#9dffb8', 18, 150)
    G.Audio.sfx('heal')
end

function Player:draw()
    -- Halo del tipo del movimiento activo, en el suelo.
    local m = self:activeMove()
    if m and not self.dead then
        U.setColor(U.TYPE_COLOR[m.type], 0.22)
        lg.setLineWidth(2)
        G.Sprites.ellipseLine(self.x, self.y, self.r * 1.5, self.r * 0.6)
    end
    G.Sprites.drawShadow(self.dex, self.x, self.y)
    -- Poder de altar: aro de su color latiendo bajo los pies.
    if self.power and not self.dead then
        U.setColor(self.power.def.color, 0.35 + sin(U.now() / 0.12) * 0.15)
        lg.setLineWidth(3)
        G.Sprites.ellipseLine(self.x, self.y, self.r * 2.1, self.r * 0.85)
    end

    local alpha = 1
    if self.invuln > 0 and not self.dead then
        alpha = (floor(self.invuln * 18) % 2 == 1) and 0.45 or 1
    end
    drawOpts.flash = self.flash > 0
    drawOpts.alpha = alpha
    self.anim:draw(self.x, self.y, drawOpts)

    -- Arcos de buff alrededor de los pies (elipse = arco escalado en Y).
    local i = 0
    for k = 1, 4 do
        local key = BUFF_KEYS[k]
        local b = self.buffs[key]
        if b.n > 0 then
            local R = self.r * 1.8 + i * 5
            U.setColor(BUFF_COL[key], 0.6)
            lg.setLineWidth(2)
            lg.push()
            lg.translate(self.x, self.y)
            lg.scale(1, 0.42)
            -- (Con los tramos justos, como G.Sprites.ellipseLine: cada tramo son 6 vértices.)
            lg.arc('line', 'open', 0, 0, R, 0, 6.2832 * (b.n / 5), max(3, floor(3.2 * math.sqrt(R * 0.5) * b.n / 5)))
            lg.pop()
            i = i + 1
        end
    end
    lg.setLineWidth(1)
    lg.setColor(1, 1, 1, 1)
end
