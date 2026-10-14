-- run.lua — interfaz de la run en la pantalla inferior: HUD con los movimientos,
-- cartas de subida de nivel, elección de objeto, vínculos, pausa y resumen final.
local U = G.U
local UI = G.UI
local R = {}
G.RunUI = R

local lg = love.graphics
local W, H = UI.W, UI.H

-- ---------------- HUD ----------------

local hud = {}

-- Estilos fijos de la fuente pixelada y textos cacheados (nada de tablas ni
-- cadenas nuevas en cada fotograma ni en cada repintado del HUD).
local BOX_DARK = { s = 2, color = "#383838", shadow = "#b8b8b0" }
local BOX_SHINY = { s = 2, color = "#50a8f0", shadow = "#b8b8b0" }
local BOX_HP = { s = 1, color = "#58d080", noOutline = true }
local STATS_ST = { s = 1, color = "#e8e4ff", shadow = "#3a3458" }
local BURST_ST = { s = 1, color = "#ffffff", shadow = "#2a2440" }
local LV_TXT = {}                          -- nivel -> "LV12"
local BUFF_KEYS = { "atk", "spd", "def", "regen" }
local BUFF_COL = { atk = "#ff6b4d", spd = "#7fe0ff", def = "#b0b8c8", regen = "#5fe08a" }
local BUFF_LBL = { atk = "ATK", spd = "VEL", def = "DEF", regen = "REG" }
local SLOT_ID = { "slot1", "slot2", "slot3", "slot4" }
local T_ITEM = { size = 10, color = "#ffffff", w = 84 }
local T_NOITEM = { size = 10, color = "#c8c0e0" }
local T_BONDS = { size = 10, color = UI.C.pink }
local B_PAUSE = { size = 10, color = "#4a4468" }
local B_BURST = { size = 10, color = "#ffffff" }
-- Texto de número cacheado por tabla (cifras que se repiten: vida, monedas...).
local function numText(cache, prefix, n, suffix)
    local s = cache[n]
    if not s then s = prefix .. n .. suffix; cache[n] = s end
    return s
end
local BURST_TXT, BONDS_TXT = {}, {}
local statParts = {}
-- Reloj de la partida ("1:23"), rehecho sólo al cambiar de segundo.
local clockSec, clockTxt, clockX, clockY = -1, "", 0, 0
local function clockText()
    local s = math.floor(G.Game.time())
    if s ~= clockSec then clockSec, clockTxt = s, U.mmss(s) end
    return clockTxt
end

local function cdOf(m, pl)
    if m.kind == "orbit" then return 0 end
    return U.clamp(m.t / (m.cd * pl.cdMul), 0, 1)
end

-- Caja de estado como la de los combates de los juegos: nombre y nivel, etiqueta
-- HP con barra que pasa de verde a amarillo y rojo, cifras a la derecha y la barra
-- azul de experiencia debajo.
local function battleBox(pl, x, y, w, live)
    local h = 56
    -- Caja gris de Platino: sombra, relleno, brillo superior y contorno oscuro
    U.setColor("#202020")
    lg.rectangle("fill", x + 2, y + 3, w, h, 6, 6)
    U.setColor("#d8d8d0")
    lg.rectangle("fill", x, y, w, h, 6, 6)
    U.setColor("#f8f8f0")
    lg.rectangle("fill", x + 3, y + 2, w - 6, 3, 2, 2)
    U.setColor("#c0c0b8")
    lg.rectangle("fill", x + 3, y + h - 6, w - 6, 3, 2, 2)
    U.setColor("#404040")
    lg.setLineWidth(2)
    lg.rectangle("line", x + 1, y + 1, w - 2, h - 2, 6, 6)
    lg.setLineWidth(1)
    -- Nombre y nivel en la fuente pixelada con la sombra clara de Platino
    local PF = G.PixelFont
    local dark = BOX_DARK
    PF.print(pl.mon.name, x + 10, y + 7, dark)
    local lv = LV_TXT[pl.level]
    if not lv then lv = "LV" .. pl.level; LV_TXT[pl.level] = lv end
    local lvw = PF.width(lv, 2)
    PF.print(lv, x + w - 12 - lvw, y + 7, dark)
    if pl.shiny then PF.print("*", x + w - 24 - lvw, y + 7, BOX_SHINY) end
    -- Etiqueta HP: texto siempre verde sobre fondo oscuro (la que cambia de color
    -- según la vida es la barra, no la etiqueta).
    local bx, by, bw, bh = x + 54, y + 25, w - 66, 7
    U.setColor("#383838")
    lg.rectangle("fill", bx - 25, by - 3, 23, 13, 4, 4)
    PF.print("HP", bx - 25 + (23 - PF.width("HP", 1)) / 2, by, BOX_HP)
    -- Barra de vida: borde oscuro, pista blanca y relleno por tramos
    local frac = U.clamp(pl.hp / pl.maxHp, 0, 1)
    U.setColor("#303030")
    lg.rectangle("fill", bx - 2, by - 2, bw + 4, bh + 4, 3, 3)
    U.setColor("#ffffff")
    lg.rectangle("fill", bx, by, bw, bh)
    local col = frac > 0.5 and "#58d080" or (frac > 0.2 and "#f8d848" or "#f85038")
    if frac > 0 then
        U.setColor(col)
        lg.rectangle("fill", bx, by, math.max(2, bw * frac), bh)
        U.setColor("#ffffff", 0.45)
        lg.rectangle("fill", bx, by, math.max(2, bw * frac), 2)
    end
    -- Cifras (dentro de la caja, bajo la barra)
    local txt = math.ceil(pl.hp) .. "/" .. U.round(pl.maxHp)
    PF.print(txt, bx + bw - PF.width(txt, 2), by + 11, dark)
    -- Barra de experiencia bajo la caja: etiqueta EXP sobre azul marino y barra azul
    local ex, ey, ew, eh = x + 40, y + h + 4, w - 48, 4
    U.setColor("#283048")
    lg.rectangle("fill", x + 6, ey - 4, 30, 12, 3, 3)
    lg.setFont(UI.font(10))
    U.setColor("#90c8ff")
    lg.print("EXP", x + 10, ey - 4)
    U.setColor("#202020")
    lg.rectangle("fill", ex - 2, ey - 2, ew + 4, eh + 4, 2, 2)
    U.setColor("#485060")
    lg.rectangle("fill", ex, ey, ew, eh)
    -- El relleno cambia con cada gema: en la imagen guardada no va (lo pone hud.draw).
    if live then R.xpFill(pl, x, y, w, h) end
    lg.setColor(1, 1, 1, 1)
    return y + h + 12
