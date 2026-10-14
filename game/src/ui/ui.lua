-- ui.lua — interfaz de la pantalla inferior (320x240, táctil): pantallas, widgets
-- en modo inmediato y avisos. Cada pantalla es una tabla registrada con
-- UI.register(nombre, { enter(data), draw(), touch(x,y), button(b), update(dt) }).
-- Los widgets se dibujan en draw() y se registran para el toque; el toque se
-- resuelve en el callback de la pantalla con UI.hit(x, y) -> id.
local U = G.U
local UI = {}
G.UI = UI

UI.W, UI.H = 320, 240
local lg = love.graphics

-- ---------------- fuentes ----------------
local fonts = {}
function UI.font(size)
    size = size or 12
    local f = fonts[size]
    if f then return f end
    local ok, res
    if G_STEP then G_STEP("fuente nueva tamaño " .. tostring(size)) end
    if U.CONSOLE then
        -- En consola, fuente del sistema: mkbcfnt no convierte Pixelify Sans (fuente
        -- variable, saca 2 glifos) y la del sistema trae acentos. A igual tamaño se ve
        -- bastante más pequeña que la Pixelify del PC: se crea 2 puntos mayor.
        ok, res = pcall(lg.newFont, size + 2)
    else
        ok, res = pcall(lg.newFont, "fonts/pixelify.ttf", size)
    end
    if not ok or not res then
        ok, res = pcall(lg.newFont, size)
        if not ok then res = lg.getFont() end
    end
    fonts[size] = res
    return res
end

function UI.load()
    UI.font(10); UI.font(12); UI.font(16); UI.font(22)
end

-- ---------------- colores ----------------
UI.C = {
    bg = "#0a1430", panel = "#13224a", panel2 = "#1b2d5c", line = "#3a5a9a",
    text = "#eaf2ff", muted = "#8fa3c4", gold = "#ffd23f", red = "#ff5f6d", green = "#5fe08a",
    blue = "#4fd1ff", pink = "#ff8ad8", purple = "#b48aff",
}

-- ---------------- pantallas ----------------
local screens = {}
local current, currentName = nil, nil
local hits = {}          -- widgets tocables de este fotograma: { id, x, y, w, h }
local nHits = 0
local toasts = {}

function UI.register(name, scr) screens[name] = scr end
function UI.current() return currentName end
function UI.screen(name) return screens[name] end

function UI.show(name, data)
    local scr = screens[name]
    if not scr then print("[UI] pantalla desconocida: " .. tostring(name)) return end
    -- (Sin G_STEP: cada uno escribía en la SD, ~20 ms en cada cambio de pantalla.)
    if current and current.leave then current.leave() end
    current, currentName = scr, name
    G.TopUI.overlay = nil
    if scr.enter then scr.enter(data) end
end

function UI.update(dt)
    if current and current.update then current.update(dt) end
    for i = #toasts, 1, -1 do
        toasts[i].t = toasts[i].t - dt
        if toasts[i].t <= 0 then table.remove(toasts, i) end
    end
    -- Avisos de progreso (misiones, logros).
    local q = G.Progress and G.Progress.toasts
    if q and #q > 0 then
        local n = table.remove(q, 1)
        UI.toast(n.title .. (n.sub and n.sub ~= "" and (" · " .. n.sub) or ""), 3.2)
    end
end

-- Fondo de las pantallas táctiles al estilo de DS: base oscura con rayas
-- diagonales suaves (como los menús de Negro/Blanco) y una franja más clara abajo.
function UI.background()
    -- El mismo fondo que la pantalla de movimientos de Platino: morado con la
    -- Poké Ball grande y su borde (G.RunUI.platinumBackground).
    if G.RunUI and G.RunUI.platinumBackground then
        G.RunUI.platinumBackground(0)
        return
    end
    U.setColor(UI.C.bg)
    lg.rectangle("fill", 0, 0, UI.W, UI.H)
    lg.setColor(1, 1, 1, 1)
