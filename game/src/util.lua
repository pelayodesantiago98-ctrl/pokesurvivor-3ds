-- util.lua — helpers compartidos (port de js/core/util.js). Ver docs/PORT.md §3.
G = G or {}

G.LIFT = 18

local U = {}
G.U = U

local floor, sqrt, random = math.floor, math.sqrt, love.math.random

function U.clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
function U.lerp(a, b, t) return a + (b - a) * t end
function U.rand(a, b) return a + random() * (b - a) end
function U.randInt(a, b) return floor(a + random() * (b - a + 1)) end
function U.pick(arr) return arr[floor(random() * #arr) + 1] end
function U.round(x) return floor(x + 0.5) end
-- Redondea una coordenada de MUNDO a píxel de pantalla entero (la cámara dibuja
-- a escala 0.5: 2 unidades = 1 píxel). Sin esto, lo que cae a medio píxel toma
-- los texels vecinos del atlas y aparecen píxeles negros sueltos.
function U.snap(v)
    local s = (G.Camera and G.Camera.scale) or 0.5
    local u = 1 / s
    return floor(v / u + 0.5) * u
end
function U.sign(x) if x > 0 then return 1 elseif x < 0 then return -1 end return 0 end
function U.hypot(x, y) return sqrt(x * x + y * y) end

-- Elige n elementos distintos al azar.
function U.pickN(arr, n)
    local c = {}
    for i = 1, #arr do c[i] = arr[i] end
    local out = {}
    while #out < n and #c > 0 do
        local i = floor(random() * #c) + 1
        out[#out + 1] = c[i]
        c[i] = c[#c]; c[#c] = nil
    end
    return out
end

function U.shuffle(arr)
    for i = #arr, 2, -1 do
        local j = floor(random() * i) + 1
        arr[i], arr[j] = arr[j], arr[i]
    end
    return arr
end

function U.dist(ax, ay, bx, by) local dx, dy = bx - ax, by - ay return sqrt(dx * dx + dy * dy) end
function U.dist2(ax, ay, bx, by) local dx, dy = bx - ax, by - ay return dx * dx + dy * dy end

-- Normaliza un vector; devuelve 0,0 si es nulo. DOS valores, no tabla.
function U.norm(x, y)
    local m = sqrt(x * x + y * y)
    if m > 1e-6 then return x / m, y / m end
    return 0, 0
end

-- Interpolación independiente del framerate.
function U.damp(a, b, rate, dt) return b + (a - b) * math.exp(-rate * dt) end

-- Hash determinista 2D -> [0,1). Lua 5.1 no tiene operadores de bits ni enteros
-- de 32 bits: se usa aritmética modular dentro del rango exacto de un double.
local P = 2147483647
function U.hash(x, y, s)
    local h = (floor(x) * 73856093 + floor(y) * 19349663 + (s or 0) * 83492791) % P
    h = (h * 48271) % P
    h = (h * 16807 + 12345) % P
    h = (h * 48271) % P
    return h / P
end

function U.mmss(s)
    local m = floor(s / 60)
    return string.format("%d:%02d", m, floor(s % 60))
end

function U.now() return love.timer.getTime() end

function U.contains(arr, v)
    for i = 1, #arr do if arr[i] == v then return true end end
    return false
end
function U.indexOf(arr, v)
    for i = 1, #arr do if arr[i] == v then return i end end
    return nil
end
function U.remove(arr, v)
    for i = 1, #arr do if arr[i] == v then table.remove(arr, i) return true end end
    return false
end
function U.removeSwap(arr, i)
    local n = #arr
    arr[i] = arr[n]; arr[n] = nil
end
function U.keys(t) local out = {} for k in pairs(t) do out[#out + 1] = k end return out end
function U.values(t) local out = {} for _, v in pairs(t) do out[#out + 1] = v end return out end
function U.count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

-- ---------------- colores ----------------

U.TYPE_COLOR = {
    normal = '#b0a99f', fire = '#ff7b3d', water = '#4b9bff', grass = '#5fcb6a',
    electric = '#ffd33d', ice = '#7fe0e0', fighting = '#e0533d', poison = '#b45ec4',
    ground = '#d6b25c', flying = '#9bb8ff', psychic = '#ff5f9e', bug = '#a3c43d',
    rock = '#bfa96b', ghost = '#7a6bc4', dragon = '#6b58ff', dark = '#6b5c52',
    steel = '#a8b8c4', fairy = '#ff9ed8'
}

U.TYPE_NAME = {
    normal = 'Normal', fire = 'Fuego', water = 'Agua', grass = 'Planta',
    electric = 'Eléctrico', ice = 'Hielo', fighting = 'Lucha', poison = 'Veneno',
    ground = 'Tierra', flying = 'Volador', psychic = 'Psíquico', bug = 'Bicho',
    rock = 'Roca', ghost = 'Fantasma', dragon = 'Dragón', dark = 'Siniestro',
    steel = 'Acero', fairy = 'Hada'
}

U.TYPES = { 'normal', 'fire', 'water', 'grass', 'electric', 'ice', 'fighting', 'poison', 'ground',
            'flying', 'psychic', 'bug', 'rock', 'ghost', 'dragon', 'dark', 'steel', 'fairy' }

local rgbCache = {}
-- "#rrggbb" -> r, g, b en 0..1 (cacheado).
function U.rgb(hex)
    local c = rgbCache[hex]
    if c then return c[1], c[2], c[3] end
    local r, g, b = 1, 1, 1
    if type(hex) == "string" and #hex >= 7 then
        r = tonumber(hex:sub(2, 3), 16) / 255
        g = tonumber(hex:sub(4, 5), 16) / 255
        b = tonumber(hex:sub(6, 7), 16) / 255
    end
    rgbCache[hex] = { r, g, b }
    return r, g, b
end

local setColor = love.graphics.setColor
function U.setColor(hex, alpha)
    local r, g, b = U.rgb(hex)
    setColor(r, g, b, alpha or 1)
end

local function hex2(v)
    return string.format("%02x", U.clamp(floor(v * 255 + 0.5), 0, 255))
end
-- Mezcla de dos colores. Cacheada por pareja y por t (redondeado a 1/1024, menos
-- de lo que se nota en 8 bits por canal): el marco de selección late con ella en
-- cada fotograma y así no crea cadenas nuevas cada vez.
local mixCache = {}
function U.hexMix(h1, h2, t)
    local c1 = mixCache[h1]
    if not c1 then c1 = {}; mixCache[h1] = c1 end
    local c2 = c1[h2]
    if not c2 then c2 = {}; c1[h2] = c2 end
    local tq = floor(t * 1024 + 0.5)
    local s = c2[tq]
    if s then return s end
    local r1, g1, b1 = U.rgb(h1)
    local r2, g2, b2 = U.rgb(h2)
    t = tq / 1024
    s = "#" .. hex2(r1 + (r2 - r1) * t) .. hex2(g1 + (g2 - g1) * t) .. hex2(b1 + (b2 - b1) * t)
    c2[tq] = s
    return s
end
-- Aclara (k>0) u oscurece (k<0) un color.
function U.shade(hex, k)
    local r, g, b = U.rgb(hex)
    local function f(v) if k >= 0 then return v + (1 - v) * k end return v * (1 + k) end
    return "#" .. hex2(f(r)) .. hex2(f(g)) .. hex2(f(b))
end

-- ¿Consola real? nest también define love._console en PC, así que se mira la
-- marca de LÖVE Potion (love._potion_version) o el sistema operativo "Horizon".
U.CONSOLE = (love._potion_version ~= nil)
    or (love.system ~= nil and love.system.getOS ~= nil and love.system.getOS() == "Horizon")

-- Ruta de imagen según plataforma (en consola solo cargan .t3x).
function U.img(path)
    return path .. (U.CONSOLE and ".t3x" or ".png")
end
