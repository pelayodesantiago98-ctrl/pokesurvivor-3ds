-- pixelfont.lua — fuente de mapa de bits en mayúsculas gruesas, al estilo de los
-- carteles de zona de los juegos de DS (letras cian con contorno oscuro). Se dibuja
-- píxel a píxel con rectángulos, así funciona igual en PC y en la consola sin
-- necesitar ficheros de fuente. Glifos de 5x7; las tildes se dibujan sin acento.
local U = G.U
local PF = {}
G.PixelFont = PF

local lg = love.graphics

local GLYPHS = {
    A = { ".###.", "##.##", "##.##", "#####", "##.##", "##.##", "##.##" },
    B = { "####.", "##.##", "##.##", "####.", "##.##", "##.##", "####." },
    C = { ".###.", "##.##", "##...", "##...", "##...", "##.##", ".###." },
    D = { "####.", "##.##", "##.##", "##.##", "##.##", "##.##", "####." },
    E = { "#####", "##...", "##...", "####.", "##...", "##...", "#####" },
    F = { "#####", "##...", "##...", "####.", "##...", "##...", "##..." },
    G = { ".###.", "##.##", "##...", "##.##", "##.##", "##.##", ".####" },
    H = { "##.##", "##.##", "##.##", "#####", "##.##", "##.##", "##.##" },
    I = { "####", ".##.", ".##.", ".##.", ".##.", ".##.", "####" },
    J = { "..###", "...##", "...##", "...##", "##.##", "##.##", ".###." },
    K = { "##.##", "##.##", "####.", "###..", "####.", "##.##", "##.##" },
    L = { "##...", "##...", "##...", "##...", "##...", "##...", "#####" },
    M = { "##...##", "###.###", "#######", "##.#.##", "##...##", "##...##", "##...##" },
    N = { "##..##", "###.##", "######", "##.###", "##..##", "##..##", "##..##" },
    O = { ".###.", "##.##", "##.##", "##.##", "##.##", "##.##", ".###." },
    P = { "####.", "##.##", "##.##", "####.", "##...", "##...", "##..." },
    Q = { ".###.", "##.##", "##.##", "##.##", "##.##", "##.#.", ".##.#" },
    R = { "####.", "##.##", "##.##", "####.", "####.", "##.##", "##.##" },
    S = { ".####", "##...", "##...", ".###.", "...##", "...##", "####." },
    T = { "######", "..##..", "..##..", "..##..", "..##..", "..##..", "..##.." },
    U = { "##.##", "##.##", "##.##", "##.##", "##.##", "##.##", ".###." },
    V = { "##.##", "##.##", "##.##", "##.##", "##.##", ".###.", "..#.." },
    W = { "##...##", "##...##", "##...##", "##.#.##", "#######", "###.###", "##...##" },
    X = { "##.##", "##.##", ".###.", "..#..", ".###.", "##.##", "##.##" },
    Y = { "##..##", "##..##", "##..##", ".####.", "..##..", "..##..", "..##.." },
    Z = { "#####", "...##", "..##.", ".##..", "##...", "##...", "#####" },
    ["Ñ"] = { ".####.", "......", "##..##", "###.##", "######", "##.###", "##..##" },
    ["0"] = { ".###.", "##.##", "##.##", "##.##", "##.##", "##.##", ".###." },
    ["1"] = { ".##", "###", ".##", ".##", ".##", ".##", ".##" },
    ["2"] = { ".###.", "##.##", "...##", "..##.", ".##..", "##...", "#####" },
    ["3"] = { "####.", "...##", "...##", ".###.", "...##", "...##", "####." },
    ["4"] = { "##.##", "##.##", "##.##", "#####", "...##", "...##", "...##" },
    ["5"] = { "#####", "##...", "####.", "...##", "...##", "##.##", ".###." },
    ["6"] = { ".###.", "##...", "####.", "##.##", "##.##", "##.##", ".###." },
    ["7"] = { "#####", "...##", "..##.", ".##..", ".##..", ".##..", ".##.." },
    ["8"] = { ".###.", "##.##", "##.##", ".###.", "##.##", "##.##", ".###." },
    ["9"] = { ".###.", "##.##", "##.##", ".####", "...##", "...##", ".###." },
    ["-"] = { "....", "....", "....", "####", "....", "....", "...." },
    ["."] = { "..", "..", "..", "..", "..", "##", "##" },
    [","] = { "..", "..", "..", "..", "##", "##", "#." },
    ["'"] = { "##", "##", "#.", "..", "..", "..", ".." },
    ["!"] = { "##", "##", "##", "##", "##", "..", "##" },
    ["¡"] = { "##", "..", "##", "##", "##", "##", "##" },
    ["?"] = { ".###.", "##.##", "...##", "..##.", ".##..", ".....", ".##.." },
    ["¿"] = { "..##.", ".....", "..##.", ".##..", "##...", "##.##", ".###." },
    ["·"] = { "..", "..", "..", "##", "##", "..", ".." },
    ["/"] = { "...##", "...##", "..##.", ".##..", ".##..", "##...", "##..." },
    [":"] = { "..", "##", "##", "..", "##", "##", ".." },
    ["+"] = { "....", ".##.", "####", "####", ".##.", "....", "...." },
    ["x"] = { "....", "....", "##.##", ".###.", "..#..", ".###.", "##.##" },
    ["%"] = { "##..#", "##.##", "..##.", ".##..", "##.##", "#..##", "...##" },
    ["*"] = { "..#..", "#.#.#", ".###.", "#####", ".###.", "#.#.#", "..#.." },
    [" "] = { "...", "...", "...", "...", "...", "...", "..." },
}