end

-- Barra de DS (arriba o abajo): banda oscura con línea clara.
function UI.bar2(y, h)
    U.setColor("#050a1c", 0.85)
    lg.rectangle("fill", 0, y, UI.W, h)
    U.setColor("#3a5a9a")
    lg.rectangle("fill", 0, y == 0 and h - 1 or y, UI.W, 1)
    lg.setColor(1, 1, 1, 1)
end

UI.frame = 0                -- fotogramas dibujados (para repartir trabajo entre fotogramas)
function UI.draw()
    nHits = 0
    UI.frame = UI.frame + 1
    UI.background()
    if G_STEP and current and not current.__drawn then G_STEP("dibuja " .. tostring(currentName)) end
    if current and current.draw then current.draw() end
    if current and not current.__drawn then current.__drawn = true; if G_STEP then G_STEP("dibujada " .. tostring(currentName)) end end
    -- Avisos
    if #toasts > 0 then
        local t = toasts[1]
        local a = math.min(1, t.t * 3, (t.dur - t.t) * 3 + 1)
        lg.setFont(UI.font(10))
        U.setColor("#000000", 0.75 * a)
        lg.rectangle("fill", 8, UI.H - 24, UI.W - 16, 18, 4, 4)
        U.setColor(UI.C.gold, a)
        lg.printf(t.text, 12, UI.H - 21, UI.W - 24, "center")
        lg.setColor(1, 1, 1, 1)
    end
end

function UI.touch(x, y)
    if current and current.touch then current.touch(x, y) end
end
function UI.touchMoved(x, y)
    if current and current.touchMoved then current.touchMoved(x, y) end
end
function UI.touchReleased(x, y)
    if current and current.touchReleased then current.touchReleased(x, y) end
end
-- Botón del mando pulsado (gamepad): se lo pasa a la pantalla actual.
function UI.pressButton(b)
    if current and current.button then current.button(b) end
end

