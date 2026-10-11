-- json.lua — codificador/decodificador JSON (Lua 5.1 puro) para la partida guardada.
--
--   G.JSON.encode(t) -> string      G.JSON.decode(s) -> t  (lanza error si el texto no es JSON)
--
-- Convenio de tablas (es importante para que la partida haga ida y vuelta sin cambios):
--   * Una tabla con claves 1..n consecutivas (y al menos una) se escribe como ARRAY JSON.
--   * Cualquier otra tabla (incluida la vacía) se escribe como OBJETO con claves string.
--     Las claves numéricas (p. ej. `owned[25]`, `pity[1]`) se escriben como "25", "1".
--   * Al decodificar, una clave de objeto que sea la forma canónica de un número
--     entero ("25", pero no "025" ni "2.0") vuelve a ser el número 25. Así
--     `save.owned[dex]` sigue funcionando con índices numéricos tras cargar.
--     (Si por casualidad un objeto decodificado queda con claves 1..n, la próxima
--     vez se escribirá como array: en Lua es la misma tabla, solo cambia el texto.)
--   * `null` se decodifica como nil (la clave desaparece; en arrays dejaría huecos:
--     no se usan arrays con null en la partida). nil no se codifica (se omite).
--   * Números: enteros sin decimales; el resto con 14 cifras significativas.
--     NaN e infinito se escriben como null.
--   * Strings: escapes \" \\ \b \f \n \r \t y \uXXXX (con parejas sustitutas → UTF-8).
local J = {}
G.JSON = J

local floor, huge = math.floor, math.huge
local concat, sort = table.concat, table.sort
local byte, char, format, find, sub, gsub = string.byte, string.char, string.format, string.find, string.sub, string.gsub

-- ---------------- codificar ----------------

