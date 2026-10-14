-- tools/bake_buttons — hornea game/img/ui/btn.png: la capa "de luces y sombras" de
-- los botones de UI.button (game/src/ui/ui.lua), sin color.
--
--   & "$env:USERPROFILE\3ds-tools\love\lovec.exe" tools\bake_buttons game\img\ui\btn.png game\img\ui\menuicons.png
--
-- (desde la raíz del proyecto: lee los iconos de game/img/menu)
--
-- Un botón eran 7 figuras (sombra, contorno, cuerpo, brillo en dos trozos y los dos
-- biseles). Ahora es un rectángulo redondeado del color del cuerpo y, encima, esta
-- capa en 3 trozos (esquina izquierda, una columna que se estira y esquina
-- derecha). Cada píxel de la capa es blanco o negro con la transparencia que da
-- el mismo color que antes sobre el cuerpo:
--   contorno = cuerpo x 0,38       -> negro 0,62
--   brillo   = cuerpo + 22 % blanco -> blanco 0,22
--   bisel claro (0,6 de blanco al 85 % sobre el brillo) -> blanco 0,543 (0,372 si está desactivado)
--   bisel oscuro = cuerpo x 0,7     -> negro 0,3
--   sombra (fuera del botón)        -> negro 0,35
-- Se dibuja con las mismas figuras que UI.button (y los mismos recortes de esquinas
-- que main.lua), así los píxeles coinciden.
--
-- La disposición (ALTOS, TW, huecos) tiene que ser la misma que en ui.lua (BTN_*).
local ALTOS = { 14, 16, 18, 20, 22, 26, 30, 31, 34, 43 }
local TW = 24                     -- ancho del botón de muestra (la plantilla mide TW + 1: la sombra)
local lg = love.graphics

-- Como lg.rectangle de main.lua: esquinas como mucho de la mitad del lado y nada
-- de tamaño <= 0.
local function rect(mode, x, y, w, h, rx, ry)
    if w <= 0 or h <= 0 then return end
    if rx then
        local m = math.min(w, h) / 2
        rx = math.min(rx, m)
        ry = math.min(ry or rx, m)
        if rx >= 1 and ry >= 1 then return lg.rectangle(mode, x, y, w, h, rx, ry) end
    end
    return lg.rectangle(mode, x, y, w, h)
end

-- Capa de un botón de w x h en (x, y), con la mezcla "replace" (cada figura pone
-- su color y transparencia tal cual).
local function layer(x, y, w, h, enabled)
    local r = math.min(6, h / 2 - 1)
    lg.setColor(0, 0, 0, 0.35)
    rect("fill", x + 1, y + 2, w, h, r, r)                                  -- sombra
    lg.setColor(0, 0, 0, 0.62)
    rect("fill", x, y, w, h, r, r)                                          -- contorno
    lg.setColor(0, 0, 0, 0)
    rect("fill", x + 2, y + 2, w - 4, h - 4, r - 1, r - 1)                  -- cuerpo (sin capa)
    lg.setColor(1, 1, 1, 0.22)
    rect("fill", x + 2, y + 2, w - 4, math.floor((h - 4) / 2), r - 1, r - 1) -- brillo
    rect("fill", x + 2, y + 2 + r, w - 4, math.max(0, math.floor((h - 4) / 2) - r))
    lg.setColor(1, 1, 1, enabled and 0.543 or 0.372)
    rect("fill", x + 2 + r - 1, y + 3, w - 4 - (r - 1) * 2, 1)              -- bisel claro
    lg.setColor(0, 0, 0, 0.3)
    rect("fill", x + 2 + r - 1, y + h - 4, w - 4 - (r - 1) * 2, 1)          -- bisel oscuro
end

-- Iconos del menú principal ya puestos en su cuadrado claro con borde (como en
-- menu.lua): 8 celdas de 33x33 en una imagen (una carga y un dibujo por botón en
-- vez de 8 texturas y 3 dibujos). Mismo orden y colores que ITEMS en menu.lua.
local MENU = {
    { "play", "#d04848" }, { "stages", "#e08838" }, { "dex", "#3c9c54" }, { "upgrades", "#8c58c0" },
    { "gacha", "#c8a024" }, { "goals", "#2e94b4" }, { "card", "#4870c8" }, { "starters", "#d0608c" },
}
-- Como U.shade(hex, -0.5) de util.lua (redondeado a 8 bits).
local function darkHalf(hex)
    local c = {}
    for i = 0, 2 do
        local v = tonumber(hex:sub(2 + i * 2, 3 + i * 2), 16) / 255
        c[i + 1] = math.max(0, math.min(255, math.floor(v * 0.5 * 255 + 0.5))) / 255
    end
    return c
end
local function readImage(path)
    local f = assert(io.open(path, "rb"))
    local data = f:read("*a")
    f:close()
    local im = lg.newImage(love.filesystem.newFileData(data, path))
    im:setFilter("nearest", "nearest")
    return im
end
local function bakeMenuIcons(out)
    local cv = lg.newCanvas(256, 128)
    lg.setCanvas(cv)
    lg.clear(0, 0, 0, 0)
    for i, it in ipairs(MENU) do
        local cx, cy = ((i - 1) % 4) * 34, math.floor((i - 1) / 4) * 34
        local sx, sy, ss = cx + 1, cy + 1, 31
        lg.setColor(darkHalf(it[2]))
        rect("fill", sx - 1, sy - 1, ss + 2, ss + 2, 6, 6)
        lg.setColor(1, 1, 1, 0.92)
        rect("fill", sx, sy, ss, ss, 5, 5)
        lg.setColor(1, 1, 1, 1)
        local im = readImage("game/img/menu/" .. it[1] .. ".png")
        lg.draw(im, sx + math.floor((ss - im:getWidth()) / 2), sy + math.floor((ss - im:getHeight()) / 2))
    end
    lg.setCanvas()
    local data = cv:newImageData():encode("png"):getString()
    local f = assert(io.open(out, "wb"))
    f:write(data)
    f:close()
    print("MENUICONS_OK " .. out)
end

function love.load(args)
    if args[2] then bakeMenuIcons(args[2]) end
    local out = args[1] or "btn.png"
    local cv = lg.newCanvas(128, 256)
    lg.setCanvas(cv)
    lg.clear(0, 0, 0, 0)
    -- ("premultiplied": que no multiplique el color por la transparencia al guardar)
    lg.setBlendMode("replace", "premultiplied")
    -- Dos grupos de 5 altos (x = 0 y 64); en cada uno, activo en +0 y desactivado en +32.
    for g = 0, 1 do
        local y = 0
        for k = 1, 5 do
            local h = ALTOS[g * 5 + k]
            layer(g * 64, y, TW, h, true)
            layer(g * 64 + 32, y, TW, h, false)
            y = y + h + 3
        end
    end
    -- Tira de 10 marcas de nivel (4x8 cada 6 px, blancas) en (0, 200) para UI.pips:
    -- una fila de marcas del mismo color es un solo dibujo.
    lg.setColor(1, 1, 1, 1)
    for k = 0, 9 do lg.rectangle("fill", k * 6, 200, 4, 8) end
    lg.setBlendMode("alpha")
    lg.setCanvas()
    local data = cv:newImageData():encode("png"):getString()
    local f = assert(io.open(out, "wb"))
    f:write(data)
    f:close()
    print("BTN_OK " .. out)
    love.event.quit()
end
