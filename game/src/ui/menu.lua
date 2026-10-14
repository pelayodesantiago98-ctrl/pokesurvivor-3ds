-- menu.lua — título, menú principal, colección (Pokédex), mejoras, gacha y misiones.
-- Pantalla inferior: botones y rejillas. Superior: el mundo de fondo y fichas.
local U = G.U
local UI = G.UI
local M = {}
G.MenuUI = M

local lg = love.graphics
local W, H = UI.W, UI.H
local GEN = UI.GEN_NAMES

-- Rendimiento (la 3DS interpreta Lua y es ~30 veces más lenta que el PC): cada
-- fotograma no se crean tablas ni textos. Las opciones de los widgets van en una
-- tabla reutilizada (UI.button y UI.text no la guardan) y los textos que dependen
-- de datos se rehacen solo cuando cambian esos datos.
local OPT = {}
local function bo(size, on, color, enabled, textColor, icon)
    OPT.size, OPT.on, OPT.color, OPT.enabled, OPT.textColor, OPT.icon = size, on, color, enabled, textColor, icon
    return OPT
end
local TOPT = {}
local function to(size, color, w, align)
    TOPT.size, TOPT.color, TOPT.w, TOPT.align = size, color, w, align
    return TOPT
end
-- Nombres cortos y ids de las pestañas de generación.
local GEN5, GENID = {}, {}
for g = 1, 9 do GEN5[g] = GEN[g]:sub(1, 5); GENID[g] = "gen" .. g end
-- Textos e ids numerados ("d12", "r3"...) hechos una sola vez.
local function idList(prefix)
    return setmetatable({}, { __index = function(t, i) local v = prefix .. i; t[i] = v; return v end })
end

-- Pokémon que tienes (U.count recorre toda la tabla): se recuenta como mucho una
-- vez por segundo.
local ownedN, ownedT = 0, -1
local function ownedCount()
    local now = U.now()
    if now - ownedT > 1 then ownedT = now; ownedN = U.count(G.DB.save.owned) end
    return ownedN
end

-- Línea de monedas y tickets de abajo (se rehace solo si cambian).
local coinsMemo = { c = nil, t1 = nil, t10 = nil, txt = "", tw = 0 }
local function coinsLine()
    local s = G.DB.save
    local t = s.tickets or { t1 = 0, t10 = 0 }
    local m = coinsMemo
    if m.c ~= s.coins or m.t1 ~= t.t1 or m.t10 ~= t.t10 then
        m.c, m.t1, m.t10 = s.coins, t.t1, t.t10
        m.txt = s.coins .. " monedas   ·   " .. (t.t1 or 0) .. " tickets   ·   " .. (t.t10 or 0) .. " tickets x10"
        m.tw = UI.font(10):getWidth(m.txt)
    end
    G.Icons.draw("coin", (W - m.tw) / 2 - 15, H - 15, 12)           -- icono de moneda delante
    UI.text(m.txt, 0, H - 14, to(10, UI.C.gold, W, "center"))
end

-- Sprites quietos de las rejillas (Pokédex, gacha) cargando como mucho UNA hoja
-- nueva por fotograma: cada hoja tarda ~40 ms en la 3DS y una página de la Pokédex
-- son 18 (más de medio segundo parado al entrar o pasar de página). Las que ya
-- están cargadas se dibujan siempre; las demás van apareciendo una a una.
local lazyFrame, lazyBudget = -1, 0
local lazyOk = {}                 -- dex -> true: ya dibujado (su hoja estaba cargada)
local function lazyReset() lazyOk = {} end
local function stillLazy(dex, x, y, scale)
    local fr = UI.frame
    if fr ~= lazyFrame then lazyFrame = fr; lazyBudget = 1 end
    if lazyOk[dex] then return G.Sprites.drawStill(dex, x, y, scale) end
    -- ¿Cargará una hoja? Se sabe por el número de hojas cargadas antes y después.
    if lazyBudget <= 0 then return false end
    local n0 = G.Sprites.loadedCount()
    local ok = G.Sprites.drawStill(dex, x, y, scale)
    if G.Sprites.loadedCount() ~= n0 then lazyBudget = lazyBudget - 1 end
    lazyOk[dex] = true
    return ok
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
        if G_STEP then G_STEP("icono de menú " .. id) end
        local ok, r = pcall(lg.newImage, U.img('img/menu/' .. id))
        im = ok and r or false
        if im and im.setFilter then pcall(im.setFilter, im, 'nearest', 'nearest') end
        menuIcons[id] = im
    end
    return im or nil
end
-- Iconos con su cuadrado ya horneados en img/ui/menuicons (tools/bake_buttons):
-- celdas de 33x33 cada 34 px, 4 por fila, en el orden de ITEMS. Si falta la
-- imagen, se dibujan como antes (cuadrados + icono suelto).
local menuAtlas, menuAtlasTried, menuAtlasQ = nil, false, {}
local function menuIconQuad(i)
    if not menuAtlasTried then
        menuAtlasTried = true
        local ok, im = pcall(lg.newImage, U.img('img/ui/menuicons'))
        if ok and im then
            if im.setFilter then pcall(im.setFilter, im, 'nearest', 'nearest') end
            menuAtlas = im
            local iw, ih = im:getWidth(), im:getHeight()
            for k = 1, #ITEMS do
                menuAtlasQ[k] = lg.newQuad(((k - 1) % 4) * 34, math.floor((k - 1) / 4) * 34, 33, 33, iw, ih)
            end
        end
    end
    return menuAtlasQ[i]
end
-- Texto blanco con sombra oscura (como en los botones de DS). En una sola línea:
-- si no cabe en `w`, baja de tamaño (hasta 8).
local function dsText(str, x, y, size, w, col, ink)
    UI.shadowText(str, x, y, size, w or (W - x), col, ink)
end
-- Color oscuro del borde del icono de cada botón (antes se calculaba cada fotograma).
for _, it in ipairs(ITEMS) do it.dark = U.shade(it.color, -0.5) end
-- Arriba, la ficha del compañero (la información va arriba y el menú abajo). Una
-- sola función (no una nueva en cada entrada): top.lua escribe en la SD cada vez
-- que cambia la ficha.
local MENU_CARD = { own = true, shiny = false, footer = "Tu compañero" }
local function menuOverlay()
    local s = G.DB.save
    MENU_CARD.shiny = s.partnerShiny and G.DB.ownsShiny(s.partner)
    G.TopUI.pokemonCard(s.partner, MENU_CARD)
end
-- Textos de las barras (se rehacen solo si cambian monedas, tickets, dificultad...).
local mm = { coins = nil, coinsTxt = "", cw = 0, dif = nil, difTxt = "", pend = -1, pendTxt = "",
             t1 = nil, t10 = nil, own = nil, tTxt = "", tw = 0 }
-- Nombres y descripciones de los botones grandes en dos bloques de texto (UI.textBlock):
-- sombra (negro al 55 %, 1 px abajo a la derecha) y letra, como dsText.
local MENU_TW = 151 - 50
local function menuItemXY(i) return 6 + ((i - 1) % 2) * 157 + 44, 27 + math.floor((i - 1) / 2) * 47 end
local menuLabels, menuSubs = {}, {}
local function menuLabelsBuild(add)
    for i = 1, #ITEMS do
        local tx, y = menuItemXY(i)
        add(ITEMS[i].label, tx + 1, y + 8, "#000000", MENU_TW, "left", 0.55)
        add(ITEMS[i].label, tx, y + 7, "#ffffff", MENU_TW, "left")
    end