-- Atlas (tools/gen_pixelfont.py): cada letra es UNA imagen. Dibujar píxel a píxel
-- con rectángulos daba >14.000 figuras por fotograma en el cuestionario y la 3DS se
-- cerraba sin error. Si falta el atlas se vuelve a los rectángulos.
-- Q[escala][capa][glifo]: escala 1, 1.5, 2; capa "b" letra, "s" sombra ya hecha,
-- "o" contorno ya hecho (empieza un píxel arriba a la izquierda).
local atlas, tried = nil, false
local Q = {}
local SCALE_CODE = { [1] = "1", [1.5] = "15", [2] = "2" }
local function loadAtlas()
    tried = true
    local okd, d = pcall(require, "data.pixelfont")
    local oki, im = false, nil
    if okd and d then oki, im = pcall(lg.newImage, U.img("img/pixelfont")) end
    if oki and im then
        if im.setFilter then pcall(im.setFilter, im, "nearest", "nearest") end
        atlas = im
        for s, code in pairs(SCALE_CODE) do
            local byLayer = {}
            for _, layer in ipairs({ "b", "s", "o" }) do
                local src, t = d[code .. layer], {}
                if src then
                    for key, gl in pairs(GLYPHS) do
                        local r = src[key]
                        if r then t[gl] = lg.newQuad(r[1], r[2], r[3], r[4], d.w, d.h) end
                    end
                end
                byLayer[layer] = t
            end
            Q[s] = byLayer
        end
    end
end

-- Mayúsculas y tildes fuera (UTF-8): á→A, é→E...; ñ→Ñ.
local MAP = {
    ["á"] = "A", ["é"] = "E", ["í"] = "I", ["ó"] = "O", ["ú"] = "U", ["ü"] = "U",
    ["Á"] = "A", ["É"] = "E", ["Í"] = "I", ["Ó"] = "O", ["Ú"] = "U", ["Ü"] = "U",
    ["ñ"] = "Ñ", ["—"] = "-", ["–"] = "-",
}