end

-- Relleno de la barra de experiencia de la caja de estado (x, y, w, h de la caja).
function R.xpFill(pl, x, y, w, h)
    U.setColor("#38a0f8")
    lg.rectangle("fill", x + 40, y + h + 4, (w - 48) * U.clamp(pl.xp / pl.xpNext, 0, 1), 4)
end

-- Geometría de los botones de movimiento y de la fila inferior (dibujo y zonas táctiles).
local MV_TOP, MV_W, MV_H = 86, 148, 58
local function slotXY(i)
    local col_i, row = (i - 1) % 2, math.floor((i - 1) / 2)
    return 8 + col_i * (MV_W + 8), MV_TOP + 6 + row * (MV_H + 4)
end
local BURST_X, BURST_W, PAUSE_X = 152, 94, W - 66
local BOX_X, BOX_Y, BOX_W, BOX_H = 8, 6, 304, 56     -- caja de estado (BOX_H: alto fijo de battleBox)

-- HUD completo. `live` = false cuando se pinta en la imagen guardada: entonces no
-- lleva lo que se mueve cada fotograma (marco del activo, velo de recarga, latido
-- del Burst), que hud.draw pone encima.
local function drawHud(pl, live)
    R.platinumBackground(0)
    local y0 = battleBox(pl, BOX_X, BOX_Y, BOX_W, live)

    -- Buffs y poder
    local bx = 170
    for _, k in ipairs(BUFF_KEYS) do
        local b = pl.buffs[k]
        if b and b.n > 0 then bx = bx + UI.chip(BUFF_LBL[k] .. " x" .. b.n, bx, y0, BUFF_COL[k]) + 4 end
    end
    if pl.power then
        bx = bx + UI.chip(string.upper(pl.power.def.name or "") .. " " .. math.ceil(pl.power.t) .. "s", bx, y0, pl.power.def.color or "#ffffff") + 4
    end

    -- Stats de la run
    -- Centrada entre la barra de experiencia (acaba en y0 - 4) y los botones (empiezan en ~92).
    -- Se escribe por trozos (mismo sitio que de una pieza): la fuente pixelada guarda
    -- los glifos de cada texto distinto, y la línea entera cambia con cada derrota.
    -- El reloj (primer trozo) cambia cada segundo: en la imagen guardada no va; hud.draw
    -- lo escribe encima en (clockX, clockY). Sólo se repinta si cambia su ancho.
    local sy = math.floor(((y0 - 4) + 89) / 2 - 3.5)
    local parts = statParts
    parts[1] = clockText(); parts[2] = "  DERROTADOS "; parts[3] = tostring(pl.kills)
    parts[4] = "  JEFES "; parts[5] = tostring(pl.bosses); parts[6] = "  MONEDAS "; parts[7] = tostring(pl.coins)
    local PF = G.PixelFont
    local tw = 0
    for i = 1, 7 do tw = tw + PF.width(parts[i], 1) end
    tw = tw + 6                                 -- separación de 1 px entre trozos (gap de s = 1)
    local sx = math.floor((W - tw) / 2 + 0.5)
    clockX, clockY = sx, sy
    for i = 1, 7 do
        if live or i > 1 then PF.print(parts[i], sx, sy, STATS_ST) end
        sx = sx + PF.width(parts[i], 1) + 1
    end

    -- Menú de movimientos como el de Platino: fondo gris carbón y 4 botones 2x2 del
    -- color del tipo, nombre arriba, etiqueta del tipo abajo a la izquierda y, en vez
    -- de los PP, los puntos de nivel. El activo lleva el cursor de esquinas rojas.
    -- (Más juntos en vertical para dejar aire al botón de pausa de abajo.)
    for i = 1, 4 do
        local x, y = slotXY(i)
        local g = pl.slots[i]
        local m = g and g[1]
        R.moveButton(x, y, MV_W, MV_H, m, g and #g > 1 and #g or nil, live and i == pl.active and m ~= nil,
                     live and m and cdOf(m, pl) or 0)
        if m then UI.hitbox(SLOT_ID[i], x, y, MV_W, MV_H) end
    end
    lg.setColor(1, 1, 1, 1)

    -- Fila inferior: objeto (con su sprite de la mochila), vínculos y pausa
    local by = H - 20
    if pl.item then
        G.Icons.draw(pl.item, 8, by - 3, 22)
        UI.text(G.Items.BY[pl.item].name, 32, by + 3, T_ITEM)
    else
        UI.text("Sin objeto", 10, by + 3, T_NOITEM)
    end
    if pl.bonds > 0 then
        G.Icons.draw("bond", 118, by, 14)
        UI.text(numText(BONDS_TXT, "x", pl.bonds, ""), 133, by + 3, T_BONDS)
    end
    -- Ataque Burst: barra que se carga; llena, botón que late (X en el mando).
    local bx, bw = BURST_X, BURST_W
    local col = U.TYPE_COLOR[pl.mon.types[1]] or "#ffd23f"
    if G.Burst.ready(pl) then
        B_BURST.color = col
        UI.button("burst", bx, by, bw, 18, "¡BURST!", B_BURST)
        if live then
            U.setColor("#ffffff", 0.25 + 0.25 * math.sin(U.now() * 8))
            lg.rectangle("fill", bx + 2, by + 2, bw - 4, 14, 5, 5)
            lg.setColor(1, 1, 1, 1)
        end
    else
        U.setColor("#2a2440")
        lg.rectangle("fill", bx, by + 1, bw, 16, 5, 5)
        U.setColor(col, 0.85)
        lg.rectangle("fill", bx + 2, by + 3, math.max(0, (bw - 4) * (pl.burst or 0)), 12, 4, 4)
        G.PixelFont.print(numText(BURST_TXT, "BURST ", math.floor((pl.burst or 0) * 100), "%"), bx + 8, by + 6, BURST_ST)
    end
    UI.button("pause", PAUSE_X, by, 58, 18, "Pausa", B_PAUSE)
