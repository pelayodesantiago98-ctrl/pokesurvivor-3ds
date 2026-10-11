-- icons.lua — iconos pixel art (port de js/ui/icons.js).
-- Si existe img/icons.png + data/icons.lua (generados por tools/gen_icons.py) se
-- dibujan de ahí; si no, un cuadrado de color con la inicial, para no romper nada.
local U = G.U
local I = {}
G.Icons = I

local lg = love.graphics
local img, quads, data = nil, {}, nil

local FALLBACK_COLOR = {
    heart = '#ff5f6d', fist = '#ff9a3d', boot = '#7fe0ff', clock = '#ffd23f', shield = '#9fd8ff',
    sprout = '#5fe08a', magnet = '#ff9ed8', book = '#c9a6ff', coin = '#ffd23f', cards = '#8fa3c4',
    berry = '#5fe08a', bomb = '#ff7b3d', star = '#ffe14d', ticket = '#ffd23f', ticket10 = '#c47bff',
    friends = '#7fc8ff', medal0 = '#c47a3a', medal1 = '#c9d2de', medal2 = '#ffd23f', crown = '#ffd23f',
}

function I.load()
    local ok, d = pcall(require, "data.icons")
    if not ok or not d then return false end
    local ok2, im = pcall(lg.newImage, U.img("img/icons"))
    if not ok2 or not im then return false end
    if im.setFilter then pcall(im.setFilter, im, "nearest", "nearest") end
    img, data = im, d
    local w, h = im:getWidth(), im:getHeight()
    for name, q in pairs(d.quads) do
        quads[name] = { lg.newQuad(q[1], q[2], q[3], q[4], w, h), q[3], q[4] }
    end
    return true
end

-- Dibuja el icono `name` con su esquina superior izquierda en (x, y) y `size` px.
-- "move:<id>" compone el emblema del tipo + la insignia de la familia.
-- Sprites de la mochila de los juegos (PokeAPI, estilo 3ª/4ª gen) para los objetos.
local itemImgs = {}
local function itemImg(name)
    local im = itemImgs[name]
    if im ~= nil then return im end
    im = false
    if G.Items and G.Items.BY[name] then
        local ok, res = pcall(lg.newImage, U.img("img/items/" .. name))
        if ok and res then
            if res.setFilter then pcall(res.setFilter, res, "nearest", "nearest") end
            im = res
        end
    end
    itemImgs[name] = im
    return im
end

function I.draw(name, x, y, size)
    size = size or 12
    local it = itemImg(name)
    if it then
        lg.setColor(1, 1, 1, 1)
        local s = size / 30
        lg.draw(it, x, y, 0, s, s)
        return
    end
    if name:sub(1, 5) == "move:" then
        local id = name:sub(6)
        local m = G.Moves and G.Moves.BY_ID[id]
        if m then
            I.draw("type_" .. m.type, x, y, size)
            I.draw("fam_" .. m.kind, x + size * 0.5, y + size * 0.5, size * 0.5)
        end
        return
    end
    local q = img and quads[name]
    if q then
        lg.setColor(1, 1, 1, 1)
        lg.draw(img, q[1], x, y, 0, size / q[2], size / q[3])
        return
    end
    -- Respaldo: cuadrado de color.
    local col = FALLBACK_COLOR[name]
    if not col then
        local t = name:match("^type_(%w+)")
        col = t and U.TYPE_COLOR[t] or '#8fa3c4'
    end
    U.setColor(col)
    lg.rectangle("fill", x, y, size, size, 2, 2)
    lg.setColor(0, 0, 0, 0.5)
    lg.rectangle("line", x + 0.5, y + 0.5, size - 1, size - 1)
    lg.setColor(1, 1, 1, 1)
end

function I.has(name) return img ~= nil and quads[name] ~= nil end