-- Recorre la cadena UTF-8 devolviendo los glifos (cacheado por texto).
-- (Como mucho 400 textos: los que cambian, como contadores o tiempos, no la hacen
-- crecer sin fin; al pasarse se vacía.)
local cache, nCache = {}, 0
local function glyphsOf(text)
    local g = cache[text]
    if g then return g end
    nCache = nCache + 1
    if nCache > 400 then cache, nCache = {}, 1 end
    g = {}
    local i, n = 1, #text
    while i <= n do
        local c = text:byte(i)
        local len = c < 0x80 and 1 or (c < 0xE0 and 2 or (c < 0xF0 and 3 or 4))
        local ch = text:sub(i, i + len - 1)
        i = i + len
        ch = MAP[ch] or ch:upper()
        g[#g + 1] = GLYPHS[ch] or GLYPHS["?"]
    end
    cache[text] = g
    return g
end

-- Ancho en píxeles de pantalla a escala s.
-- `gap`: píxeles de pantalla entre letras (por defecto, uno de arte: s).
-- Tamaño intermedio (s = 1.5): en vez de escalar con decimales (trazos
-- irregulares), cada letra duplica siempre las mismas columnas (primera, central y
-- última) y filas (primera, central y última): 5x7 -> 8x10, nítida y uniforme.
local MID_ROWS = { 2, 1, 1, 2, 1, 1, 2 }
local midCols = {}
local function midColW(w)
    local t = midCols[w]
    if t then return t end
    t = {}
    local mid = math.floor(w / 2) + 1
    for c = 1, w do t[c] = (c == 1 or c == w or c == mid) and 2 or 1 end
    midCols[w] = t
    return t
end
local function glyphW(gl, s)
    local w = #gl[1]
    if s ~= 1.5 then return w * s end
    local t, sum = midColW(w), 0
    for c = 1, w do sum = sum + t[c] end
    return sum
end

-- Ancho en píxeles de pantalla a escala s.
-- `gap`: píxeles de pantalla entre letras (por defecto, uno de arte: s).
function PF.width(text, s, gap)
    s = s or 2
    gap = gap or math.floor(s)
    local w = 0
    local g = glyphsOf(text)
    for k = 1, #g do w = w + glyphW(g[k], s) + gap end
    return math.max(0, w - gap)
end

function PF.height(s)
    if s == 1.5 then return 10 end
    return 7 * (s or 2)
end

-- Una capa ("b" letra, "s" sombra, "o" contorno) del texto. Con atlas, una imagen por
-- letra; sin él (o a una escala que no está), la letra píxel a píxel y la sombra o el
-- contorno repitiéndola desplazada.
local blitRaw
local function blit(g, x, y, s, gap, layer)
    if not tried then loadAtlas() end
    layer = layer or "b"
    local qs = atlas and Q[s] and Q[s][layer]
    if qs then
        local off = layer == "o" and -1 or 0
        for k = 1, #g do
            local gl = g[k]
            local q = qs[gl]
            if q then lg.draw(atlas, q, x + off, y + off) end
            x = x + glyphW(gl, s) + gap
        end
        return
    end
    if layer == "s" then
        blitRaw(g, x + 1, y, s, gap); blitRaw(g, x, y + 1, s, gap); blitRaw(g, x + 1, y + 1, s, gap)
    elseif layer == "o" then
        for dy = -1, 1 do
            for dx = -1, 1 do
                if dx ~= 0 or dy ~= 0 then blitRaw(g, x + dx, y + dy, s, gap) end
            end
        end
    else
        blitRaw(g, x, y, s, gap)
    end
end

blitRaw = function(g, x, y, s, gap)
    for k = 1, #g do
        local gl = g[k]
        if s == 1.5 then
            local cw = midColW(#gl[1])
            local yy = y
            for r = 1, 7 do
                local row, rh = gl[r], MID_ROWS[r]
                local xx = x
                for c = 1, #row do
                    if row:byte(c) == 35 then lg.rectangle("fill", xx, yy, cw[c], rh) end
                    xx = xx + cw[c]
                end
                yy = yy + rh
            end
        else
            for r = 1, 7 do
                local row = gl[r]
                for c = 1, #row do
                    if row:byte(c) == 35 then lg.rectangle("fill", x + (c - 1) * s, y + (r - 1) * s, s, s) end
                end
            end
        end
        x = x + glyphW(gl, s) + gap
    end
end

-- Dibuja con contorno oscuro de 1 px y relleno cian con la mitad inferior algo
-- más clara, como el cartel de los juegos. opts: { s, color, shade, outline, alpha }
function PF.print(text, x, y, opts)
    local s = (opts and opts.s) or 2
    local a = (opts and opts.alpha) or 1
    local gap = (opts and opts.gap) or math.floor(s)
    local g = glyphsOf(text)
    x, y = math.floor(x + 0.5), math.floor(y + 0.5)
    if opts and opts.shadow then
        -- Estilo de los menús de Platino: sombra clara abajo a la derecha.
        U.setColor(opts.shadow, a)
        blit(g, x, y, s, gap, "s")
    elseif not (opts and opts.noOutline) then
        U.setColor((opts and opts.outline) or "#0a1418", a)
        blit(g, x, y, s, gap, "o")
    end
    U.setColor((opts and opts.color) or "#70d0f0", a)
    blit(g, x, y, s, gap)
    lg.setColor(1, 1, 1, 1)
end

-- Cartel de zona: banda oscura translúcida (se ve el mapa) con el nombre centrado.
-- Parte `text` en líneas que quepan en `maxw` píxeles (cortando por espacios).
-- Caché por texto y, dentro, por (escala, ancho, separación) en un número: sin
-- montar una clave de texto en cada llamada. Como mucho 200 textos.
local wrapCache, nWrap = {}, 0
function PF.wrap(text, s, maxw, gap)
    local byT = wrapCache[text]
    if not byT then
        nWrap = nWrap + 1
        if nWrap > 200 then wrapCache, nWrap = {}, 1 end
        byT = {}
        wrapCache[text] = byT
    end
    local key = (maxw * 1000 + (s or 2) * 100) * 100 + (gap or 99)
    local out = byT[key]
    if out then return out end
    out = {}
    local line = ""
    for word in text:gmatch("%S+") do
        local try = line == "" and word or (line .. " " .. word)
        if line ~= "" and PF.width(try, s, gap) > maxw then
            out[#out + 1] = line
            line = word
        else
            line = try
        end
    end
    if line ~= "" then out[#out + 1] = line end
    byT[key] = out
    return out
end

-- Texto en varias líneas, centrado en [x, x + w]. Devuelve la altura usada.
function PF.printBlock(text, x, y, w, opts)
    local s = (opts and opts.s) or 2
    local gap = opts and opts.gap
    local lines = PF.wrap(text, s, w, gap)
    local lh = PF.height(s) + math.max(2, math.floor(PF.height(s) / 3))
    for i, l in ipairs(lines) do
        PF.print(l, x + (w - PF.width(l, s, gap)) / 2, y + (i - 1) * lh, opts)
    end
    return #lines * lh
end

function PF.zoneSign(text, cx, y, alpha, s)
    s = s or 2
    alpha = alpha or 1
    local w = PF.width(text, s) + 24
    local h = PF.height(s) + 12
    lg.setColor(0, 0, 0, 0.55 * alpha)
    lg.rectangle("fill", cx - w / 2, y, w, h, 3, 3)
    lg.setColor(0, 0, 0, 0.35 * alpha)
    lg.rectangle("fill", cx - w / 2 + 2, y + 2, w - 4, 1)
    PF.print(text, cx - PF.width(text, s) / 2, y + 6, { s = s, alpha = alpha })
end
