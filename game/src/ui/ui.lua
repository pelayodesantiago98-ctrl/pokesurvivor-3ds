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
    if U.CONSOLE then
        -- En consola, fuente del sistema: mkbcfnt no convierte Pixelify Sans (fuente
        -- variable, saca 2 glifos) y la del sistema trae acentos.
        ok, res = pcall(lg.newFont, size)
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

function UI.draw()
    nHits = 0
    UI.background()
    if current and current.draw then current.draw() end
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

function UI.text(str, x, y, opts)
    local size = (opts and opts.size) or 12
    lg.setFont(UI.font(size))
    U.setColor((opts and opts.color) or UI.C.text, (opts and opts.alpha) or 1)
    if opts and opts.w then
        lg.printf(str, x, y, opts.w, opts.align or "left")
    else
        lg.print(str, x, y)
    end
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

-- Cursor de esquinas rojo (como el de la botonera de combate de Platino).
-- Marco de selección (como el de los menús de HGSS): borde grueso que late entre
-- blanco y dorado alrededor del botón, con un contorno oscuro fino para que se vea
-- sobre cualquier color, y un brillo suave encima del botón.
function UI.selectFrame(x, y, w, h)
    local k = (math.sin(U.now() * 6) + 1) / 2
    local r = math.min(7, h / 2)
    lg.setColor(1, 1, 1, 0.06 + 0.08 * k)                    -- brillo sobre el botón
    lg.rectangle("fill", x + 2, y + 2, w - 4, h - 4, r - 1, r - 1)
    U.setColor("#1a1830")
    lg.setLineWidth(1)
    lg.rectangle("line", x - 4.5, y - 4.5, w + 9, h + 9, r + 3, r + 3)
    U.setColor(U.hexMix("#ffffff", "#ffd23f", k))
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
    -- Texto (blanco con contorno del color del botón)
    local size = (opts and opts.size) or 12
    local f = UI.font(size)
    local tx = x
    if opts and opts.icon then
        G.Icons.draw(opts.icon, x + 6, y + (h - 14) / 2, 14)
        tx = x + 16
    end
    local tw, al = w - (tx - x) - 8, (opts and opts.align) or "center"
    -- Que nunca salte de línea: si no cabe, menos margen y, si aún no, letra menor.
    local pad = 4
    if f:getWidth(label) > tw then
        pad, tw = 1, w - (tx - x) - 2
        while size > 8 and f:getWidth(label) > tw do size = size - 2; f = UI.font(size) end
    end
    lg.setFont(f)
    local ty = math.floor(y + (h - f:getHeight()) / 2 + 0.5)
    tx = tx + pad - 4
    U.setColor(p.ink, enabled and 1 or 0.6)
    for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 }, { 1, 1 } }) do
        lg.printf(label, tx + 4 + d[1], ty + d[2], tw, al)
    end
    U.setColor(enabled and ((opts and opts.textColor) or "#ffffff") or "#c4c6d4")
    lg.printf(label, tx + 4, ty, tw, al)
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
