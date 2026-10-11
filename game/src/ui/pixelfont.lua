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
    ["·"] = { "..", "..", "..", "##", "##", "..", ".." },
    ["/"] = { "...##", "...##", "..##.", ".##..", ".##..", "##...", "##..." },
    [":"] = { "..", "##", "##", "..", "##", "##", ".." },
    ["+"] = { "....", ".##.", "####", "####", ".##.", "....", "...." },
    ["x"] = { "....", "....", "##.##", ".###.", "..#..", ".###.", "##.##" },
    ["*"] = { "..#..", "#.#.#", ".###.", "#####", ".###.", "#.#.#", "..#.." },
    [" "] = { "...", "...", "...", "...", "...", "...", "..." },
}

-- Mayúsculas y tildes fuera (UTF-8): á→A, é→E...; ñ→Ñ.
local MAP = {
    ["á"] = "A", ["é"] = "E", ["í"] = "I", ["ó"] = "O", ["ú"] = "U", ["ü"] = "U",
    ["Á"] = "A", ["É"] = "E", ["Í"] = "I", ["Ó"] = "O", ["Ú"] = "U", ["Ü"] = "U",
    ["ñ"] = "Ñ", ["—"] = "-", ["–"] = "-",
}

-- Recorre la cadena UTF-8 devolviendo los glifos (cacheado por texto).
local cache = {}
local function glyphsOf(text)
    local g = cache[text]
    if g then return g end
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

local function blit(g, x, y, s, gap)
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
        blit(g, x + 1, y, s, gap)
        blit(g, x, y + 1, s, gap)
        blit(g, x + 1, y + 1, s, gap)
    elseif not (opts and opts.noOutline) then
        U.setColor((opts and opts.outline) or "#0a1418", a)
        for dy = -1, 1 do
            for dx = -1, 1 do
                if dx ~= 0 or dy ~= 0 then blit(g, x + dx, y + dy, s, gap) end
            end
        end
    end
    U.setColor((opts and opts.color) or "#70d0f0", a)
    blit(g, x, y, s, gap)
    lg.setColor(1, 1, 1, 1)
end

-- Cartel de zona: banda oscura translúcida (se ve el mapa) con el nombre centrado.
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
