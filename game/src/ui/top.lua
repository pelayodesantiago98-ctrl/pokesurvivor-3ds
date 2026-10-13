-- top.lua — superposiciones de la PANTALLA SUPERIOR (400x240), en coordenadas de
-- pantalla, encima del mundo: barra de XP, vida, reloj, jefe, avisos, flechas a
-- shinies y a la grieta. Fuera de la run, `TopUI.overlay` (función) la pone la
-- interfaz (ficha de la Pokédex, resultado del gacha...).
local U = G.U
local T = {}
G.TopUI = T

T.overlay = nil
local lg = love.graphics
local W, H = 400, 240

local function font(size) return G.UI.font(size) end

local function arrowTo(sx, sy, col, label)
    -- Flecha en el borde hacia un punto fuera de la vista.
    local M = 18
    local ex, ey = U.clamp(sx, M, W - M), U.clamp(sy, M + 30, H - M - 20)
    local a = math.atan2(sy - ey, sx - ex)
    U.setColor(col)
    lg.polygon("fill", ex + math.cos(a) * 14, ey + math.sin(a) * 14,
               ex + math.cos(a + 2.5) * 7, ey + math.sin(a + 2.5) * 7,
               ex + math.cos(a - 2.5) * 7, ey + math.sin(a - 2.5) * 7)
    if label then
        lg.setFont(font(10))
        local tw = font(10):getWidth(label)
        local lx = ex - math.cos(a) * 20 - tw / 2
        local ly = ey - math.sin(a) * 18 - 5
        U.setColor("#000000", 0.7)
        lg.rectangle("fill", lx - 2, ly - 1, tw + 4, 12)
        U.setColor(col)
        lg.print(label, lx, ly)
    end
    lg.setColor(1, 1, 1, 1)
end

local function drawRun(pl)
    local st = G.Game.state()
    -- La Sentencia de Arceus: durante la animación sólo se ve ella.
    if G.Judgment.cinematic() then G.Judgment.drawHud(W, H, pl, nil) lg.setColor(1, 1, 1, 1) return end
    -- Barra de experiencia (borde superior)
    local xpF = pl.xp / pl.xpNext
    lg.setColor(0, 0, 0, 0.5)
    lg.rectangle("fill", 0, 0, W, 4)
    U.setColor("#4fd1ff")
    lg.rectangle("fill", 0, 0, W * U.clamp(xpF, 0, 1), 4)

    -- Solo el reloj arriba: nombre, nivel, vida, derrotados y monedas van en la
    -- pantalla de abajo; el nombre de la zona sale en su cartel al entrar.
    lg.setFont(font(16))
    U.setColor("#000000", 0.6)
    lg.printf(U.mmss(G.Game.time()), 1, 7, W, "center")
    U.setColor("#ffffff", 0.95)
    lg.printf(U.mmss(G.Game.time()), 0, 6, W, "center")

    -- Clima (arriba a la derecha)
    local wx = G.Weather.current and G.Weather.current()
    if wx then
        lg.setFont(font(10))
        local txt = string.upper(wx.name or "") .. " · " .. math.ceil(wx.left or 0) .. "s"
        local tw = font(10):getWidth(txt) + 8
        U.setColor("#000000", 0.55)
        lg.rectangle("fill", W - tw - 6, 6, tw, 14, 4, 4)
        U.setColor(wx.color or "#ffffff")
        lg.print(txt, W - tw - 2, 7)
    end

    -- Barra del jefe
    local boss = nil
    local all = G.EnemyMgr.all()
    for i = 1, #all do if all[i].boss and not all[i].dead then boss = all[i] break end end
    if boss then
        G.UI.bar((W - 220) / 2, 38, 220, 8, boss.hp / boss.maxHp, "#ffcb3d")
        lg.setFont(font(10))
        U.setColor("#ffe9a0")
        lg.printf(string.upper(boss.name), 0, 46, W, "center")
    end

    -- Shinies fuera de pantalla
    local cam = G.Camera
    local sh = G.EnemyMgr.shinies()
    for i = 1, #sh do
        local e = sh[i]
        local sx, sy = cam.toScreen(e.x, e.y)
        if not (sx > 0 and sx < W and sy > 0 and sy < H) then arrowTo(sx, sy, "#9ae6ff", "SHINY") end
    end

    -- Poder de altar activo
    if pl.power then
        lg.setFont(font(10))
        U.setColor(pl.power.def.color or "#ffffff")
        lg.print(string.upper(pl.power.def.name or "") .. " " .. math.ceil(pl.power.t) .. "s", 6, 32)
    end

    -- Grieta: flecha si no se ve; encima, flecha que bota; en la arena, cuenta atrás.
    if G.Rift.arrow then
        local rx, ry, dist, ttl = G.Rift.arrow()
        if rx then
            local sx, sy = cam.toScreen(rx, ry - 40)
            local now = U.now()
            local beat = 0.5 + math.sin(now * 7) * 0.5
            local col = beat > 0.5 and "#e2d0ff" or "#a06bff"
            if sx < 0 or sx > W or sy < 0 or sy > H then
                arrowTo(sx, sy, col, "GRIETA · " .. U.round(dist / 32) .. " m · " .. math.ceil(ttl) .. " s")
            else
                local by = sy - 20 - math.abs(math.sin(now * 4)) * 5
                U.setColor(col)
                lg.polygon("fill", sx - 7, by - 6, sx + 7, by - 6, sx, by + 4)
                lg.setFont(font(10))
                lg.printf("GRIETA · " .. math.ceil(ttl) .. " s", sx - 60, by - 18, 120, "center")
            end
        end
    end
    if G.Rift.inArena() then
        lg.setFont(font(10))
        U.setColor("#d9c2ff")
        lg.printf("GRIETA · " .. U.mmss(G.Rift.timeLeft and G.Rift.timeLeft() or 0), 0, boss and 58 or 40, W, "center")
    end

    -- La Sentencia de Arceus: ceniza, contador y flecha hacia él.
    if G.Judgment.active() then G.Judgment.drawHud(W, H, pl, boss) end

    -- Eventos (cuenta atrás, flechas)
    if G.Events.drawHud then G.Events.drawHud(W, H, pl) end

    -- Cartel de zona: entra, se queda y se desvanece
    local zt, left, dur = G.Spawner.zone()
    if zt then
        local a = math.min(1, (dur - left) * 4, left * 2)
        G.PixelFont.zoneSign(zt, W / 2, 40, a, 2)
    end

    -- Aviso grande
    local ban = G.Spawner.banner()
    if ban then
        local a = math.min(1, ban.t * 1.6)
        lg.setFont(font(16))
        U.setColor("#000000", 0.7 * a)
        lg.printf(ban.text, 1, H * 0.3 + 1, W, "center")
        U.setColor("#ffcb3d", a)
        lg.printf(ban.text, 0, H * 0.3, W, "center")
    end

    if st == "paused" then
        lg.setColor(0, 0, 0, 0.5)
        lg.rectangle("fill", 0, 0, W, H)
        lg.setFont(font(22))
        U.setColor("#ffffff")
        lg.printf("PAUSA", 0, H / 2 - 14, W, "center")
    end
    lg.setColor(1, 1, 1, 1)