end
local function menuSubsBuild(add)
    local pend = mm.pend
    for i = 1, #ITEMS do
        local it = ITEMS[i]
        local tx, y = menuItemXY(i)
        local hot = it.id == "goals" and pend > 0
        local sub = hot and mm.pendTxt or it.sub
        add(sub, tx + 1, y + 25, "#000000", MENU_TW, "left", 0.55)
        add(sub, tx, y + 24, hot and "#fff2a0" or "#f0f4ff", MENU_TW, "left")
    end
end
-- ¿Caben todos a su tamaño (12 y 10)? Si alguno no, dsText lo achica: uno a uno.
local function menuFits(pendTxt)
    for i = 1, #ITEMS do
        if not UI.fits(ITEMS[i].label, 12, MENU_TW) or not UI.fits(ITEMS[i].sub, 10, MENU_TW) then return false end
    end
    return UI.fits(pendTxt, 10, MENU_TW)
end
function menu.enter()
    -- (Antes había dos G_STEP alrededor de checkAch: cada uno escribía en la SD,
    -- ~20 ms en la consola.)
    G.Progress.checkAch()
    local s = G.DB.save
    G.Sprites.preload({ s.partner }, false)
    ownedT = -1
    G.TopUI.overlay = menuOverlay
end
function menu.draw()
    local s = G.DB.save
    -- Barra de arriba: título y monedas
    UI.bar2(0, 22)
    dsText("MENÚ", 8, 4, 12)
    -- Dificultad (toca para cambiar; L/R con el mando)
    local dif = G.Difficulty.get()
    if mm.dif ~= dif then mm.dif = dif; mm.difTxt = "Dificultad: " .. dif.name end
    UI.button("difficulty", 54, 2, 118, 18, mm.difTxt, bo(10, nil, dif.color))
    -- Monedas con su icono delante
    if mm.coins ~= s.coins then
        mm.coins = s.coins
        mm.coinsTxt = s.coins .. " monedas"
        mm.cw = UI.font(12):getWidth(mm.coinsTxt)
    end
    local cw = mm.cw
    G.Icons.draw("coin", W - 8 - cw - 16, 5, 12)
    dsText(mm.coinsTxt, W - 8 - cw, 4, 12, cw + 2, UI.C.gold)
    local pend = G.Progress.pending()
    if mm.pend ~= pend then
        mm.pend = pend; mm.pendTxt = pend .. " premios"
        mm.fit = menuFits(mm.pendTxt)
    end
    local textsFit = mm.fit
    -- Botones grandes
    for i = 1, #ITEMS do
        local it = ITEMS[i]
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local x, y, bw, bh = 6 + col * 157, 27 + row * 47, 151, 43
        UI.button(it.id, x, y, bw, bh, "", bo(nil, focus == i, it.color))
        -- Icono en un cuadrado claro redondeado (como los iconos de HGSS), centrado
        local sx, sy, ss = x + 6, y + 6, 31
        local q = menuIconQuad(i)
        if q then
            lg.draw(menuAtlas, q, sx - 1, sy - 1)          -- ya horneado: un dibujo
        else
            U.setColor(it.dark)
            lg.rectangle("fill", sx - 1, sy - 1, ss + 2, ss + 2, 6, 6)
            U.setColor("#ffffff", 0.92)
            lg.rectangle("fill", sx, sy, ss, ss, 5, 5)
            lg.setColor(1, 1, 1, 1)
            local im = menuIcon(it.id)
            if im then
                lg.draw(im, sx + math.floor((ss - im:getWidth()) / 2), sy + math.floor((ss - im:getHeight()) / 2))
            end
        end
        -- Nombre y descripción, cada uno en una línea
        if not textsFit then
            local hot = it.id == "goals" and pend > 0
            local tx, tw = x + 44, bw - 50
            dsText(it.label, tx, y + 7, 12, tw)
            dsText(hot and mm.pendTxt or it.sub, tx, y + 24, 10, tw, hot and "#fff2a0" or "#f0f4ff")
        end
    end
    if textsFit then
        -- Todos caben a su tamaño: nombres y descripciones (con su sombra) en dos dibujos.
        UI.textBlock(menuLabels, 12, 1, menuLabelsBuild)
        UI.textBlock(menuSubs, 10, pend, menuSubsBuild)
    end
    -- Barra de abajo: tickets
    UI.bar2(H - 20, 20)
    local t = s.tickets or { t1 = 0, t10 = 0 }
    local own = ownedCount()
    if mm.t1 ~= t.t1 or mm.t10 ~= t.t10 or mm.own ~= own then
        mm.t1, mm.t10, mm.own = t.t1, t.t10, own
        mm.tTxt = (t.t1 or 0) .. " tickets   ·   " .. (t.t10 or 0) .. " tickets x10   ·   Pokédex " .. own .. "/" .. #G.DEX
        mm.tw = UI.font(10):getWidth(mm.tTxt)
    end
    G.Icons.draw("ticket", (W - mm.tw) / 2 - 15, H - 16, 12)
    UI.text(mm.tTxt, 0, H - 15, to(10, UI.C.gold, W, "center"))
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
local function cycleDifficulty(step)
    local d = G.Difficulty.cycle(step)
    G.Audio.sfx("select")
    UI.toast("Dificultad: " .. d.name .. string.format("  (enemigos x%.2f vida, x%.2f daño · monedas x%.2f)", d.hp, d.dmg, d.reward), 2.6)
end
function menu.touch(x, y)
    local id = UI.hit(x, y)
    if id == "difficulty" then cycleDifficulty(1) return end
    if id then go(id) end
end
function menu.button(b)
    if b == "rightshoulder" then cycleDifficulty(1) return end
    if b == "leftshoulder" then cycleDifficulty(-1) return end
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

local DID = idList("d")
local FX = { { "all", "Todos", "fall" }, { "own", "Tengo", "fown" }, { "miss", "Faltan", "fmiss" } }
local dexMemo = { own = nil, ownTxt = "", page = nil, pages = nil, pageTxt = "" }

local thumbsRelease               -- (más abajo, con las miniaturas)
local function rebuildList()
    local s = G.DB.save
    lazyReset()                   -- página nueva: comprobar otra vez qué hojas hay
    thumbsRelease(dexGen)         -- solo la hoja de miniaturas de la generación visible
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

-- Ficha de arriba del Pokémon elegido: una sola función que lee dexCard (top.lua
-- escribe en la SD cada vez que cambia la función de la ficha).
local dexCard = { dex = nil, opts = { own = false, shiny = false, footer = nil } }
local function dexOverlay() G.TopUI.pokemonCard(dexCard.dex, dexCard.opts) end
local function selectDex(d)
    dexSel = d
    local s = G.DB.save
    local own = s.owned[d] ~= nil
    G.Sprites.preload({ d }, false)
    local shiny = s.shiny and s.shiny[d] ~= nil and d == s.partner and s.partnerShiny
    dexCard.dex = d
    dexCard.opts.own, dexCard.opts.shiny = own, shiny
    dexCard.opts.mark = d == s.partner and "crown" or (s.shiny and s.shiny[d] ~= nil and "shiny") or nil
    dexCard.opts.footer = own and (d == s.partner and "Es tu compañero" or "Toca ELEGIR para que sea tu compañero") or nil
    G.TopUI.overlay = dexOverlay