local ESC = { ['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b', ['\f'] = '\\f',
              ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
local function escChar(c) return ESC[c] or format("\\u%04x", byte(c)) end
local function encString(s) return '"' .. gsub(s, '[%c"\\]', escChar) .. '"' end

local function encNumber(n)
    if n ~= n or n == huge or n == -huge then return "null" end
    if n == floor(n) and n > -1e15 and n < 1e15 then return format("%d", n) end
    return format("%.14g", n)
end

-- ¿Claves 1..n consecutivas (y n >= 1)?
local function isArray(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    if n == 0 then return false end
    for i = 1, n do if t[i] == nil then return false end end
    return true
end

local function keyString(k)
    local tk = type(k)
    if tk == "string" then return k end
    if tk == "number" then return encNumber(k) end
    error("JSON: clave de tipo " .. tk .. " no admitida")
end

local function sortKeys(a, b) return keyString(a) < keyString(b) end

local encValue
local function encTable(t, out, seen)
    if seen[t] then error("JSON: la tabla se contiene a sí misma") end
    seen[t] = true
    if isArray(t) then
        out[#out + 1] = "["
        for i = 1, #t do
            if i > 1 then out[#out + 1] = "," end
            encValue(t[i], out, seen)
        end
        out[#out + 1] = "]"
    else
        -- Claves ordenadas: salida determinista (facilita comparar guardados).
        local keys = {}
        for k in pairs(t) do keys[#keys + 1] = k end
        sort(keys, sortKeys)
        out[#out + 1] = "{"
        for i = 1, #keys do
            local k = keys[i]
            if i > 1 then out[#out + 1] = "," end
            out[#out + 1] = encString(keyString(k))
            out[#out + 1] = ":"
            encValue(t[k], out, seen)
        end
        out[#out + 1] = "}"
    end
    seen[t] = nil
end

encValue = function(v, out, seen)
    local tv = type(v)
    if tv == "nil" then out[#out + 1] = "null"
    elseif tv == "boolean" then out[#out + 1] = v and "true" or "false"
    elseif tv == "number" then out[#out + 1] = encNumber(v)
    elseif tv == "string" then out[#out + 1] = encString(v)
    elseif tv == "table" then encTable(v, out, seen)
    else error("JSON: no se puede codificar un valor de tipo " .. tv) end
end

function J.encode(v)
    local out = {}
    encValue(v, out, {})
    return concat(out)
end

-- ---------------- decodificar ----------------

local function fail(s, i, msg)
    error(format("JSON: %s en la posición %d (…%s…)", msg, i, sub(s, i, i + 12)), 0)
end

local function skipWs(s, i)
    local _, e = find(s, "^[ \t\r\n]*", i)
    return e + 1
end

-- Punto de código → bytes UTF-8 (sin operadores de bits).
local function utf8(cp)
    if cp < 0x80 then return char(cp) end
    if cp < 0x800 then return char(0xC0 + floor(cp / 0x40), 0x80 + cp % 0x40) end
    if cp < 0x10000 then
        return char(0xE0 + floor(cp / 0x1000), 0x80 + floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
    end
    return char(0xF0 + floor(cp / 0x40000), 0x80 + floor(cp / 0x1000) % 0x40,
                0x80 + floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
end

local SIMPLE = { ['"'] = '"', ['\\'] = '\\', ['/'] = '/', b = '\b', f = '\f', n = '\n', r = '\r', t = '\t' }

local function decString(s, i)
    -- s[i] es la comilla de apertura
    local parts, n = {}, 0
    local j = i + 1
    while true do
        local a, b = find(s, '[%c"\\]', j)
        if not a then fail(s, i, "string sin cerrar") end
        local c = sub(s, a, b)
        if a > j then n = n + 1; parts[n] = sub(s, j, a - 1) end
        if c == '"' then
            return concat(parts), b + 1
        elseif c == '\\' then
            local e = sub(s, a + 1, a + 1)
            if e == 'u' then
                local hex = sub(s, a + 2, a + 5)
                if not find(hex, "^%x%x%x%x$") then fail(s, a, "escape \\u inválido") end
                local cp = tonumber(hex, 16)
                j = a + 6
                -- Pareja sustituta (UTF-16) → un solo punto de código.
                if cp >= 0xD800 and cp <= 0xDBFF and sub(s, j, j + 1) == '\\u' then
                    local lo = tonumber(sub(s, j + 2, j + 5), 16)
                    if lo and lo >= 0xDC00 and lo <= 0xDFFF then
                        cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
                        j = j + 6
                    end
                end
                n = n + 1; parts[n] = utf8(cp)
            else
                local r = SIMPLE[e]
                if not r then fail(s, a, "escape inválido") end
                n = n + 1; parts[n] = r
                j = a + 2
            end
        else
            fail(s, a, "carácter de control dentro de un string")
        end
    end
end

local function decNumber(s, i)
    local a, b = find(s, "^-?%d+%.?%d*[eE]?[-+]?%d*", i)
    if not a then fail(s, i, "número inválido") end
    local n = tonumber(sub(s, a, b))
    if not n then fail(s, i, "número inválido") end
    return n, b + 1
end

-- Clave de objeto: si es la forma canónica de un entero, vuelve a ser número.
local function objKey(k)
    local n = tonumber(k)
    if n and n == floor(n) and tostring(n) == k then return n end
    return k
end

local decValue

local function decArray(s, i)
    local out, n = {}, 0
    i = skipWs(s, i + 1)
    if sub(s, i, i) == "]" then return out, i + 1 end
    while true do
        local v
        v, i = decValue(s, i)
        n = n + 1
        out[n] = v
        i = skipWs(s, i)
        local c = sub(s, i, i)
        if c == "]" then return out, i + 1 end
        if c ~= "," then fail(s, i, "se esperaba , o ]") end
        i = skipWs(s, i + 1)
    end
end

local function decObject(s, i)
    local out = {}
    i = skipWs(s, i + 1)
    if sub(s, i, i) == "}" then return out, i + 1 end
    while true do
        if sub(s, i, i) ~= '"' then fail(s, i, "se esperaba una clave") end
        local k
        k, i = decString(s, i)
        i = skipWs(s, i)
        if sub(s, i, i) ~= ":" then fail(s, i, "se esperaba :") end
        i = skipWs(s, i + 1)
        local v
        v, i = decValue(s, i)
        out[objKey(k)] = v
        i = skipWs(s, i)
        local c = sub(s, i, i)
        if c == "}" then return out, i + 1 end
        if c ~= "," then fail(s, i, "se esperaba , o }") end
        i = skipWs(s, i + 1)
    end
end

decValue = function(s, i)
    local c = sub(s, i, i)
    if c == "{" then return decObject(s, i) end
    if c == "[" then return decArray(s, i) end
    if c == '"' then return decString(s, i) end
    if c == "-" or find(c, "^%d") then return decNumber(s, i) end
    if sub(s, i, i + 3) == "true" then return true, i + 4 end
    if sub(s, i, i + 4) == "false" then return false, i + 5 end
    if sub(s, i, i + 3) == "null" then return nil, i + 4 end
    fail(s, i, "valor inesperado")
end

function J.decode(s)
    if type(s) ~= "string" then error("JSON: decode espera un string", 0) end
    local i = skipWs(s, 1)
    local v, j = decValue(s, i)
    j = skipWs(s, j)
    if j <= #s then fail(s, j, "texto sobrante tras el valor") end
    return v
end
