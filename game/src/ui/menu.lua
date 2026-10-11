-- menu.lua — título, menú principal, colección (Pokédex), mejoras, gacha y misiones.
-- Pantalla inferior: botones y rejillas. Superior: el mundo de fondo y fichas.
local U = G.U
local UI = G.UI
local M = {}
G.MenuUI = M

local lg = love.graphics
local W, H = UI.W, UI.H
local GEN = UI.GEN_NAMES

local function coinsLine()
    local s = G.DB.save
    local t = s.tickets or { t1 = 0, t10 = 0 }
    local txt = s.coins .. " monedas   ·   " .. (t.t1 or 0) .. " tickets   ·   " .. (t.t10 or 0) .. " tickets x10"
    local tw = UI.font(10):getWidth(txt)
    G.Icons.draw("coin", (W - tw) / 2 - 15, H - 15, 12)           -- icono de moneda delante
    UI.text(txt, 0, H - 14, { size = 10, color = UI.C.gold, w = W, align = "center" })
end

-- ---------------- título ----------------
local title = {}
function title.draw()
    UI.text("PokéSurvivor", 0, 60, { size = 22, color = UI.C.gold, w = W, align = "center" })
    UI.text("Mundo Misterioso", 0, 90, { size = 16, w = W, align = "center" })
    UI.text("Sobrevive a las hordas con tu compañero Pokémon", 0, 116, { size = 10, color = UI.C.muted, w = W, align = "center" })
    if math.floor(U.now() * 2) % 2 == 0 then
        UI.text("Pulsa A o toca la pantalla", 0, 170, { size = 12, w = W, align = "center" })
    end
    UI.hitbox("go", 0, 0, W, H)
    UI.text("Sprites: SpriteCollab (CC BY-NC 4.0) · Pokémon (c) Nintendo/GAME FREAK · Fan game sin ánimo de lucro",
            6, H - 24, { size = 10, color = UI.C.muted, w = W - 12, align = "center" })
end
function title.touch(x, y) if UI.hit(x, y) then G.Flow.afterTitle() end end
function title.button(b) if b == "a" or b == "start" then G.Flow.afterTitle() end end
UI.register("title", title)

-- ---------------- menú principal ----------------
local menu = {}
local focus = 1
-- Menú principal al estilo de los menús táctiles de HeartGold/SoulSilver y
-- Negro/Blanco: barra arriba, 8 botones grandes de colores con su icono de objeto
-- en un círculo claro, nombre y descripción, y barra abajo. El compañero se ve
-- arriba (pantalla superior), como en la DS.
local ITEMS = {
    { id = "play", label = "Jugar", sub = "Arena infinita", color = "#d04848" },
    { id = "stages", label = "Fases", sub = "8 fases y jefes", color = "#e08838" },
    { id = "dex", label = "Pokédex", sub = "Tu colección", color = "#3c9c54" },
    { id = "upgrades", label = "Mejoras", sub = "Más fuerte en cada run", color = "#8c58c0" },
    { id = "gacha", label = "Gacha", sub = "9 regiones", color = "#c8a024" },
    { id = "goals", label = "Misiones", sub = "Misiones y logros", color = "#2e94b4" },
    { id = "card", label = "Tarjeta", sub = "Tu tarjeta", color = "#4870c8" },
    { id = "starters", label = "Inicial", sub = "Cambiar de inicial", color = "#d0608c" },
}
local menuIcons = {}
local function menuIcon(id)
    local im = menuIcons[id]
    if im == nil then
        local ok, r = pcall(lg.newImage, U.img('img/menu/' .. id))
        im = ok and r or false
        if im and im.setFilter then pcall(im.setFilter, im, 'nearest', 'nearest') end
        menuIcons[id] = im
    end
    return im or nil
end
-- Texto blanco con sombra oscura (como en los botones de DS). En una sola línea:
-- si no cabe en `w`, baja de tamaño (hasta 8).
local function dsText(str, x, y, size, w, col, ink)
    w = w or (W - x)
    while size > 8 and UI.font(size):getWidth(str) > w do size = size - 1 end
    lg.setFont(UI.font(size))
    U.setColor(ink or "#000000", 0.55)
    lg.printf(str, x + 1, y + 1, w, "left")
    U.setColor(col or "#ffffff")
    lg.printf(str, x, y, w, "left")
    lg.setColor(1, 1, 1, 1)
end
function menu.enter()
    G.Progress.checkAch()
    local s = G.DB.save
    G.Sprites.preload({ s.partner }, false)
    -- Arriba, la ficha del compañero (la información va arriba y el menú abajo).
    G.TopUI.overlay = function()
        local sh = s.partnerShiny and G.DB.ownsShiny(s.partner)
        G.TopUI.pokemonCard(s.partner, { own = true, shiny = sh, footer = "Tu compañero" })
    end