end

-- Miniaturas de la rejilla (tools/gen_thumbs.py): el mismo fotograma quieto que
-- dibuja G.Sprites.drawStill, pero sacado de una hoja de 512x256 por generación.
-- Antes cada casilla cargaba la hoja ENTERA de su Pokémon (~40 ms cada una en la
-- 3DS: tirones de 0,2-0,5 s al pasar de página). Solo se tiene cargada la hoja de
-- la generación visible y se suelta al salir de la Pokédex. Se dibujan con
-- lg.draw normal (no SpriteBatch): así se pueden teñir las siluetas.
local THUMBS = nil                -- data/thumbs.lua (se lee al entrar la primera vez)
local thumbImg, thumbQuad, thumbFailed = {}, {}, {}
local function thumbSheet(i)
    local sh = THUMBS.sheets[i]
    if thumbFailed[i] and U.now() - thumbFailed[i] < 3 then return nil end
    if G_MARKF then G_MARKF("THUMB:" .. sh.gen) end
    local ok, img = pcall(lg.newImage, U.img(sh.path))
    if not ok or not img then thumbFailed[i] = U.now() return nil end
    if img.setFilter then pcall(img.setFilter, img, "nearest", "nearest") end
    thumbFailed[i] = nil
    thumbImg[i] = img
    return img
end
-- Suelta las hojas de miniaturas que no sean de la generación keepGen (todas si es nil).
function thumbsRelease(keepGen)
    if not THUMBS then return end
    for i, img in pairs(thumbImg) do
        if THUMBS.sheets[i].gen ~= keepGen then
            if img.release then pcall(img.release, img) end
            thumbImg[i] = nil
        end
    end
end
-- Pies en (x, y), a escala 0,5 (1 píxel de arte = 1 de pantalla), con el mismo
-- redondeo que drawStill. false si el dex no tiene miniatura o no se pudo cargar.
local function drawThumb(d, x, y)
    local t = THUMBS and THUMBS[d]
    if not t then return false end
    local img = thumbImg[t[1]] or thumbSheet(t[1])
    if not img then return false end
    local q = thumbQuad[d]
    if not q then
        local sh = THUMBS.sheets[t[1]]
        q = lg.newQuad(t[2], t[3], t[4], t[5], sh.w, sh.h)
        thumbQuad[d] = q
    end
    lg.draw(img, q, U.round(x - t[6]), U.round(y - t[7]))
    return true
end

-- Marco de cada casilla (tools/gen_dexcell.py): ya pintado en img/ui/dexcell.png,
-- un lg.draw por casilla en vez de rectángulos redondeados. Variantes: 1 lo tienes,
-- 2 no lo tienes, 3 seleccionada. Se carga al entrar y se suelta al salir.
local cellImg, cellQuads = nil, nil
local function cellLoad()
    if cellImg then return end
    local ok, img = pcall(lg.newImage, U.img("img/ui/dexcell"))
    if not ok or not img then return end
    if img.setFilter then pcall(img.setFilter, img, "nearest", "nearest") end
    cellImg = img
    if not cellQuads then
        cellQuads = {}
        for i = 1, 3 do cellQuads[i] = lg.newQuad((i - 1) * CW, 0, CW - 2, CH - 2, 256, 64) end
    end
end
local function cellRelease()
    if cellImg and cellImg.release then pcall(cellImg.release, cellImg) end
    cellImg = nil
end

function dex.enter()
    local s = G.DB.save
    cellLoad()
    if not THUMBS then
        local ok, t = pcall(require, "data.thumbs")
        THUMBS = ok and t or { sheets = {} }
    end
    if not dexSel then dexSel = s.partner; dexGen = G.DEX_BY[s.partner].gen end
    ownedT = -1
    rebuildList()
    selectDex(dexSel)
