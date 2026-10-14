-- game.lua — flujo del juego y bucle principal (port de js/game.js, sin cooperativo).
--
--   título ──> test de personalidad ──> menú ──> run ──> resumen ──> menú
--                 (solo la 1ª vez)         │
--                                          ├─ Pokémon (colección)
--                                          ├─ Mejoras / Gacha / Misiones
--
-- Estados: 'ui' (menús, con el mundo de fondo), 'playing', 'levelup', 'choice',
-- 'paused', 'over'. La interfaz vive en la pantalla inferior (src/ui/*).
local U = G.U
local Game = {}
G.Game = Game

local state = "ui"
local time, pendingLevels = 0, 0
local pl = nil
local caught = {}          -- shinies conseguidos en esta run
local biome = -1
local deathT = 0
local flashT, flashDur, flashCol = 0, 1, "#ffffff"
local frameDt = 0
-- Tickets de esta partida que ya están en la partida guardada (ver bankTickets).
local banked1, banked10 = 0, 0
local ticketsDirty, ticketSaveT = false, 60     -- tickets apuntados pero aún no escritos en la SD

G.BIOME_MUSIC = { "forest", "cave", "volcano" }

function Game.state() return state end
function Game.player() return pl end
function Game.time() return time end
function Game.setState(s) state = s end

-- ---------------- run ----------------

-- @param stageIdx  nil = arena infinita; número = fase del modo Fases
-- Nombre de la zona en la arena infinita, numerado según las veces que has
-- entrado en ese bioma en esta partida: MONTE ASCUAS I, II, III...
local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }
local zoneVisits = {}
local function zoneName()
    -- El ciclo de biomas también pasa por los temas de las arenas, cuyo nombre lleva
    -- "Grieta · " delante: fuera de una grieta se quita. Se cuenta por nombre, así la
    -- zona de fuego del volcán y la de la arena de fuego siguen la misma numeración.
    local name = G.World.biomeName():gsub("^Grieta · ", "")
    zoneVisits[name] = (zoneVisits[name] or 0) + 1
    local n = zoneVisits[name]
    return name .. " " .. (ROMAN[n] or tostring(n))
end

function Game.startRun(stageIdx)
    local save = G.DB.save
    local mon = G.DEX_BY[save.partner]
    local perks = G.Upgrades.perks(G.DB.upgradesOf(mon.dex))
    if stageIdx then G.Stages.start(stageIdx) else G.Stages.stop() end
    local stage = G.Stages.current()

    G.FX.clear()
    G.Projectiles.clear()
    G.Combat.clearFields()
    G.EnemyMgr.clear()
    G.Pickups.clear()
    G.Rift.reset()
    G.Judgment.reset()
    G.Events.reset()
    G.Weather.reset()
    G.Path.clear()
    G.Hazards.clear(); G.Interact.clear()
    G.Sprites.clearQueue()
    G.Sprites.gc({})
    G.World.reset(math.floor(love.math.random() * 1e6))
    biome = stage and stage.biome or 0
    G.World.setBiome(biome, true)
    time = 0; pendingLevels = 0

    pl = G.Player.new(mon, perks, save.partnerShiny and G.DB.ownsShiny(mon.dex))
    banked1, banked10 = 0, 0
    caught = {}
    -- Atajos (Mejoras): movimientos con hueco fijo (save.pbind[dex] = { [hueco] = id }),
    -- antes de aprender nada: addMove ya los coloca.
    local binds = save.pbind and save.pbind[mon.dex]
    if type(binds) == "table" then
        for i = 1, 4 do
            local id = binds[i]
            if type(id) == "string" and G.Moves.BY_ID[id] then pl.bind[id] = i end
        end
    end
    -- Mejora "Veto": movimientos elegidos en Mejoras que no salen en las cartas
    -- (van con las cartas vetadas en la run: clave 'new:<id>').
    local bans = save.pban and save.pban[mon.dex]
    if type(bans) == "table" then
        for i = 1, math.min(#bans, perks.bans or 0) do pl.banned["new:" .. bans[i]] = true end
    end
    pl:addMove(G.startMoveOf(mon.dex))
    -- Mejora "Repertorio": un segundo movimiento de ataque al azar.
    if perks.startMoves >= 2 then
        local pool = {}
        for _, id in ipairs(G.Moves.poolFor(mon)) do
            if not pl:hasMove(id) and not pl.banned["new:" .. id] and G.Moves.BY_ID[id].kind ~= "buff" then pool[#pool + 1] = id end
        end
        if #pool > 0 then pl:addMove(U.pick(pool)) end
        pl:setActive(1)
    end

    G.Camera.x = pl.x; G.Camera.y = pl.y; G.Camera.shake = 0
    G.Sprites.preload({ mon.dex }, true)
    if pl.shiny then G.Sprites.preload({ mon.dex }, false, true) end
    G.Spawner.reset()
    G.Audio.finishPreload()
    G.Audio.music(G.BIOME_MUSIC[(biome % #G.BIOME_MUSIC) + 1])
    deathT = 0
    state = "playing"
    G.UI.show("hud")
    zoneVisits = {}
    G.Spawner.sayZone(stage and stage.name or zoneName())
    -- En las fases avanzadas empiezas con algunas subidas de nivel (eliges sus
    -- cartas al empezar), para no llegar a nivel 1 contra enemigos de tramo alto.
    if stageIdx and stageIdx > 1 then
        for _ = 1, stageIdx - 1 do
            pl.level = pl.level + 1
            pendingLevels = pendingLevels + 1
        end
        pl.xpNext = G.Player.xpFor(pl.level)
    end
end

function Game.quitRun()
    Game.endRun(false)
end

-- Experiencia que hace falta para el siguiente nivel (cofres con candado).
function Game.levelXp()
    if not pl then return 20 end
    local k = pl.xpMul or 1
    return math.ceil((pl.xpNext - pl.xp + 1) / k)
end

-- Destello de pantalla completa (viaje a la grieta).
function Game.flash(col, dur)
    flashCol = col; flashDur = dur; flashT = dur
end

-- Has llevado a casa a un Pokémon perdido y se une a ti (events.lua).
function Game.onRescue(dex, name)
    if not G.DB.save or not pl then return end
    local isNew = not G.DB.owns(dex)
    if isNew then G.DB.grant(dex, "rescue"); G.DB.commit()
    else pl.coins = pl.coins + 150 end
    G.Spawner.say(isNew and ("¡" .. name .. " se une a tu equipo!") or ("¡" .. name .. " te da las gracias! (+150 monedas)"), 4)
    G.Audio.sfx("shinyGet")
end

-- Un shiny salvaje cae: te lo quedas (y la versión normal si no la tenías).
function Game.onShinyCaught(e)
    if not G.DB.save or not pl then return end
    local isNew = G.DB.grantShiny(e.dex, "wild")
    G.DB.save.stats.shinies = (G.DB.save.stats.shinies or 0) + 1
    G.DB.commit()
    caught[#caught + 1] = { dex = e.dex, isNew = isNew }
    G.Spawner.say(isNew and ("¡Has conseguido a " .. e.name .. " shiny!") or ("¡Otro " .. e.name .. " shiny! (+300 monedas)"), 4)
    if not isNew then pl.coins = pl.coins + 300 end
    G.Audio.sfx("shinyGet")
end

-- Los tickets recogidos se guardan en cuanto los coges (como los shinies):
-- antes sólo al acabar, y si se apagaba la consola a mitad se perdían.
-- Sólo se suma lo que aún no estaba guardado (banked1/banked10), así que
-- endRun no los cuenta dos veces.
-- @param commit  false = no escribir aún (endRun guarda luego todo junto)
local function bankTickets(commit)
    local sv = G.DB.save
    if not sv or not pl then return end
    sv.tickets = sv.tickets or { t1 = 0, t10 = 0 }
    local d1, d10 = math.max(0, pl.t1 - banked1), math.max(0, pl.t10 - banked10)
    if d1 == 0 and d10 == 0 then return end
    sv.tickets.t1 = (sv.tickets.t1 or 0) + d1
    sv.tickets.t10 = (sv.tickets.t10 or 0) + d10
    banked1, banked10 = pl.t1, pl.t10
    if commit ~= false then G.DB.commit() end
end

-- @param won  true si se ha superado la fase (modo Fases)
function Game.endRun(dead, won)
    if dead == nil then dead = true end
    if state == "over" or not pl then return end
    state = "over"
    G.Audio.music(nil)
    G.Audio.sfx(won and "legend" or (dead and "gameover" or "back"))
    local save = G.DB.save
    local mul = pl.coinMul
    local stageIdx = G.Stages.index()
    local parts = {
        { "tiempo", math.floor(time / 5) },
        { "derrotados", math.floor(pl.kills * 0.25) },
        { "jefes", pl.bosses * 80 },
        { "recogidas", pl.coins },
    }
    if won and stageIdx then
        parts[#parts + 1] = { "fase superada", 150 * stageIdx }
        G.Stages.markCleared(stageIdx, time)
        save.stats.stagesCleared = (save.stats.stagesCleared or 0) + 1
    end
    save.stats.playTime = (save.stats.playTime or 0) + time
    local sum = 0
    for _, p in ipairs(parts) do sum = sum + p[2] end
    local dif = G.Difficulty.get()
    local coins = U.round(sum * mul * dif.reward)
    local record = time > (save.stats.bestTime or 0)

    save.coins = save.coins + coins
    bankTickets(false)          -- los que falten (normalmente ya están guardados)
    save.stats.runs = (save.stats.runs or 0) + 1
    save.stats.totalKills = (save.stats.totalKills or 0) + pl.kills
    save.stats.bestTime = math.max(save.stats.bestTime or 0, math.floor(time))
    save.stats.bestLevel = math.max(save.stats.bestLevel or 0, pl.level)
    save.stats.coinsEarned = (save.stats.coinsEarned or 0) + coins
    -- La Sentencia de Arceus: lo aguantado ante él (logros) y fin.
    local judge = G.Judgment.summary()
    if judge then G.Progress.event("judgeEnd", judge) end
    G.Judgment.reset()
    G.Progress.event("runEnd", { time = time, level = pl.level, coins = pl.coins, types = pl.mon.types })
    G.Progress.checkAch()
    G.DB.commit()

    local breakdown = {}
    for _, p in ipairs(parts) do if p[2] > 0 then breakdown[#breakdown + 1] = p[1] .. " " .. p[2] end end
    local bd = table.concat(breakdown, " · ")
    if mul > 1 then bd = bd .. string.format(" · x%.2f Fortuna", mul) end
    if dif.reward ~= 1 then bd = bd .. string.format(" · x%.2f %s", dif.reward, dif.name) end

    local stage = G.Stages.current()
    G.RunUI.showOver({
        dead = dead, won = won, stage = stage and stage.name or nil, time = time, level = pl.level, kills = pl.kills,
        bosses = pl.bosses, coins = coins, record = record and not stage, t1 = pl.t1, t10 = pl.t10, moves = pl.moves,
        caught = caught, breakdown = bd, form = pl.form or 1, name = pl.mon.name, judge = judge,
    }, function() pl = nil; G.Flow.afterRun() end)
end

-- ---------------- subida de nivel ----------------

local function maybeLevelUp()
    if pendingLevels <= 0 or state ~= "playing" then return end
    -- Nunca abras cartas con el Pokémon caído (morir y recoger XP en el mismo frame).
    if pl.dead then return end
    pendingLevels = pendingLevels - 1
    state = "levelup"
    G.Audio.sfx("levelup")
    G.RunUI.showLevelUp(pl.level, G.LevelUp.offer(pl), function(card)
        G.Audio.sfx("confirm")
        card.apply(pl)
        state = "playing"
    end, {
        -- Repetir / vetar (idea de Pokémon Survivor Burst)
        left = function() return pl.rerolls, pl.bans end,
        reroll = function()
            if pl.rerolls <= 0 then return nil end
            pl.rerolls = pl.rerolls - 1
            return G.LevelUp.offer(pl)
        end,
        ban = function(c)
            if pl.bans <= 0 or c.type == "evo" then return nil end
            pl.bans = pl.bans - 1
            pl.banned[c.key] = true
            return G.LevelUp.offer(pl)
        end,
    })
end

-- ---------------- vínculos ----------------

-- Vínculo de un legendario: eliges qué movimientos se fusionan. Si ahora no se
-- puede (no hay dos sueltos), se guarda hasta que aprendas otro movimiento.
function Game.offerBond(quiet)
    if not pl or pl.bonds <= 0 or pl.dead or state ~= "playing" or G.Rift.inArena() then return end
    local opt = pl:bondOptions()
    if not opt then
        if not quiet then G.Spawner.say("Guardas el vínculo: aprende otro movimiento para usarlo", 3, true) end
        return
    end
    state = "choice"
    G.Audio.sfx("levelup")
    G.RunUI.showBond(opt, function(picked)
        local group = pl:fuse(picked, opt.group)
        G.Audio.sfx("legend")
        G.FX.ring(pl.x, pl.y, 8, 130, "#ff8ad8", 0.8, 6)
        G.FX.burst(pl.x, pl.y - pl.bodyH * 0.5, "#ffb3e6", 40, 240)
        G.Spawner.say("¡Vínculo! " .. #group .. " movimientos a la vez", 2.6, true)
        if state == "choice" then state = "playing" end
    end)
end

-- ---------------- recogida ----------------

local PICK_SFX = { xp = "xp", xpBig = "xp", coin = "coin", heal = "heal", bomb = "break", magnet = "confirm",
                   ticket = "shiny", ticket10 = "legend", item = "legend" }

-- Has cogido un objeto: si no llevas ninguno te lo pones; si no, eliges.
function Game.offerItem(id)
    if not pl or not G.Items.BY[id] then return end
    local function take(got)
        if got ~= pl.item then
            pl:equip(got)
            G.Spawner.say("¡Llevas " .. G.Items.BY[got].name .. "!", 2.6, true)
            G.Progress.event("item", { id = got })
        end
        if state == "choice" then state = "playing" end
    end
    if not pl.item then take(id) return end
    if pl.item == id then G.Spawner.say("Ya llevas " .. G.Items.BY[id].name, 2, true) return end
    state = "choice"
    G.RunUI.showItemChoice(pl.item, id, take)
end

local function onCollect(p, who)
    who = who or pl
    G.Audio.sfx(PICK_SFX[p.kind])
    local kind = p.kind
    if kind == "xp" or kind == "xpBig" then
        pendingLevels = pendingLevels + pl:gainXp(p.value)
        return
    end
    if kind == "coin" then
        pl.coins = pl.coins + p.value
        G.FX.dmgText(who.x, who.y - who.bodyH - 6, "+" .. p.value, "#ffd23f")
        return
    end
    if kind == "item" then Game.offerItem(p.value) return end
    if kind == "ticket" or kind == "ticket10" then
        if kind == "ticket" then pl.t1 = pl.t1 + 1 else pl.t10 = pl.t10 + 1 end
        -- Se guardan luego (Game.frame): escribir en la SD en plena partida daba
        -- tirones y en la 3DS coincidía con cierres (dos tickets seguidos de un cofre).
        bankTickets(false)
        ticketsDirty = true
        G.FX.dmgText(who.x, who.y - who.bodyH - 8, kind == "ticket" and "+1 ticket" or "¡Ticket x10!",
                     kind == "ticket" and "#ffd23f" or "#d9a6ff", true)
        G.FX.ring(who.x, who.y, 6, 50, kind == "ticket" and "#ffd23f" or "#c47bff", 0.4, 3)
        return
    end
    if kind == "heal" then
        pl:heal(pl.maxHp * 0.3)
        G.FX.ring(who.x, who.y, 6, 60, "#5fe08a", 0.4, 3)
        return
    end
    if kind == "magnet" then
        G.Pickups.pullAll()
        G.FX.ring(who.x, who.y, 10, 420, "#ff9ed8", 0.6, 4)
        return
    end
    if kind == "bomb" then
        G.Camera.kick(0.8)
        local R = G.Camera.outerRadius()
        G.FX.ring(who.x, who.y, 20, R, "#ff7b3d", 0.5, 6)
        local all = G.EnemyMgr.all()
        for i = 1, #all do
            local e = all[i]
            if G.Camera.sees(e.x, e.y, 0) then
                e:hurt(60 + pl.level * 14, "#ff7b3d", e.x - who.x, e.y - who.y, 160)
            end
        end
    end
end

-- ---------------- pausa y controles de la run ----------------

function Game.togglePause()
    if state == "playing" then
        state = "paused"; G.RunUI.showPause(); G.Audio.sfx("pause")
    elseif state == "paused" then
        state = "playing"; G.UI.show("hud")
    end
end

local function handleButtons()
    local In = G.Input
    -- La Sentencia de Arceus: A, B o START saltan la animación (si se puede).
    if state == "playing" and pl and G.Judgment.cinematic() then
        if In.pressed("a") or In.pressed("b") or In.pressed("start") then G.Judgment.skip() end
        return
    end
    if state == "playing" and pl then
        if In.pressed("start") then Game.togglePause() return end
        if In.pressed("leftshoulder") then pl:cycle(-1) end
        if In.pressed("rightshoulder") then pl:cycle(1) end
        if In.pressed("x") then pl:setActive((pl.active % #pl.slots) + 1) end
    elseif state == "paused" then
        if In.pressed("start") or In.pressed("b") then Game.togglePause() end
    end
end

-- ---------------- bucle ----------------

local function update(dt)
    if flashT > 0 then flashT = flashT - dt end
    -- La Sentencia de Arceus: mientras dura la animación, todo lo demás se para
    -- (también el reloj).
    if G.Judgment.cinematic() then
        G.Judgment.cineTick(dt)
        pl.anim:update(dt)
        G.World.update(dt, G.Camera)
        G.FX.update(dt)
        G.Audio.music(G.Judgment.music())
        return
    end
    -- Tras caer, deja que se vea la animación de Faint antes del resumen.
    -- (En la arena de la grieta no: allí caer solo te echa de vuelta.)
    if pl.dead and not G.Rift.inArena() then
        deathT = deathT + dt
        pl:update(dt)
        G.EnemyMgr.update(dt * 0.3, pl)
        G.FX.update(dt)
        G.Camera.follow(pl.x, pl.y, dt)
        if deathT > 1.3 then deathT = 0; Game.endRun(true) end
        return
    end
    time = time + dt

    -- Una run cambia de bioma cada 4 min y recorre toda la lista (normales y
    -- los de las arenas); al acabarse, vuelve a empezar. (Antes, pasado el
    -- último, hacia el minuto 84, se pedía un bioma que no existe y el juego
    -- se rompía; World.setBiome sólo da la vuelta a los normales.)
    local nb = G.Tiles.ARENA + #G.Tiles.ARENA_TYPES
    local b = math.floor(time / 240) % nb
    if G.Stages.active() then b = biome end     -- en una fase el bioma es fijo
    if b ~= biome and not G.Rift.inArena() and not G.Judgment.active() then
        biome = b
        G.World.setBiome(b)
        G.Audio.sfx("biome")
        G.Spawner.sayZone(zoneName())
        G.FX.ring(pl.x, pl.y, 10, G.Camera.outerRadius(), "#ffffff", 0.7, 6)
    end

    pl:update(dt)
    G.Evolution.update(pl)
    G.World.rustle(pl.x, pl.y, dt)
    G.Camera.follow(pl.x, pl.y, dt)
    G.World.update(dt, G.Camera)

    G.Path.update(dt, pl)
    G.Spawner.update(dt, pl, time)
    G.EnemyMgr.update(dt, pl)
    G.EnemyMgr.rebuildGrid()
    G.Combat.tick(dt, pl, time)
    G.Projectiles.update(dt, pl, G.EnemyMgr.all())
    G.Combat.resolve(dt, pl, time)
    G.Combat.updateFields(dt)
    G.Pickups.update(dt, pl, onCollect)
    G.Hazards.update(dt)
    G.Interact.update(dt, pl)
    G.Rift.update(dt, pl, time)
    G.Judgment.update(dt, pl, time)
    G.Events.update(dt, pl, time)
    G.Weather.update(dt, time, pl)
    G.FX.update(dt)

    if G.Judgment.active() then G.Audio.music(G.Judgment.music())
    else G.Audio.music(G.Rift.inArena() and "rift" or (G.EnemyMgr.bossAlive() and "boss" or G.BIOME_MUSIC[(biome % #G.BIOME_MUSIC) + 1])) end
    -- `--killbosses` (depuración): los jefes caen al instante.
    if Game.autoKillBosses then
        local all = G.EnemyMgr.all()
        for i = 1, #all do
            local e = all[i]
            if e.boss and not e.dead then e:hurt(1e9, "#ffffff") end
        end
    end
    G.Stages.update(dt)
    if G.Stages.cleared() and state == "playing" and not pl.dead then
        Game.endRun(false, true)
        return
    end
    maybeLevelUp()
    if pl.bonds > 0 then Game.offerBond(true) end
end

-- Un fotograma: lógica según el estado (lo llama main.lua desde love.update).
function Game.frame(dt)
    frameDt = (state == "playing") and dt or 0
    handleButtons()
    -- Tickets cogidos sin guardar: se guardan en cuanto se pausa (o se sube de
    -- nivel, o se abre un menú) o, como mucho, cada 60 s de partida.
    if ticketsDirty then
        ticketSaveT = ticketSaveT - dt
        if state ~= "playing" or ticketSaveT <= 0 then
            ticketsDirty, ticketSaveT = false, 60
            G.DB.commit()
        end
    end
    if state == "playing" then G.Sprites.step() end
    if state == "playing" then update(dt)
    elseif pl and state ~= "ui" then
        G.FX.update(dt * 0.25)
        pl.anim:update(dt * 0.25)
    end
    if state == "ui" then Game.Backdrop.step(dt) end
    G.Audio.update(dt)
end

-- ---------------- dibujo (pantalla superior) ----------------

local ents = {}       -- entidades a la vista (lista reutilizada), ordenadas por Y
local function byY(a, b) return a.y < b.y end
local reflOpts = { reflect = true }

local function drawScene(cam, extra)
    local World = G.World
    local t = U.now()
    World.drawGround(cam)
    World.drawLiquid(cam, t)
    -- Objetos a la vista: los planos y los que se ordenan (éstos ya vienen
    -- ordenados por Y, ver World.visibleSplit).
    local flat, props = World.visibleSplit(cam)
    G.Hazards.draw()
    G.Combat.drawGroundFields()
    G.Pickups.draw()

    -- Lo plano, las flores y las matitas de hierba van pegados al suelo: siempre por
    -- debajo de quien los pisa, así que se dibujan ya y no entran en la ordenación
    -- (son la mayoría de los objetos a la vista).
    World.drawFlat(flat, t)

    -- Todo lo que tiene "pies" se ordena por Y: objetos, enemigos, jugador. Sólo
    -- se ordenan las entidades; luego se mezclan con los objetos (ya ordenados).
    local n = 0
    local ds = G.EnemyMgr.drawables(cam)
    for i = 1, #ds do n = n + 1; ents[n] = ds[i] end
    for i = 1, #extra do n = n + 1; ents[n] = extra[i] end
    local rift = G.Rift.drawable()
    if rift then n = n + 1; ents[n] = rift end
    local arceus = (pl and state ~= "ui") and G.Judgment.drawable() or nil
    if arceus then n = n + 1; ents[n] = arceus end
    if pl and state ~= "ui" then
        local evs = G.Events.drawables()
        for i = 1, #evs do n = n + 1; ents[n] = evs[i] end
    end
    for i = #ents, n + 1, -1 do ents[i] = nil end
    if n > 1 then table.sort(ents, byY) end
    -- Reflejos en el agua (debajo de todo): quien pisa agua con agua también debajo.
    if World.reflects() then
        for i = 1, n do
            local e = ents[i]
            if e.anim and not e.flying and not e.dead
               and World.isLiquid(e.x, e.y) and World.isLiquid(e.x, e.y + 24) then
                e.anim:draw(e.x, e.y, reflOpts)
            end
        end
    end
    local np = #props
    local i, j = 1, 1
    while i <= np or j <= n do
        if j > n or (i <= np and props[i]._sy < ents[j].y) then
            World.drawProp(props[i], t); i = i + 1
        else
            ents[j]:draw(); j = j + 1
        end
    end
end

local extraOne = {}
function Game.render()
    if pl and state ~= "ui" then
        G.Camera.apply()
        extraOne[1] = pl
        drawScene(G.Camera, extraOne)
        G.Projectiles.draw()
        G.Combat.drawAirFields()
        G.FX.draw()
        G.Judgment.drawAir()
        G.Camera.unapply()
        G.Weather.draw(400, 240, frameDt)
        G.World.drawVignette(400, 240)
        if flashT > 0 then
            U.setColor(flashCol, math.min(1, flashT / flashDur * 1.4))
            love.graphics.rectangle("fill", 0, 0, 400, 240)
            love.graphics.setColor(1, 1, 1, 1)
        end
    else
        Game.Backdrop.render()
    end
end

-- ---------------- fondo de los menús ----------------

-- El mundo de verdad, con Pokémon salvajes paseando y la cámara a la deriva.
local Backdrop = {}
Game.Backdrop = Backdrop
local wanderers, bt, ready, biomeT, bi = {}, 0, false, 0, 0
local CAST = { 1, 4, 7, 25, 133, 52, 39, 35, 16, 43, 60, 69, 74, 92, 129, 147, 113, 143, 54, 79 }

local Wanderer = {}
Wanderer.__index = Wanderer
function Wanderer:draw()
    G.Sprites.drawShadow(self.dex, self.x, self.y)
    self.anim:draw(self.x, self.y)
end

local function spawnWanderer(dex, anywhere)
    local w = setmetatable({}, Wanderer)
    w.dex = dex
    w.anim = G.Sprites.Animator.new(dex, 1)
    w.r = G.Sprites.bodyRadius(dex)
    local x, y = 0, 0
    for i = 1, 20 do
        x = G.Camera.x + U.rand(-1, 1) * (anywhere and G.Camera.w * 0.6 or G.Camera.w * 0.7)
        y = G.Camera.y + U.rand(-1, 1) * (anywhere and G.Camera.h * 0.6 or G.Camera.h * 0.7)
        if G.World.isFree(x, y, w.r) then break end
    end
    w.x, w.y, w.vx, w.vy, w.t = x, y, 0, 0, 0
    return w
end

-- Los paseantes aparecen de uno en uno (uno por fotograma, ver Backdrop.step): en
-- la consola cada hoja de sprites tarda ~40 ms en cargarse y cargar las 20 de golpe
-- era casi un segundo parado al arrancar y al volver de una partida.
local castN = 0                 -- paseantes ya creados
local oneDex = {}               -- (lista reutilizada para Sprites.preload)

function Backdrop.init()
    G.World.reset(4242)
    G.World.setBiome(0, true)
    G.Camera.x = 0; G.Camera.y = 0
    wanderers = {}
    castN = 0
    ready = true
end

function Backdrop.step(dt)
    if not ready then return end
    if castN < #CAST then
        castN = castN + 1
        oneDex[1] = CAST[castN]
        G.Sprites.preload(oneDex, false)
        wanderers[castN] = spawnWanderer(CAST[castN], true)
    end
    bt = bt + dt
    G.World.update(dt, G.Camera)
    -- Deriva lenta de la cámara.
    G.Camera.x = G.Camera.x + math.cos(bt * 0.05) * 14 * dt
    G.Camera.y = G.Camera.y + math.sin(bt * 0.037) * 10 * dt
    G.Camera.follow(G.Camera.x, G.Camera.y, dt)

    biomeT = biomeT + dt
    if biomeT > 30 then biomeT = 0; bi = (bi + 1) % 3; G.World.setBiome(bi) end

    for i = 1, #wanderers do
        local wd = wanderers[i]
        wd.t = wd.t - dt
        if wd.t <= 0 then
            -- Pasea, se para o "ataca" al aire de vez en cuando.
            wd.t = U.rand(1, 3.5)
            local r = love.math.random()
            if r < 0.55 then
                local a, s = love.math.random() * 6.2832, U.rand(25, 55)
                wd.vx = math.cos(a) * s; wd.vy = math.sin(a) * s
            else
                wd.vx, wd.vy = 0, 0
                if r > 0.85 then wd.anim:play("Attack") end
            end
        end
        wd.x = wd.x + wd.vx * dt; wd.y = wd.y + wd.vy * dt
        G.World.collide(wd)
        local moving = math.abs(wd.vx) + math.abs(wd.vy) > 1
        if moving then wd.anim.dir = G.Sprites.dirFromAngle(math.atan2(wd.vy, wd.vx)) end
        wd.anim:loop(moving and "Walk" or "Idle")
        wd.anim:update(dt)
        -- Si se queda fuera de cámara, reaparece dentro.
        if not G.Camera.sees(wd.x, wd.y, 120) then
            local nw = spawnWanderer(wd.dex, false)
            wd.x, wd.y, wd.vx, wd.vy, wd.t = nw.x, nw.y, 0, 0, 0
        end
    end
end

function Backdrop.render()
    if not ready then return end
    G.Camera.apply()
    drawScene(G.Camera, wanderers)
    G.Camera.unapply()
    G.World.drawVignette(400, 240)
end

-- Al volver de una run, recupera el mundo del menú.
function Backdrop.restore()
    G.World.reset(4242)
    G.World.setBiome(bi, true)
    G.FX.clear(); G.Projectiles.clear(); G.Combat.clearFields(); G.EnemyMgr.clear(); G.Pickups.clear()
    G.Sprites.gc({})
    wanderers = {}
    castN = 0                   -- (vuelven a aparecer poco a poco, ver Backdrop.step)
end

function Game.toUI()
    state = "ui"
    G.Stages.stop()
    Backdrop.restore()
end

function Game.wanderers() return wanderers end

-- ============ Flow — transiciones entre pantallas ============
G.Flow = {}

function G.Flow.boot()
    G.DB.load()
    G.Progress.ensure(G.DB.save)
    Backdrop.init()
    G.Audio.music("village")
    G.UI.show("title")
end

function G.Flow.afterTitle()
    if not G.DB.save.partner then G.TestUI.start() else G.Flow.goMenu() end
end

function G.Flow.goMenu()
    if state ~= "ui" then Game.toUI() end
    G.Audio.music("village")
    G.MenuUI.open()
end

function G.Flow.afterRun()
    G.Flow.goMenu()
end

function G.Flow.play()
    Game.startRun()
end

function G.Flow.playStage(i)
    Game.startRun(i)
end

-- Prueba de resistencia: elige cartas/objetos/vínculos solo y reanuda pausas.
local autoT = 0
function Game.autoplay(dt)
    -- Invulnerable: lo que se prueba es la lógica, no la habilidad del autómata.
    -- (En el modo demostración, no: se juega de verdad.)
    if not Game.demo then
        if pl and not pl.god then pl.god = true; pl.hurt = function() end end
        if pl and not pl.dead then pl.hp = pl.maxHp end
    end
    autoT = autoT + dt
    if autoT < 0.3 then return end
    autoT = 0
    local scr = G.UI.current()
    if scr == "cards" then G.UI.pressButton("a")
    elseif scr == "pause" then Game.togglePause()
    elseif state == "playing" and pl and pl.bonds > 0 then Game.offerBond(true)
    elseif state == "playing" and not G.Judgment.cinematic() and G.Burst.ready(pl) then G.Burst.fire(pl) end
end

-- Depuración: fuerza una subida de nivel o la caída del jugador.
function Game.debugLevelUp()
    if pl then pl.level = pl.level + 1; pendingLevels = pendingLevels + 1 end
end
function Game.debugDie()
    if pl then pl.invuln = 0; pl:hurt(99999) end
end
function Game.debugSetLevel(n)
    if pl then pl.level = n; pl.xpNext = G.Player.xpFor(n) end
end
function Game.debugTime(t) time = t end

-- Prueba de humo / F1: empieza una run con el compañero (o Pikachu) sin pasar por menús.
function G.Flow.debugStartRun(stageIdx)
    if state ~= "ui" then return end
    local s = G.DB.save
    if not s.partner then s.partner = 25; G.DB.grant(25, "debug") end
    Game.startRun(stageIdx)
end