end
function menu.draw()
    local s = G.DB.save
    -- Barra de arriba: título y monedas
    UI.bar2(0, 22)
    dsText("MENÚ", 8, 4, 12)
    -- Monedas con su icono delante
    local coins = s.coins .. " monedas"
    local cw = UI.font(12):getWidth(coins)
    G.Icons.draw("coin", W - 8 - cw - 16, 5, 12)
    dsText(coins, W - 8 - cw, 4, 12, cw + 2, UI.C.gold)
    local pend = G.Progress.pending()
    -- Botones grandes
    for i, it in ipairs(ITEMS) do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local x, y, bw, bh = 6 + col * 157, 27 + row * 47, 151, 43
        UI.button(it.id, x, y, bw, bh, "", { color = it.color, on = focus == i })
        -- Icono en un cuadrado claro redondeado (como los iconos de HGSS), centrado
        local sx, sy, ss = x + 6, y + 6, 31
        U.setColor(U.shade(it.color, -0.5))
        lg.rectangle("fill", sx - 1, sy - 1, ss + 2, ss + 2, 6, 6)
        U.setColor("#ffffff", 0.92)
        lg.rectangle("fill", sx, sy, ss, ss, 5, 5)
        lg.setColor(1, 1, 1, 1)
        local im = menuIcon(it.id)
        if im then
            lg.draw(im, sx + math.floor((ss - im:getWidth()) / 2), sy + math.floor((ss - im:getHeight()) / 2))
        end
        -- Nombre y descripción, cada uno en una línea
        local sub = it.sub
        if it.id == "goals" and pend > 0 then sub = pend .. " premios" end
        local tx, tw = x + 44, bw - 50
        dsText(it.label, tx, y + 7, 12, tw)
        dsText(sub, tx, y + 24, 10, tw, (it.id == "goals" and pend > 0) and "#fff2a0" or "#f0f4ff")
    end
    -- Barra de abajo: tickets
    UI.bar2(H - 20, 20)
    local t = s.tickets or { t1 = 0, t10 = 0 }
    local txt = (t.t1 or 0) .. " tickets   ·   " .. (t.t10 or 0) .. " tickets x10   ·   Pokédex " .. U.count(s.owned) .. "/" .. #G.DEX
    local tw = UI.font(10):getWidth(txt)
    G.Icons.draw("ticket", (W - tw) / 2 - 15, H - 16, 12)
    UI.text(txt, 0, H - 15, { size = 10, color = UI.C.gold, w = W, align = "center" })
end
local function go(id)
    G.Audio.sfx(id == "play" and "confirm" or "click")
    if id == "play" then G.Flow.play()
    elseif id == "stages" then UI.show("stages")
    elseif id == "card" then UI.show("card")
    elseif id == "dex" then UI.show("dex")
    elseif id == "upgrades" then UI.show("upgrades")
    elseif id == "gacha" then UI.show("gacha")
    elseif id == "goals" then UI.show("goals")
    elseif id == "starters" then UI.show("starters") end
end
function menu.touch(x, y)
    local id = UI.hit(x, y)
    if id then go(id) end