end

-- La pantalla de abajo casi no cambia de un fotograma a otro, pero son ~300 piezas
-- (en la 3DS, 10-16 ms por fotograma). Se pinta en una imagen y sólo se repinta
-- cuando cambia algo de lo que muestra (firma); lo animado va encima en directo.
local hudCv, hudCvTried, hudDirty = nil, false, true
-- Firma: los valores que se ven en el HUD guardado, en una tabla que se compara
-- campo a campo con la del último repintado (sin crear cadenas ni tablas). Los
-- primeros SOFT_N son contadores que en plena pelea cambian casi en cada fotograma
-- (derrotados, jefes, monedas, % del Burst, segundos del poder): si sólo cambian
-- ellos, se repinta como mucho cada SOFT_GAP s; lo demás, al momento. La barra de
-- experiencia (cambia con cada gema) y el reloj (cada segundo) no van en la imagen:
-- se pintan encima; del reloj sólo cuenta su ancho (mueve el resto de la línea).
local SOFT_N, SOFT_GAP = 5, 0.25
local sigNow, sigOld, sigOldN, lastPaint = {}, {}, 0, -1
HUD_REPAINTS = 0                           -- repintados de la imagen desde el arranque (main.lua: «rendimiento»)
local function hudChanged(pl)
    local p = sigNow
    -- Contadores (blandos)
    local burstReady = G.Burst.ready(pl)
    p[1] = pl.kills; p[2] = pl.bosses; p[3] = pl.coins
    p[4] = burstReady and -1 or math.floor((pl.burst or 0) * 100)
    p[5] = pl.power and math.ceil(pl.power.t) or 0
    -- Lo demás (duros)
    p[6] = G.PixelFont.width(clockText(), 1)
    p[7] = pl.mon.name; p[8] = pl.level; p[9] = pl.shiny and 1 or 0
    p[10] = math.ceil(pl.hp); p[11] = U.round(pl.maxHp)
    local n = 11
    for i = 1, 4 do local b = pl.buffs[BUFF_KEYS[i]]; n = n + 1; p[n] = b and b.n or 0 end
    n = n + 1; p[n] = pl.power and (pl.power.def.name or "?") or ""
    for i = 1, 4 do
        local g = pl.slots[i]
        local m = g and g[1]
        if m then
            p[n + 1] = m.name; p[n + 2] = #g; p[n + 3] = m.type; p[n + 4] = m.lvl; p[n + 5] = m.evolved and 1 or 0
            n = n + 5
        else
            n = n + 1; p[n] = "-"
        end
    end
    p[n + 1] = pl.item or ""; p[n + 2] = pl.bonds; p[n + 3] = burstReady and 1 or 0
    n = n + 3
    local now = love.timer.getTime()
    local changed = hudDirty or n ~= sigOldN
    if not changed then
        for i = SOFT_N + 1, n do if p[i] ~= sigOld[i] then changed = true break end end
    end
    if not changed and now - lastPaint >= SOFT_GAP then
        for i = 1, SOFT_N do if p[i] ~= sigOld[i] then changed = true break end end
    end
    if changed then
        for i = 1, n do sigOld[i] = p[i] end
        for i = n + 1, sigOldN do sigOld[i] = nil end
        sigOldN = n
        hudDirty = false
        lastPaint = now
        HUD_REPAINTS = HUD_REPAINTS + 1
    end
    return changed
end

function hud.draw()
    local pl = G.Game.player()
    if not pl then return end
    if not hudCvTried then
        hudCvTried = true
        -- (A la SD ya: la imagen del HUD aún no está probada en la consola.)
        if G_STEP then G_STEP("hud: creando imagen", true) end
        local ok, cv = false, nil
        if not G_NO_HUD_CANVAS then ok, cv = pcall(lg.newCanvas, W, H) end
        if ok and cv then hudCv = cv end
        if G_STEP then G_STEP("hud: imagen " .. (hudCv and "ok" or "no disponible"), true) end
    end
    if not hudCv then drawHud(pl, true) return end

    if hudChanged(pl) then
        lg.push()
        lg.origin()
        lg.setCanvas(hudCv)
        lg.clear(0, 0, 0, 1)
        drawHud(pl, false)
        lg.setCanvas()
        lg.pop()
    end
    lg.setColor(1, 1, 1, 1)
    lg.draw(hudCv, 0, 0)
    R.xpFill(pl, BOX_X, BOX_Y, BOX_W, BOX_H)
    G.PixelFont.print(clockText(), clockX, clockY, STATS_ST)

    -- Zonas táctiles (se borran en cada fotograma) y lo animado.
    local by = H - 20
    for i = 1, 4 do
        local x, y = slotXY(i)
        local g = pl.slots[i]
        local m = g and g[1]
        if m then
            UI.hitbox(SLOT_ID[i], x, y, MV_W, MV_H)
            R.moveVeil(x, y, MV_W, MV_H, cdOf(m, pl))
            if i == pl.active then UI.selectFrame(x, y, MV_W, MV_H) end
        end
    end
    if G.Burst.ready(pl) then
        UI.hitbox("burst", BURST_X, by, BURST_W, 18)
        U.setColor("#ffffff", 0.25 + 0.25 * math.sin(U.now() * 8))
        lg.rectangle("fill", BURST_X + 2, by + 2, BURST_W - 4, 14, 5, 5)
    end
    UI.hitbox("pause", PAUSE_X, by, 58, 18)
    lg.setColor(1, 1, 1, 1)