function UI.toast(text, secs)
    toasts[#toasts + 1] = { text = text, t = secs or 2.4, dur = secs or 2.4 }
end

-- ---------------- widgets ----------------

local function addHit(id, x, y, w, h)
    nHits = nHits + 1
    local h0 = hits[nHits]
    if not h0 then h0 = {}; hits[nHits] = h0 end
    h0.id, h0.x, h0.y, h0.w, h0.h = id, x, y, w, h
end

-- Devuelve el id del widget bajo (x, y) o nil. Si hay varios, el último dibujado.
function UI.hit(x, y)
    for i = nHits, 1, -1 do
        local h = hits[i]
        if x >= h.x and x <= h.x + h.w and y >= h.y and y <= h.y + h.h then return h.id end
    end
    return nil
end

function UI.panel(x, y, w, h, col, alpha, r)
    U.setColor(col or UI.C.panel, alpha or 1)
    lg.rectangle("fill", x, y, w, h, r or 6, r or 6)
    lg.setColor(1, 1, 1, 1)
end

-- ---------------- textos ya colocados (TextBatch) ----------------
-- En la 3DS cada print/printf vuelve a decodificar el texto, colocar cada letra y
-- crear sus vértices (y el botón lo hacía 6 veces: 5 de contorno y la letra). Los
-- textos que se repiten fotograma a fotograma se guardan en un TextBatch (LÖVE
-- Potion; Text en LÖVE 11) ya colocado, con sus colores y todas sus pasadas
-- dentro: un solo dibujo. Los colores van en el propio texto (en la consola el
-- TextBatch no usa el color actual) y se dibuja con el color blanco.
-- Solo se guarda un texto a partir de su 3.er uso (los que cambian cada fotograma,
-- como un reloj, siguen con print); como mucho TB_MAX a la vez.
local newBatch = lg.newTextBatch or lg.newText
UI.TEXT_BATCH = newBatch ~= nil
local TB, nTB, TB_MAX = {}, 0, 96          -- TB[fuente][texto][clave] = { b = batch, v = vértices }
local seen, nSeen = {}, 0                  -- texto -> veces visto
local CT = { { 1, 1, 1, 1 }, "" }          -- texto con color (se reutiliza; addf lo copia)
local colorIds, nColorIds = {}, 0          -- "#rrggbb" -> número (para las claves)
local clearBatches
local function cid(hex)
    local i = colorIds[hex]
    if not i then
        -- (colores que cambian cada fotograma: que la tabla no crezca sin fin)
        if nColorIds >= 500 then clearBatches(); colorIds, nColorIds = {}, 0 end
        nColorIds = nColorIds + 1; i = nColorIds; colorIds[hex] = i
    end
    return i
end
clearBatches = function()
    for _, byF in pairs(TB) do
        for _, byS in pairs(byF) do
            for _, e in pairs(byS) do
                if type(e) == "table" and e.b.release then pcall(e.b.release, e.b) end
            end
        end
    end
    TB, nTB = {}, 0
end
UI.clearTextCache = clearBatches
-- Entrada guardada de (fuente, texto, clave) o nil si aún no toca. Si es nueva
-- (segundo resultado true), el que llama le añade el texto con addText.
local function batchFor(f, str, key)
    local byF = TB[f]
    local byS = byF and byF[str]
    local e = byS and byS[key]
    if e then return e, false end
    if not UI.TEXT_BATCH then return nil end
    local n = seen[str]
    if not n then
        nSeen = nSeen + 1
        if nSeen > 400 then seen = {}; nSeen = 1 end
        n = 0
    end
    n = n + 1
    seen[str] = n
    if n < 3 then return nil end
    -- Un mismo texto con muchos estilos (color o transparencia animados): no se guarda.
    if byS and byS[0] >= 4 then return nil end
    if nTB >= TB_MAX then clearBatches(); byS = nil end
    local ok, b = pcall(newBatch, f)
    if not ok or not b then UI.TEXT_BATCH = false return nil end
    byF = TB[f]
    if not byF then byF = {}; TB[f] = byF end
    if not byS then byS = { [0] = 0 }; byF[str] = byS end
    e = { b = b, v = 0 }
    byS[key] = e
    byS[0] = byS[0] + 1
    nTB = nTB + 1
    return e, true
end
local function addText(e, str, r, g, b, a, w, align, dx, dy)
    local c = CT[1]
    c[1], c[2], c[3], c[4] = r, g, b, a
    CT[2] = str
    if w then e.b:addf(CT, w, align, dx, dy) else e.b:add(CT, dx, dy) end
    e.v = e.v + #str * 6                  -- (como cuenta main.lua: 6 por byte)
end
-- Dibuja la entrada en (x, y). El presupuesto de vértices de main.lua solo cuenta
-- 4 por lg.draw: se gasta aquí el resto (y si no cabe, no se dibuja).
local function drawBatch(e, x, y)
    if G_VERT_SPEND and e.v > 4 and not G_VERT_SPEND(e.v - 4) then return end
    lg.setColor(1, 1, 1, 1)
    lg.draw(e.b, x, y)
end

-- Bloque de textos de un mismo tamaño que se dibujan juntos (por ejemplo, los
-- números y nombres de una página de la Pokédex): un solo TextBatch. `blk` es una
-- tabla del que llama ({}); `build(add)` se llama solo cuando cambia `ver` (un
-- número que resume lo que se escribe), y add(texto, x, y, color, w, align, alfa)
-- pone cada texto en coordenadas de pantalla. Sin TextBatch, se escribe uno a uno.
local blkCur, blkF = nil, nil
local function blkAdd(str, x, y, col, w, align, alpha)
    if str == "" then return end
    local r, g, b = U.rgb(col or UI.C.text)
    addText(blkCur, str, r, g, b, alpha or 1, w, w and (align or "left"), x, y)
end
local function blkPrint(str, x, y, col, w, align, alpha)
    lg.setFont(blkF)
    U.setColor(col or UI.C.text, alpha or 1)
    if w then lg.printf(str, x, y, w, align or "left") else lg.print(str, x, y) end
end
function UI.textBlock(blk, size, ver, build)
    local f = UI.font(size)
    if blk.ver ~= ver or blk.f ~= f or not blk.b then
        if UI.TEXT_BATCH and (blk.f ~= f or not blk.b) then
            if blk.b and blk.b.release then pcall(blk.b.release, blk.b) end
            local ok, b = pcall(newBatch, f)
            blk.b = ok and b or nil
            if not blk.b then UI.TEXT_BATCH = false end
        elseif blk.b then
            blk.b:clear()
        end
        blk.f, blk.ver, blk.v = f, ver, 0
        if blk.b then
            blkCur = blk
            build(blkAdd)
            blkCur = nil
        end
    end
    if blk.b then
        lg.setFont(f)
        drawBatch(blk, 0, 0)
    else
        blkF = f
        build(blkPrint)
    end
    lg.setColor(1, 1, 1, 1)
end

local ALIGN = { left = 0, center = 1, right = 2, justify = 3 }
function UI.text(str, x, y, opts)
    local size = (opts and opts.size) or 12
    local f = UI.font(size)
    lg.setFont(f)
    local col = (opts and opts.color) or UI.C.text
    local alpha = (opts and opts.alpha) or 1
    local w = opts and opts.w
    if type(str) ~= "string" then str = tostring(str) end
    if str == "" then lg.setColor(1, 1, 1, 1) return end
    local key = cid(col) * 1e7 + math.floor(alpha * 100 + 0.5) * 1e5
              + (w and (math.floor(w * 2) + 1) * 4 + ALIGN[opts.align or "left"] or 0)
    local e, new = batchFor(f, str, key)
    if e then
        if new then
            local r, g, b = U.rgb(col)
            addText(e, str, r, g, b, alpha, w, w and (opts.align or "left"), 0, 0)
        end
        drawBatch(e, x, y)
        return
    end
    U.setColor(col, alpha)
    if w then
        lg.printf(str, x, y, w, opts.align or "left")
    else
        lg.print(str, x, y)
    end
    lg.setColor(1, 1, 1, 1)
end

-- ¿Cabe `str` a tamaño `size` en `w` píxeles (UI.shadowText no lo achica)?
function UI.fits(str, size, w) return UI.font(size):getWidth(str) <= w end

-- Texto blanco con sombra oscura abajo a la derecha (botones de DS), en una línea:
-- si no cabe en `w`, baja de tamaño (hasta 8). Mismo dibujo que dos printf.
local shadowLay, nShadowLay = {}, 0       -- texto -> { [ancho*64+tamaño] = tamaño que cabe }
function UI.shadowText(str, x, y, size, w, col, ink)
    col, ink = col or "#ffffff", ink or "#000000"
    if str == "" then lg.setColor(1, 1, 1, 1) return end
    local byS = shadowLay[str]
    if not byS then
        nShadowLay = nShadowLay + 1
        if nShadowLay > 300 then shadowLay, nShadowLay = {}, 1 end
        byS = {}
        shadowLay[str] = byS
    end
    local k = w * 64 + size
    local fs = byS[k]
    if not fs then
        fs = size
        while fs > 8 and UI.font(fs):getWidth(str) > w do fs = fs - 1 end
        byS[k] = fs
    end
    local f = UI.font(fs)
    lg.setFont(f)
    local e, new = batchFor(f, str, (cid(col) * 1000 + cid(ink)) * 1e4 + w)
    if e then
        if new then
            local r, g, b = U.rgb(ink)
            addText(e, str, r, g, b, 0.55, w, "left", 1, 1)
            r, g, b = U.rgb(col)
            addText(e, str, r, g, b, 1, w, "left", 0, 0)
        end
        drawBatch(e, x, y)
        return
    end
    U.setColor(ink, 0.55)
    lg.printf(str, x + 1, y + 1, w, "left")
    U.setColor(col)
    lg.printf(str, x, y, w, "left")
    lg.setColor(1, 1, 1, 1)
end

function UI.textWidth(str, size)
    return UI.font(size or 12):getWidth(str)
end

-- Paleta de un botón (cacheada por color base): cuerpo, brillo, bisel, contorno, texto.
local BTN = {}
local function btnPal(col)
    local p = BTN[col]
    if p then return p end
    -- Los colores muy oscuros (fondos de menú antiguos) se aclaran un poco para que
    -- el botón tenga cuerpo, como en la DS.
    local r, g, b = U.rgb(col)
    local lum = 0.3 * r + 0.59 * g + 0.11 * b
    local base = lum < 0.22 and U.shade(col, 0.55) or col
    p = {
        body = base,
        gloss = U.shade(base, 0.22),             -- mitad de arriba (brillo de Negro/Blanco)
        hi = U.hexMix(base, "#ffffff", 0.6),     -- bisel claro de arriba
        lo = U.shade(base, -0.3),                -- bisel oscuro de abajo
        edge = U.shade(base, -0.62),             -- contorno grueso
        ink = U.shade(base, -0.7),               -- contorno del texto
    }
    BTN[col] = p
    return p
end

-- Capa de luces y sombras de los botones ya horneada (tools/bake_buttons ->
-- img/ui/btn): contorno, brillo, biseles y sombra en blanco/negro translúcido. Un
-- botón pasa de 7 figuras (4 redondeadas) a 1 rectángulo redondeado del color del
-- cuerpo + 3 trozos de imagen (esquina, columna estirada, esquina). Solo para los
-- altos horneados, r = 6 (alto >= 14), ancho >= 16 y posición entera; si no, se
-- dibuja como antes. La disposición es la de tools/bake_buttons/main.lua.
local BTN_ALTOS, BTN_TW = { 14, 16, 18, 20, 22, 26, 30, 31, 34, 43 }, 24
local btnImg, btnTried, btnQ, pipQ = nil, false, {}, {}
local function btnAtlas()
    btnTried = true
    local ok, im = pcall(lg.newImage, U.img("img/ui/btn"))
    if not ok or not im then return end
    if im.setFilter then pcall(im.setFilter, im, "nearest", "nearest") end
    btnImg = im
    local iw, ih = im:getWidth(), im:getHeight()
    for g = 0, 1 do
        local y = 0
        for k = 1, 5 do
            local hh = BTN_ALTOS[g * 5 + k]
            for v = 0, 1 do                     -- 0 activo, 1 desactivado
                local x0 = g * 64 + v * 32
                btnQ[hh * 2 + v] = { lg.newQuad(x0, y, 8, hh + 2, iw, ih),
                                     lg.newQuad(x0 + 8, y, 1, hh + 2, iw, ih),
                                     lg.newQuad(x0 + BTN_TW - 7, y, 8, hh + 2, iw, ih) }
            end
            y = y + hh + 3
        end
    end
    -- Tira de marcas de nivel: n marcas = los n * 6 - 2 primeros píxeles.
    for n = 1, 10 do pipQ[n] = lg.newQuad(0, 200, n * 6 - 2, 8, iw, ih) end
end
local function btnLayer(h, enabled)
    if not btnTried then btnAtlas() end
    return btnQ[h * 2 + (enabled and 0 or 1)]
end

-- `n` marcas de nivel (4x8 cada 6 px) desde (x, y) del color `col`: un dibujo en
-- vez de un rectángulo por marca.
function UI.pips(x, y, n, col)
    if n <= 0 then return end
    if not btnTried then btnAtlas() end
    U.setColor(col)
    local q = pipQ[n]
    if q and btnImg then
        lg.draw(btnImg, q, x, y)
    else
        for k = 0, n - 1 do lg.rectangle("fill", x + k * 6, y, 4, 8) end
    end
    lg.setColor(1, 1, 1, 1)
end

-- Contorno del texto de los botones: desplazamientos (x, y) de las 5 pasadas.
local OUTLINE = { -1, 0, 1, 0, 0, -1, 0, 1, 1, 1 }

-- Medidas del texto de un botón (cacheadas por texto, ancho, tamaño e icono): que
-- nunca salte de línea; si no cabe, menos margen y, si aún no, letra menor.
-- { f = fuente, fh = alto, dx = x del texto desde el botón, tw = ancho, k = clave }
local btnLay, nBtnLay = {}, 0
local function btnLayout(label, w, size, icon)
    local byL = btnLay[label]
    if not byL then
        nBtnLay = nBtnLay + 1
        if nBtnLay > 300 then btnLay, nBtnLay = {}, 1 end
        byL = {}
        btnLay[label] = byL
    end
    local k = (w * 32 + size) * 2 + (icon and 1 or 0)
    local L = byL[k]
    if L then return L end
    local f = UI.font(size)
    local io = icon and 16 or 0
    local tw, pad = w - io - 8, 4
    if f:getWidth(label) > tw then
        pad, tw = 1, w - io - 2
        while size > 8 and f:getWidth(label) > tw do size = size - 2; f = UI.font(size) end
    end
    L = { f = f, fh = f:getHeight(), dx = io + pad, tw = tw, k = k }
    byL[k] = L
    return L
end

-- Cursor de esquinas rojo (como el de la botonera de combate de Platino).
-- Marco de selección (como el de los menús de HGSS): borde grueso que late entre
-- blanco y dorado alrededor del botón, con un contorno oscuro fino para que se vea
-- sobre cualquier color, y un brillo suave encima del botón.
function UI.selectFrame(x, y, w, h)
    if G_STEP and not UI.__sel then UI.__sel = true; G_STEP("primer marco de selección") end
    local k = (math.sin(U.now() * 6) + 1) / 2
    local r = math.min(7, h / 2)
    lg.setColor(1, 1, 1, 0.06 + 0.08 * k)                    -- brillo sobre el botón
    lg.rectangle("fill", x + 2, y + 2, w - 4, h - 4, r - 1, r - 1)
    U.setColor("#1a1830")
    lg.setLineWidth(1)
    lg.rectangle("line", x - 4.5, y - 4.5, w + 9, h + 9, r + 3, r + 3)
    -- De blanco a dorado (#ffd23f) sin crear textos de color cada fotograma.
    lg.setColor(1, 1 - 0.1765 * k, 1 - 0.7529 * k, 1)
    lg.setLineWidth(3)
    lg.rectangle("line", x - 2.5, y - 2.5, w + 5, h + 5, r + 2, r + 2)
    lg.setLineWidth(1)
    lg.setColor(1, 1, 1, 1)
end
UI.cornerCursor = UI.selectFrame          -- nombre antiguo

-- Botón tocable al estilo de las pantallas táctiles de DS (4.ª y 5.ª gen): contorno
-- grueso oscuro, cuerpo a dos tonos con brillo arriba, bisel y sombra; texto blanco
-- con contorno. El activo (`on`) lleva el cursor rojo de esquinas.
-- opts: color, enabled (false = gris), size (fuente), icon, align, on, textColor
function UI.button(id, x, y, w, h, label, opts)
    local enabled = not (opts and opts.enabled == false)
    local col = (opts and opts.color) or "#3c6cc4"
    if not enabled then col = "#6e7088" end
    local on = opts and opts.on
    local p = btnPal(col)
    local r = math.min(6, h / 2 - 1)
    local q = w >= 16 and x % 1 == 0 and y % 1 == 0 and btnLayer(h, enabled)
    if q then
        -- Cuerpo (con la forma del contorno) y encima la capa horneada.
        U.setColor(p.body)
        lg.rectangle("fill", x, y, w, h, r, r)
        lg.setColor(1, 1, 1, 1)
        lg.draw(btnImg, q[1], x, y)
        lg.draw(btnImg, q[2], x + 8, y, 0, w - 15, 1)
        lg.draw(btnImg, q[3], x + w - 7, y)
    else
        -- Sombra
        lg.setColor(0, 0, 0, 0.35)
        lg.rectangle("fill", x + 1, y + 2, w, h, r, r)
        -- Contorno grueso y cuerpo
        U.setColor(p.edge)
        lg.rectangle("fill", x, y, w, h, r, r)
        U.setColor(p.body)
        lg.rectangle("fill", x + 2, y + 2, w - 4, h - 4, r - 1, r - 1)
        -- Mitad de arriba más clara
        U.setColor(p.gloss)
        lg.rectangle("fill", x + 2, y + 2, w - 4, math.floor((h - 4) / 2), r - 1, r - 1)
        lg.rectangle("fill", x + 2, y + 2 + r, w - 4, math.max(0, math.floor((h - 4) / 2) - r))
        -- Bisel: línea clara arriba y oscura abajo
        U.setColor(p.hi, enabled and 0.85 or 0.4)
        lg.rectangle("fill", x + 2 + r - 1, y + 3, w - 4 - (r - 1) * 2, 1)
        U.setColor(p.lo)
        lg.rectangle("fill", x + 2 + r - 1, y + h - 4, w - 4 - (r - 1) * 2, 1)
    end
    -- Texto (blanco con contorno del color del botón)
    local size = (opts and opts.size) or 12
    local icon = opts and opts.icon
    if icon then G.Icons.draw(icon, x + 6, y + (h - 14) / 2, 14) end
    if label == "" then
        lg.setColor(1, 1, 1, 1)
        if on then UI.selectFrame(x, y, w, h) end
        if enabled then addHit(id, x, y, w, h) end
        return
    end
    local al = (opts and opts.align) or "center"
    local L = btnLayout(label, w, size, icon ~= nil)
    local f = L.f
    lg.setFont(f)
    local ty = math.floor(y + (h - L.fh) / 2 + 0.5)
    local tx = x + L.dx
    local tcol = enabled and ((opts and opts.textColor) or "#ffffff") or "#c4c6d4"
    local e, new = batchFor(f, label, (cid(col) * 1000 + cid(tcol)) * 1e6 + L.k * 8 + (ALIGN[al] or 0) * 2 + (enabled and 1 or 0))
    if e then
        -- Las 6 pasadas (5 de contorno y la letra) en un solo dibujo.
        if new then
            local ia = enabled and 1 or 0.6
            local r, g, b = U.rgb(p.ink)
            for i = 1, 10, 2 do addText(e, label, r, g, b, ia, L.tw, al, OUTLINE[i], OUTLINE[i + 1]) end
            r, g, b = U.rgb(tcol)
            addText(e, label, r, g, b, 1, L.tw, al, 0, 0)
        end
        drawBatch(e, tx, ty)
    else
        U.setColor(p.ink, enabled and 1 or 0.6)
        for i = 1, 10, 2 do lg.printf(label, tx + OUTLINE[i], ty + OUTLINE[i + 1], L.tw, al) end
        U.setColor(tcol)
        lg.printf(label, tx, ty, L.tw, al)
    end
    lg.setColor(1, 1, 1, 1)
    if on then UI.selectFrame(x, y, w, h) end
    if enabled then addHit(id, x, y, w, h) end
end

-- Zona tocable sin dibujo (celdas, pestañas).
function UI.hitbox(id, x, y, w, h) addHit(id, x, y, w, h) end

function UI.bar(x, y, w, h, frac, col, bg)
    U.setColor(bg or "#000000", bg and 1 or 0.55)
    lg.rectangle("fill", x, y, w, h, h / 2, h / 2)
    if frac > 0 then
        U.setColor(col)
        lg.rectangle("fill", x, y, w * U.clamp(frac, 0, 1), h, h / 2, h / 2)
    end
    lg.setColor(1, 1, 1, 1)
end

-- Chip de color con texto; devuelve el ancho.
function UI.chip(label, x, y, col, size)
    size = size or 10
    lg.setFont(UI.font(size))
    local w = UI.font(size):getWidth(label) + 10
    U.setColor(col)
    lg.rectangle("fill", x, y, w, size + 5, 4, 4)
    U.setColor("#0a1430")
    lg.print(label, x + 5, y + 2)
    lg.setColor(1, 1, 1, 1)
    return w
end

function UI.typeChips(types, x, y, size)
    local cx = x
    for _, t in ipairs(types) do
        cx = cx + UI.chip(U.TYPE_NAME[t] or t, cx, y, U.TYPE_COLOR[t] or "#8fa3c4", size) + 4
    end
    return cx - x
end

-- Estrellas de rareza (1..5).
function UI.stars(rarity, x, y, size)
    size = size or 8
    for i = 1, 5 do
        U.setColor(i <= rarity and UI.C.gold or "#2a3350")
        local cx, cy = x + (i - 1) * (size + 2) + size / 2, y + size / 2
        lg.polygon("fill", cx, cy - size / 2, cx + size * 0.18, cy - size * 0.15, cx + size / 2, cy - size * 0.15,
                   cx + size * 0.25, cy + size * 0.1, cx + size * 0.32, cy + size / 2, cx, cy + size * 0.25,
                   cx - size * 0.32, cy + size / 2, cx - size * 0.25, cy + size * 0.1, cx - size / 2, cy - size * 0.15,
                   cx - size * 0.18, cy - size * 0.15)
    end
    lg.setColor(1, 1, 1, 1)
end

-- Escenario para un sprite: recuadro oscuro con borde del color del tipo.
function UI.stage(x, y, w, h, col)
    U.setColor("#070d1f")
    lg.rectangle("fill", x, y, w, h, 6, 6)
    U.setColor(col or UI.C.line)
    lg.setLineWidth(2)
    lg.rectangle("line", x + 1, y + 1, w - 2, h - 2, 6, 6)
    lg.setLineWidth(1)
    lg.setColor(1, 1, 1, 1)
end

-- Sprite quieto o animado en coordenadas de pantalla (k = píxeles por píxel de arte).
function UI.sprite(dex, x, y, k, anim)
    if anim then
        anim:draw(x, y, nil)
    else
        G.Sprites.drawStill(dex, x, y, (k or 1) / G.Sprites.PX)
    end
end

-- Animators para los menús (compañero, selección): uno por dex, con Idle en bucle.
local menuAnims = {}
function UI.menuAnim(dex, k, shiny)
    local key = shiny and (dex .. "s") or dex
    local a = menuAnims[key]
    if not a then
        a = G.Sprites.Animator.new(dex, (k or 1) / G.Sprites.PX, shiny or false, false)
        menuAnims[key] = a
    end
    a.scale = (k or 1) / G.Sprites.PX
    return a
end
function UI.updateMenuAnims(dt)
    for _, a in pairs(menuAnims) do a:update(dt) end
end
function UI.clearMenuAnims() menuAnims = {} end

-- Nombres de generación.
UI.GEN_NAMES = { "Kanto", "Johto", "Hoenn", "Sinnoh", "Teselia", "Kalos", "Alola", "Galar", "Paldea" }

function UI.pad3(n) return string.format("%03d", n) end