end
function menu.button(b)
    if b == "dpdown" then focus = (focus + 1 <= #ITEMS) and focus + 2 or focus; if focus > #ITEMS then focus = focus - 2 end
    elseif b == "dpup" then focus = math.max(1, focus - 2)
    elseif b == "dpright" then focus = math.min(#ITEMS, focus + 1)
    elseif b == "dpleft" then focus = math.max(1, focus - 1)
    elseif b == "a" or b == "start" then go(ITEMS[focus].id) end
end
UI.register("menu", menu)

function M.open() UI.show("menu") end

-- ---------------- Pokédex / colección ----------------
local dex = {}
local dexGen, dexPage, dexSel, dexFilter = 1, 1, nil, "all"
local COLS, ROWS, CW, CH = 6, 3, 48, 46
local PER = COLS * ROWS
local dexList = {}

local function rebuildList()
    local s = G.DB.save
    dexList = {}
    for _, p in ipairs(G.DEX) do
        if p.gen == dexGen then
            local own = s.owned[p.dex] ~= nil
            local ok = dexFilter == "all" or (dexFilter == "own" and own) or (dexFilter == "miss" and not own)
            if ok then dexList[#dexList + 1] = p end
        end
    end
    local pages = math.max(1, math.ceil(#dexList / PER))
    if dexPage > pages then dexPage = pages end
end

local function selectDex(d)
    dexSel = d
    local s = G.DB.save
    local own = s.owned[d] ~= nil
    G.Sprites.preload({ d }, false)
    local shiny = s.shiny and s.shiny[d] ~= nil and d == s.partner and s.partnerShiny
    G.TopUI.overlay = function()
        G.TopUI.pokemonCard(d, { own = own, shiny = shiny, footer = own and (d == s.partner and "Es tu compañero" or "Toca ELEGIR para que sea tu compañero") or nil })
    end
end

function dex.enter()
    local s = G.DB.save
    if not dexSel then dexSel = s.partner; dexGen = G.DEX_BY[s.partner].gen end
    rebuildList()
    selectDex(dexSel)
end
function dex.draw()
    local s = G.DB.save
    -- Pestañas de generación
    for g = 1, 9 do
        local x = 2 + (g - 1) * 35
        UI.button("gen" .. g, x, 2, 33, 16, GEN[g]:sub(1, 5), { size = 10, on = g == dexGen })
    end
    -- Filtros
    local FX = { { "all", "Todos" }, { "own", "Tengo" }, { "miss", "Faltan" } }
    for i, f in ipairs(FX) do
        UI.button("f" .. f[1], 2 + (i - 1) * 50, 21, 48, 14, f[2], { size = 10, on = dexFilter == f[1] })
    end
    local owned = U.count(s.owned)
    UI.text(owned .. " / " .. #G.DEX, 160, 22, { size = 10, color = UI.C.muted, w = 156, align = "right" })
    -- Rejilla
    local start = (dexPage - 1) * PER
    for i = 1, PER do
        local p = dexList[start + i]
        if not p then break end
        local c, r = (i - 1) % COLS, math.floor((i - 1) / COLS)
        local x, y = 14 + c * CW, 38 + r * CH
        local own = s.owned[p.dex] ~= nil
        local on = p.dex == dexSel
        U.setColor(on and "#2a3a1a" or (own and UI.C.panel or "#0d1630"))
        lg.rectangle("fill", x, y, CW - 2, CH - 2, 4, 4)
        if on then U.setColor(UI.C.gold); lg.rectangle("line", x + 0.5, y + 0.5, CW - 3, CH - 3, 4, 4) end
        lg.setColor(1, 1, 1, 1)
        if own then
            G.Sprites.drawStill(p.dex, x + CW / 2 - 1, y + CH - 12, 0.5)
        else
            lg.setColor(0.15, 0.18, 0.3, 1)
            G.Sprites.drawStill(p.dex, x + CW / 2 - 1, y + CH - 12, 0.5)
            lg.setColor(1, 1, 1, 1)
        end
        UI.text(UI.pad3(p.dex), x + 2, y + 1, { size = 10, color = UI.C.muted })
        if p.dex == s.partner then G.Icons.draw("crown", x + CW - 16, y + 2, 12)
        elseif s.shiny and s.shiny[p.dex] then G.Icons.draw("shiny", x + CW - 16, y + 2, 12) end
        UI.text(own and p.name or "???", x, y + CH - 12, { size = 10, w = CW - 2, align = "center" })
        UI.hitbox("d" .. (start + i), x, y, CW - 2, CH - 2)
    end
    local pages = math.max(1, math.ceil(#dexList / PER))
    UI.button("prev", 14, 180, 40, 18, "<", { size = 10, enabled = dexPage > 1 })
    UI.text(dexPage .. " / " .. pages, 58, 183, { size = 10, color = UI.C.muted, w = 60, align = "center" })
    UI.button("next", 122, 180, 40, 18, ">", { size = 10, enabled = dexPage < pages })
    local sel = dexSel and G.DEX_BY[dexSel]
    local hasSh = dexSel and G.DB.ownsShiny(dexSel)
    local canPick = sel and s.owned[dexSel] and (dexSel ~= s.partner or (hasSh and s.partnerShiny))
    UI.button("pick", 170, 180, 136, 18, "Elegir de compañero", { size = 10, color = "#1b3a2a", enabled = canPick == true })
    UI.button("back", 14, 206, 100, 20, "Volver", { size = 10 })
    if hasSh then
        local isShinyPartner = dexSel == s.partner and s.partnerShiny
        UI.button("pickshiny", 170, 204, 136, 18, isShinyPartner and "Compañero shiny *" or "Elegir shiny *",
                  { size = 10, color = "#1a2a3a", enabled = not isShinyPartner })
    end
    coinsLine()
end
function dex.touch(x, y)
    local id = UI.hit(x, y)
    if not id then return end
    if id == "back" then UI.show("menu") return end
    if id == "prev" then dexPage = dexPage - 1 return end
    if id == "next" then dexPage = dexPage + 1 return end
    if id == "pick" or id == "pickshiny" then
        local s = G.DB.save
        s.partner = dexSel; s.partnerShiny = (id == "pickshiny")
        G.DB.commit()
        UI.toast(G.DEX_BY[dexSel].name .. (s.partnerShiny and " shiny" or "") .. " es ahora tu compañero")
        selectDex(dexSel)
        return
    end
    local g = tonumber(id:match("^gen(%d+)$"))
    if g then dexGen = g; dexPage = 1; rebuildList() return end
    local f = id:match("^f(%a+)$")
    if f then dexFilter = f; dexPage = 1; rebuildList() return end
    local i = tonumber(id:match("^d(%d+)$"))
    if i and dexList[i] then selectDex(dexList[i].dex); G.Audio.sfx("select") end
end
function dex.button(b)
    if b == "b" then UI.show("menu")
    elseif b == "rightshoulder" then dexGen = dexGen % 9 + 1; dexPage = 1; rebuildList()
    elseif b == "leftshoulder" then dexGen = (dexGen - 2) % 9 + 1; dexPage = 1; rebuildList()
    elseif b == "dpright" or b == "dpleft" or b == "dpup" or b == "dpdown" then
        local i = 1
        for k, p in ipairs(dexList) do if p.dex == dexSel then i = k end end
        if b == "dpright" then i = i + 1 elseif b == "dpleft" then i = i - 1
        elseif b == "dpdown" then i = i + COLS else i = i - COLS end
        if i >= 1 and i <= #dexList then
            selectDex(dexList[i].dex)
            dexPage = math.floor((i - 1) / PER) + 1
        end
    elseif b == "a" then dex.touch(-1, -1) end
end
UI.register("dex", dex)

-- ---------------- mejoras ----------------
local upg = {}
local upgDex = nil
local upgList = {}
function upg.enter()
    local s = G.DB.save
    upgList = {}
    for d in pairs(s.owned) do if G.DEX_BY[d] then upgList[#upgList + 1] = d end end
    table.sort(upgList, function(a, b)
        if (a == s.partner) ~= (b == s.partner) then return a == s.partner end
        return a < b
    end)
    if not upgDex or not s.owned[upgDex] then upgDex = s.partner end
    G.Sprites.preload({ upgDex }, false)
    G.TopUI.overlay = function() G.TopUI.pokemonCard(upgDex, { footer = "Las mejoras son de cada Pokémon: solo cuentan cuando juegas con él" }) end
end
function upg.draw()
    local s = G.DB.save
    local levels = G.DB.upgradesOf(upgDex)
    local mon = G.DEX_BY[upgDex]
    UI.button("prevmon", 4, 4, 22, 18, "<", { size = 10 })
    UI.text(mon.name .. (upgDex == s.partner and " (compañero)" or ""), 28, 7, { size = 12, w = 180, align = "center" })
    UI.button("nextmon", 210, 4, 22, 18, ">", { size = 10 })
    UI.text(s.coins .. " monedas", 236, 7, { size = 10, color = UI.C.gold, w = 80, align = "right" })
    for i, u in ipairs(G.Upgrades.LIST) do
        local y = 26 + (i - 1) * 19
        local lvl = levels[u.id] or 0
        local maxed = lvl >= u.max
        local cost = maxed and 0 or G.Upgrades.cost(u.id, lvl)
        G.Icons.draw(u.icon, 6, y + 2, 14)
        UI.text(u.name, 24, y + 2, { size = 10 })
        UI.text(u.unit, 90, y + 2, { size = 10, color = UI.C.muted })
        for k = 1, u.max do
            U.setColor(k <= lvl and UI.C.gold or "#2a3350")
            lg.rectangle("fill", 196 + (k - 1) * 6, y + 5, 4, 8)
        end
        lg.setColor(1, 1, 1, 1)
        local can = not maxed and s.coins >= cost
        UI.button("buy" .. i, 262, y, 54, 16, maxed and "Máx." or tostring(cost), { size = 10, color = can and "#2a2410" or nil, enabled = can,
                  textColor = can and UI.C.gold or nil })
    end
    UI.button("back", 110, 218, 100, 18, "Volver", { size = 10 })
end
function upg.touch(x, y)
    local id = UI.hit(x, y)
    if not id then return end
    if id == "back" then UI.show("menu") return end
    local k = U.indexOf(upgList, upgDex) or 1
    if id == "prevmon" then upgDex = upgList[(k - 2) % #upgList + 1]; upg.enter() return end
    if id == "nextmon" then upgDex = upgList[k % #upgList + 1]; upg.enter() return end
    local i = tonumber(id:match("^buy(%d+)$"))
    if i then
        local u = G.Upgrades.LIST[i]
        if G.DB.buyUpgrade(upgDex, u.id) then
            G.Audio.sfx("buy")
            UI.toast(G.DEX_BY[upgDex].name .. " · " .. u.name .. ": nivel " .. (G.DB.upgradesOf(upgDex)[u.id] or 0))
        end
    end
end
function upg.button(b)
    if b == "b" then UI.show("menu")
    elseif b == "leftshoulder" then upg.touch(5, 5)
    elseif b == "rightshoulder" then upg.touch(211, 5) end
end
UI.register("upgrades", upg)

-- ---------------- gacha ----------------
local gacha = {}
local gGen, gResults, gIdx = 1, {}, 0
function gacha.enter()
    gResults = {}
    G.TopUI.overlay = function()
        if #gResults > 0 and gIdx >= 1 then
            local r = gResults[gIdx]
            local p = G.DEX_BY[r.dex]
            G.TopUI.pokemonCard(r.dex, { shiny = r.shiny, footer = (r.shiny and "¡SHINY! " or "") .. (r.isNew and "¡Nuevo!" or ("Repetido: +" .. (r.coins or 0) .. " monedas")) .. "  (" .. gIdx .. "/" .. #gResults .. ")" })
        else
            UI.text("Banner de " .. GEN[gGen], 0, 100, { size = 22, color = UI.C.gold, w = 400, align = "center" })
            local b = G.Gacha.banner and G.Gacha.banner(gGen)
            if b and b.featured then
                local names = {}
                for i, d in ipairs(b.featured) do names[i] = G.DEX_BY[d] and G.DEX_BY[d].name or tostring(d) end
                UI.text("Destacados: " .. table.concat(names, " · "), 0, 130, { size = 12, w = 400, align = "center" })
            end
        end
    end
end
function gacha.draw()
    local s = G.DB.save
    local t = s.tickets or { t1 = 0, t10 = 0 }
    for g = 1, 9 do
        UI.button("gen" .. g, 2 + (g - 1) * 35, 2, 33, 16, GEN[g]:sub(1, 5), { size = 10, on = g == gGen })
    end
    local pity = s.pity and s.pity[gGen] or (s.pity and s.pity[tostring(gGen)]) or 0
    UI.text("Común 45% · Poco común 30% · Rara 17% · Épica 6,5% · Legendaria 1,5% · Shiny 1% · Pity " .. pity .. "/70",
            4, 21, { size = 10, color = UI.C.muted, w = W - 8, align = "center" })
    UI.button("p1", 10, 50, 96, 30, "Tirar x1\n1 ticket", { size = 10, enabled = (t.t1 or 0) >= 1 })
    UI.button("p10", 112, 50, 96, 30, "Tirar x10\n10 tickets", { size = 10, enabled = (t.t1 or 0) >= 10 })
    UI.button("p10b", 214, 50, 96, 30, "Tirar x10\n1 ticket x10", { size = 10, color = "#2a1a3a", enabled = (t.t10 or 0) >= 1 })
    -- Resultados
    if #gResults > 0 then
        for i, r in ipairs(gResults) do
            local x, y = 10 + ((i - 1) % 5) * 60, 90 + math.floor((i - 1) / 5) * 56
            local on = i == gIdx
            U.setColor(r.shiny and "#1a2a3a" or (on and "#2a3a1a" or UI.C.panel))
            lg.rectangle("fill", x, y, 56, 50, 4, 4)
            if on then U.setColor(UI.C.gold); lg.rectangle("line", x + 0.5, y + 0.5, 55, 49, 4, 4) end
            lg.setColor(1, 1, 1, 1)
            G.Sprites.drawStill(r.dex, x + 28, y + 36, 0.5)
            local p = G.DEX_BY[r.dex]
            UI.text((r.isNew and "¡Nuevo! " or "") .. (p and p.name or ""), x, y + 38, { size = 10, w = 56, align = "center", color = r.isNew and UI.C.gold or UI.C.muted })
            UI.hitbox("r" .. i, x, y, 56, 50)
        end
    else
        UI.text("Los tickets se ganan jugando: algunos Pokémon sueltan uno, los jefes y los legendarios dan tickets x10.", 20, 100, { size = 10, color = UI.C.muted, w = W - 40, align = "center" })
    end
    UI.button("back", 110, 206, 100, 18, "Volver", { size = 10 })
    coinsLine()
end
local function pull(n, payWith)
    local ok, res = pcall(G.Gacha.pull, gGen, n, payWith)
    if not ok then UI.toast("Gacha: " .. tostring(res)) return end
    if not res or #res == 0 then UI.toast("No tienes tickets suficientes") return end
    gResults = res
    gIdx = 1
    local dexes = {}
    for i, r in ipairs(res) do dexes[i] = r.dex end
    G.Sprites.preload(dexes, false)
    G.Audio.sfx("legend")
    G.DB.commit()
end
function gacha.touch(x, y)
    local id = UI.hit(x, y)
    if not id then return end
    if id == "back" then UI.show("menu") return end
    if id == "p1" then pull(1, "t1") return end
    if id == "p10" then pull(10, "t1") return end
    if id == "p10b" then pull(10, "t10") return end
    local g = tonumber(id:match("^gen(%d+)$"))
    if g then gGen = g; gResults = {}; gIdx = 0 return end
    local i = tonumber(id:match("^r(%d+)$"))
    if i then gIdx = i end
end
function gacha.button(b)
    if b == "b" then UI.show("menu")
    elseif b == "rightshoulder" then gGen = gGen % 9 + 1; gResults = {}; gIdx = 0
    elseif b == "leftshoulder" then gGen = (gGen - 2) % 9 + 1; gResults = {}; gIdx = 0
    elseif b == "dpright" and #gResults > 0 then gIdx = gIdx % #gResults + 1
    elseif b == "dpleft" and #gResults > 0 then gIdx = (gIdx - 2) % #gResults + 1
    elseif b == "a" then pull(1, "t1") end
end
UI.register("gacha", gacha)

-- ---------------- misiones y logros ----------------
local goals = {}
local function rewardText(r)
    local p = {}
    if r.t10 then p[#p + 1] = r.t10 .. " ticket x10" end
    if r.t1 then p[#p + 1] = r.t1 .. " ticket(s)" end
    if r.coins then p[#p + 1] = r.coins .. " monedas" end
    return table.concat(p, " + ")
end
function goals.enter()
    G.Progress.ensure(G.DB.save)
    G.TopUI.overlay = function()
        local s = G.DB.save
        local n, total = U.count(s.ach or {}), #G.AchDefs.LIST
        UI.text("Logros: " .. n .. " / " .. total, 0, 20, { size = 16, color = UI.C.gold, w = 400, align = "center" })
        local y = 44
        local shown = 0
        for _, a in ipairs(G.AchDefs.LIST) do
            if s.ach and s.ach[a.id] then
                UI.text("· " .. a.name .. (a.title and ("  [" .. a.title .. "]") or ""), 20, y, { size = 10, w = 360 })
                y = y + 12; shown = shown + 1
                if shown >= 15 then break end
            end
        end
        local titles = G.Progress.titles()
        if #titles > 0 then UI.text("Títulos: " .. table.concat(titles, ", "), 20, 222, { size = 10, color = UI.C.muted, w = 360 }) end
    end
end
function goals.draw()
    local s = G.DB.save
    local Mi = s.missions or {}
    local y = 4
    local function block(label, list, weekly)
        UI.text(label, 6, y, { size = 12, color = UI.C.gold })
        y = y + 16
        for i, m in ipairs(list or {}) do
            local def = G.MissionDefs.BY[m.id]
            local done = G.Progress.done(m)
            local txt = G.Progress.text(m)
            UI.text(txt, 6, y, { size = 10, w = 200 })
            UI.bar(6, y + 12, 200, 5, math.min(1, m.prog / m.goal), done and UI.C.green or UI.C.blue)
            UI.text(math.floor(m.prog) .. "/" .. m.goal, 210, y, { size = 10, color = UI.C.muted })
            local id = (weekly and "w" or "d") .. i
            if m.claimed then
                UI.text("Recogido", 250, y + 3, { size = 10, color = UI.C.muted })
            else
                UI.button(id, 250, y, 66, 18, done and "Recoger" or rewardText(def and def.reward or {}), { size = 10, enabled = done, color = done and "#2a2410" or nil, textColor = done and UI.C.gold or nil })
            end
            y = y + 24
        end
    end
    block("Misiones diarias", Mi.daily, false)
    block("Misiones semanales", Mi.weekly, true)
    UI.button("back", 110, 216, 100, 18, "Volver", { size = 10 })
end
function goals.touch(x, y)
    local id = UI.hit(x, y)
    if not id then return end
    if id == "back" then UI.show("menu") return end
    local kind, i = id:match("^(%a)(%d+)$")
    if kind then
        local Mi = G.DB.save.missions
        local list = kind == "w" and Mi.weekly or Mi.daily
        local m = list and list[tonumber(i)]
        if m and G.Progress.claim(m, kind == "w") then G.Audio.sfx("confirm"); UI.toast("Premio recogido") end
    end
end
function goals.button(b) if b == "b" then UI.show("menu") end end
UI.register("goals", goals)

-- ---------------- modo Fases ----------------
local stages = {}
local stSel = 1
local function stageInfo()
    local st = G.Stages.LIST[stSel]
    local unlocked = G.Stages.isUnlocked(stSel)
    local prog = G.Stages.progress()
    local e = prog[stSel] or prog[tostring(stSel)]
    G.TopUI.overlay = function()
        lg.setColor(0, 0, 0, 0.45)
        lg.rectangle("fill", 0, 0, 400, 240)
        UI.text("Fase " .. stSel, 0, 24, { size = 12, color = UI.C.muted, w = 400, align = "center" })
        UI.text(st.name, 0, 38, { size = 22, color = unlocked and UI.C.gold or UI.C.muted, w = 400, align = "center" })
        UI.text("10 minutos · 20 oleadas · " .. #st.bosses .. " jefes", 0, 68, { size = 12, w = 400, align = "center" })
        local names = {}
        for i, b in ipairs(st.bosses) do names[i] = G.DEX_BY[b.dex].name end
        UI.text("Jefes: " .. table.concat(names, " → "), 0, 86, { size = 10, color = UI.C.muted, w = 400, align = "center" })
        -- Jefes dibujados
        local n = #st.bosses
        for i, b in ipairs(st.bosses) do
            local x = 200 + (i - (n + 1) / 2) * 70
            G.Sprites.drawStill(b.dex, x, 170, 1)
        end
        if e and e.cleared then
            UI.text("Superada · mejor tiempo " .. U.mmss(e.best or 0), 0, 196, { size = 12, color = UI.C.green, w = 400, align = "center" })
        elseif not unlocked then
            UI.text("Supera la fase anterior para desbloquearla", 0, 196, { size = 12, color = UI.C.red, w = 400, align = "center" })
        else
            UI.text("Derrota al jefe final para superar la fase", 0, 196, { size = 12, w = 400, align = "center" })
        end
        UI.text("Tu Pokémon evoluciona al nivel 16 y al 36 durante la partida", 0, 218, { size = 10, color = UI.C.muted, w = 400, align = "center" })
    end
end
function stages.enter()
    local dexes = {}
    for _, st in ipairs(G.Stages.LIST) do for _, b in ipairs(st.bosses) do dexes[#dexes + 1] = b.dex end end
    G.Sprites.preload(dexes, false)
    stageInfo()
end
function stages.draw()
    UI.text("Fases", 0, 4, { size = 16, color = UI.C.gold, w = W, align = "center" })
    for i, st in ipairs(G.Stages.LIST) do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local x, y = 10 + col * 152, 26 + row * 40
        local unlocked = G.Stages.isUnlocked(i)
        local cleared = G.Stages.isCleared(i)
        UI.button("s" .. i, x, y, 148, 34, (cleared and "* " or "") .. st.name, { size = 10, enabled = unlocked, on = i == stSel,
                  color = cleared and "#1b3a2a" or nil })
    end
    UI.button("go", 170, 206, 140, 22, "Empezar fase", { size = 12, color = "#1b3a2a", enabled = G.Stages.isUnlocked(stSel) })
    UI.button("back", 10, 206, 100, 22, "Volver", { size = 10 })
end
function stages.touch(x, y)
    local id = UI.hit(x, y)
    if not id then return end
    if id == "back" then UI.show("menu") return end
    if id == "go" then G.Audio.sfx("confirm"); G.Flow.playStage(stSel) return end
    local i = tonumber(id:match("^s(%d+)$"))
    if i then stSel = i; G.Audio.sfx("select"); stageInfo() end
end
function stages.button(b)
    if b == "b" then UI.show("menu")
    elseif b == "a" then if G.Stages.isUnlocked(stSel) then G.Flow.playStage(stSel) end
    elseif b == "dpdown" then stSel = math.min(#G.Stages.LIST, stSel + 2); stageInfo()
    elseif b == "dpup" then stSel = math.max(1, stSel - 2); stageInfo()
    elseif b == "dpright" then stSel = math.min(#G.Stages.LIST, stSel + 1); stageInfo()
    elseif b == "dpleft" then stSel = math.max(1, stSel - 1); stageInfo() end
end
UI.register("stages", stages)

-- ---------------- tarjeta de entrenador ----------------
local card = {}
local ownedList = {}
local function medals()
    local s = G.DB.save
    local out = {}
    for _, a in ipairs(G.AchDefs.LIST) do
        local at = s.ach and s.ach[a.id]
        if at then out[#out + 1] = { a = a, at = at } end
    end
    table.sort(out, function(x, y)
        if (x.a.tier or 1) ~= (y.a.tier or 1) then return (x.a.tier or 1) > (y.a.tier or 1) end
        return (x.at or 0) > (y.at or 0)
    end)
    return out
end
-- Estilos "legacy" de Pokécharms (tools/gen_cards.py): fondo, entrenador y paneles
-- de Pokémon, cada uno en su sitio según el fondo. Las medallas son las del juego.
local okCS, CS = pcall(require, 'data.cardstyle')
if not okCS then CS = nil end
local cardImg = {}           -- caché de imágenes de la tarjeta: clave -> Image (se libera al salir)
local function cardImage(key, path)
    local im = cardImg[key]
    if im == nil then
        local ok, r = pcall(lg.newImage, U.img(path))
        im = ok and r or false
        if im and im.setFilter then pcall(im.setFilter, im, 'nearest', 'nearest') end
        cardImg[key] = im
    end
    return im or nil
end
local function releaseCardImages()
    for k, im in pairs(cardImg) do
        if im and im.release then pcall(im.release, im) end
        cardImg[k] = nil
    end
end
local quadCache = {}
local function quadFor(x, y, w, h, im)
    local k = x * 100000 + y * 10 + w
    local q = quadCache[k]
    if not q then q = lg.newQuad(x, y, w, h, im:getWidth(), im:getHeight()); quadCache[k] = q end
    return q
end
-- Índice (1..n) del fondo / entrenador elegido (por id guardado).
local function pickIndex(list, id)
    if not list then return 1 end
    for i, e in ipairs(list) do if e.id == id then return i end end
    return 1
end

local function statsPanel(x, y, w)
    local s = G.DB.save
    local st = s.stats or {}
    local prof = s.profile or {}
    local PF = G.PixelFont
    U.setColor("#101828", 0.88)
    lg.rectangle("fill", x, y, w, 171, 6, 6)
    U.setColor("#4a6ab8")
    lg.rectangle("line", x + 0.5, y + 0.5, w - 1, 170, 6, 6)
    local title = (prof.title and prof.title ~= "") and prof.title or "Novato"
    PF.print(string.upper(title), x + (w - PF.width(string.upper(title), 1)) / 2, y + 7, { s = 1, color = "#ffd23f", noOutline = true })
    local ms = medals()
    local rows = {
        { "DINERO", (s.coins or 0) .. " P" },
        { "POKEDEX", U.count(s.owned or {}) .. "/" .. #G.DEX },
        { "SHINIES", tostring(U.count(s.shiny or {})) },
        { "TIEMPO", U.mmss(st.playTime or 0) },
        { "MEJOR", U.mmss(st.bestTime or 0) },
        { "FASES", tostring(st.stagesCleared or 0) },
        { "MEDALLAS", #ms .. "/" .. #G.AchDefs.LIST },
    }
    -- Cuántas faltan para la siguiente Poké Ball de la tarjeta.
    for i = 1, 8 do
        local need = math.ceil(i * #G.AchDefs.LIST / 8)
        if #ms < need then rows[#rows + 1] = { "SIG. BALL", (need - #ms) .. " MEDALLAS" } break end
    end
    for i, r in ipairs(rows) do
        local yy = y + 21 + (i - 1) * 18
        PF.print(r[1], x + 7, yy, { s = 1, color = "#9fb4e8", noOutline = true })
        PF.print(r[2], x + w - 7 - PF.width(r[2], 1), yy + 9, { s = 1, color = "#ffffff", noOutline = true })
    end
end

-- ¿Tienes este Pokémon? (las claves del guardado pueden ser número o texto)
local function owns(d)
    local o = G.DB.save.owned or {}
    return o[d] ~= nil or o[tostring(d)] ~= nil
end

-- Panel de 50x30 de un Pokémon: sprite oficial de Negro/Blanco si lo hay (1..649);
-- si no, fondo claro con su sprite del juego.
local function drawPanel(d, x, y)
    local p = d and CS and CS.panels[d]
    if p then
        local im = cardImage('pn' .. p[1], 'img/panels/' .. p[1])
        if im then lg.setColor(1, 1, 1, 1); lg.draw(im, quadFor(p[2], p[3], 50, 30, im), x, y) end
    elseif d then
        U.setColor("#f4f6f8")
        lg.rectangle("fill", x, y, 50, 30)
        lg.setColor(1, 1, 1, 1)
        G.Sprites.drawStill(d, x + 25, y + 29, 0.5)
    end
end

-- Panel derecho de los diseños "de juego": el equipo (los datos ya van en la tarjeta).
local function teamPanel(x, y, w, team)
    U.setColor("#101828", 0.88)
    lg.rectangle("fill", x, y, w, 171, 6, 6)
    U.setColor("#4a6ab8")
    lg.rectangle("line", x + 0.5, y + 0.5, w - 1, 170, 6, 6)
    local PF = G.PixelFont
    PF.print("EQUIPO", x + (w - PF.width("EQUIPO", 1)) / 2, y + 7, { s = 1, color = "#ffd23f", noOutline = true })
    local gx = x + math.floor((w - 106) / 2)
    for i = 1, 6 do
        -- Huecos separados (4 px entre uno y otro); vacíos si no tienes ese Pokémon.
        local px, py = gx + ((i - 1) % 2) * 56, y + 21 + math.floor((i - 1) / 2) * 35
        U.setColor("#2a3a68")
        lg.rectangle("fill", px - 1, py - 1, 52, 32)
        U.setColor("#1a2444")
        lg.rectangle("fill", px, py, 50, 30)
        drawPanel(team[i], px, py)
    end
    local ms = #medals()
    local txt = "MEDALLAS " .. ms .. "/" .. #G.AchDefs.LIST
    PF.print(txt, x + (w - PF.width(txt, 1)) / 2, y + 128, { s = 1, color = "#9fb4e8", noOutline = true })
    for i = 1, 8 do
        local need = math.ceil(i * #G.AchDefs.LIST / 8)
        if ms < need then
            local t2 = "SIG. BALL: " .. (need - ms)
            PF.print(t2, x + (w - PF.width(t2, 1)) / 2, y + 144, { s = 1, color = "#ffffff", noOutline = true })
            break
        end
    end
end

local function drawCard()
    local s = G.DB.save
    local prof = s.profile or {}
    local favs = prof.favs or {}
    local CX, CY = 4, 34                      -- tarjeta a tamaño real (246x171)
    -- Equipo: compañero y 5 favoritos; sólo salen los que tienes.
    local team = {}
    for i, d in ipairs({ s.partner or false, favs[1] or false, favs[2] or false, favs[3] or false, favs[4] or false, favs[5] or false }) do
        team[i] = (d and owns(d)) and d or nil
    end
    if not CS or #CS.cards == 0 then statsPanel(CX + 250, CY, 400 - CX - 254) return end
    local c = CS.cards[pickIndex(CS.cards, prof.cardBg)]
    local game = c.layout == "game"
    if game then teamPanel(CX + 250, CY, 400 - CX - 254, team) else statsPanel(CX + 250, CY, 400 - CX - 254) end
    lg.setColor(1, 1, 1, 1)
    local bg = cardImage('bg' .. c.id, 'img/cards/' .. c.id)
    if bg then lg.draw(bg, CX, CY) end
    -- Entrenador (sprite oficial)
    local tr = CS.trainers[pickIndex(CS.trainers, prof.trainer)]
    if tr then
        local im = cardImage('tr' .. tr.atlas, 'img/trainers/' .. tr.atlas)
        if im then lg.draw(im, quadFor(tr.x, tr.y, 80, 80, im), CX + c.trainer[1], CY + c.trainer[2]) end
    end
    local PF = G.PixelFont
    local id = string.format("%05d", (s.created or 0) % 65536)
    if game then
        -- Como en los juegos: título, número de ID y los datos en filas.
        PF.print("TARJETA DE ENTRENADOR", CX + c.title[1], CY + c.title[2], { s = 1, color = c.titleColor, noOutline = true })
        PF.print("ID " .. id, CX + c.code[1], CY + c.code[2], { s = 1, color = c.codeColor, noOutline = true })
        local st = s.stats or {}
        local vals = {
            name = string.upper(s.name or "Entrenador"),
            money = (s.coins or 0) .. " P",
            dex = U.count(s.owned or {}) .. "/" .. #G.DEX,
            time = U.mmss(st.playTime or 0),
            stages = tostring(st.stagesCleared or 0),
        }
        for _, r in ipairs(c.rows) do
            PF.print(r[1], CX + c.labelX, CY + r[3], { s = 1, color = c.labelColor, noOutline = true })
            local v = vals[r[2]] or ""
            PF.print(v, CX + c.valueX - PF.width(v, 1), CY + r[3], { s = 1, color = c.valueColor, noOutline = true })
        end
    else
        PF.print("TARJETA DE ENTRENADOR", CX + 10, CY + 10, { s = 1, color = c.titleColor or "#ffffff", noOutline = true })
        PF.print(string.upper(s.name or "Entrenador"), CX + c.name[1], CY + c.name[2] - 3, { s = 1, color = c.nameColor, noOutline = true })
        PF.print("ID " .. id, CX + c.code[1], CY + c.code[2] - 3, { s = 1, color = c.codeColor, noOutline = true })
        -- Equipo: compañero y 5 favoritos
        for i = 1, 6 do
            local pos = c.pokemon[i]
            drawPanel(team[i], CX + pos[1], CY + pos[2])
        end
    end
    -- 8 Poké Balls de colores en los huecos de medalla: las medallas del juego se
    -- reparten en 8 tramos (con 127: 16, 32, 48... 127) y cada tramo cumplido
    -- desbloquea una. Las bloqueadas, en silueta.
    local have, total = #medals(), #G.AchDefs.LIST
    for i = 1, 8 do
        local pos = c.badges[i]
        local im = pos and cardImage('ball' .. i, 'img/badges/' .. i)
        if im then
            local bx = CX + pos[1] + 8 - math.floor(im:getWidth() / 2)
            local by = CY + pos[2] + 8 - math.floor(im:getHeight() / 2)
            if have >= math.ceil(i * total / 8) then
                lg.setColor(1, 1, 1, 1)
            else
                lg.setColor(0, 0, 0, 0.45)
            end
            lg.draw(im, bx, by)
        end
    end
    lg.setColor(1, 1, 1, 1)
end
function card.enter()
    local s = G.DB.save
    s.profile = s.profile or { favs = {}, title = "" }
    s.profile.favs = s.profile.favs or {}
    ownedList = {}
    for d in pairs(s.owned or {}) do if G.DEX_BY[tonumber(d) or d] then ownedList[#ownedList + 1] = tonumber(d) or d end end
    table.sort(ownedList)
    G.Sprites.preload(s.profile.favs, false)
    G.TopUI.overlay = drawCard
end
function card.leave() releaseCardImages(); quadCache = {} end
-- Fila "< etiqueta >" para recorrer una lista.
local function cycler(id, y, label)
    UI.button(id .. "-", 10, y, 34, 22, "<", { size = 12 })
    UI.text(label, 46, y + 5, { size = 10, w = W - 92, align = "center" })
    UI.button(id .. "+", W - 44, y, 34, 22, ">", { size = 12 })
end
function card.draw()
    local s = G.DB.save
    local prof = s.profile
    UI.text("Tarjeta de entrenador", 0, 4, { size = 16, color = UI.C.gold, w = W, align = "center" })
    if CS then
        local ci = pickIndex(CS.cards, prof.cardBg)
        local c = CS.cards[ci]
        cycler("bg", 26, "Fondo: " .. c.cat .. "  (" .. ci .. "/" .. #CS.cards .. ")")
        local ti = pickIndex(CS.trainers, prof.trainer)
        cycler("tr", 52, "Entrenador: " .. CS.trainers[ti].cat .. "  (" .. ti .. "/" .. #CS.trainers .. ")")
    end
    -- Equipo: el 1 es tu compañero (se cambia en Pokémon); 2..6, favoritos.
    for i = 1, 5 do
        local d = prof.favs[i]
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        UI.button("fav" .. i, 10 + col * 152, 80 + row * 26, 148, 22,
                  (i + 1) .. ": " .. (d and owns(d) and G.DEX_BY[d] and G.DEX_BY[d].name or "—"), { size = 10 })
    end
    local titles = G.Progress.titles()
    UI.button("title", 162, 132, 148, 22, "Título: " .. (prof.title ~= "" and prof.title or "Novato"),
              { size = 10, enabled = #titles > 0 })
    UI.text("Toca un hueco para cambiar de Pokémon. L/R: fondo · Cruceta: entrenador", 10, 162, { size = 10, color = UI.C.muted, w = W - 20, align = "center" })
    UI.button("back", 110, 206, 100, 22, "Volver", { size = 10 })
end
local function cycle(field, list, step)
    local s = G.DB.save
    local i = pickIndex(list, s.profile[field])
    i = (i - 1 + step) % #list + 1
    s.profile[field] = list[i].id
    releaseCardImages()
    G.Audio.sfx("select")
    G.DB.commit()
end
function card.touch(x, y)
    local id = UI.hit(x, y)
    if not id then return end
    local s = G.DB.save
    local prof = s.profile
    if id == "back" then UI.show("menu") return end
    if CS then
        if id == "bg-" then cycle("cardBg", CS.cards, -1) return end
        if id == "bg+" then cycle("cardBg", CS.cards, 1) return end
        if id == "tr-" then cycle("trainer", CS.trainers, -1) return end
        if id == "tr+" then cycle("trainer", CS.trainers, 1) return end
    end
    if id == "title" then
        local titles = G.Progress.titles()
        local k = (U.indexOf(titles, prof.title) or 0) % #titles + 1
        prof.title = titles[k]
        G.DB.commit()
        return
    end
    local i = tonumber(id:match("^fav(%d+)$"))
    if i and #ownedList > 0 then
        local k = (U.indexOf(ownedList, prof.favs[i]) or 0) % #ownedList + 1
        prof.favs[i] = ownedList[k]
        G.Sprites.preload({ ownedList[k] }, false)
        G.Audio.sfx("select")
        G.DB.commit()
    end
end
function card.button(b)
    if b == "b" then UI.show("menu")
    elseif CS and b == "rightshoulder" then cycle("cardBg", CS.cards, 1)
    elseif CS and b == "leftshoulder" then cycle("cardBg", CS.cards, -1)
    elseif CS and b == "dpright" then cycle("trainer", CS.trainers, 1)
    elseif CS and b == "dpleft" then cycle("trainer", CS.trainers, -1) end
end
UI.register("card", card)

-- Animaciones de los menús.
local oldUpdate = UI.update
function UI.update(dt)
    oldUpdate(dt)
    UI.updateMenuAnims(dt)
end