end

-- Velo de recarga sobre la cara del botón (de abajo arriba). La cara empieza bajo
-- las 7 filas de la tapa (ver R.moveButton).
function R.moveVeil(x, y, w, h, cd)
    if not cd or cd <= 0.05 then return end
    local fx, fy, fw, fh = x + 10, y + 8, w - 20, h - 14
    lg.setColor(0, 0, 0, 0.12)
    lg.rectangle("fill", fx, fy + fh * (1 - cd), fw, fh * cd)
end

-- Al empezar otra partida (o volver al HUD) se repinta seguro.
function hud.enter() hudDirty = true end

-- ---------------- estilo Platino ----------------

-- Fondo de la pantalla de movimientos de Platino: morado grisáceo con una franja
-- más oscura arriba que se aclara (colores muestreados del juego).
-- Fondo de la pantalla de movimientos de Platino (muestreado de la captura):
-- franja oscura arriba, morado de fondo y una Poké Ball grande y tenue en el
-- centro (mitad de arriba marrón rojiza, mitad de abajo morado más oscuro).
-- Ya horneado en img/ui/platbg (main.lua --bakebg lo genera con esta misma función):
-- un dibujo en vez de quince figuras con círculos y arcos.
local platImg, platTried = nil, false
function R.platinumBackground(top)
    top = top or 0
    if top == 0 and not G_BAKING then
        if not platTried then
            platTried = true
            local ok, im = pcall(lg.newImage, U.img("img/ui/platbg"))
            if ok and im then platImg = im end
        end
        if platImg then
            lg.setColor(1, 1, 1, 1)
            lg.draw(platImg, 0, 0)
            return
        end
    end
    U.setColor("#706891")
    lg.rectangle("fill", 0, top, W, H - top)
    U.setColor("#525078")
    lg.rectangle("fill", 0, top, W, 14)
    local grad = { "#5b5981", "#6b5f8d", "#736b8c" }
    for i, c in ipairs(grad) do
        U.setColor(c)
        lg.rectangle("fill", 0, top + 14 + (i - 1) * 2, W, 2)
    end
    -- Poké Ball con su línea de borde (colores de la captura): contorno morado
    -- oscuro, mitad de arriba marrón rojiza, franja y botón central con aro.
    local cx, cy, r = W / 2, top + 150, 64
    local EDGE = "#5c6084"
    -- Borde grueso (5 px) alrededor de la bola, en la franja y en el botón.
    U.setColor(EDGE)
    lg.circle("fill", cx, cy, r + 5, 48)
    U.setColor("#886060")
    lg.arc("fill", cx, cy, r, math.pi, 2 * math.pi, 48)
    U.setColor("#6c648c")
    lg.arc("fill", cx, cy, r, 0, math.pi, 48)
    U.setColor(EDGE)
    lg.rectangle("fill", cx - r, cy - 5, r * 2, 10)
    lg.circle("fill", cx, cy, 22, 32)
    U.setColor("#716a92")
    lg.circle("fill", cx, cy, 14, 32)
    U.setColor(EDGE)
    lg.setLineWidth(3)
    lg.circle("line", cx, cy, 8, 24)
    lg.setLineWidth(1)
    lg.setColor(1, 1, 1, 1)
end