end
function dex.leave() thumbsRelease(nil); cellRelease() end
function dex.draw()
    local s = G.DB.save
    local C = UI.C
    -- Pestañas de generación
    for g = 1, 9 do
        local x = 2 + (g - 1) * 35
        UI.button(GENID[g], x, 2, 33, 16, GEN5[g], bo(10, g == dexGen))
    end
    -- Filtros
    for i = 1, 3 do
        local f = FX[i]
        UI.button(f[3], 2 + (i - 1) * 50, 21, 48, 14, f[2], bo(10, dexFilter == f[1]))
    end
    local m = dexMemo
    local owned = ownedCount()
    if m.own ~= owned then m.own = owned; m.ownTxt = owned .. " / " .. #G.DEX end
    UI.text(m.ownTxt, 160, 22, to(10, C.muted, 156, "right"))
    -- Rejilla
    if m.lazyPage ~= dexPage then m.lazyPage = dexPage; lazyReset() end
    local start = (dexPage - 1) * PER
    local owns, shinies, partner = s.owned, s.shiny, s.partner
    for i = 1, PER do
        local p = dexList[start + i]
        if not p then break end
        local c, r = (i - 1) % COLS, math.floor((i - 1) / COLS)
        local x, y = 14 + c * CW, 38 + r * CH
        local d = p.dex
        local own = owns[d] ~= nil
        local on = d == dexSel
        if cellImg then
            lg.setColor(1, 1, 1, 1)
            lg.draw(cellImg, cellQuads[on and 3 or (own and 1 or 2)], x, y)
        else
            U.setColor(on and "#2a3a1a" or (own and C.panel or "#0d1630"))
            lg.rectangle("fill", x, y, CW - 2, CH - 2, 4, 4)
            if on then U.setColor(C.gold); lg.rectangle("line", x + 0.5, y + 0.5, CW - 3, CH - 3, 4, 4) end
        end
        if own then
            lg.setColor(1, 1, 1, 1)
        else
            lg.setColor(0.15, 0.18, 0.3, 1)
        end
        -- (Solo el sprite: número, nombre y datos van en la ficha de arriba.)
        if not drawThumb(d, x + CW / 2 - 1, y + CH - 12) then
            stillLazy(d, x + CW / 2 - 1, y + CH - 12, 0.5)
        end
        lg.setColor(1, 1, 1, 1)
        if d == partner then G.Icons.draw("crown", x + CW - 16, y + 2, 12)
        elseif shinies and shinies[d] then G.Icons.draw("shiny", x + CW - 16, y + 2, 12) end
        UI.hitbox(DID[start + i], x, y, CW - 2, CH - 2)
    end
    local pages = math.max(1, math.ceil(#dexList / PER))
    if m.page ~= dexPage or m.pages ~= pages then m.page, m.pages = dexPage, pages; m.pageTxt = dexPage .. " / " .. pages end
    UI.button("prev", 14, 180, 40, 18, "<", bo(10, nil, nil, dexPage > 1))
    UI.text(m.pageTxt, 58, 183, to(10, C.muted, 60, "center"))
    UI.button("next", 122, 180, 40, 18, ">", bo(10, nil, nil, dexPage < pages))
    local sel = dexSel and G.DEX_BY[dexSel]
    local hasSh = dexSel and G.DB.ownsShiny(dexSel)
    local canPick = sel and owns[dexSel] and (dexSel ~= partner or (hasSh and s.partnerShiny))
    UI.button("pick", 170, 180, 136, 18, "Elegir de compañero", bo(10, nil, "#3c9c54", canPick == true))
    UI.button("back", 14, 206, 100, 20, "Volver", bo(10))
    if hasSh then
        local isShinyPartner = dexSel == partner and s.partnerShiny
        UI.button("pickshiny", 170, 204, 136, 18, isShinyPartner and "Compañero shiny *" or "Elegir shiny *",
                  bo(10, nil, "#3c6cc4", not isShinyPartner))
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
local UPG_CARD = { footer = "Las mejoras son de cada Pokémon: solo cuentan cuando juegas con él" }
local function upgOverlay() G.TopUI.pokemonCard(upgDex, UPG_CARD) end
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
    G.TopUI.overlay = upgOverlay
end
local BUYID = idList("buy")
local upgTexts, upgBan = {}, false
local function upgTextsBuild(add)
    local muted = UI.C.muted
    local LIST = G.Upgrades.LIST
    for i = 1, #LIST do
        local u = LIST[i]
        local y = 25 + (i - 1) * 15
        add(u.name, 22, y + 1)
        if not (u.id == "ban" and upgBan) then add(u.unit, 90, y + 1, muted) end
    end
end
local COSTTXT = setmetatable({}, { __index = function(t, c) local v = tostring(c); t[c] = v; return v end })
local um0 = { dex = nil, partner = nil, name = "", coins = nil, coinsTxt = "", ban = nil, lvl = nil, banTxt = "" }
function upg.draw()
    local s = G.DB.save
    local C = UI.C
    local levels = G.DB.upgradesOf(upgDex)
    local m = um0
    if m.dex ~= upgDex or m.partner ~= s.partner then
        m.dex, m.partner = upgDex, s.partner
        m.name = G.DEX_BY[upgDex].name .. (upgDex == s.partner and " (compañero)" or "")
    end
    if m.coins ~= s.coins then m.coins = s.coins; m.coinsTxt = s.coins .. " monedas" end
    UI.button("prevmon", 4, 4, 22, 18, "<", bo(10))
    UI.text(m.name, 28, 7, to(12, nil, 180, "center"))
    UI.button("nextmon", 210, 4, 22, 18, ">", bo(10))
    UI.text(m.coinsTxt, 236, 7, to(10, C.gold, 80, "right"))
    -- (13 mejoras: filas de 15 px para que quepan todas.)
    -- Nombres y unidades, en un solo dibujo (la unidad del Veto no sale si ya
    -- tiene nivel: ahí va el botón "Elegir").
    local banOn = (levels.ban or 0) > 0
    upgBan = banOn
    UI.textBlock(upgTexts, 10, banOn and 1 or 0, upgTextsBuild)
    local LIST = G.Upgrades.LIST
    for i = 1, #LIST do
        local u = LIST[i]
        local y = 25 + (i - 1) * 15
        local lvl = levels[u.id] or 0
        local maxed = lvl >= u.max
        local cost = maxed and 0 or G.Upgrades.cost(u.id, lvl)
        G.Icons.draw(u.icon, 6, y, 12)
        if u.id == "ban" and lvl > 0 then
            -- Veto: elegir los movimientos vetados (pantalla "upgmoves").
            local n = #(G.MenuUI.banList(upgDex))
            if m.ban ~= n or m.lvl ~= lvl then m.ban, m.lvl = n, lvl; m.banTxt = "Elegir (" .. math.min(n, lvl) .. "/" .. lvl .. ")" end
            UI.button("pickban", 88, y, 104, 14, m.banTxt, bo(10, nil, "#d04848"))
        end
        -- Marcas de nivel: las conseguidas en dorado y las que faltan en oscuro.
        local got = math.min(lvl, u.max)
        UI.pips(196, y + 3, got, C.gold)
        UI.pips(196 + got * 6, y + 3, u.max - got, "#2a3350")
        local can = not maxed and s.coins >= cost
        UI.button(BUYID[i], 262, y, 54, 14, maxed and "Máx." or COSTTXT[cost], bo(10, nil, can and "#2a2410" or nil, can,
                  can and C.gold or nil))
    end
    UI.button("back", 56, 222, 100, 16, "Volver", bo(10))
    UI.button("binds", 164, 222, 100, 16, "Atajos", bo(10, nil, "#3c8c5a"))
end
function upg.touch(x, y)
    local id = UI.hit(x, y)
    if not id then return end
    if id == "back" then UI.show("menu") return end
    if id == "pickban" then UI.show("upgmoves", { dex = upgDex, mode = "ban" }) return end
    if id == "binds" then UI.show("upgmoves", { dex = upgDex, mode = "bind" }) return end
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

-- ---------------- mejoras: veto y atajos de movimientos ----------------
-- Veto: save.pban[dex] = { id, ... } (tantos como niveles de Veto; el de inicio
-- no se puede vetar). Atajos: save.pbind[dex] = { [hueco 1-4] = id }: ese
-- movimiento va siempre en ese hueco (ver Player:arrange).
function M.banList(dex)
    local s = G.DB.save
    s.pban = s.pban or {}
    local l = s.pban[dex]
    if type(l) ~= "table" then l = {}; s.pban[dex] = l end
    return l
end
local function bindList(dex)
    local s = G.DB.save
    s.pbind = s.pbind or {}
    local l = s.pbind[dex]
    if type(l) ~= "table" then l = {}; s.pbind[dex] = l end
    return l
end

local um = {}
local umDex, umMode, umIds, umPage, umSlot = nil, "ban", {}, 1, 1
local UM_PER = 14                 -- 2 columnas x 7 filas
function um.enter(d)
    d = d or {}                     -- (`--ui=upgmoves`: atajos del compañero)
    umDex, umMode = d.dex or G.DB.save.partner, d.mode or "bind"
    umPage, umSlot = 1, 1
    local mon = G.DEX_BY[umDex]
    local start = G.startMoveOf(umDex)
    umIds = {}
    local seen = {}
    for _, id in ipairs(G.Moves.poolFor(mon)) do
        if not seen[id] and (umMode == "bind" or id ~= start) then umIds[#umIds + 1] = id; seen[id] = true end
    end
    if umMode == "bind" and not seen[start] then umIds[#umIds + 1] = start end
    table.sort(umIds, function(a, b) return G.Moves.BY_ID[a].name < G.Moves.BY_ID[b].name end)
    G.TopUI.overlay = function()
        G.TopUI.pokemonCard(umDex, { footer = umMode == "ban"
            and "Los movimientos vetados no te salen nunca en las cartas"
            or "Cada movimiento con atajo va siempre en su hueco (1-4)" })
    end
end
function um.draw()
    local mon = G.DEX_BY[umDex]
    local y0 = 26
    if umMode == "ban" then
        local max = G.DB.upgradesOf(umDex).ban or 0
        UI.text("Veto · " .. mon.name .. " (" .. #M.banList(umDex) .. "/" .. max .. ")", 0, 7, { size = 12, w = W, align = "center", color = UI.C.gold })
    else
        UI.text("Atajos · " .. mon.name, 0, 4, { size = 12, w = W, align = "center", color = UI.C.gold })
        local binds = bindList(umDex)
        for i = 1, 4 do
            local id = binds[i]
            local name = (id and G.Moves.BY_ID[id]) and G.Moves.BY_ID[id].name or "Libre"
            UI.button("slot" .. i, 4 + (i - 1) * 79, 20, 75, 18, i .. ": " .. name, { size = 10, on = umSlot == i, color = "#3c6cc4" })
        end
        y0 = 46
    end
    local pages = math.max(1, math.ceil(#umIds / UM_PER))
    if umPage > pages then umPage = pages end
    local bans, binds = M.banList(umDex), bindList(umDex)
    for k = 1, UM_PER do
        local idx = (umPage - 1) * UM_PER + k
        local id = umIds[idx]
        if not id then break end
        local m = G.Moves.BY_ID[id]
        local col, row = (k - 1) % 2, math.floor((k - 1) / 2)
        local x, y = 4 + col * 158, y0 + row * 23
        local on, label = false, m.name
        if umMode == "ban" then
            on = U.contains(bans, id)
            if on then label = "X " .. m.name end
        else
            for i = 1, 4 do if binds[i] == id then label = i .. " · " .. m.name; on = i == umSlot end end
        end
        UI.button("mv" .. idx, x, y, 154, 20, label, { size = 10, icon = "move:" .. id, on = on,
                  color = (umMode == "ban" and on) and "#d04848" or U.TYPE_COLOR[m.type] })
    end
    if pages > 1 then
        UI.button("pprev", 4, 218, 40, 18, "<", { size = 10, enabled = umPage > 1 })
        UI.text(umPage .. "/" .. pages, 46, 222, { size = 10, w = 40, align = "center" })
        UI.button("pnext", 88, 218, 40, 18, ">", { size = 10, enabled = umPage < pages })
    end
    UI.button("back", 200, 218, 116, 18, "Volver", { size = 10 })
end
function um.touch(x, y)
    local id = UI.hit(x, y)
    if not id then return end
    if id == "back" then UI.show("upgrades") return end
    if id == "pprev" then umPage = math.max(1, umPage - 1) return end
    if id == "pnext" then umPage = umPage + 1 return end
    local s = tonumber(id:match("^slot(%d)$"))
    if s then umSlot = s; G.Audio.sfx("click") return end
    local idx = tonumber(id:match("^mv(%d+)$"))
    local mid = idx and umIds[idx]
    if not mid then return end
    if umMode == "ban" then
        local l = M.banList(umDex)
        local i = U.indexOf(l, mid)
        local max = G.DB.upgradesOf(umDex).ban or 0
        if i then table.remove(l, i)
        elseif #l >= max then UI.toast("Ya tienes " .. max .. " vetados: quita uno primero") return
        else l[#l + 1] = mid end
    else
        -- Un movimiento sólo puede estar en un hueco; tocar el del hueco lo deja libre.
        local l = bindList(umDex)
        local was = l[umSlot]
        for i = 1, 4 do if l[i] == mid then l[i] = nil end end
        if was ~= mid then l[umSlot] = mid end
    end
    G.DB.commit()
    G.Audio.sfx("select")
end
function um.button(b)
    if b == "b" then UI.show("upgrades")
    elseif b == "leftshoulder" then umPage = math.max(1, umPage - 1)
    elseif b == "rightshoulder" then umPage = umPage + 1 end
end
UI.register("upgmoves", um)

-- ---------------- gacha ----------------
local gacha = {}
local gGen, gResults, gIdx = 1, {}, 0
-- Arriba: el resultado elegido o el banner. Una sola función; los textos se hacen
-- al tirar o al cambiar de banner, no en cada fotograma.
local gCard = { shiny = false, footer = "" }
local gTop = { key = nil, gen = nil, title = "", feat = nil }
local function gachaOverlay()
    if #gResults > 0 and gIdx >= 1 then
        local r = gResults[gIdx]
        local k = gIdx * 1000 + #gResults
        if gTop.key ~= k or gTop.res ~= gResults then
            gTop.key, gTop.res = k, gResults
            gCard.shiny = r.shiny
            gCard.footer = (r.shiny and "¡SHINY! " or "") .. (r.isNew and "¡Nuevo!" or ("Repetido: +" .. (r.coins or 0) .. " monedas")) .. "  (" .. gIdx .. "/" .. #gResults .. ")"
        end
        G.TopUI.pokemonCard(r.dex, gCard)
    else
        if gTop.gen ~= gGen then
            gTop.gen = gGen
            gTop.title = "Banner de " .. GEN[gGen]
            gTop.feat = nil
            local b = G.Gacha.banner and G.Gacha.banner(gGen)
            if b and b.featured then
                local names = {}
                for i, d in ipairs(b.featured) do names[i] = G.DEX_BY[d] and G.DEX_BY[d].name or tostring(d) end
                gTop.feat = "Destacados: " .. table.concat(names, " · ")
            end
        end
        UI.text(gTop.title, 0, 100, to(22, UI.C.gold, 400, "center"))
        if gTop.feat then UI.text(gTop.feat, 0, 130, to(12, nil, 400, "center")) end
    end
end
function gacha.enter()
    gResults = {}
    lazyReset()
    G.TopUI.overlay = gachaOverlay
end
local RID = idList("r")
local gm = { pity = nil, rates = "" }
function gacha.draw()
    local s = G.DB.save
    local C = UI.C
    local t = s.tickets or { t1 = 0, t10 = 0 }
    for g = 1, 9 do
        UI.button(GENID[g], 2 + (g - 1) * 35, 2, 33, 16, GEN5[g], bo(10, g == gGen))
    end
    local pity = s.pity and s.pity[gGen] or (s.pity and s.pity[tostring(gGen)]) or 0
    if gm.pity ~= pity then
        gm.pity = pity
        gm.rates = "Común 45% · Poco común 30% · Rara 17% · Épica 6,5% · Legendaria 1,5% · Shiny 1% · Pity " .. pity .. "/70"
    end
    UI.text(gm.rates, 4, 21, to(10, C.muted, W - 8, "center"))
    UI.button("p1", 10, 50, 96, 30, "Tirar x1\n1 ticket", bo(10, nil, nil, (t.t1 or 0) >= 1))
    UI.button("p10", 112, 50, 96, 30, "Tirar x10\n10 tickets", bo(10, nil, nil, (t.t1 or 0) >= 10))
    UI.button("p10b", 214, 50, 96, 30, "Tirar x10\n1 ticket x10", bo(10, nil, "#2a1a3a", (t.t10 or 0) >= 1))
    -- Resultados
    if #gResults > 0 then
        for i = 1, #gResults do
            local r = gResults[i]
            local x, y = 10 + ((i - 1) % 5) * 60, 90 + math.floor((i - 1) / 5) * 56
            local on = i == gIdx
            U.setColor(r.shiny and "#1a2a3a" or (on and "#2a3a1a" or C.panel))
            lg.rectangle("fill", x, y, 56, 50, 4, 4)
            if on then U.setColor(C.gold); lg.rectangle("line", x + 0.5, y + 0.5, 55, 49, 4, 4) end
            lg.setColor(1, 1, 1, 1)
            stillLazy(r.dex, x + 28, y + 36, 0.5)
            UI.text(r.label, x, y + 38, to(10, r.isNew and C.gold or C.muted, 56, "center"))
            UI.hitbox(RID[i], x, y, 56, 50)
        end
    else
        UI.text("Los tickets se ganan jugando: algunos Pokémon sueltan uno, los jefes y los legendarios dan tickets x10.", 20, 100, to(10, C.muted, W - 40, "center"))
    end
    UI.button("back", 110, 206, 100, 18, "Volver", bo(10))
    coinsLine()
end
local function pull(n, payWith)
    local ok, res = pcall(G.Gacha.pull, gGen, n, payWith)
    if not ok then UI.toast("Gacha: " .. tostring(res)) return end
    if not res or #res == 0 then UI.toast("No tienes tickets suficientes") return end
    gResults = res
    gIdx = 1
    for _, r in ipairs(res) do
        local p = G.DEX_BY[r.dex]
        r.label = (r.isNew and "¡Nuevo! " or "") .. (p and p.name or "")
    end
    -- Solo la hoja del primero (el de la ficha de arriba); las de la rejilla se
    -- cargan una por fotograma (stillLazy) en vez de 10 de golpe (~0,4 s en la 3DS).
    G.Sprites.preload({ res[1].dex }, false)
    lazyReset()
    G.Audio.sfx("legend")
    -- (G.Gacha.pull ya guarda la partida: otro commit era codificar y escribir en
    -- la SD otra vez lo mismo.)
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
-- Arriba, los logros conseguidos: los textos se hacen al entrar (antes se recorrían
-- todos los logros y se montaban los textos en cada fotograma).
local goalsTop = { head = "", lines = {}, titles = nil }
local function goalsOverlay()
    local C = UI.C
    UI.text(goalsTop.head, 0, 20, to(16, C.gold, 400, "center"))
    local lines = goalsTop.lines
    for i = 1, #lines do UI.text(lines[i], 20, 44 + (i - 1) * 12, to(10, nil, 360)) end
    if goalsTop.titles then UI.text(goalsTop.titles, 20, 222, to(10, C.muted, 360)) end
end
local function goalsRefresh()
    local s = G.DB.save
    goalsTop.head = "Logros: " .. U.count(s.ach or {}) .. " / " .. #G.AchDefs.LIST
    local lines = {}
    for _, a in ipairs(G.AchDefs.LIST) do
        if s.ach and s.ach[a.id] then
            lines[#lines + 1] = "· " .. a.name .. (a.title and ("  [" .. a.title .. "]") or "")
            if #lines >= 15 then break end
        end
    end
    goalsTop.lines = lines
    local titles = G.Progress.titles()
    goalsTop.titles = #titles > 0 and ("Títulos: " .. table.concat(titles, ", ")) or nil
end
function goals.enter()
    G.Progress.ensure(G.DB.save)
    goalsRefresh()
    G.TopUI.overlay = goalsOverlay
end
-- Textos de cada misión (la tabla de la misión vive en el guardado): enunciado,
-- premio y progreso, rehecho solo si cambia el progreso.
local missionTxt = setmetatable({}, { __mode = "k" })
local function mText(m)
    local t = missionTxt[m]
    if not t or t.goal ~= m.goal or t.id ~= m.id then
        local def = G.MissionDefs.BY[m.id]
        t = { id = m.id, goal = m.goal, txt = G.Progress.text(m), reward = rewardText(def and def.reward or {}), prog = nil, progTxt = "" }
        missionTxt[m] = t
    end
    local p = math.floor(m.prog)
    if t.prog ~= p then t.prog = p; t.progTxt = p .. "/" .. m.goal end
    return t
end
local GID = { [false] = idList("d"), [true] = idList("w") }
local EMPTYL = {}
local function goalBlock(label, list, weekly, y)
    local C = UI.C
    UI.text(label, 6, y, to(12, C.gold))
    y = y + 16
    list = list or EMPTYL
    for i = 1, #list do
        local m = list[i]
        local t = mText(m)
        local done = G.Progress.done(m)
        UI.text(t.txt, 6, y, to(10, nil, 200))
        UI.bar(6, y + 12, 200, 5, math.min(1, m.prog / m.goal), done and C.green or C.blue)
        UI.text(t.progTxt, 210, y, to(10, C.muted))
        if m.claimed then
            UI.text("Recogido", 250, y + 3, to(10, C.muted))
        else
            UI.button(GID[weekly][i], 250, y, 66, 18, done and "Recoger" or t.reward, bo(10, nil, done and "#2a2410" or nil, done, done and C.gold or nil))
        end
        y = y + 24
    end
    return y
end
function goals.draw()
    local s = G.DB.save
    local Mi = s.missions or EMPTYL
    local y = goalBlock("Misiones diarias", Mi.daily, false, 4)
    goalBlock("Misiones semanales", Mi.weekly, true, y)
    UI.button("back", 110, 216, 100, 18, "Volver", bo(10))
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
        if m and G.Progress.claim(m, kind == "w") then G.Audio.sfx("confirm"); UI.toast("Premio recogido"); goalsRefresh() end
    end
end
function goals.button(b) if b == "b" then UI.show("menu") end end
UI.register("goals", goals)

-- ---------------- modo Fases ----------------
local stages = {}
local stSel = 1
-- Ficha de arriba de la fase elegida: textos hechos al elegirla (stageInfo) y una
-- sola función de ficha (top.lua escribe en la SD cada vez que cambia).
local stTop = { st = nil, unlocked = false, fase = "", info = "", bosses = "", foot = "", footCol = nil }
local function stagesOverlay()
    local T, C = stTop, UI.C
    lg.setColor(0, 0, 0, 0.45)
    lg.rectangle("fill", 0, 0, 400, 240)
    UI.text(T.fase, 0, 24, to(12, C.muted, 400, "center"))
    UI.text(T.st.name, 0, 38, to(22, T.unlocked and C.gold or C.muted, 400, "center"))
    UI.text(T.info, 0, 68, to(12, nil, 400, "center"))
    UI.text(T.bosses, 0, 86, to(10, C.muted, 400, "center"))
    -- Jefes dibujados
    local bs = T.st.bosses
    local n = #bs
    for i = 1, n do
        local x = 200 + (i - (n + 1) / 2) * 70
        G.Sprites.drawStill(bs[i].dex, x, 170, 1)
    end
    UI.text(T.foot, 0, 196, to(12, T.footCol, 400, "center"))
    UI.text("Tu Pokémon evoluciona durante la partida a sus niveles de los juegos", 0, 218, to(10, C.muted, 400, "center"))
end
local function stageInfo()
    local st = G.Stages.LIST[stSel]
    local unlocked = G.Stages.isUnlocked(stSel)
    local prog = G.Stages.progress()
    local e = prog[stSel] or prog[tostring(stSel)]
    local T, C = stTop, UI.C
    T.st, T.unlocked = st, unlocked
    T.fase = "Fase " .. stSel
    T.info = "10 minutos · 20 oleadas · " .. #st.bosses .. " jefes"
    local names = {}
    for i, b in ipairs(st.bosses) do names[i] = G.DEX_BY[b.dex].name end
    T.bosses = "Jefes: " .. table.concat(names, " → ")
    if e and e.cleared then
        T.foot, T.footCol = "Superada · mejor tiempo " .. U.mmss(e.best or 0), C.green
    elseif not unlocked then
        T.foot, T.footCol = "Supera la fase anterior para desbloquearla", C.red
    else
        T.foot, T.footCol = "Derrota al jefe final para superar la fase", nil
    end
    G.TopUI.overlay = stagesOverlay
end
function stages.enter()
    -- Sólo los jefes de la fase que se ve (los de las demás se cargan al elegirla).
    local dexes = {}
    for _, b in ipairs(G.Stages.LIST[stSel].bosses) do dexes[#dexes + 1] = b.dex end
    G.Sprites.preload(dexes, false)
    stageInfo()
end
local SID = idList("s")
local stLabel = {}             -- [i] = { cleared, texto }
function stages.draw()
    UI.text("Fases", 0, 4, to(16, UI.C.gold, W, "center"))
    local LIST = G.Stages.LIST
    for i = 1, #LIST do
        local st = LIST[i]
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local x, y = 10 + col * 152, 26 + row * 40
        local unlocked = G.Stages.isUnlocked(i)
        local cleared = G.Stages.isCleared(i)
        local L = stLabel[i]
        if not L or L[1] ~= cleared or L[3] ~= st.name then
            L = { cleared, (cleared and "* " or "") .. st.name, st.name }
            stLabel[i] = L
        end
        UI.button(SID[i], x, y, 148, 34, L[2], bo(10, i == stSel, cleared and "#1b3a2a" or nil, unlocked))
    end
    UI.button("go", 170, 206, 140, 22, "Empezar fase", bo(12, nil, "#3c9c54", G.Stages.isUnlocked(stSel)))
    UI.button("back", 10, 206, 100, 22, "Volver", bo(10))
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
-- Medallas conseguidas, ordenadas. Se hacían (y ordenaban) tres veces por
-- fotograma; en la tarjeta no cambian: se guardan al entrar (card.enter).
local medalList = nil
local function medals()
    if medalList then return medalList end
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
    medalList = out
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
-- Suelta las imágenes de la tarjeta (todas, o solo las de claves que empiezan por
-- `prefix`: al cambiar de fondo no hace falta volver a cargar entrenador, paneles y
-- Poké Balls, ~40 ms cada una en la 3DS).
local function releaseCardImages(prefix)
    for k, im in pairs(cardImg) do
        if not prefix or k:sub(1, #prefix) == prefix then
            if im and im.release then pcall(im.release, im) end
            cardImg[k] = nil
        end
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

-- ¿Tienes este Pokémon? (las claves del guardado pueden ser número o texto)
local function owns(d)
    local o = G.DB.save.owned or {}
    return o[d] ~= nil or o[tostring(d)] ~= nil
end

-- Datos ya preparados de la tarjeta (textos, anchos, equipo, estilo). Antes se
-- rehacían en cada fotograma (tablas, string.format, U.count, ordenar medallas...);
-- ahora al entrar y al cambiar algo (cardDirty).
local cd = nil
local function cardDirty() cd = nil end
local PFO = { s = 1, color = "#ffffff", noOutline = true }      -- opciones de PF.print (reutilizada)
local function pfo(col) PFO.color = col; return PFO end
local PNKEY = setmetatable({}, { __index = function(t, k) local v = { 'pn' .. k, 'img/panels/' .. k }; t[k] = v; return v end })
local BALLKEY, BALLPATH = {}, {}
for i = 1, 8 do BALLKEY[i] = 'ball' .. i; BALLPATH[i] = 'img/badges/' .. i end
local function cardData()
    if cd then return cd end
    local s = G.DB.save
    local prof = s.profile or {}
    local favs = prof.favs or {}
    local st = s.stats or {}
    local PF = G.PixelFont
    cd = {}
    -- Equipo: compañero y 5 favoritos; sólo salen los que tienes.
    local src = { s.partner or false, favs[1] or false, favs[2] or false, favs[3] or false, favs[4] or false, favs[5] or false }
    local team = {}
    for i = 1, 6 do
        local d = src[i]
        team[i] = (d and owns(d)) and d or nil
    end
    cd.team = team
    local ms, total = #medals(), #G.AchDefs.LIST
    cd.have, cd.total = ms, total
    -- Panel de datos (diseños que no son "de juego")
    local title = string.upper((prof.title and prof.title ~= "") and prof.title or "Novato")
    cd.title, cd.titleW = title, PF.width(title, 1)
    local rows = {
        { "DINERO", (s.coins or 0) .. " P" },
        { "POKEDEX", U.count(s.owned or {}) .. "/" .. #G.DEX },
        { "SHINIES", tostring(U.count(s.shiny or {})) },
        { "TIEMPO", U.mmss(st.playTime or 0) },
        { "MEJOR", U.mmss(st.bestTime or 0) },
        { "FASES", tostring(st.stagesCleared or 0) },
        { "MEDALLAS", ms .. "/" .. total },
    }
    -- Cuántas faltan para la siguiente Poké Ball de la tarjeta.
    cd.nextBall = nil
    for i = 1, 8 do
        local need = math.ceil(i * total / 8)
        if ms < need then
            rows[#rows + 1] = { "SIG. BALL", (need - ms) .. " MEDALLAS" }
            cd.nextBall = "SIG. BALL: " .. (need - ms)
            cd.nextBallW = PF.width(cd.nextBall, 1)
            break
        end
    end
    for i = 1, #rows do rows[i][3] = PF.width(rows[i][2], 1) end
    cd.rows = rows
    cd.medTxt = "MEDALLAS " .. ms .. "/" .. total
    cd.medW = PF.width(cd.medTxt, 1)
    cd.equipoW = PF.width("EQUIPO", 1)
    -- Tarjeta
    cd.id = "ID " .. string.format("%05d", (s.created or 0) % 65536)
    cd.name = string.upper(s.name or "Entrenador")
    if CS and #CS.cards > 0 then
        local c = CS.cards[pickIndex(CS.cards, prof.cardBg)]
        cd.c = c
        cd.bgKey, cd.bgPath = 'bg' .. c.id, 'img/cards/' .. c.id
        local tr = CS.trainers[pickIndex(CS.trainers, prof.trainer)]
        cd.tr = tr
        if tr then cd.trKey, cd.trPath = 'tr' .. tr.atlas, 'img/trainers/' .. tr.atlas end
        if c.layout == "game" then
            local vals = {
                name = cd.name,
                money = (s.coins or 0) .. " P",
                dex = U.count(s.owned or {}) .. "/" .. #G.DEX,
                time = U.mmss(st.playTime or 0),
                stages = tostring(st.stagesCleared or 0),
            }
            local rv = {}
            for i, r in ipairs(c.rows) do
                local v = vals[r[2]] or ""
                rv[i] = { v, PF.width(v, 1) }
            end
            cd.rowVals = rv
        end
    end
    return cd
end

local function statsPanel(x, y, w)
    local D = cardData()
    local PF = G.PixelFont
    U.setColor("#101828", 0.88)
    lg.rectangle("fill", x, y, w, 171, 6, 6)
    U.setColor("#4a6ab8")
    lg.rectangle("line", x + 0.5, y + 0.5, w - 1, 170, 6, 6)
    PF.print(D.title, x + (w - D.titleW) / 2, y + 7, pfo("#ffd23f"))
    local rows = D.rows
    for i = 1, #rows do
        local r = rows[i]
        local yy = y + 21 + (i - 1) * 18
        PF.print(r[1], x + 7, yy, pfo("#9fb4e8"))
        PF.print(r[2], x + w - 7 - r[3], yy + 9, pfo("#ffffff"))
    end
end

-- Panel de 50x30 de un Pokémon: sprite oficial de Negro/Blanco si lo hay (1..649);
-- si no, fondo claro con su sprite del juego.
local function drawPanel(d, x, y)
    local p = d and CS and CS.panels[d]
    if p then
        local k = PNKEY[p[1]]
        local im = cardImage(k[1], k[2])
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
    local D = cardData()
    U.setColor("#101828", 0.88)
    lg.rectangle("fill", x, y, w, 171, 6, 6)
    U.setColor("#4a6ab8")
    lg.rectangle("line", x + 0.5, y + 0.5, w - 1, 170, 6, 6)
    local PF = G.PixelFont
    PF.print("EQUIPO", x + (w - D.equipoW) / 2, y + 7, pfo("#ffd23f"))
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
    PF.print(D.medTxt, x + (w - D.medW) / 2, y + 128, pfo("#9fb4e8"))
    if D.nextBall then
        PF.print(D.nextBall, x + (w - D.nextBallW) / 2, y + 144, pfo("#ffffff"))
    end
end

local function drawCard()
    local D = cardData()
    local CX, CY = 4, 34                      -- tarjeta a tamaño real (246x171)
    local team = D.team
    if not D.c then statsPanel(CX + 250, CY, 400 - CX - 254) return end
    local c = D.c
    local game = c.layout == "game"
    if game then teamPanel(CX + 250, CY, 400 - CX - 254, team) else statsPanel(CX + 250, CY, 400 - CX - 254) end
    lg.setColor(1, 1, 1, 1)
    local bg = cardImage(D.bgKey, D.bgPath)
    if bg then lg.draw(bg, CX, CY) end
    -- Entrenador (sprite oficial)
    local tr = D.tr
    if tr then
        local im = cardImage(D.trKey, D.trPath)
        if im then lg.draw(im, quadFor(tr.x, tr.y, 80, 80, im), CX + c.trainer[1], CY + c.trainer[2]) end
    end
    local PF = G.PixelFont
    if game then
        -- Como en los juegos: título, número de ID y los datos en filas.
        PF.print("TARJETA DE ENTRENADOR", CX + c.title[1], CY + c.title[2], pfo(c.titleColor))
        PF.print(D.id, CX + c.code[1], CY + c.code[2], pfo(c.codeColor))
        local rv = D.rowVals
        for i, r in ipairs(c.rows) do
            PF.print(r[1], CX + c.labelX, CY + r[3], pfo(c.labelColor))
            PF.print(rv[i][1], CX + c.valueX - rv[i][2], CY + r[3], pfo(c.valueColor))
        end
    else
        PF.print("TARJETA DE ENTRENADOR", CX + 10, CY + 10, pfo(c.titleColor or "#ffffff"))
        PF.print(D.name, CX + c.name[1], CY + c.name[2] - 3, pfo(c.nameColor))
        PF.print(D.id, CX + c.code[1], CY + c.code[2] - 3, pfo(c.codeColor))
        -- Equipo: compañero y 5 favoritos
        for i = 1, 6 do
            local pos = c.pokemon[i]
            drawPanel(team[i], CX + pos[1], CY + pos[2])
        end
    end
    -- 8 Poké Balls de colores en los huecos de medalla: las medallas del juego se
    -- reparten en 8 tramos (con 127: 16, 32, 48... 127) y cada tramo cumplido
    -- desbloquea una. Las bloqueadas, en silueta.
    local have, total = D.have, D.total
    for i = 1, 8 do
        local pos = c.badges[i]
        local im = pos and cardImage(BALLKEY[i], BALLPATH[i])
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
-- Textos de la pantalla de abajo de la tarjeta (se rehacen con cardDirty).
local cb = nil
local FAVID = idList("fav")
local function cardBottom()
    if cb and cb.cd == cd and cd then return cb end
    local D = cardData()
    local s = G.DB.save
    local prof = s.profile
    cb = { cd = D }
    if CS then
        local ci = pickIndex(CS.cards, prof.cardBg)
        cb.bgTxt = "Fondo: " .. CS.cards[ci].cat .. "  (" .. ci .. "/" .. #CS.cards .. ")"
        local ti = pickIndex(CS.trainers, prof.trainer)
        cb.trTxt = "Entrenador: " .. CS.trainers[ti].cat .. "  (" .. ti .. "/" .. #CS.trainers .. ")"
    end
    cb.fav = {}
    for i = 1, 5 do
        local d = prof.favs[i]
        cb.fav[i] = (i + 1) .. ": " .. (d and owns(d) and G.DEX_BY[d] and G.DEX_BY[d].name or "—")
    end
    cb.nTitles = #G.Progress.titles()
    cb.titleTxt = "Título: " .. (prof.title ~= "" and prof.title or "Novato")
    return cb
end
function card.enter()
    local s = G.DB.save
    s.profile = s.profile or { favs = {}, title = "" }
    s.profile.favs = s.profile.favs or {}
    ownedList = {}
    for d in pairs(s.owned or {}) do if G.DEX_BY[tonumber(d) or d] then ownedList[#ownedList + 1] = tonumber(d) or d end end
    table.sort(ownedList)
    G.Sprites.preload(s.profile.favs, false)
    medalList = nil
    cardDirty()
    G.TopUI.overlay = drawCard
end
function card.leave() releaseCardImages(); quadCache = {} end
-- Fila "< etiqueta >" para recorrer una lista.
local function cycler(idm, idp, y, label)
    UI.button(idm, 10, y, 34, 22, "<", bo(12))
    UI.text(label, 46, y + 5, to(10, nil, W - 92, "center"))
    UI.button(idp, W - 44, y, 34, 22, ">", bo(12))
end
function card.draw()
    local B = cardBottom()
    UI.text("Tarjeta de entrenador", 0, 4, to(16, UI.C.gold, W, "center"))
    if CS then
        cycler("bg-", "bg+", 26, B.bgTxt)
        cycler("tr-", "tr+", 52, B.trTxt)
    end
    -- Equipo: el 1 es tu compañero (se cambia en Pokémon); 2..6, favoritos.
    for i = 1, 5 do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        UI.button(FAVID[i], 10 + col * 152, 80 + row * 26, 148, 22, B.fav[i], bo(10))
    end
    UI.button("title", 162, 132, 148, 22, B.titleTxt, bo(10, nil, nil, B.nTitles > 0))
    UI.text("Toca un hueco para cambiar de Pokémon. L/R: fondo · Cruceta: entrenador", 10, 162, to(10, UI.C.muted, W - 20, "center"))
    UI.button("back", 110, 206, 100, 22, "Volver", bo(10))
end
local function cycle(field, list, step)
    local s = G.DB.save
    local i = pickIndex(list, s.profile[field])
    i = (i - 1 + step) % #list + 1
    s.profile[field] = list[i].id
    releaseCardImages(field == "cardBg" and "bg" or "tr")
    cardDirty()
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
        cardDirty()
        G.DB.commit()
        return
    end
    local i = tonumber(id:match("^fav(%d+)$"))
    if i and #ownedList > 0 then
        local k = (U.indexOf(ownedList, prof.favs[i]) or 0) % #ownedList + 1
        prof.favs[i] = ownedList[k]
        G.Sprites.preload({ ownedList[k] }, false)
        cardDirty()
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