end

function T.draw()
    local pl = G.Game.player()
    local st = G.Game.state()
    if pl and st ~= "ui" then
        drawRun(pl)
    elseif T.overlay then
        T.overlay()
    end
    lg.setFont(font(12))
    lg.setColor(1, 1, 1, 1)
end

-- Ficha grande de un Pokémon sobre el fondo (Pokédex, resultado del test, gacha).
function T.pokemonCard(dex, opts)
    local p = G.DEX_BY[dex]
    if not p then return end
    local own = not opts or opts.own ~= false
    local shiny = opts and opts.shiny
    local col = shiny and "#9ae6ff" or (own and U.TYPE_COLOR[p.types[1]] or "#5b83d6")
    lg.setColor(0, 0, 0, 0.5)
    lg.rectangle("fill", 0, 0, W, H)
    -- Panel oscuro detrás de los datos (antes iban sobre el mapa y no se leían).
    U.setColor("#0a1430", 0.9)
    lg.rectangle("fill", 180, 28, 212, 176, 6, 6)
    U.setColor("#3a5a9a")
    lg.rectangle("line", 180.5, 28.5, 211, 175, 6, 6)
    G.UI.stage(20, 30, 150, 170, col)
    local anim = G.UI.menuAnim(dex, 3, shiny)
    if own then
        anim:draw(95, 180, nil)
    else
        lg.setColor(0.1, 0.1, 0.2, 1)
        anim:draw(95, 180, { alpha = 0.001 })
        lg.setFont(font(22))
        U.setColor("#5b83d6")
        lg.printf("?", 20, 100, 150, "center")
    end
    lg.setFont(font(10))
    U.setColor("#8fa3c4")
    lg.print("Nº " .. G.UI.pad3(p.dex) .. " · " .. (G.UI.GEN_NAMES[p.gen] or ""), 190, 34)
    lg.setFont(font(22))
    U.setColor("#ffffff")
    lg.print(own and p.name or "???", 190, 46)
    G.UI.stars(p.rarity, 190, 76, 10)
    if own then
        G.UI.typeChips(p.types, 190, 92, 10)
        local max = { hp = 183, atk = 1.55, spd = 137 }
        local function bar(label, v, m, txt, y)
            lg.setFont(font(10))
            U.setColor("#eaf2ff")
            lg.print(label, 190, y)
            G.UI.bar(250, y + 3, 92, 6, v / m, "#4fd1ff")
            U.setColor("#ffffff")
            lg.printf(txt, 344, y, 42, "right")
        end
        bar("Vida", p.hp, max.hp, tostring(p.hp), 116)
        bar("Ataque", p.atk, max.atk, string.format("x%.2f", p.atk), 132)
        bar("Velocidad", p.spd, max.spd, tostring(p.spd), 148)
        local sm = G.Moves.BY_ID[G.startMoveOf(dex)]
        lg.setFont(font(10))
        U.setColor("#eaf2ff")
        lg.print("Empieza con ", 190, 168)
        U.setColor("#ffd23f")
        lg.print(sm and sm.name or "?", 190 + font(10):getWidth("Empieza con "), 168)
        -- Movimientos que puede aprender
        local pool = G.Moves.poolFor(p)
        local x = 190
        for i, id in ipairs(pool) do
            if i > 12 then break end
            G.Icons.draw("move:" .. id, x, 184, 14)
            x = x + 16
        end
        lg.setColor(1, 1, 1, 1)
    else
        lg.setFont(font(10))
        U.setColor("#8fa3c4")
        lg.printf("Aún no lo tienes. Consíguelo en el banner de " .. (G.UI.GEN_NAMES[p.gen] or "") .. " o derrotándolo cuando salga shiny.", 190, 100, 190, "left")
    end
    if opts and opts.footer then
        lg.setFont(font(10))
        local fw = font(10):getWidth(opts.footer) + 16
        U.setColor("#0a1430", 0.85)
        lg.rectangle("fill", (W - fw) / 2, H - 23, fw, 16, 4, 4)
        U.setColor("#ffd23f")
        lg.printf(opts.footer, 0, H - 20, W, "center")
    end
    lg.setColor(1, 1, 1, 1)
end