-- Colores del marco de cada tipo derivados de su color (el de Agua y Siniestro
-- salen del juego: bisel claro, línea oscura, marco, lateral, base).
local FRAME = {}
local function frameOf(t)
    local f = FRAME[t]
    if f then return f end
    local base = U.TYPE_COLOR[t] or "#a0a0a0"
    -- (Agua en el juego: bisel #82d1e7/#95e5eb, línea #1d6486, marco #178dca,
    -- lateral #0e2e4e, base #1f77aa; las proporciones se aplican a cada tipo.)
    f = {
        bevel = U.hexMix(base, "#ffffff", 0.42),
        bevel2 = U.hexMix(base, "#ffffff", 0.58),
        line = U.shade(base, -0.55),
        frame = U.shade(base, -0.12),
        frameDark = U.shade(base, -0.35),
        side = U.shade(base, -0.78),
        bottom = U.shade(base, -0.3),
        badge = U.hexMix(base, "#ffffff", 0.18),
        badgeEdge = U.shade(base, -0.5),
    }
    f.badgeSt = { s = 1, color = "#ffffff", shadow = f.badgeEdge }
    FRAME[t] = f
    return f
end
-- Marco de un hueco vacío.
local EMPTY_FRAME = { bevel = "#9894b0", bevel2 = "#aca8c4", line = "#3e3a52", frame = "#6a6688", frameDark = "#4e4a68",
                      side = "#24202e", bottom = "#4a4664" }
-- Filas de la tapa de cada marco: { color, sangría }.
local function lidOf(f)
    local lid = f.lid
    if not lid then
        lid = { { "#303132", 5 }, { "#86888b", 4 }, { "#f2f7ec", 3 }, { f.bevel, 2 }, { f.bevel2, 2 }, { f.bevel2, 1 }, { f.line, 1 } }
        f.lid = lid
    end
    return lid
end
local NAME_ST = { s = 1.5, gap = 1, color = "#403f30", shadow = "#fbf6f0" }
local FUSED_NAME = {}                -- nombre -> { [n] = "nombre +n" }

-- Cómo se escribe el nombre de un movimiento en su botón (una o dos líneas, ya
-- centradas), calculado una vez por nombre y ancho: { a, ax, b, bx } (b = nil: una línea).
local nameLayouts = {}
local function nameLayout(name, fw)
    local byW = nameLayouts[fw]
    if not byW then byW = {}; nameLayouts[fw] = byW end
    local L = byW[name]
    if L then return L end
    local PFn = G.PixelFont
    local FS = 1.5                       -- tamaño intermedio de la fuente pixelada
    local maxw = fw - 2
    if PFn.width(name, FS, 1) <= maxw then
        L = { name, (fw - PFn.width(name, FS, 1)) / 2 }
    else
        local best, a, b = math.huge, name, ""
        local i = name:find(" ", 1, true)
        while i do
            local l1, l2 = name:sub(1, i - 1), name:sub(i + 1)
            local wmax = math.max(PFn.width(l1, FS, 1), PFn.width(l2, FS, 1))
            if wmax < best then best, a, b = wmax, l1, l2 end
            i = name:find(" ", i + 1, true)
        end
        if best > maxw then
            -- Una palabra sola que no cabe (TERRATEMBLOR): se parte con guion, por
            -- la letra que más equilibra (sólo entre letras ASCII, por los acentos).
            -- Corte silábico sencillo: tras vocal y antes de consonante + vocal (TERRA-TEMBLOR).
            local function vowel(ch) return ch and ("AEIOUaeiou"):find(string.char(ch), 1, true) ~= nil end
            for k = 2, #name - 2 do
                local c1, c2, c3 = name:byte(k), name:byte(k + 1), name:byte(k + 2)
                if c1 < 128 and c2 < 128 and c1 ~= 32 and c2 ~= 32
                   and vowel(c1) and not vowel(c2) and (vowel(c3) or (c3 and c3 >= 128)) then
                    local l1, l2 = name:sub(1, k) .. "-", name:sub(k + 1)
                    local wmax = math.max(PFn.width(l1, FS, 1), PFn.width(l2, FS, 1))
                    if wmax < best then best, a, b = wmax, l1, l2 end
                end
            end
        end
        L = { a, (fw - PFn.width(a, FS, 1)) / 2, b, (fw - PFn.width(b, FS, 1)) / 2 }
    end
    byW[name] = L
    return L
end

-- Botón de movimiento de Platino: contorno negro, marco del color del tipo con
-- bisel claro arriba y lateral oscuro, cara crema con banda inferior amarilla,
-- nombre centrado oscuro con sombra clara, etiqueta del tipo abajo a la izquierda.
-- Sin PP: a la derecha, los puntos de nivel del movimiento.
function R.moveButton(x, y, w, h, m, fused, active, cd)
    local f = m and frameOf(m.type) or EMPTY_FRAME
    -- Sombra de la caja sobre el fondo
    lg.setColor(0, 0, 0, 0.35)
    lg.rectangle("fill", x + 1, y + 2, w, h, 3, 3)
    -- Contorno negro (la caja entera)
    U.setColor("#101010")
    lg.rectangle("fill", x, y, w, h, 3, 3)
    -- Tapa vista en perspectiva: cada fila un poco más ancha (esquinas en diagonal)
    local lid = lidOf(f)
    for i = 1, #lid do
        local row = lid[i]
        U.setColor(row[1])
        lg.rectangle("fill", x + row[2], y + i - 1, w - row[2] * 2, 1)
    end
    local ly = y + #lid
    -- Laterales oscuros anchos, marco del color del tipo y base
    U.setColor(f.side)
    lg.rectangle("fill", x + 1, ly, w - 2, h - #lid - 1)
    U.setColor(f.frameDark)
    lg.rectangle("fill", x + 6, ly, w - 12, h - #lid - 3)
    U.setColor(f.frame)
    lg.rectangle("fill", x + 8, ly, w - 16, h - #lid - 4)
    U.setColor(f.bottom)
    lg.rectangle("fill", x + 6, y + h - 4, w - 12, 2)
    -- Cara crema con su borde amarillo y la banda inferior más oscura
    local fx, fy, fw, fh = x + 10, ly + 1, w - 20, h - #lid - 7
    local c1, c2, c3, c4 = "#ded065", "#eae097", "#f0e8aa", "#dfd168"
    if not m then c1, c2, c3, c4 = "#8c8a9c", "#a8a6b8", "#b4b2c4", "#9c9aac" end
    U.setColor(c1)
    lg.rectangle("fill", fx, fy, fw, fh)
    U.setColor(c2)
    lg.rectangle("fill", fx + 1, fy + 1, fw - 2, 1)
    local band = math.floor(fh * 0.32)
    U.setColor(c3)
    lg.rectangle("fill", fx + 1, fy + 2, fw - 2, fh - 3 - band)
    U.setColor(c4)
    lg.rectangle("fill", fx + 1, fy + fh - 1 - band, fw - 2, band)
    if not m then
        lg.setFont(UI.font(12))
        U.setColor("#5c5a6c")
        lg.printf("-", fx, fy + fh / 2 - 8, fw, "center")
    end
    if m then
        -- Recarga: velo oscuro de abajo arriba sobre la cara
        if cd and cd > 0.05 then
            lg.setColor(0, 0, 0, 0.12)
            lg.rectangle("fill", fx, fy + fh * (1 - cd), fw, fh * cd)
        end
        -- Nombre
        -- Mismo tipo de letra que el nombre del Pokémon (pixelada, sombra clara).
        -- Siempre al mismo tamaño: si no cabe en una línea, se parte en dos por el
        -- espacio que deja las dos líneas más equilibradas.
        local name = m.name
        if fused then
            local byN = FUSED_NAME[m.name]
            if not byN then byN = {}; FUSED_NAME[m.name] = byN end
            name = byN[fused]
            if not name then name = m.name .. " +" .. (fused - 1); byN[fused] = name end
        end
        local PF = G.PixelFont
        local L = nameLayout(name, fw)
        if not L[3] then
            PF.print(L[1], fx + L[2], fy + 10, NAME_ST)
        else
            PF.print(L[1], fx + L[2], fy + 3, NAME_ST)
            PF.print(L[3], fx + L[4], fy + 16, NAME_ST)
        end
        -- Etiqueta del tipo (fuente pixelada: mayúsculas sin tilde, como en el juego)
        local tn = U.TYPE_NAME[m.type] or m.type
        local tw = PF.width(tn, 1) + 10
        local bx, by = fx + 3, fy + fh - 13
        U.setColor(f.badgeEdge)
        lg.rectangle("fill", bx, by, tw, 13, 3, 3)
        U.setColor(f.badge)
        lg.rectangle("fill", bx + 1, by + 1, tw - 2, 11, 3, 3)
        PF.print(tn, bx + 5, by + 3, f.badgeSt)
        -- Nivel del movimiento en vez de PP
        local dots = m.def.maxLvl
        for d = 1, dots do
            local px = fx + fw - 6 - (dots - d + 1) * 8
            U.setColor("#403f30")
            lg.rectangle("fill", px, by + 3, 6, 7)
            U.setColor(d <= m.lvl and (m.evolved and "#f8b020" or "#38a0f8") or "#c8c090")
            lg.rectangle("fill", px + 1, by + 4, 4, 5)
        end
    end
    -- Marco de selección en el activo (el mismo de los menús)
    if active then UI.selectFrame(x, y, w, h) end
    lg.setColor(1, 1, 1, 1)
end

function hud.touch(x, y)
    local id = UI.hit(x, y)
    if not id then return end
    local pl = G.Game.player()
    if id == "pause" then G.Game.togglePause() return end
    if id == "burst" then G.Burst.fire(pl) return end
    local i = tonumber(id:match("^slot(%d+)$"))
    if i and pl and G.Game.state() == "playing" and pl.active ~= i then pl:setActive(i); G.Audio.sfx("click") end
end
function hud.button(b)
    if b == "x" then G.Burst.fire(G.Game.player()) end
end

UI.register("hud", hud)

-- ---------------- cartas de nivel ----------------

local cards = {}   -- pantalla genérica de cartas: { title, sub, list = {card...}, cb, focus }
local cur = nil

-- Opciones de texto reutilizadas (UI.text sólo las lee).
local C_TITLE = { size = 12 }
local C_DESC = { size = 10, color = UI.C.muted, w = 0 }
local C_HEAD = { size = 16, color = UI.C.gold, w = W, align = "center" }
local C_SUB = { size = 10, color = UI.C.muted, w = W - 20, align = "center" }
local C_BACK = { size = 10 }
local C_REROLL = { size = 10, color = "#3c6cc4", enabled = true }
local C_BAN = { size = 10, color = "#d04848", enabled = true, on = false }
local CARD_ID = {}                         -- "card1", "card2"...
local REROLL_TXT, BAN_TXT = {}, {}

local function drawCard(c, x, y, w, h, focused)
    local col = c.color or UI.C.line
    U.setColor(c.type == "evo" and "#2a2410" or UI.C.panel)
    lg.rectangle("fill", x, y, w, h, 6, 6)
    U.setColor(focused and UI.C.gold or col, focused and 1 or 0.6)
    lg.setLineWidth(focused and 2 or 1)
    lg.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 6, 6)
    lg.setLineWidth(1)
    U.setColor(col, 0.25)
    lg.rectangle("fill", x + 6, y + 6, h - 12, h - 12, 4, 4)
    G.Icons.draw(c.icon or "star", x + 6 + (h - 12 - 24) / 2, y + 6 + (h - 12 - 24) / 2, 24)
    local tx = x + h + 2
    UI.text(c.title, tx, y + 5, C_TITLE)
    if c.tag then
        -- Ancho del título y texto de la carta: una vez por carta (no en cada fotograma).
        local tw = c.__tw
        if not tw then tw = UI.textWidth(c.title, 12); c.__tw = tw end
        UI.chip(c.tag, tx + tw + 6, y + 6, c.type == "stat" and (c.color == "#ffd23f" and "#ffd23f" or "#9fb1c9") or col, 10)
    end
    local desc = c.__desc
    if not desc then desc = (c.desc or "") .. (c.desc2 and (" " .. c.desc2) or ""); c.__desc = desc end
    C_DESC.w = w - (tx - x) - 6
    UI.text(desc, tx, y + 22, C_DESC)
    lg.setColor(1, 1, 1, 1)
end

function cards.enter(data)
    cur = data
    cur.focus = 1
end

function cards.draw()
    if not cur then return end
    UI.text(cur.title or "", 0, 4, C_HEAD)
    if cur.sub then UI.text(cur.sub, 10, 24, C_SUB) end
    local n = #cur.list
    local top = cur.sub and 40 or 28
    local tools = cur.opts ~= nil                 -- repetir / vetar
    local avail = H - top - ((cur.back or tools) and 30 or 8)
    local h = math.min(60, math.floor((avail - (n - 1) * 6) / math.max(1, n)))
    for i, c in ipairs(cur.list) do
        local y = top + (i - 1) * (h + 6)
        drawCard(c, 8, y, W - 16, h, i == cur.focus)
        if cur.banning and c.type ~= "evo" then
            -- Modo vetar: las cartas se marcan en rojo
            U.setColor("#d04848", 0.35)
            lg.rectangle("fill", 8, y, W - 16, h, 6, 6)
            lg.setColor(1, 1, 1, 1)
        end
        local id = CARD_ID[i]
        if not id then id = "card" .. i; CARD_ID[i] = id end
        UI.hitbox(id, 8, y, W - 16, h)
    end
    if cur.back then UI.button("back", W / 2 - 50, H - 28, 100, 22, "Atrás", C_BACK) end
    if tools then
        local rr, bb = cur.opts.left()
        local rt = REROLL_TXT[rr]
        if not rt then rt = "Repetir (" .. rr .. ")"; REROLL_TXT[rr] = rt end
        local bt = BAN_TXT[bb]
        if not bt then bt = "Vetar (" .. bb .. ")"; BAN_TXT[bb] = bt end
        C_REROLL.enabled = rr > 0
        UI.button("reroll", 8, H - 27, 148, 22, rt, C_REROLL)
        C_BAN.enabled, C_BAN.on = bb > 0, cur.banning
        UI.button("ban", W - 156, H - 27, 148, 22, cur.banning and "Toca la carta a vetar" or bt, C_BAN)
    end
end

-- Cambia las cartas mostradas (tras repetir o vetar).
local function replaceList(list)
    if list and #list > 0 then cur.list = list; cur.focus = 1 end
    cur.banning = false
end

local function pickCard(i)
    if not cur or not cur.list[i] then return end
    local c, cb = cur.list[i], cur.cb
    cur = nil
    UI.show("hud")
    cb(c)
end

function cards.touch(x, y)
    local id = UI.hit(x, y)
    if not id then return end
    if id == "back" and cur and cur.onBack then cur.onBack() return end
    if cur and cur.opts then
        if id == "reroll" then G.Audio.sfx("select"); replaceList(cur.opts.reroll()) return end
        if id == "ban" then cur.banning = not cur.banning; G.Audio.sfx("click") return end
    end
    local i = tonumber(id:match("^card(%d+)$"))
    if i and cur and cur.banning then
        local c = cur.list[i]
        if c and c.type ~= "evo" then G.Audio.sfx("back"); replaceList(cur.opts.ban(c)) end
        return
    end
    if i then pickCard(i) end
end

function cards.button(b)
    if not cur then return end
    if b == "dpup" or b == "dpleft" then cur.focus = (cur.focus - 2) % #cur.list + 1; G.Audio.sfx("select")
    elseif b == "dpdown" or b == "dpright" then cur.focus = cur.focus % #cur.list + 1; G.Audio.sfx("select")
    elseif b == "a" then
        if cur.banning then
            local c = cur.list[cur.focus]
            if c and c.type ~= "evo" then replaceList(cur.opts.ban(c)) end
        else pickCard(cur.focus) end
    elseif b == "x" and cur.opts then replaceList(cur.opts.reroll())       -- X: repetir
    elseif b == "y" and cur.opts then cur.banning = not cur.banning        -- Y: modo vetar
    elseif b == "b" and cur.banning then cur.banning = false
    elseif b == "b" and cur.onBack then cur.onBack() end
end

UI.register("cards", cards)

-- opts (opcional): { left() -> repeticiones, vetos; reroll() -> lista; ban(carta) -> lista }
function R.showLevelUp(level, list, cb, opts)
    UI.show("cards", { title = "¡Nivel " .. level .. "!", sub = "Elige una recompensa", list = list, cb = cb, opts = opts })
end

-- Has encontrado un objeto llevando ya otro: ¿con cuál te quedas?
function R.showItemChoice(curId, nextId, cb)
    local list = {}
    for i, pair in ipairs({ { curId, "Quedarme con" }, { nextId, "Cambiar a" } }) do
        local it = G.Items.BY[pair[1]]
        list[i] = { title = pair[2] .. " " .. it.name, desc = it.desc, icon = pair[1], color = i == 2 and UI.C.gold or UI.C.line,
                    type = i == 2 and "evo" or "item", id = pair[1] }
    end
    UI.show("cards", { title = "¡Un objeto!", sub = "Solo puedes llevar uno", list = list, cb = function(c) cb(c.id) end })
end

-- Vínculo: qué movimientos se fusionan ('add': uno al grupo; 'pair': dos sueltos en dos pasos).
function R.showBond(opt, cb)
    local first = nil
    local function names(ms)
        local t = {}
        for i, m in ipairs(ms) do t[i] = m.name end
        return table.concat(t, " + ")
    end
    local render
    render = function()
        local step2 = opt.mode == "pair" and first
        local sub = opt.mode == "add" and ("Elige qué movimiento se une a " .. names(opt.group))
                 or (step2 and ("¿Con cuál unes " .. first.name .. "?") or "Elige el primer movimiento que vas a unir")
        local list = {}
        for _, m in ipairs(opt.loose) do
            if m ~= first then
                list[#list + 1] = { title = m.name, tag = "Nv." .. m.lvl, color = U.TYPE_COLOR[m.type], icon = "move:" .. m.id,
                                    desc = opt.mode == "add" and ("Se lanzará a la vez que " .. names(opt.group) .. ".")
                                        or (step2 and ("Se lanzará a la vez que " .. first.name .. ". Queda un hueco libre.") or (m.desc or "")),
                                    m = m }
            end
        end
        UI.show("cards", { title = "¡Vínculo!", sub = sub, list = list, back = step2 ~= nil and step2 ~= false,
            onBack = function() first = nil; render() end,
            cb = function(c)
                if opt.mode == "pair" and not first then
                    first = c.m; G.Audio.sfx("select"); render()
                    return
                end
                local picked = opt.mode == "add" and { c.m } or { first, c.m }
                cb(picked)
            end })
    end
    render()
end

-- ---------------- pausa ----------------

local pause = {}
-- Los textos de la pausa no cambian mientras está abierta (el reloj está parado):
-- se hacen al entrar (la cabecera y, por movimiento, { icono, texto }).
local P_TITLE = { size = 22, w = W, align = "center" }
local P_HEAD = { size = 12, color = UI.C.muted, w = W, align = "center" }
local P_MOVE = { size = 10 }
local P_RESUME = { color = "#3c9c54", size = 12 }
local P_QUIT = { color = "#3a1b22", size = 12 }
local pausePl, pauseHead, pauseMoves, pauseSec = nil, "", {}, -1
function pause.enter()
    local pl = G.Game.player()
    pausePl = pl
    pauseMoves = {}
    if not pl then return end
    pauseSec = math.floor(G.Game.time())
    pauseHead = pl.mon.name .. " · Nv. " .. pl.level .. " · " .. U.mmss(G.Game.time())
    for i, m in ipairs(pl.moves) do
        pauseMoves[i] = { "move:" .. m.id, m.name .. "  Nv." .. m.lvl .. (m.evolved and "  (evolucionado)" or "") }
    end
end
function pause.draw()
    UI.text("PAUSA", 0, 30, P_TITLE)
    local pl = G.Game.player()
    if pl then
        if pl ~= pausePl or math.floor(G.Game.time()) ~= pauseSec then pause.enter() end
        UI.text(pauseHead, 0, 62, P_HEAD)
        local y = 86
        for i = 1, #pauseMoves do
            local pm = pauseMoves[i]
            G.Icons.draw(pm[1], 40, y, 14)
            UI.text(pm[2], 60, y, P_MOVE)
            y = y + 16
        end
    end
    UI.button("resume", 40, 170, 240, 26, "Continuar", P_RESUME)
    UI.button("quit", 40, 204, 240, 26, "Abandonar run", P_QUIT)
end
function pause.touch(x, y)
    local id = UI.hit(x, y)
    if id == "resume" then G.Game.togglePause()
    elseif id == "quit" then G.Game.quitRun() end
end
function pause.button(b)
    if b == "a" then G.Game.togglePause() end
end
UI.register("pause", pause)

function R.showPause() UI.show("pause") end

-- ---------------- resumen ----------------

local over = {}
local overData, overCb = nil, nil
-- El resumen no cambia: al entrar se prepara la lista de textos { texto, x, y, opts }
-- y en cada fotograma sólo se dibuja.
local overItems = {}
local O_BACK = { size = 12, color = "#3c9c54" }
local function buildOver(r)
    local items = {}
    local function put(text, x, y, opts) items[#items + 1] = { text, x, y, opts } end
    local title = r.won and "¡Fase superada!" or (r.dead and "Has caído..." or "Run terminada")
    put(title, 0, 6, { size = 22, color = r.won and UI.C.green or (r.dead and UI.C.red or UI.C.gold), w = W, align = "center" })
    if r.stage then put(r.stage .. ((r.form or 1) > 1 and ("  ·  " .. r.name) or ""), 0, 30, { size = 10, color = UI.C.muted, w = W, align = "center" }) end
    local y = 44
    local LABEL = { size = 12, color = UI.C.muted }
    local function row(label, value, col)
        put(label, 24, y, LABEL)
        put(value, 150, y, { size = 12, color = col or UI.C.text })
        y = y + 16
    end
    row("Tiempo", U.mmss(r.time))
    row("Nivel", tostring(r.level))
    row("Derrotados", tostring(r.kills))
    row("Jefes", tostring(r.bosses))
    if r.judge then
        -- Lo aguantado en la Sentencia de Arceus.
        row("Ante Arceus", U.mmss(r.judge.time) .. " · " .. r.judge.bosses .. (r.judge.bosses == 1 and " legendario" or " legendarios"), UI.C.gold)
    end
    row("Pokémonedas", "+" .. r.coins, UI.C.gold)
    put(r.breakdown or "", 150, y - 2, { size = 10, color = UI.C.muted, w = 160 })
    y = y + (UI.textWidth(r.breakdown or "", 10) > 160 and 24 or 14)
    if (r.t1 or 0) > 0 or (r.t10 or 0) > 0 then
        row("Tickets", (r.t1 > 0 and ("+" .. r.t1 .. " ") or "") .. (r.t10 > 0 and ("+" .. r.t10 .. " x10") or ""), UI.C.purple)
    end
    local mv = {}
    for i, m in ipairs(r.moves or {}) do mv[i] = m.name .. " Nv." .. m.lvl end
    put("Movimientos: " .. (#mv > 0 and table.concat(mv, " · ") or "—"), 24, y, { size = 10, color = UI.C.muted, w = W - 48 })
    y = y + 24
    if r.caught and #r.caught > 0 then
        local names = {}
        for i, c in ipairs(r.caught) do names[i] = G.DEX_BY[c.dex].name .. (c.isNew and " (¡nuevo!)" or "") end
        put("Shinies: " .. table.concat(names, ", "), 24, y, { size = 10, color = UI.C.blue, w = W - 48 })
        y = y + 14
    end
    if r.record then put("¡Nuevo récord de tiempo!", 0, y, { size = 12, color = UI.C.gold, w = W, align = "center" }) end
    return items
end
function over.enter(d)
    overData = d.r; overCb = d.cb
    overItems = overData and buildOver(overData) or {}
    G.Audio.sfx("confirm")
end
function over.draw()
    if not overData then return end
    for i = 1, #overItems do
        local it = overItems[i]
        UI.text(it[1], it[2], it[3], it[4])
    end
    UI.button("back", 60, H - 32, 200, 26, "Volver al menú", O_BACK)
end
function over.touch(x, y)
    if UI.hit(x, y) == "back" and overCb then local cb = overCb; overCb = nil; cb() end
end
function over.button(b)
    if (b == "a" or b == "start") and overCb then local cb = overCb; overCb = nil; cb() end
end
UI.register("over", over)

function R.showOver(r, cb) UI.show("over", { r = r, cb = cb }) end
